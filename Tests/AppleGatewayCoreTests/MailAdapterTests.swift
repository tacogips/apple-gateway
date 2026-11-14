import Foundation
import SQLite3
import Testing
@testable import AppleGatewayCore

@Test func mailRootResolverUsesConfiguredRootBeforeProbing() throws {
  let overrideRoot = URL(fileURLWithPath: "/Custom/Mail/V10", isDirectory: true)
  let home = URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
  let fileSystem = FakeMailFileSystem(readableDirectories: [
    overrideRoot.path,
    overrideRoot.appendingPathComponent("MailData", isDirectory: true).path,
    "/tmp/apple-gateway-test-home/Library/Mail/V11",
    "/tmp/apple-gateway-test-home/Library/Mail/V11/MailData"
  ], readableFiles: [
    overrideRoot.appendingPathComponent("MailData/Envelope Index").path,
    "/tmp/apple-gateway-test-home/Library/Mail/V11/MailData/Envelope Index"
  ])
  let config = AppleGatewayConfig(mail: .init(mailRoot: overrideRoot.path))

  let result = try MailRootResolver(fileSystem: fileSystem, homeDirectory: home).resolve(config: config)

  #expect(result.root.path == overrideRoot.path)
  #expect(result.envelopeIndex.path == overrideRoot.appendingPathComponent("MailData/Envelope Index").path)
}

@Test func mailRootResolverProbesNewestSupportedRootFirst() throws {
  let home = URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
  let v11 = home.appendingPathComponent("Library/Mail/V11", isDirectory: true)
  let v10 = home.appendingPathComponent("Library/Mail/V10", isDirectory: true)
  let fileSystem = FakeMailFileSystem(readableDirectories: [
    v11.path,
    v11.appendingPathComponent("MailData", isDirectory: true).path,
    v10.path,
    v10.appendingPathComponent("MailData", isDirectory: true).path
  ], readableFiles: [
    v11.appendingPathComponent("MailData/Envelope Index").path,
    v10.appendingPathComponent("MailData/Envelope Index").path
  ])

  let result = try MailRootResolver(fileSystem: fileSystem, homeDirectory: home).resolve(config: .defaultValue)

  #expect(result.root.path == v11.path)
}

