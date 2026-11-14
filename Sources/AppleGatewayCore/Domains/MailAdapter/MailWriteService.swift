import Foundation

public struct MailWriteService: Sendable {
  private let provider: any MailProviding
  private let writer: any MailWriting

  public init(provider: any MailProviding, writer: any MailWriting) {
    self.provider = provider
    self.writer = writer
  }

  public func setMessageRead(messageId: String, isRead: Bool) throws -> MailUpdateResult {
    let target = try messageTarget(messageId: messageId)
    try writer.setRead(target: target, isRead: isRead)
    return MailUpdateResult(messageId: messageId)
  }

  public func setMessageFlagged(messageId: String, isFlagged: Bool) throws -> MailUpdateResult {
    let target = try messageTarget(messageId: messageId)
    try writer.setFlagged(target: target, isFlagged: isFlagged)
    return MailUpdateResult(messageId: messageId)
  }

  public func moveMessage(messageId: String, mailboxId: String) throws -> MailMoveResult {
    let target = try messageTarget(messageId: messageId)
    let destination = try mailboxTarget(mailboxId: mailboxId)
    try writer.move(target: target, destination: destination)
    return MailMoveResult(messageId: messageId, mailboxId: mailboxId)
  }

  public func deleteMessage(messageId: String) throws -> DeleteResult {
    let target = try messageTarget(messageId: messageId)
    try writer.delete(target: target)
    return DeleteResult(success: true)
  }

  private func messageTarget(messageId: String) throws -> MailMessageTarget {
    guard let rowId = MailStableIdentifier.messageRowId(messageId) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Invalid Mail message id",
        details: ["messageId": messageId]
      )
    }
    guard let message = try provider.message(messageId: messageId) else {
      throw AppleGatewayError(
        code: .messageNotFound,
        message: "Mail message not found",
        details: ["messageId": messageId]
      )
    }
    let mailbox = try mailbox(mailboxId: message.mailboxId)
    let account = try account(accountId: message.accountId)
    return MailMessageTarget(
      messageId: message.id,
      storeRowId: rowId,
      rfcMessageId: message.messageId,
      accountName: account.name,
      mailboxPath: mailbox.path
    )
  }

  private func mailboxTarget(mailboxId: String) throws -> MailboxTarget {
    let mailbox = try mailbox(mailboxId: mailboxId)
    let account = try account(accountId: mailbox.accountId)
    return MailboxTarget(
      mailboxId: mailbox.id,
      accountName: account.name,
      mailboxPath: mailbox.path
    )
  }

  private func mailbox(mailboxId: String) throws -> Mailbox {
    guard let mailbox = try provider.mailboxes(accountId: nil).first(where: { $0.id == mailboxId }) else {
      throw AppleGatewayError(
        code: .mailboxNotFound,
        message: "Mailbox not found",
        details: ["mailboxId": mailboxId]
      )
    }
    return mailbox
  }

  private func account(accountId: String) throws -> MailAccount {
    guard let account = try provider.accounts().first(where: { $0.id == accountId }) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Unknown Mail account id",
        details: ["accountId": accountId]
      )
    }
    return account
  }
}
