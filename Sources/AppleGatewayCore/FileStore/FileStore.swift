import CryptoKit
import Foundation

public struct FileStore: Sendable {
  public var cacheRoot: String
  private var secretOverride: Data?

  public init(cacheRoot: String, secret: Data? = nil) {
    self.cacheRoot = cacheRoot
    secretOverride = secret
  }

  public func issueDownloadKey(_ payload: FileStoreDownloadKeyPayload) throws -> String {
    try codec(createIfMissing: true).encode(payload)
  }

  public func download(
    keys: [String],
    outputDirectory: String?,
    materializer: any FileStoreMaterializing
  ) throws -> FileStoreDownloadManifest {
    guard !keys.isEmpty else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "At least one --key is required"
      )
    }
    let cache = try cacheRootURL()
    let outputRoot = try outputDirectory.map { try FileStorePathSafety.normalizedRoot($0, field: "outputDir") }
    try keys.forEach { try FileStoreDownloadKeyCodec.prevalidateSyntax($0) }
    let codec = try codec(createIfMissing: false)
    let decoded = try keys.map { key in
      (key: key, payload: try codec.decode(key))
    }
    let root = outputRoot ?? cache.appendingPathComponent("downloads", isDirectory: true)
    try FileStorePathSafety.ensureContained(root, in: outputRoot ?? cache)

    var files: [FileStoreDownloadedFile] = []
    for item in decoded {
      let destination = try destinationURL(
        payload: item.payload,
        root: root,
        containmentRoot: outputRoot ?? cache,
        useManagedLayout: outputRoot == nil
      )
      let source = try materializer.sourceFile(for: item.payload)
      try copyFile(from: source, to: destination)
      files.append(
        FileStoreDownloadedFile(
          downloadKey: item.key,
          domain: item.payload.domain.rawValue,
          kind: item.payload.kind.rawValue,
          path: destination.path
        )
      )
    }
    return FileStoreDownloadManifest(files: files)
  }

  public func prune(all: Bool = false) throws -> FileStorePruneReport {
    let root = try cacheRootURL()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let managedNames = all ? ["downloads", "snapshots", "keys"] : ["downloads", "snapshots"]
    var removedFiles = 0
    var removedDirectories = 0
    for name in managedNames {
      let candidate = root.appendingPathComponent(name, isDirectory: true)
      try FileStorePathSafety.ensureContained(candidate, in: root)
      guard FileManager.default.fileExists(atPath: candidate.path) else {
        continue
      }
      let counts = countContents(at: candidate)
      try FileManager.default.removeItem(at: candidate)
      removedFiles += counts.files
      removedDirectories += counts.directories + 1
    }
    return FileStorePruneReport(removedFiles: removedFiles, removedDirectories: removedDirectories)
  }

  public func snapshotSQLiteDatabase(
    sourcePath: String,
    domain: FileStoreDomain,
    sourceId: String
  ) throws -> FileStoreSnapshotResult {
    try FileStorePathSafety.validateSegment(sourceId, field: "sourceId")
    let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "SQLite source database does not exist",
        details: ["path": source.path]
      )
    }
    let root = try cacheRootURL()
    let destinationDirectory = root
      .appendingPathComponent("snapshots", isDirectory: true)
      .appendingPathComponent(domain.rawValue, isDirectory: true)
      .appendingPathComponent(Self.shortHash(sourceId), isDirectory: true)
    try FileStorePathSafety.ensureContained(destinationDirectory, in: root)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

    var copiedPaths: [String] = []
    for path in [source.path, source.path + "-wal", source.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
      let sourceURL = URL(fileURLWithPath: path)
      let destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
      try FileStorePathSafety.ensureContained(destination, in: root)
      if try snapshotIsCurrent(source: sourceURL, destination: destination) {
        copiedPaths.append(destination.path)
        continue
      }
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destination)
      copiedPaths.append(destination.path)
    }

    return FileStoreSnapshotResult(
      databasePath: destinationDirectory.appendingPathComponent(source.lastPathComponent).path,
      copiedPaths: copiedPaths
    )
  }

  private func snapshotIsCurrent(source: URL, destination: URL) throws -> Bool {
    guard FileManager.default.fileExists(atPath: destination.path) else {
      return false
    }
    let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
    let destinationAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    guard
      let sourceModifiedAt = sourceAttributes[.modificationDate] as? Date,
      let destinationModifiedAt = destinationAttributes[.modificationDate] as? Date
    else {
      return false
    }
    return destinationModifiedAt >= sourceModifiedAt
  }

  private func destinationURL(
    payload: FileStoreDownloadKeyPayload,
    root: URL,
    containmentRoot: URL,
    useManagedLayout: Bool
  ) throws -> URL {
    let filename = payload.filename ?? defaultFilename(for: payload.kind)
    try FileStorePathSafety.validateSegment(filename, field: "filename")
    let base: URL
    if useManagedLayout {
      base = root
        .appendingPathComponent(payload.domain.rawValue, isDirectory: true)
        .appendingPathComponent(Self.shortHash(payload.sourceId), isDirectory: true)
        .appendingPathComponent(payload.kind.rawValue, isDirectory: true)
    } else {
      base = root
    }
    let destination = base.appendingPathComponent(filename)
    try FileStorePathSafety.ensureContained(destination, in: containmentRoot)
    return destination
  }

  private func copyFile(from source: URL, to destination: URL) throws {
    let parent = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Destination already exists",
        details: ["path": destination.path]
      )
    }
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch let error as AppleGatewayError {
      throw error
    } catch {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Could not materialize file",
        details: ["path": destination.path, "reason": String(describing: error)]
      )
    }
  }

  private func cacheRootURL() throws -> URL {
    let root = try FileStorePathSafety.normalizedRoot(cacheRoot, field: "cacheRoot")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func codec(createIfMissing: Bool) throws -> FileStoreDownloadKeyCodec {
    if let secretOverride {
      return FileStoreDownloadKeyCodec(secret: secretOverride)
    }
    let secret = try secretData(createIfMissing: createIfMissing)
    return FileStoreDownloadKeyCodec(secret: secret)
  }

  private func secretData(createIfMissing: Bool) throws -> Data {
    let root = try FileStorePathSafety.normalizedRoot(cacheRoot, field: "cacheRoot")
    let keyDirectory = root.appendingPathComponent("keys", isDirectory: true)
    let keyURL = keyDirectory.appendingPathComponent("download-key.secret")
    if let data = try? Data(contentsOf: keyURL), !data.isEmpty {
      return data
    }
    guard createIfMissing else {
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Download key validation material is unavailable",
        details: ["reason": "Download key validation material is unavailable"]
      )
    }
    try FileManager.default.createDirectory(at: keyDirectory, withIntermediateDirectories: true)
    let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    try secret.write(to: keyURL, options: [.atomic])
    return secret
  }

  private func countContents(at url: URL) -> (files: Int, directories: Int) {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return (0, 0)
    }
    var files = 0
    var directories = 0
    for case let child as URL in enumerator {
      let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      if values?.isDirectory == true && values?.isSymbolicLink != true {
        directories += 1
      } else {
        files += 1
      }
    }
    return (files, directories)
  }

  private func defaultFilename(for kind: FileStoreFileKind) -> String {
    switch kind {
    case .bodyText, .plaintext:
      return "body.txt"
    case .bodyHTML, .html:
      return "body.html"
    case .rawSource:
      return "raw.eml"
    case .attachment:
      return "attachment.bin"
    }
  }

  static func shortHash(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
  }
}