@Test func mailRootResolverReportsMissingStore() throws {
  let resolver = MailRootResolver(
    fileSystem: FakeMailFileSystem(readableDirectories: [], readableFiles: []),
    homeDirectory: URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
  )

  do {
    _ = try resolver.resolve(config: .defaultValue)
    Issue.record("Expected missing Mail store error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .mailStoreNotFound)
    #expect(error.details?["expectedFile"] == "MailData/Envelope Index")
  }
}

@Test func mailRootResolverReportsFullDiskAccessForUnreadableRoot() throws {
  let root = URL(fileURLWithPath: "/tmp/apple-gateway-test-home/Library/Mail/V11", isDirectory: true)
  let fileSystem = FakeMailFileSystem(
    readableDirectories: [],
    readableFiles: [],
    unreadableDirectories: [root.path]
  )
  let resolver = MailRootResolver(
    fileSystem: fileSystem,
    homeDirectory: URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
  )

  do {
    _ = try resolver.resolve(config: .defaultValue)
    Issue.record("Expected Full Disk Access error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fullDiskAccessRequired)
    #expect(error.details?["settingsURL"] == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    #expect(error.details?["path"] == root.path)
  }
}

@Test func mailRootResolverReportsFullDiskAccessForUnreadableEnvelopeIndex() throws {
  let root = URL(fileURLWithPath: "/tmp/apple-gateway-test-home/Library/Mail/V11", isDirectory: true)
  let mailData = root.appendingPathComponent("MailData", isDirectory: true)
  let envelopeIndex = mailData.appendingPathComponent("Envelope Index")
  let fileSystem = FakeMailFileSystem(
    readableDirectories: [root.path, mailData.path],
    readableFiles: [],
    unreadableFiles: [envelopeIndex.path]
  )
  let resolver = MailRootResolver(
    fileSystem: fileSystem,
    homeDirectory: URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
  )

  do {
    _ = try resolver.resolve(config: .defaultValue)
    Issue.record("Expected Full Disk Access error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fullDiskAccessRequired)
    #expect(error.details?["settingsURL"] == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    #expect(error.details?["path"] == envelopeIndex.path)
    #expect(error.details?["resource"] == "Envelope Index")
  }
}

@Test func mailEnvelopeIndexStoreOpensOnlyReadOnlyImmutableSnapshot() throws {
  let root = URL(fileURLWithPath: "/tmp/apple-gateway-test-home/Library/Mail/V10", isDirectory: true)
  let liveIndex = root.appendingPathComponent("MailData/Envelope Index")
  let snapshotPath = "/tmp/apple-gateway/snapshots/mail/hash/Envelope Index"
  let snapshotter = RecordingSnapshotter(snapshotPath: snapshotPath)
  let opener = RecordingSQLiteOpener()
  let fileSystem = FakeMailFileSystem(readableDirectories: [
    root.path,
    root.appendingPathComponent("MailData", isDirectory: true).path
  ], readableFiles: [
    liveIndex.path
  ])
  let store = MailEnvelopeIndexStore(
    rootResolver: MailRootResolver(
      fileSystem: fileSystem,
      homeDirectory: URL(fileURLWithPath: "/tmp/apple-gateway-test-home", isDirectory: true)
    ),
    snapshotter: snapshotter,
    sqliteOpener: opener
  )

  _ = try store.open(config: .defaultValue)

  #expect(snapshotter.sourcePath == liveIndex.path)
  #expect(snapshotter.sourceId?.hasPrefix("mail-root-") == true)
  #expect(snapshotter.sourceId?.contains("/") == false)
  #expect(snapshotter.sourceId != root.path)
  #expect(opener.request?.snapshotPath == snapshotPath)
  #expect(opener.request?.uri.hasPrefix(URL(fileURLWithPath: snapshotPath).absoluteString) == true)
  #expect(opener.request?.uri.hasSuffix("?mode=ro&immutable=1") == true)
  #expect(opener.request?.uri.contains(URL(fileURLWithPath: liveIndex.path).absoluteString) == false)
  #expect(opener.request?.flags == MailSQLiteOpenFlags.readOnly | MailSQLiteOpenFlags.uri)
  #expect((opener.request?.flags ?? 0) & MailSQLiteOpenFlags.readWrite == 0)
  #expect((opener.request?.flags ?? 0) & MailSQLiteOpenFlags.create == 0)
}

@Test func mailSQLiteOpensReadOnlyImmutableSnapshotAndRunsSmokeStatement() throws {
  let root = try makeMailTemporaryRoot()
  let live = root.appendingPathComponent("Envelope Index")
  try createSmokeSQLiteDatabase(at: live)
  let snapshot = try FileStore(cacheRoot: root.appendingPathComponent("cache").path)
    .snapshotSQLiteDatabase(sourcePath: live.path, domain: .mail, sourceId: "mail-root")
  let request = MailSQLiteOpenRequest(
    snapshotPath: snapshot.databasePath,
    uri: MailSQLiteDatabase.immutableReadOnlyURI(forSnapshotPath: snapshot.databasePath),
    flags: MailSQLiteOpenFlags.mailReadOnlySnapshot
  )
  let database = try #require(try LiveMailSQLiteOpener().open(request) as? MailSQLiteDatabase)
  let statement = try database.prepare("SELECT value FROM smoke")

  #expect(try statement.step() == .row)
  #expect(statement.int64(at: 0) == 1)
  #expect(try statement.step() == .done)
}

@Test func snapshotSQLiteDatabaseSkipsCopyWhenDestinationIsCurrent() throws {
  let root = try makeMailTemporaryRoot()
  let live = root.appendingPathComponent("Envelope Index")
  try Data("db".utf8).write(to: live)

  let store = FileStore(cacheRoot: root.appendingPathComponent("cache").path)
  let first = try store.snapshotSQLiteDatabase(sourcePath: live.path, domain: FileStoreDomain.mail, sourceId: "mail-root")
  try Data("snapshot".utf8).write(to: URL(fileURLWithPath: first.databasePath))
  let futureDate = Date(timeIntervalSinceNow: 60)
  try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: first.databasePath)

  let second = try store.snapshotSQLiteDatabase(sourcePath: live.path, domain: FileStoreDomain.mail, sourceId: "mail-root")

  #expect(second.databasePath == first.databasePath)
  #expect(try String(contentsOfFile: second.databasePath, encoding: .utf8) == "snapshot")
}

@Test func snapshotSQLiteDatabaseRefreshesDatabaseAndExactSidecarsWhenSourceMtimeChanges() throws {
  let root = try makeMailTemporaryRoot()
  let live = root.appendingPathComponent("Envelope Index")
  let liveWal = URL(fileURLWithPath: live.path + "-wal")
  let liveShm = URL(fileURLWithPath: live.path + "-shm")
  try Data("db-old".utf8).write(to: live)
  try Data("wal-old".utf8).write(to: liveWal)
  try Data("shm-old".utf8).write(to: liveShm)
  let oldDate = Date(timeIntervalSince1970: 1_000)
  try setModificationDate(oldDate, for: [live, liveWal, liveShm])

  let store = FileStore(cacheRoot: root.appendingPathComponent("cache").path)
  let first = try store.snapshotSQLiteDatabase(sourcePath: live.path, domain: .mail, sourceId: "mail-root")
  let snapshotDatabase = URL(fileURLWithPath: first.databasePath)
  let snapshotWal = URL(fileURLWithPath: first.databasePath + "-wal")
  let snapshotShm = URL(fileURLWithPath: first.databasePath + "-shm")
  try setModificationDate(oldDate, for: [snapshotDatabase, snapshotWal, snapshotShm])

  try Data("db-new".utf8).write(to: live)
  try Data("wal-new".utf8).write(to: liveWal)
  try Data("shm-new".utf8).write(to: liveShm)
  let newDate = Date(timeIntervalSince1970: 2_000)
  try setModificationDate(newDate, for: [live, liveWal, liveShm])

  let second = try store.snapshotSQLiteDatabase(sourcePath: live.path, domain: .mail, sourceId: "mail-root")

  #expect(second.databasePath == first.databasePath)
  #expect(Set(second.copiedPaths) == Set([snapshotDatabase.path, snapshotWal.path, snapshotShm.path]))
  #expect(try String(contentsOf: snapshotDatabase, encoding: .utf8) == "db-new")
  #expect(try String(contentsOf: snapshotWal, encoding: .utf8) == "wal-new")
  #expect(try String(contentsOf: snapshotShm, encoding: .utf8) == "shm-new")
}

private struct FakeMailFileSystem: MailFileSystem {
  var readableDirectories: Set<String>
  var readableFiles: Set<String>
  var unreadableDirectories: Set<String>
  var unreadableFiles: Set<String>

  init(
    readableDirectories: Set<String>,
    readableFiles: Set<String>,
    unreadableDirectories: Set<String> = [],
    unreadableFiles: Set<String> = []
  ) {
    self.readableDirectories = readableDirectories
    self.readableFiles = readableFiles
    self.unreadableDirectories = unreadableDirectories
    self.unreadableFiles = unreadableFiles
  }

  func directoryExists(atPath path: String) -> Bool {
    readableDirectories.contains(path) || unreadableDirectories.contains(path)
  }

  func fileExists(atPath path: String) -> Bool {
    readableFiles.contains(path) || unreadableFiles.contains(path)
  }

  func isReadableFile(atPath path: String) -> Bool {
    readableDirectories.contains(path) || readableFiles.contains(path)
  }
}

private final class RecordingSnapshotter: MailEnvelopeIndexSnapshotting, @unchecked Sendable {
  private let snapshotPath: String
  private(set) var sourcePath: String?
  private(set) var sourceId: String?

  init(snapshotPath: String) {
    self.snapshotPath = snapshotPath
  }

  func snapshotEnvelopeIndex(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult {
    self.sourcePath = sourcePath
    self.sourceId = sourceId
    return FileStoreSnapshotResult(databasePath: snapshotPath, copiedPaths: [snapshotPath])
  }
}

private final class RecordingSQLiteOpener: MailSQLiteOpening, @unchecked Sendable {
  private(set) var request: MailSQLiteOpenRequest?

  func open(_ request: MailSQLiteOpenRequest) throws -> any MailSQLiteDatabaseHandle {
    self.request = request
    return FakeMailSQLiteDatabaseHandle()
  }
}

private final class FakeMailSQLiteDatabaseHandle: MailSQLiteDatabaseHandle, @unchecked Sendable {}

private func makeMailTemporaryRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-mail-tests")
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func setModificationDate(_ date: Date, for urls: [URL]) throws {
  for url in urls {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
  }
}

private func createSmokeSQLiteDatabase(at url: URL) throws {
  var handle: OpaquePointer?
  guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
    throw AppleGatewayError(
      code: .fileOperationFailed,
      message: "Could not create smoke SQLite database",
      details: ["path": url.path]
    )
  }
  defer {
    sqlite3_close(handle)
  }
  let sql = "CREATE TABLE smoke(value INTEGER NOT NULL); INSERT INTO smoke(value) VALUES (1);"
  guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
    throw AppleGatewayError(
      code: .fileOperationFailed,
      message: "Could not initialize smoke SQLite database",
      details: ["path": url.path, "reason": String(cString: sqlite3_errmsg(handle))]
    )
  }
}
