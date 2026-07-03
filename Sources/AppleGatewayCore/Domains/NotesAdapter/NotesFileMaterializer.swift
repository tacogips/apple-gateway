import Foundation

public struct NotesFileMaterializer: FileStoreMaterializing {
  private let provider: any NotesProviding
  private let scratchDirectory: URL

  public init(
    provider: any NotesProviding,
    scratchDirectory: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-notes-materializer", isDirectory: true)
  ) {
    self.provider = provider
    self.scratchDirectory = scratchDirectory
  }

  public func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    guard payload.domain == .notes else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Notes materializer cannot handle \(payload.domain.rawValue) files",
        details: ["domain": payload.domain.rawValue]
      )
    }
    switch payload.kind {
    case .plaintext, .html:
      return try materializeBody(payload)
    case .attachment:
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Notes attachment export is unavailable",
        details: ["sourceId": payload.sourceId]
      )
    case .bodyText, .bodyHTML, .rawSource:
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Unsupported Notes file kind",
        details: ["kind": payload.kind.rawValue]
      )
    }
  }

  private func materializeBody(_ payload: FileStoreDownloadKeyPayload) throws -> URL {
    let noteId = try NotesFileStoreIdentifier.decode(payload.sourceId)
    let kind = try payload.kind.noteBodyKind()
    let result = try provider.noteBody(noteId: noteId, kind: kind)
    guard case .found(let bodyResult) = result else {
      throw AppleGatewayError(
        code: result == .locked ? .noteLocked : .noteNotFound,
        message: result == .locked ? "Note is password protected" : "Note not found"
      )
    }
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let filename = NotesFileStoreIdentifier.sanitizedFilename(
      payload.filename ?? kind.defaultFilename,
      fallback: kind.defaultFilename
    )
    let destination = scratchDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent(filename)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(bodyResult.body.utf8).write(to: destination, options: [.atomic])
    return destination
  }
}

private extension FileStoreFileKind {
  func noteBodyKind() throws -> NoteBodyKind {
    switch self {
    case .plaintext:
      return .plaintext
    case .html:
      return .html
    case .bodyText, .bodyHTML, .rawSource, .attachment:
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Download key does not reference a Notes body",
        details: ["kind": rawValue]
      )
    }
  }
}
