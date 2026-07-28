import Foundation

public struct MailMessageTarget: Codable, Equatable, Sendable {
  public var messageId: String
  public var storeRowId: Int64
  public var rfcMessageId: String?
  public var accountName: String
  public var mailboxPath: String

  public init(
    messageId: String,
    storeRowId: Int64,
    rfcMessageId: String?,
    accountName: String,
    mailboxPath: String
  ) {
    self.messageId = messageId
    self.storeRowId = storeRowId
    self.rfcMessageId = rfcMessageId
    self.accountName = accountName
    self.mailboxPath = mailboxPath
  }
}

public struct MailboxTarget: Codable, Equatable, Sendable {
  public var mailboxId: String
  public var accountName: String
  public var mailboxPath: String

  public init(mailboxId: String, accountName: String, mailboxPath: String) {
    self.mailboxId = mailboxId
    self.accountName = accountName
    self.mailboxPath = mailboxPath
  }
}

public struct MailUpdateResult: Codable, Equatable, Sendable {
  public var success: Bool
  public var messageId: String

  public init(success: Bool = true, messageId: String) {
    self.success = success
    self.messageId = messageId
  }
}

public struct MailMoveResult: Codable, Equatable, Sendable {
  public var success: Bool
  public var messageId: String
  public var mailboxId: String

  public init(success: Bool = true, messageId: String, mailboxId: String) {
    self.success = success
    self.messageId = messageId
    self.mailboxId = mailboxId
  }
}
