import Foundation
import SQLite3
import Testing
@testable import AppleGatewayCore

@Test func mailEnvelopeIndexDerivesAccountsAndMailboxes() throws {
  let fixture = try MailEnvelopeFixture()
  let accounts = try fixture.service.accounts()
  let mailboxes = try fixture.service.mailboxes()
  let imapAccount = try #require(accounts.first { $0.id == fixture.imapAccountId })
  let inbox = try #require(mailboxes.first { $0.id == fixture.inboxMailboxId })
  let archive = try #require(mailboxes.first { $0.path == "Archive" })
  let unknown = try #require(accounts.first { $0.kind == .unknown })

  #expect(imapAccount.name == "Example Mail")
  #expect(imapAccount.kind == .imap)
  #expect(inbox.accountId == fixture.imapAccountId)
  #expect(inbox.name == "INBOX")
  #expect(inbox.totalCount == 3)
  #expect(inbox.unreadCount == 2)
  #expect(archive.name == "Archive")
  #expect(unknown.name == "Unknown Account")
}

@Test func mailEnvelopeIndexFallsBackWhenAccountsPlistIsUnreadable() throws {
  let fixture = try MailEnvelopeFixture(accountsPlistMode: .unreadableDirectory)
  let accounts = try fixture.service.accounts()
  let imapAccount = try #require(accounts.first { $0.id == fixture.imapAccountId })

  #expect(imapAccount.name == "user@example.com")
}

@Test func mailEnvelopeIndexFiltersMessages() throws {
  let fixture = try MailEnvelopeFixture()

  #expect(try fixture.messageIds(MailSearchInput(accountId: fixture.imapAccountId)) == [
    "message-103",
    "message-101",
    "message-106",
    "message-102"
  ])
  #expect(try fixture.messageIds(MailSearchInput(mailboxId: fixture.receiptsMailboxId)) == ["message-103"])
  #expect(try fixture.messageIds(MailSearchInput(query: "planning")) == ["message-102"])
  #expect(try fixture.messageIds(MailSearchInput(from: "alice")) == ["message-103", "message-101"])
  #expect(try fixture.messageIds(MailSearchInput(to: "team")) == ["message-101", "message-104"])
  #expect(try fixture.messageIds(MailSearchInput(subject: "flag", flaggedOnly: true)) == ["message-103"])
  #expect(try fixture.messageIds(MailSearchInput(unreadOnly: true)) == ["message-105", "message-101", "message-106"])
  #expect(try fixture.messageIds(MailSearchInput(
    receivedAfter: try date("2026-01-05T00:00:00Z"),
    receivedBefore: try date("2026-01-06T00:00:00Z")
  )) == ["message-103", "message-101"])
  #expect(try fixture.messageIds(MailSearchInput(
    accountId: fixture.imapAccountId,
    subject: "invoice",
    unreadOnly: true
  )) == ["message-101", "message-106"])
}

@Test func mailEnvelopeIndexEscapesLikeWildcards() throws {
  let fixture = try MailEnvelopeFixture()

  #expect(try fixture.messageIds(MailSearchInput(query: "100%_")) == ["message-101"])
  #expect(try fixture.messageIds(MailSearchInput(subject: "100%_")) == ["message-101"])
}

