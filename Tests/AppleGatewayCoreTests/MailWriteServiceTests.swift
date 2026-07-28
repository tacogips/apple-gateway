import Foundation
import Testing
@testable import AppleGatewayCore

@Test func mailWriteServiceResolvesStableTargetsBeforeUpdating() throws {
  let provider = MailWriteProviderFake()
  let writer = MailWriterFake()
  let service = MailWriteService(provider: provider, writer: writer)

  #expect(try service.setMessageRead(messageId: "message-42", isRead: true).success)
  #expect(try service.setMessageFlagged(messageId: "message-42", isFlagged: false).success)
  let move = try service.moveMessage(messageId: "message-42", mailboxId: "mailbox-archive")
  #expect(try service.deleteMessage(messageId: "message-42").success)

  #expect(writer.targets.count == 4)
  #expect(writer.targets.first?.storeRowId == 42)
  #expect(writer.targets.first?.rfcMessageId == "rfc-42@example.com")
  #expect(writer.targets.first?.accountName == "Example Mail")
  #expect(writer.targets.first?.mailboxPath == "INBOX")
  #expect(writer.readValues == [true])
  #expect(writer.flaggedValues == [false])
  #expect(writer.destinations.first?.mailboxPath == "Archive")
  #expect(move.mailboxId == "mailbox-archive")
  #expect(writer.deleteCount == 1)
}

@Test func mailWriteServiceRejectsInvalidOrMissingTargetsBeforeAutomation() throws {
  let provider = MailWriteProviderFake()
  let writer = MailWriterFake()
  let service = MailWriteService(provider: provider, writer: writer)

  #expect(throws: AppleGatewayError.self) {
    try service.setMessageRead(messageId: "not-stable", isRead: true)
  }
  #expect(throws: AppleGatewayError.self) {
    try service.setMessageRead(messageId: "message-999", isRead: true)
  }
  #expect(throws: AppleGatewayError.self) {
    try service.moveMessage(messageId: "message-42", mailboxId: "missing")
  }
  #expect(writer.targets.isEmpty)
}

@Test func mailJXATemplatesKeepUserValuesInJSONArguments() {
  for template in MailJXATemplate.allCases {
    #expect(template.source.contains("JSON.parse(argv[0])"))
    #expect(template.source.contains("Application('Mail')"))
    #expect(!template.source.contains("rfc-42@example.com"))
  }
}

private struct MailWriteProviderFake: MailProviding {
  func accounts() throws -> [MailAccount] {
    [MailAccount(id: "mail-account-1", name: "Example Mail", kind: .imap)]
  }

  func mailboxes(accountId: String?) throws -> [Mailbox] {
    [
      Mailbox(
        id: "mailbox-inbox",
        accountId: "mail-account-1",
        name: "INBOX",
        path: "INBOX",
        totalCount: 1,
        unreadCount: 1
      ),
      Mailbox(
        id: "mailbox-archive",
        accountId: "mail-account-1",
        name: "Archive",
        path: "Archive",
        totalCount: 0,
        unreadCount: 0
      )
    ]
  }

  func messages(input: MailSearchInput) throws -> MailMessageConnection {
    MailMessageConnection(edges: [], pageInfo: PageInfo(hasNextPage: false, endCursor: nil), totalCount: 0)
  }

  func message(messageId: String) throws -> MailMessage? {
    guard messageId == "message-42" else {
      return nil
    }
    return MailMessage(
      id: messageId,
      mailboxId: "mailbox-inbox",
      accountId: "mail-account-1",
      messageId: "rfc-42@example.com",
      isRead: false,
      isFlagged: true,
      hasAttachments: false
    )
  }
}

private final class MailWriterFake: MailWriting, @unchecked Sendable {
  var targets: [MailMessageTarget] = []
  var readValues: [Bool] = []
  var flaggedValues: [Bool] = []
  var destinations: [MailboxTarget] = []
  var deleteCount = 0

  func setRead(target: MailMessageTarget, isRead: Bool) throws {
    targets.append(target)
    readValues.append(isRead)
  }

  func setFlagged(target: MailMessageTarget, isFlagged: Bool) throws {
    targets.append(target)
    flaggedValues.append(isFlagged)
  }

  func move(target: MailMessageTarget, destination: MailboxTarget) throws {
    targets.append(target)
    destinations.append(destination)
  }

  func delete(target: MailMessageTarget) throws {
    targets.append(target)
    deleteCount += 1
  }
}
