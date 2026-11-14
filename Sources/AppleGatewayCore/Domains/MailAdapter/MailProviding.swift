import Foundation

public protocol MailProviding: Sendable {
  func accounts() throws -> [MailAccount]
  func mailboxes(accountId: String?) throws -> [Mailbox]
  func messages(input: MailSearchInput) throws -> MailMessageConnection
  func message(messageId: String) throws -> MailMessage?
}
