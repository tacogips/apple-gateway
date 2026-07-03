import Foundation
import SQLite3
import Testing
@testable import AppleGatewayCore

@Test func usernotedPostSequoiaFixtureListsFiltersAndWarnsOnUndecodablePayload() throws {
  let fixture = try UsernotedNotificationFixture(schema: .postSequoia)
  let connection = try fixture.service.notifications(input: NotificationSearchInput(first: 10))

  #expect(connection.totalCount == 3)
  #expect(connection.edges.map(\.node.id) == ["system-db-3", "system-db-1"])
  #expect(connection.edges.first?.node.appBundleId == "com.example.chat")
  #expect(connection.edges.first?.node.title == "Chat")
  #expect(connection.edges.first?.node.subtitle == "Team")
  #expect(connection.edges.first?.node.body == "Planning")
  #expect(connection.warnings == [
    NotificationListingWarning(id: "system-db-2", message: "Skipped undecodable Notification Center payload")
  ])

  let filtered = try fixture.service.notifications(input: NotificationSearchInput(appBundleId: "com.example.mail", first: 10))
  #expect(filtered.edges.map(\.node.title) == ["Mail"])

  let after = try #require(connection.edges.first?.cursor)
  let secondPage = try fixture.service.notifications(input: NotificationSearchInput(first: 1, after: after))
  #expect(secondPage.edges.map(\.node.title) == ["Mail"])
  #expect(!secondPage.pageInfo.hasNextPage)
}

@Test func usernotedLegacyFixtureSupportsAlternateColumnNamesAndDateFilters() throws {
  let fixture = try UsernotedNotificationFixture(schema: .legacy)
  let connection = try fixture.service.notifications(input: NotificationSearchInput(
    deliveredAfter: try date("2026-07-03T10:30:00Z"),
    deliveredBefore: try date("2026-07-03T12:30:00Z"),
    first: 10
  ))

  #expect(connection.edges.map(\.node.title) == ["Chat", "Mail"])
  #expect(connection.edges.map(\.node.source) == [.systemDb, .systemDb])
}

@Test func usernotedSchemaDriftMapsToNotificationDatabaseUnavailable() throws {
  let fixture = try UsernotedNotificationFixture(schema: .unsupported)

  do {
    _ = try fixture.service.notifications()
    Issue.record("Expected notification DB unavailable")
  } catch let error as AppleGatewayError {
    #expect(error.code == .notificationDBUnavailable)
    #expect(error.message.contains("schema"))
  }
}

@Test func usernotedStoreMapsDeniedAndMissingSourcePaths() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-usernoted-store-tests")
    .appendingPathComponent(UUID().uuidString)
  let resolver = UsernotedDatabasePathResolver(
    homeDirectory: root.appendingPathComponent("home").path,
    darwinUserDirectory: root.appendingPathComponent("darwin").path
  )
  let deniedStore = UsernotedNotificationStore(
    pathResolver: resolver,
    accessChecker: StaticUsernotedAccessChecker(status: .denied),
    snapshotter: StaticUsernotedSnapshotter(snapshotPath: root.appendingPathComponent("db").path)
  )
  let missingStore = UsernotedNotificationStore(
    pathResolver: resolver,
    accessChecker: StaticUsernotedAccessChecker(status: .missing),
    snapshotter: StaticUsernotedSnapshotter(snapshotPath: root.appendingPathComponent("db").path)
  )

  do {
    _ = try deniedStore.openDatabase()
    Issue.record("Expected FDA error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fullDiskAccessRequired)
  }

  do {
    _ = try missingStore.openDatabase()
    Issue.record("Expected unavailable DB")
  } catch let error as AppleGatewayError {
    #expect(error.code == .notificationDBUnavailable)
  }
}

@Test func usernotedStoreSnapshotsReadableResolvedDatabase() throws {
  let fixture = try UsernotedNotificationFixture(schema: .postSequoia)
  let store = UsernotedNotificationStore(
    pathResolver: UsernotedDatabasePathResolver(homeDirectory: fixture.home.path, darwinUserDirectory: nil),
    accessChecker: LiveUsernotedDatabaseAccessChecker(),
    snapshotter: StaticUsernotedSnapshotter(snapshotPath: fixture.databaseURL.path)
  )
  let database = try store.openDatabase()
  defer {
    database.close()
  }

  let connection = try UsernotedNotificationQueryService(database: database).notifications(input: NotificationSearchInput(first: 1))

  #expect(connection.edges.first?.node.title == "Chat")
}

private enum UsernotedFixtureSchema {
  case postSequoia
  case legacy
  case unsupported
}

