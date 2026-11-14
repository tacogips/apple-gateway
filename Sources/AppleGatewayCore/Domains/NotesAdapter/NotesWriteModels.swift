import Foundation

public enum NoteBodyUpdateMode: String, Codable, Sendable {
  case replace = "REPLACE"
  case append = "APPEND"
}

public struct CreateNoteInput: Codable, Equatable, Sendable {
  public var accountId: String?
  public var folderId: String?
  public var title: String
  public var bodyHtml: String?
  public var bodyText: String?

  public init(
    accountId: String? = nil,
    folderId: String? = nil,
    title: String,
    bodyHtml: String? = nil,
    bodyText: String? = nil
  ) {
    self.accountId = accountId
    self.folderId = folderId
    self.title = title
    self.bodyHtml = bodyHtml
    self.bodyText = bodyText
  }
}

public struct UpdateNoteBodyInput: Codable, Equatable, Sendable {
  public var noteId: String
  public var mode: NoteBodyUpdateMode
  public var bodyHtml: String?
  public var bodyText: String?

  public init(
    noteId: String,
    mode: NoteBodyUpdateMode = .replace,
    bodyHtml: String? = nil,
    bodyText: String? = nil
  ) {
    self.noteId = noteId
    self.mode = mode
    self.bodyHtml = bodyHtml
    self.bodyText = bodyText
  }
}

public struct NotesCreateRequest: Codable, Equatable, Sendable {
  public var accountId: String
  public var folderId: String
  public var title: String
  public var bodyHtml: String

  public init(accountId: String, folderId: String, title: String, bodyHtml: String) {
    self.accountId = accountId
    self.folderId = folderId
    self.title = title
    self.bodyHtml = bodyHtml
  }
}

public struct NotesBodyWriteRequest: Codable, Equatable, Sendable {
  public var noteId: String
  public var bodyHtml: String

  public init(noteId: String, bodyHtml: String) {
    self.noteId = noteId
    self.bodyHtml = bodyHtml
  }
}

public struct NotesMoveRequest: Codable, Equatable, Sendable {
  public var noteId: String
  public var accountId: String
  public var folderId: String

  public init(noteId: String, accountId: String, folderId: String) {
    self.noteId = noteId
    self.accountId = accountId
    self.folderId = folderId
  }
}
