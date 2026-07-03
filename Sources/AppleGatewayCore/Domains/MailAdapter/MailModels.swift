import Foundation

public enum MailAccountKind: String, Codable, Sendable {
  case imap
  case exchange
  case local
  case pop
  case unknown
}

public struct MailAccount: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var kind: MailAccountKind

  public init(id: String, name: String, kind: MailAccountKind) {
    self.id = id
    self.name = name
    self.kind = kind
  }
}

public struct Mailbox: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var accountId: String
  public var name: String
  public var path: String
  public var totalCount: Int
  public var unreadCount: Int

  public init(
    id: String,
    accountId: String,
    name: String,
    path: String,
    totalCount: Int,
    unreadCount: Int
  ) {
    self.id = id
    self.accountId = accountId
    self.name = name
    self.path = path
    self.totalCount = totalCount
    self.unreadCount = unreadCount
  }
}

public struct MailAddress: Codable, Equatable, Sendable {
  public var raw: String
  public var name: String?
  public var email: String?

  public init(raw: String, name: String? = nil, email: String? = nil) {
    self.raw = raw
    self.name = name
    self.email = email
  }
}

public enum MailFileKind: String, CaseIterable, Codable, Sendable {
  case bodyText = "BODY_TEXT"
  case bodyHTML = "BODY_HTML"
  case rawSource = "RAW_SOURCE"
  case attachment = "ATTACHMENT"
}

public struct MailMessageFile: Codable, Equatable, Sendable {
  public var downloadKey: String
  public var kind: MailFileKind
  public var filename: String?
  public var mimeType: String?
  public var byteSize: Int?

  public init(
    downloadKey: String,
    kind: MailFileKind,
    filename: String? = nil,
    mimeType: String? = nil,
    byteSize: Int? = nil
  ) {
    self.downloadKey = downloadKey
    self.kind = kind
    self.filename = filename
    self.mimeType = mimeType
    self.byteSize = byteSize
  }
}

public struct MailMessageFileSet: Codable, Equatable, Sendable {
  public var bodyText: MailMessageFile?
  public var bodyHtml: MailMessageFile?
  public var rawSource: MailMessageFile?
  public var attachments: [MailMessageFile]

  public init(
    bodyText: MailMessageFile? = nil,
    bodyHtml: MailMessageFile? = nil,
    rawSource: MailMessageFile? = nil,
    attachments: [MailMessageFile] = []
  ) {
    self.bodyText = bodyText
    self.bodyHtml = bodyHtml
    self.rawSource = rawSource
    self.attachments = attachments
  }
}

public struct MailMessage: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var mailboxId: String
  public var accountId: String
  public var messageId: String?
  public var subject: String?
  public var snippet: String?
  public var from: MailAddress?
  public var to: [MailAddress]
  public var cc: [MailAddress]
  public var dateSent: Date?
  public var dateReceived: Date?
  public var isRead: Bool
  public var isFlagged: Bool
  public var hasAttachments: Bool
  public var files: MailMessageFileSet

  public init(
    id: String,
    mailboxId: String,
    accountId: String,
    messageId: String? = nil,
    subject: String? = nil,
    snippet: String? = nil,
    from: MailAddress? = nil,
    to: [MailAddress] = [],
    cc: [MailAddress] = [],
    dateSent: Date? = nil,
    dateReceived: Date? = nil,
    isRead: Bool,
    isFlagged: Bool,
    hasAttachments: Bool,
    files: MailMessageFileSet = MailMessageFileSet()
  ) {
    self.id = id
    self.mailboxId = mailboxId
    self.accountId = accountId
    self.messageId = messageId
    self.subject = subject
    self.snippet = snippet
    self.from = from
    self.to = to
    self.cc = cc
    self.dateSent = dateSent
    self.dateReceived = dateReceived
    self.isRead = isRead
    self.isFlagged = isFlagged
    self.hasAttachments = hasAttachments
    self.files = files
  }
}

public struct MailSearchInput: Sendable {
  public var accountId: String?
  public var mailboxId: String?
  public var query: String?
  public var from: String?
  public var to: String?
  public var subject: String?
  public var receivedAfter: Date?
  public var receivedBefore: Date?
  public var unreadOnly: Bool
  public var flaggedOnly: Bool
  public var first: Int?
  public var after: String?
  public var unsupportedFields: [String]

  public init(
    accountId: String? = nil,
    mailboxId: String? = nil,
    query: String? = nil,
    from: String? = nil,
    to: String? = nil,
    subject: String? = nil,
    receivedAfter: Date? = nil,
    receivedBefore: Date? = nil,
    unreadOnly: Bool = false,
    flaggedOnly: Bool = false,
    first: Int? = nil,
    after: String? = nil,
    unsupportedFields: [String] = []
  ) {
    self.accountId = accountId
    self.mailboxId = mailboxId
    self.query = query
    self.from = from
    self.to = to
    self.subject = subject
    self.receivedAfter = receivedAfter
    self.receivedBefore = receivedBefore
    self.unreadOnly = unreadOnly
    self.flaggedOnly = flaggedOnly
    self.first = first
    self.after = after
    self.unsupportedFields = unsupportedFields
  }
}

public struct MailMessageConnection: Codable, Equatable, Sendable {
  public var edges: [MailMessageEdge]
  public var pageInfo: PageInfo
  public var totalCount: Int

  public init(edges: [MailMessageEdge], pageInfo: PageInfo, totalCount: Int) {
    self.edges = edges
    self.pageInfo = pageInfo
    self.totalCount = totalCount
  }
}

public struct MailMessageEdge: Codable, Equatable, Sendable {
  public var cursor: String
  public var node: MailMessage

  public init(cursor: String, node: MailMessage) {
    self.cursor = cursor
    self.node = node
  }
}
