import Foundation

public protocol MailWriting: Sendable {
  func setRead(target: MailMessageTarget, isRead: Bool) throws
  func setFlagged(target: MailMessageTarget, isFlagged: Bool) throws
  func move(target: MailMessageTarget, destination: MailboxTarget) throws
  func delete(target: MailMessageTarget) throws
}
