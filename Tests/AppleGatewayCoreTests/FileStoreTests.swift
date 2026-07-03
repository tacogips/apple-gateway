import Foundation
import Testing
@testable import AppleGatewayCore

@Test func downloadKeyRoundTripAndTamperRejection() throws {
  let codec = FileStoreDownloadKeyCodec(secret: Data("test-secret-32-bytes-test-secret".utf8))
  let payload = FileStoreDownloadKeyPayload(
    domain: .mail,
    sourceId: "message-1",
    kind: .bodyText,
    filename: "body.txt"
  )
  let key = try codec.encode(payload)

  #expect(try codec.decode(key) == payload)

  var tampered = key
  tampered.replaceSubrange(tampered.index(before: tampered.endIndex)..., with: "x")
  do {
    _ = try codec.decode(tampered)
    Issue.record("Expected tampered key rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidDownloadKey)
  }
}

@Test func downloadKeyRejectsTraversalSegments() throws {
  let codec = FileStoreDownloadKeyCodec(secret: Data("test-secret-32-bytes-test-secret".utf8))
  let payload = FileStoreDownloadKeyPayload(
    domain: .mail,
    sourceId: "../message",
    kind: .bodyText,
    filename: "body.txt"
  )

  do {
    _ = try codec.encode(payload)
    Issue.record("Expected traversal source id rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidDownloadKey)
  }
}

@Test func fileDownloadWritesUnderCacheRoot() throws {
  let root = try makeTemporaryRoot()
  let source = root.appendingPathComponent("source.txt")
  try Data("body".utf8).write(to: source)
  let store = FileStore(cacheRoot: root.appendingPathComponent("cache").path)
  let key = try store.issueDownloadKey(
    FileStoreDownloadKeyPayload(domain: .mail, sourceId: "message-1", kind: .bodyText, filename: "body.txt")
  )

  let manifest = try store.download(
    keys: [key],
    outputDirectory: nil,
    materializer: StaticFileMaterializer(source: source)
  )
  let path = try #require(manifest.files.first?.path)

  #expect(path.contains("/downloads/mail/"))
  #expect(path.hasPrefix(root.appendingPathComponent("cache").path))
  #expect(try String(contentsOfFile: path, encoding: .utf8) == "body")
}

@Test func fileDownloadWritesUnderExplicitOutputDirectory() throws {
  let root = try makeTemporaryRoot()
  let source = root.appendingPathComponent("source.txt")
  let output = root.appendingPathComponent("out")
  try Data("body".utf8).write(to: source)
  let store = FileStore(cacheRoot: root.appendingPathComponent("cache").path)
  let key = try store.issueDownloadKey(
    FileStoreDownloadKeyPayload(domain: .notes, sourceId: "note-1", kind: .plaintext, filename: "note.txt")
  )

  let manifest = try store.download(
    keys: [key],
    outputDirectory: output.path,
    materializer: StaticFileMaterializer(source: source)
  )
  let path = try #require(manifest.files.first?.path)

  #expect(path == output.appendingPathComponent("note.txt").path)
  #expect(try String(contentsOfFile: path, encoding: .utf8) == "body")
}

@Test func cachePruneRefusesFilesystemRootAndPreservesKeyMaterialByDefault() throws {
  let root = try makeTemporaryRoot()
  let cache = root.appendingPathComponent("cache")
  let keys = cache.appendingPathComponent("keys")
  let downloads = cache.appendingPathComponent("downloads")
  try FileManager.default.createDirectory(at: keys, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
  try Data("secret".utf8).write(to: keys.appendingPathComponent("download-key.secret"))
  try Data("file".utf8).write(to: downloads.appendingPathComponent("file.txt"))

  let report = try FileStore(cacheRoot: cache.path).prune()

  #expect(report.removedFiles == 1)
  #expect(FileManager.default.fileExists(atPath: keys.appendingPathComponent("download-key.secret").path))

  do {
    _ = try FileStore(cacheRoot: "/").prune(all: true)
    Issue.record("Expected root prune refusal")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fileOperationFailed)
  }
}

@Test func cachePruneAllRemovesKeyMaterialInsideRootOnly() throws {
  let root = try makeTemporaryRoot()
  let cache = root.appendingPathComponent("cache")
  let keys = cache.appendingPathComponent("keys")
  try FileManager.default.createDirectory(at: keys, withIntermediateDirectories: true)
  try Data("secret".utf8).write(to: keys.appendingPathComponent("download-key.secret"))

  _ = try FileStore(cacheRoot: cache.path).prune(all: true)

  #expect(!FileManager.default.fileExists(atPath: keys.path))
  #expect(FileManager.default.fileExists(atPath: cache.path))
}

@Test func cachePruneDoesNotFollowSymlinksOutsideRoot() throws {
  let root = try makeTemporaryRoot()
  let cache = root.appendingPathComponent("cache")
  let downloads = cache.appendingPathComponent("downloads")
  let outside = root.appendingPathComponent("outside")
  let outsideFile = outside.appendingPathComponent("keep.txt")
  try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try Data("keep".utf8).write(to: outsideFile)
  try FileManager.default.createSymbolicLink(
    at: downloads.appendingPathComponent("outside-link"),
    withDestinationURL: outside
  )

  _ = try FileStore(cacheRoot: cache.path).prune()

  #expect(FileManager.default.fileExists(atPath: outsideFile.path))
}

@Test func snapshotSQLiteCopiesDatabaseAndSidecars() throws {
  let root = try makeTemporaryRoot()
  let live = root.appendingPathComponent("Envelope Index")
  try Data("db".utf8).write(to: live)
  try Data("wal".utf8).write(to: URL(fileURLWithPath: live.path + "-wal"))
  try Data("shm".utf8).write(to: URL(fileURLWithPath: live.path + "-shm"))

  let result = try FileStore(cacheRoot: root.appendingPathComponent("cache").path)
    .snapshotSQLiteDatabase(sourcePath: live.path, domain: .mail, sourceId: "mail-root")

  #expect(result.copiedPaths.count == 3)
  #expect(try String(contentsOfFile: result.databasePath, encoding: .utf8) == "db")
  #expect(FileManager.default.fileExists(atPath: result.databasePath + "-wal"))
  #expect(FileManager.default.fileExists(atPath: result.databasePath + "-shm"))
}

@Test func commandFileDownloadProducesManifestEnvelope() throws {
  let root = try makeTemporaryRoot()
  let source = root.appendingPathComponent("source.txt")
  let cache = root.appendingPathComponent("cache")
  try Data("body".utf8).write(to: source)
  let key = try FileStore(cacheRoot: cache.path).issueDownloadKey(
    FileStoreDownloadKeyPayload(domain: .mail, sourceId: "message-1", kind: .bodyText, filename: "body.txt")
  )
  let command = AppleGatewayCommand(
    arguments: ["file", "download", "--key", key],
    environment: ["APPLE_GATEWAY_STORAGE_CACHE_DIR": cache.path],
    fileMaterializer: StaticFileMaterializer(source: source)
  )

  let result = try command.runResult()
  let object = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
  let data = try #require(object["data"] as? [String: Any])
  let files = try #require(data["files"] as? [[String: Any]])

  #expect(result.exitCode == 0)
  #expect(files.first?["kind"] as? String == "BODY_TEXT")
}

@Test func commandFileDownloadRejectsForgedKeyAsBusinessEnvelope() throws {
  let root = try makeTemporaryRoot()
  let cache = root.appendingPathComponent("cache")
  let command = AppleGatewayCommand(
    arguments: ["file", "download", "--key", "agdk1.bad.bad"],
    environment: ["APPLE_GATEWAY_STORAGE_CACHE_DIR": cache.path],
    fileMaterializer: StaticFileMaterializer(source: root.appendingPathComponent("source.txt"))
  )

  let result = try command.runResult()
  let object = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
  let errors = try #require(object["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])

  #expect(result.exitCode == 5)
  #expect(extensions["code"] as? String == "INVALID_DOWNLOAD_KEY")
}

private struct StaticFileMaterializer: FileStoreMaterializing {
  var source: URL

  func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    source
  }
}

private func makeTemporaryRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-file-store-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
