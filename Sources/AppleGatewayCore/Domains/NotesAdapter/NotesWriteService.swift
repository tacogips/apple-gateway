import Foundation

public struct NotesWriteService: Sendable {
  private let provider: any NotesProviding
  private let writer: any NotesWriting
  private let readService: NotesReadService

  public init(
    provider: any NotesProviding,
    writer: any NotesWriting,
    limits: AppleGatewayConfig.Limits = .defaultValue,
    fileStore: FileStore = FileStore(cacheRoot: AppleGatewayConfig.Storage.defaultValue.cacheDir),
    attachmentExportStore: NotesAttachmentExportStore? = nil
  ) {
    self.provider = provider
    self.writer = writer
    readService = NotesReadService(
      provider: provider,
      limits: limits,
      fileStore: fileStore,
      attachmentExportStore: attachmentExportStore
    )
  }

  public func createNote(_ input: CreateNoteInput) throws -> Note {
    let bodyHtml = try resolvedBodyHtml(bodyHtml: input.bodyHtml, bodyText: input.bodyText)
    let folder = try targetFolder(accountId: input.accountId, folderId: input.folderId)
    let noteId = try writer.createNote(
      NotesCreateRequest(
        accountId: folder.accountId,
        folderId: folder.id,
        title: input.title,
        bodyHtml: bodyHtml
      )
    )
    return try refetchNote(noteId: noteId, bodyKind: .html)
  }

  public func updateNoteBody(_ input: UpdateNoteBodyInput) throws -> Note {
    let bodyHtml = try resolvedBodyHtml(bodyHtml: input.bodyHtml, bodyText: input.bodyText)
    let updatedBody: String
    switch input.mode {
    case .replace:
      updatedBody = bodyHtml
    case .append:
      updatedBody = try currentBodyHtml(noteId: input.noteId) + bodyHtml
    }

    let noteId = try writer.replaceNoteBody(
      NotesBodyWriteRequest(noteId: input.noteId, bodyHtml: updatedBody)
    )
    return try refetchNote(noteId: noteId, bodyKind: .html)
  }

  public func deleteNote(noteId: String) throws -> DeleteResult {
    _ = try existingNote(noteId: noteId)
    return try writer.deleteNote(noteId: noteId)
  }

  public func moveNote(noteId: String, folderId: String) throws -> Note {
    _ = try existingNote(noteId: noteId)
    let folder = try targetFolder(accountId: nil, folderId: folderId)
    let movedId = try writer.moveNote(
      NotesMoveRequest(noteId: noteId, accountId: folder.accountId, folderId: folder.id)
    )
    return try refetchNote(noteId: movedId, bodyKind: .html)
  }

  private func currentBodyHtml(noteId: String) throws -> String {
    switch try provider.noteBody(noteId: noteId, kind: .html) {
    case .found(let result):
      return result.body
    case .locked:
      throw AppleGatewayError(code: .noteLocked, message: "Note is password protected")
    case .missing:
      throw noteNotFound(noteId: noteId)
    }
  }

  private func existingNote(noteId: String) throws -> Note {
    switch try provider.noteMetadata(noteId: noteId) {
    case .found(let note):
      return note
    case .locked:
      throw AppleGatewayError(code: .noteLocked, message: "Note is password protected")
    case .missing:
      throw noteNotFound(noteId: noteId)
    }
  }

  private func refetchNote(noteId: String, bodyKind: NoteBodyKind) throws -> Note {
    guard let note = try readService.note(noteId: noteId, bodyKind: bodyKind) else {
      throw noteNotFound(noteId: noteId)
    }
    return note
  }

  private func targetFolder(accountId: String?, folderId: String?) throws -> NoteFolder {
    if let accountId {
      let accountExists = try provider.accounts().contains { $0.id == accountId }
      guard accountExists else {
        throw AppleGatewayError(
          code: .invalidArgument,
          message: "Unknown Notes account id",
          details: ["accountId": accountId]
        )
      }
    }

    let folders = try provider.folders(accountId: accountId)
    if let folderId {
      guard let folder = folders.first(where: { $0.id == folderId }) else {
        throw AppleGatewayError(
          code: .noteFolderNotFound,
          message: "Notes folder not found",
          details: ["folderId": folderId]
        )
      }
      return folder
    }

    if let defaultFolder = folders.first {
      return defaultFolder
    }
    throw AppleGatewayError(code: .noteFolderNotFound, message: "Default Notes folder not found")
  }

  private func resolvedBodyHtml(bodyHtml: String?, bodyText: String?) throws -> String {
    switch (bodyHtml, bodyText) {
    case (.some(let html), .none):
      return html
    case (.none, .some(let text)):
      return Self.htmlParagraphs(from: text)
    default:
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Exactly one of bodyHtml or bodyText is required"
      )
    }
  }

  private func noteNotFound(noteId: String) -> AppleGatewayError {
    AppleGatewayError(code: .noteNotFound, message: "Note not found", details: ["noteId": noteId])
  }

  private static func htmlParagraphs(from text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    return lines.map { line in
      if line.isEmpty {
        return "<div><br></div>"
      }
      return "<div>\(escapedHtml(line))</div>"
    }.joined()
  }

  private static func escapedHtml(_ value: String) -> String {
    value.reduce(into: "") { output, character in
      switch character {
      case "&":
        output += "&amp;"
      case "<":
        output += "&lt;"
      case ">":
        output += "&gt;"
      case "\"":
        output += "&quot;"
      case "'":
        output += "&#39;"
      default:
        output.append(character)
      }
    }
  }
}
