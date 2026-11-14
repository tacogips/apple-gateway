import Foundation

public struct NoteAccount: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var isDefault: Bool

  public init(id: String, name: String, isDefault: Bool) {
    self.id = id
    self.name = name
    self.isDefault = isDefault
  }
}

public struct NoteFolder: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var accountId: String
  public var name: String
  public var parentFolderId: String?
  public var noteCount: Int

  public init(
    id: String,
    accountId: String,
    name: String,
    parentFolderId: String? = nil,
    noteCount: Int
  ) {
    self.id = id
    self.accountId = accountId
    self.name = name
    self.parentFolderId = parentFolderId
    self.noteCount = noteCount
  }
}

public struct NoteBodyFile: Codable, Equatable, Sendable {
  public var downloadKey: String
  public var kind: NoteBodyKind
  public var byteSize: Int

  public init(downloadKey: String, kind: NoteBodyKind, byteSize: Int) {
    self.downloadKey = downloadKey
    self.kind = kind
    self.byteSize = byteSize
  }
}

public enum NoteBodyKind: String, CaseIterable, Codable, Sendable {
  case plaintext = "PLAINTEXT"
  case html = "HTML"
}

public struct NoteBodyFetchResult: Equatable, Sendable {
  public var note: Note
  public var kind: NoteBodyKind
  public var body: String

  public init(note: Note, kind: NoteBodyKind, body: String) {
    self.note = note
    self.kind = kind
    self.body = body
  }
}

public struct NoteAttachment: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var contentIdentifier: String?
  public var downloadKey: String?

  public init(
    id: String,
    name: String,
    contentIdentifier: String? = nil,
    downloadKey: String? = nil
  ) {
    self.id = id
    self.name = name
    self.contentIdentifier = contentIdentifier
    self.downloadKey = downloadKey
  }
}

public struct Note: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var accountId: String
  public var folderId: String
  public var name: String
  public var snippet: String
  public var plaintext: String?
  public var bodyHtml: String?
  public var bodyFile: NoteBodyFile?
  public var isPasswordProtected: Bool
  public var isShared: Bool
  public var creationDate: Date
  public var modificationDate: Date
  public var attachments: [NoteAttachment]

  public init(
    id: String,
    accountId: String,
    folderId: String,
    name: String,
    snippet: String,
    plaintext: String? = nil,
    bodyHtml: String? = nil,
    bodyFile: NoteBodyFile? = nil,
    isPasswordProtected: Bool = false,
    isShared: Bool = false,
    creationDate: Date,
    modificationDate: Date,
    attachments: [NoteAttachment] = []
  ) {
    self.id = id
    self.accountId = accountId
    self.folderId = folderId
    self.name = name
    self.snippet = snippet
    self.plaintext = plaintext
    self.bodyHtml = bodyHtml
    self.bodyFile = bodyFile
    self.isPasswordProtected = isPasswordProtected
    self.isShared = isShared
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.attachments = attachments
  }
}

public struct NoteSearchInput: Sendable {
  public var accountId: String?
  public var folderId: String?
  public var query: String?
  public var modifiedAfter: Date?
  public var modifiedBefore: Date?
  public var first: Int?
  public var after: String?

  public init(
    accountId: String? = nil,
    folderId: String? = nil,
    query: String? = nil,
    modifiedAfter: Date? = nil,
    modifiedBefore: Date? = nil,
    first: Int? = nil,
    after: String? = nil
  ) {
    self.accountId = accountId
    self.folderId = folderId
    self.query = query
    self.modifiedAfter = modifiedAfter
    self.modifiedBefore = modifiedBefore
    self.first = first
    self.after = after
  }
}

public struct NotesBodySearchInput: Equatable, Sendable {
  public var accountId: String?
  public var folderId: String?
  public var query: String

  public init(accountId: String? = nil, folderId: String? = nil, query: String) {
    self.accountId = accountId
    self.folderId = folderId
    self.query = query
  }
}

public struct NoteConnection: Codable, Equatable, Sendable {
  public var edges: [NoteEdge]
  public var pageInfo: PageInfo
  public var totalCount: Int

  public init(edges: [NoteEdge], pageInfo: PageInfo, totalCount: Int) {
    self.edges = edges
    self.pageInfo = pageInfo
    self.totalCount = totalCount
  }
}

public struct NoteEdge: Codable, Equatable, Sendable {
  public var cursor: String
  public var node: Note

  public init(cursor: String, node: Note) {
    self.cursor = cursor
    self.node = node
  }
}

public enum NoteLookupResult: Equatable, Sendable {
  case found(Note)
  case locked
  case missing
}

public enum NoteBodyLookupResult: Equatable, Sendable {
  case found(NoteBodyFetchResult)
  case locked
  case missing
}
