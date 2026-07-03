import Foundation
import Testing
@testable import AppleGatewayCore

@Test func mailRootResolverUsesConfiguredRootBeforeProbing() throws {
  let overrideRoot = URL(fileURLWithPath: "/Custom/Mail/V10", isDirectory: true)
  let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
  let fileSystem = FakeMailFileSystem(readableDirectories: [
    overrideRoot.path,
    overrideRoot.appendingPathComponent("MailData", isDirectory: true).path,
    "/Users/test/Library/Mail/V11",
    "/Users/test/Library/Mail/V11/MailData"
  ], readableFiles: [
    overrideRoot.appendingPathComponent("MailData/Envelope Index").path,
    "/Users/test/Library/Mail/V11/MailData/Envelope Index"
  ])
  let config = AppleGatewayConfig(mail: .init(mailRoot: overrideRoot.path))

  let result = try MailRootResolver(fileSystem: fileSystem, homeDirectory: home).resolve(config: config)

  #expect(result.root.path == overrideRoot.path)
  #expect(result.envelopeIndex.path == overrideRoot.appendingPathComponent("MailData/Envelope Index").path)
}

@Test func mailRootResolverProbesNewestSupportedRootFirst() throws {
  let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
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
    homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true)
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
  let root = URL(fileURLWithPath: "/Users/test/Library/Mail/V11", isDirectory: true)
  let fileSystem = FakeMailFileSystem(
    readableDirectories: [],
    readableFiles: [],
    unreadableDirectories: [root.path]
  )
  let resolver = MailRootResolver(
    fileSystem: fileSystem,
    homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true)
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

@Test func mailEnvelopeIndexStoreOpensOnlyReadOnlyImmutableSnapshot() throws {
  let root = URL(fileURLWithPath: "/Users/test/Library/Mail/V10", isDirectory: true)
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
      homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true)
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