private final class UsernotedNotificationFixture {
  let root: URL
  let home: URL
  let databaseURL: URL
  let database: MailSQLiteDatabase
  let service: UsernotedNotificationQueryService

  init(schema: UsernotedFixtureSchema) throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-usernoted-tests")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    home = root.appendingPathComponent("home")
    databaseURL = home
      .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.createDatabase(at: databaseURL, schema: schema)
    let request = MailSQLiteOpenRequest(
      snapshotPath: databaseURL.path,
      uri: MailSQLiteDatabase.immutableReadOnlyURI(forSnapshotPath: databaseURL.path),
      flags: MailSQLiteOpenFlags.mailReadOnlySnapshot
    )
    database = try #require(try LiveMailSQLiteOpener().open(request) as? MailSQLiteDatabase)
    service = UsernotedNotificationQueryService(database: database)
  }

  deinit {
    database.close()
    try? FileManager.default.removeItem(at: root)
  }

  private static func createDatabase(at url: URL, schema: UsernotedFixtureSchema) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
      throw AppleGatewayError(code: .fileOperationFailed, message: "Could not create fixture database")
    }
    defer {
      sqlite3_close(handle)
    }
    switch schema {
    case .postSequoia:
      try exec(
        """
        CREATE TABLE app(app_id INTEGER PRIMARY KEY, identifier TEXT NOT NULL);
        CREATE TABLE record(record_id INTEGER PRIMARY KEY, app_id INTEGER, delivered_date REAL, data BLOB);
        INSERT INTO app(app_id, identifier) VALUES
          (1, 'com.example.mail'),
          (2, 'com.example.chat');
        INSERT INTO record(record_id, app_id, delivered_date, data) VALUES
          (1, 1, \(cf("2026-07-03T11:00:00Z")), X'\(plistHex(title: "Mail", subtitle: nil, body: "Invoice"))'),
          (2, 1, \(cf("2026-07-03T12:00:00Z")), X'\(Data("not plist".utf8).hexString)'),
          (3, 2, \(cf("2026-07-03T12:00:00Z")), X'\(plistHex(title: "Chat", subtitle: "Team", body: "Planning"))');
        """,
        handle: handle
      )
    case .legacy:
      try exec(
        """
        CREATE TABLE app(ROWID INTEGER PRIMARY KEY, bundleid TEXT NOT NULL);
        CREATE TABLE record(ROWID INTEGER PRIMARY KEY, app INTEGER, deliveredDate REAL, plist BLOB);
        INSERT INTO app(ROWID, bundleid) VALUES
          (1, 'com.example.mail'),
          (2, 'com.example.chat');
        INSERT INTO record(ROWID, app, deliveredDate, plist) VALUES
          (1, 1, \(cf("2026-07-03T11:00:00Z")), X'\(plistHex(title: "Mail", subtitle: nil, body: "Invoice"))'),
          (2, 2, \(cf("2026-07-03T12:00:00Z")), X'\(plistHex(title: "Chat", subtitle: "Team", body: "Planning"))');
        """,
        handle: handle
      )
    case .unsupported:
      try exec(
        """
        CREATE TABLE app(app_id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE record(record_id INTEGER PRIMARY KEY, app_id INTEGER);
        """,
        handle: handle
      )
    }
  }

  private static func exec(_ sql: String, handle: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
      let reason = errorMessage.map { String(cString: $0) } ?? "sqlite3_exec failed"
      sqlite3_free(errorMessage)
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Could not initialize usernoted fixture database",
        details: ["reason": reason]
      )
    }
  }

  private static func plistHex(title: String, subtitle: String?, body: String) -> String {
    var plist: [String: String] = [
      "title": title,
      "body": body
    ]
    if let subtitle {
      plist["subtitle"] = subtitle
    }
    let data = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
    return data.hexString
  }

  private static func cf(_ value: String) -> Double {
    (try? date(value).timeIntervalSince1970 - 978_307_200) ?? 0
  }
}

private struct StaticUsernotedAccessChecker: UsernotedDatabaseAccessChecking {
  var status: UsernotedDatabaseAccessStatus

  func accessStatus(path: String) -> UsernotedDatabaseAccessStatus {
    status
  }
}

private struct StaticUsernotedSnapshotter: UsernotedNotificationSnapshotting {
  var snapshotPath: String

  func snapshotUsernotedDatabase(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult {
    FileStoreSnapshotResult(databasePath: snapshotPath, copiedPaths: [snapshotPath])
  }
}

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

private func date(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}
