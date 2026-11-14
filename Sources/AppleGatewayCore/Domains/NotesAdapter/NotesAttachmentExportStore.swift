import Foundation

public struct NotesAttachmentExportStore: Sendable {
  private let cacheRoot: URL

  public init(cacheRoot: String) {
    self.cacheRoot = URL(fileURLWithPath: cacheRoot).standardizedFileURL
  }

  public func preparedFile(
    noteId: String,
    attachmentId: String,
    filename: String
  ) throws -> URL? {
    let locations = try preparedLocations(
      noteId: noteId,
      attachmentId: attachmentId,
      filename: filename
    )
    guard FileManager.default.fileExists(atPath: locations.destination.path) else {
      return nil
    }
    return try validatedRegularFile(locations.destination, root: locations.root)
  }

  public func export(
    provider: any NotesProviding,
    noteId: String,
    attachmentId: String,
    filename: String
  ) throws -> NotesAttachmentExportResult {
    let locations = try preparedLocations(
      noteId: noteId,
      attachmentId: attachmentId,
      filename: filename
    )
    if let prepared = try preparedFile(
      noteId: noteId,
      attachmentId: attachmentId,
      filename: filename
    ) {
      return .exported(prepared)
    }

    try removePartialFile(at: locations.destination)
    let result: NotesAttachmentExportResult
    do {
      result = try provider.exportAttachment(
        noteId: noteId,
        attachmentId: attachmentId,
        to: locations.destination
      )
    } catch {
      try? removePartialFile(at: locations.destination)
      throw error
    }

    guard case .exported(let exportedURL) = result else {
      try? removePartialFile(at: locations.destination)
      return result
    }
    guard exportedURL.standardizedFileURL.path == locations.destination.standardizedFileURL.path else {
      try? removePartialFile(at: locations.destination)
      return .unavailable
    }
    do {
      guard let file = try validatedRegularFile(exportedURL, root: locations.root) else {
        try? removePartialFile(at: locations.destination)
        return .unavailable
      }
      return .exported(file)
    } catch {
      try? removePartialFile(at: locations.destination)
      throw error
    }
  }

  private func preparedLocations(
    noteId: String,
    attachmentId: String,
    filename: String
  ) throws -> (root: URL, destination: URL) {
    let configuredRoot = try FileStorePathSafety.normalizedRoot(cacheRoot.path, field: "cacheDir")
      .appendingPathComponent("snapshots", isDirectory: true)
      .appendingPathComponent("notes", isDirectory: true)
      .appendingPathComponent("attachments", isDirectory: true)
    try createDirectoryWithoutSymlink(at: configuredRoot)
    let root = configuredRoot.resolvingSymlinksInPath().standardizedFileURL
    try requireDirectoryWithoutSymlink(configuredRoot)

    let noteDirectory = root.appendingPathComponent(NotesFileStoreIdentifier.encode(noteId), isDirectory: true)
    let attachmentDirectory = noteDirectory
      .appendingPathComponent(NotesFileStoreIdentifier.encode(attachmentId), isDirectory: true)
    try FileStorePathSafety.ensureContained(attachmentDirectory, in: root)
    try createDirectoryWithoutSymlink(at: noteDirectory)
    try createDirectoryWithoutSymlink(at: attachmentDirectory)

    let safeFilename = NotesFileStoreIdentifier.sanitizedFilename(filename, fallback: "attachment.bin")
    let destination = attachmentDirectory.appendingPathComponent(safeFilename)
    try FileStorePathSafety.ensureContained(destination, in: root)
    if FileManager.default.fileExists(atPath: destination.path) {
      let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true else {
        throw fileError("Prepared Notes attachment must not be a symbolic link", path: destination.path)
      }
    }
    return (root, destination)
  }

  private func createDirectoryWithoutSymlink(at url: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        try requireDirectoryWithoutSymlink(url)
        return
      }
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try requireDirectoryWithoutSymlink(url)
    } catch let error as AppleGatewayError {
      throw error
    } catch {
      throw fileError("Could not create prepared Notes attachment directory", path: url.path, error: error)
    }
  }

  private func requireDirectoryWithoutSymlink(_ url: URL) throws {
    do {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw fileError("Prepared Notes attachment path must be a real directory", path: url.path)
      }
    } catch let error as AppleGatewayError {
      throw error
    } catch {
      throw fileError("Could not inspect prepared Notes attachment directory", path: url.path, error: error)
    }
  }

  private func validatedRegularFile(_ url: URL, root: URL) throws -> URL? {
    let standardized = url.standardizedFileURL
    try FileStorePathSafety.ensureContained(standardized, in: root)
    guard FileManager.default.fileExists(atPath: standardized.path) else {
      return nil
    }
    do {
      let values = try standardized.resourceValues(forKeys: [
        .isRegularFileKey,
        .isReadableKey,
        .isSymbolicLinkKey
      ])
      guard
        values.isRegularFile == true,
        values.isReadable == true,
        values.isSymbolicLink != true,
        standardized.resolvingSymlinksInPath().path == standardized.path
      else {
        return nil
      }
      return standardized
    } catch {
      throw fileError("Could not inspect prepared Notes attachment", path: standardized.path, error: error)
    }
  }

  private func removePartialFile(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      throw fileError("Could not remove partial Notes attachment export", path: url.path, error: error)
    }
  }

  private func fileError(_ message: String, path: String, error: Error? = nil) -> AppleGatewayError {
    var details = ["path": path]
    if let error {
      details["underlyingError"] = String(describing: error)
    }
    return AppleGatewayError(code: .fileOperationFailed, message: message, details: details)
  }
}