@Test func mailEnvelopeIndexPaginationIsStableAndRejectsCrossQueryCursor() throws {
  let fixture = try MailEnvelopeFixture()
  let firstPage = try fixture.service.messages(input: MailSearchInput(
    accountId: fixture.imapAccountId,
    first: 1
  ))
  let secondPage = try fixture.service.messages(input: MailSearchInput(
    accountId: fixture.imapAccountId,
    first: 2,
    after: firstPage.pageInfo.endCursor
  ))

  #expect(firstPage.totalCount == 4)
  #expect(firstPage.edges.map(\.node.id) == ["message-103"])
  #expect(firstPage.pageInfo.hasNextPage)
  #expect(secondPage.edges.map(\.node.id) == ["message-101", "message-106"])
  #expect(secondPage.pageInfo.hasNextPage)

  do {
    _ = try fixture.service.messages(input: MailSearchInput(query: "flag", after: firstPage.pageInfo.endCursor))
    Issue.record("Expected cross-query cursor rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

@Test func mailEnvelopeIndexRejectsInvalidFilters() throws {
  let fixture = try MailEnvelopeFixture()

  try expectInvalidArgument {
    _ = try fixture.service.messages(input: MailSearchInput(accountId: "missing"))
  }
  try expectInvalidArgument {
    _ = try fixture.service.messages(input: MailSearchInput(mailboxId: "missing"))
  }
  try expectInvalidArgument {
    _ = try fixture.service.messages(input: MailSearchInput(first: 0))
  }
  try expectInvalidArgument {
    _ = try fixture.service.messages(input: MailSearchInput(
      receivedAfter: try date("2026-01-03T00:00:00Z"),
      receivedBefore: try date("2026-01-02T00:00:00Z")
    ))
  }
  try expectInvalidArgument {
    _ = try fixture.service.messages(input: MailSearchInput(unsupportedFields: ["bodyKind"]))
  }
}

@Test func mailEnvelopeIndexMapsMessageFieldsAndCocoaEpochDates() throws {
  let fixture = try MailEnvelopeFixture()
  let message = try #require(try fixture.service.messages(input: MailSearchInput(subject: "flag")).edges.first?.node)
  let expectedReceivedDate = try date("2026-01-05T12:00:00Z")

  #expect(message.messageId == "rfc-103")
  #expect(message.mailboxId == fixture.receiptsMailboxId)
  #expect(message.accountId == fixture.imapAccountId)
  #expect(message.subject == "Flag update")
  #expect(message.snippet == "Flag summary")
  #expect(message.from?.email == "alice@example.com")
  #expect(message.to.map(\.email) == ["bob@example.com"])
  #expect(message.cc.map(\.email) == ["carol@example.com"])
  #expect(message.dateReceived == expectedReceivedDate)
  #expect(message.isRead)
  #expect(message.isFlagged)
  #expect(!message.hasAttachments)
  #expect(message.files.attachments.isEmpty)
}

enum AccountsPlistMode {
  case readable
  case unreadableDirectory
}

final class MailEnvelopeFixture {
  let root: URL
  let database: MailSQLiteDatabase
  let service: MailEnvelopeIndexQueryService
  let imapAccountId: String
  let inboxMailboxId: String
  let receiptsMailboxId: String

  init(accountsPlistMode: AccountsPlistMode = .readable) throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-mail-query-tests")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("Envelope Index")
    try Self.createDatabase(at: databaseURL)
    let request = MailSQLiteOpenRequest(
      snapshotPath: databaseURL.path,
      uri: MailSQLiteDatabase.immutableReadOnlyURI(forSnapshotPath: databaseURL.path),
      flags: MailSQLiteOpenFlags.mailReadOnlySnapshot
    )
    database = try #require(try LiveMailSQLiteOpener().open(request) as? MailSQLiteDatabase)

    let accountsPlist = root.appendingPathComponent("Accounts.plist")
    switch accountsPlistMode {
    case .readable:
      try Self.writeAccountsPlist(to: accountsPlist)
    case .unreadableDirectory:
      try FileManager.default.createDirectory(at: accountsPlist, withIntermediateDirectories: true)
    }

    service = MailEnvelopeIndexQueryService(
      database: database,
      accountsPlistURL: accountsPlist,
      limits: AppleGatewayConfig.Limits(
        defaultPageSize: 20,
        maxPageSize: 50,
        maxInlineBodyBytes: 65_536,
        appleEventTimeoutSeconds: 30,
        appleEventBatchSize: 200
      )
    )
    let inboxInfo = MailboxURLParser.parse("imap://user@example.com/INBOX", rowId: 1)
    let receiptsInfo = MailboxURLParser.parse("imap://user@example.com/Receipts", rowId: 2)
    imapAccountId = inboxInfo.accountId
    inboxMailboxId = MailStableIdentifier.mailboxId(rowId: 1, accountKey: inboxInfo.accountKey)
    receiptsMailboxId = MailStableIdentifier.mailboxId(rowId: 2, accountKey: receiptsInfo.accountKey)
  }

  deinit {
    database.close()
    try? FileManager.default.removeItem(at: root)
  }

  func messageIds(_ input: MailSearchInput) throws -> [String] {
    try service.messages(input: input).edges.map(\.node.id)
  }

  private static func writeAccountsPlist(to url: URL) throws {
    let plist: [[String: String]] = [
      ["AccountName": "Example Mail", "Username": "user", "Hostname": "example.com"],
      ["AccountName": "Local Archive", "Name": "On My Mac"]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url)
  }

  private static func createDatabase(at url: URL) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
      throw AppleGatewayError(code: .fileOperationFailed, message: "Could not create fixture database")
    }
    defer {
      sqlite3_close(handle)
    }
    try exec(
      """
      CREATE TABLE mailboxes(ROWID INTEGER PRIMARY KEY, url TEXT NOT NULL);
      CREATE TABLE subjects(ROWID INTEGER PRIMARY KEY, subject TEXT);
      CREATE TABLE addresses(ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);
      CREATE TABLE summaries(message_id INTEGER PRIMARY KEY, summary TEXT);
      CREATE TABLE recipients(ROWID INTEGER PRIMARY KEY, message_id INTEGER, type TEXT, address_id INTEGER);
      CREATE TABLE messages(
        ROWID INTEGER PRIMARY KEY,
        message_id TEXT,
        mailbox INTEGER NOT NULL,
        subject INTEGER,
        sender INTEGER,
        date_sent REAL,
        date_received REAL,
        flags INTEGER NOT NULL
      );

      INSERT INTO mailboxes(ROWID, url) VALUES
        (1, 'imap://user@example.com/INBOX'),
        (2, 'imap://user@example.com/Receipts'),
        (3, 'local:///Archive.mbox'),
        (4, 'odd://opaque/Quarantine');
      INSERT INTO subjects(ROWID, subject) VALUES
        (1, 'Invoice 100%_ literal'),
        (2, 'Project Plan'),
        (3, 'Flag update'),
        (4, 'Archive News'),
        (5, 'Unknown Source'),
        (6, 'Invoice 100AA literal');
      INSERT INTO addresses(ROWID, address, comment) VALUES
        (1, 'alice@example.com', 'Alice'),
        (2, 'bob@example.com', 'Bob'),
        (3, 'carol@example.com', 'Carol'),
        (4, 'team@example.com', 'Team'),
        (5, 'literal@example.com', 'Percent_User');
      INSERT INTO messages(ROWID, message_id, mailbox, subject, sender, date_sent, date_received, flags) VALUES
        (101, 'rfc-101', 1, 1, 1, \(cocoa("2026-01-05T11:00:00Z")), \(cocoa("2026-01-05T12:00:00Z")), 0),
        (102, 'rfc-102', 1, 2, 2, \(cocoa("2026-01-04T11:00:00Z")), \(cocoa("2026-01-04T12:00:00Z")), 1),
        (103, 'rfc-103', 2, 3, 1, \(cocoa("2026-01-05T11:30:00Z")), \(cocoa("2026-01-05T12:00:00Z")), 17),
        (104, 'rfc-104', 3, 4, 3, \(cocoa("2026-01-03T11:00:00Z")), \(cocoa("2026-01-03T12:00:00Z")), 1025),
        (105, 'rfc-105', 4, 5, 3, \(cocoa("2026-01-06T11:00:00Z")), \(cocoa("2026-01-06T12:00:00Z")), 0),
        (106, 'rfc-106', 1, 6, 5, \(cocoa("2026-01-04T10:00:00Z")), \(cocoa("2026-01-04T13:00:00Z")), 0);
      INSERT INTO summaries(message_id, summary) VALUES
        (101, 'Receipt summary 100%_ literal'),
        (102, 'Planning summary'),
        (103, 'Flag summary'),
        (104, 'Archive summary'),
        (105, 'Unknown summary'),
        (106, 'Receipt summary 100AA literal');
      INSERT INTO recipients(ROWID, message_id, type, address_id) VALUES
        (1, 101, 'to', 4),
        (2, 101, 'cc', 3),
        (3, 102, 'to', 3),
        (4, 103, 'to', 2),
        (5, 103, 'cc', 3),
        (6, 104, 'to', 4),
        (7, 106, 'to', 5);
      """,
      handle: handle
    )
  }

  private static func exec(_ sql: String, handle: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
      let reason = errorMessage.map { String(cString: $0) } ?? "sqlite3_exec failed"
      sqlite3_free(errorMessage)
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Could not initialize fixture database",
        details: ["reason": reason]
      )
    }
  }

  private static func cocoa(_ value: String) -> Double {
    (try? date(value).timeIntervalSince1970 - 978_307_200) ?? 0
  }
}

private func expectInvalidArgument(_ operation: () throws -> Void) throws {
  do {
    try operation()
    Issue.record("Expected INVALID_ARGUMENT")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

private func date(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}
