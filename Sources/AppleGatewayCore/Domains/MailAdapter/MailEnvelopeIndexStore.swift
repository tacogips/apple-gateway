import Foundation

protocol MailEnvelopeIndexSnapshotting: Sendable {
  func snapshotEnvelopeIndex(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult
}

struct FileStoreMailEnvelopeIndexSnapshotter: MailEnvelopeIndexSnapshotting {
  var fileStore: FileStore

  func snapshotEnvelopeIndex(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult {
    try fileStore.snapshotSQLiteDatabase(sourcePath: sourcePath, domain: .mail, sourceId: sourceId)
  }
}

struct MailEnvelopeIndexStore: Sendable {
  var rootResolver: MailRootResolver
  var snapshotter: any MailEnvelopeIndexSnapshotting
  var sqliteOpener: any MailSQLiteOpening

  init(
    rootResolver: MailRootResolver = MailRootResolver(),
    snapshotter: any MailEnvelopeIndexSnapshotting,
    sqliteOpener: any MailSQLiteOpening = LiveMailSQLiteOpener()
  ) {
    self.rootResolver = rootResolver
    self.snapshotter = snapshotter
    self.sqliteOpener = sqliteOpener
  }

  init(config: AppleGatewayConfig) {
    let fileStore = FileStore(cacheRoot: config.storage.cacheDir.expandingTildeInMailPath)
    self.init(snapshotter: FileStoreMailEnvelopeIndexSnapshotter(fileStore: fileStore))
  }

  @discardableResult
  func open(config: AppleGatewayConfig) throws -> any MailSQLiteDatabaseHandle {
    let paths = try rootResolver.resolve(config: config)
    let snapshot = try snapshotter.snapshotEnvelopeIndex(
      sourcePath: paths.envelopeIndex.path,
      sourceId: paths.root.path
    )
    let request = MailSQLiteOpenRequest(
      snapshotPath: snapshot.databasePath,
      uri: MailSQLiteDatabase.immutableReadOnlyURI(forSnapshotPath: snapshot.databasePath),
      flags: MailSQLiteOpenFlags.mailReadOnlySnapshot
    )
    return try sqliteOpener.open(request)
  }
}

private extension String {
  var expandingTildeInMailPath: String {
    (self as NSString).expandingTildeInPath
  }
}
