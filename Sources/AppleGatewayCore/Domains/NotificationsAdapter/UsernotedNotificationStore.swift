import CryptoKit
import Foundation

protocol UsernotedNotificationSnapshotting: Sendable {
  func snapshotUsernotedDatabase(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult
}

struct FileStoreUsernotedSnapshotter: UsernotedNotificationSnapshotting {
  var fileStore: FileStore

  func snapshotUsernotedDatabase(sourcePath: String, sourceId: String) throws -> FileStoreSnapshotResult {
    try fileStore.snapshotSQLiteDatabase(sourcePath: sourcePath, domain: .notifications, sourceId: sourceId)
  }
}

enum UsernotedDatabaseAccessStatus: Equatable, Sendable {
  case readable
  case missing
  case denied
}

protocol UsernotedDatabaseAccessChecking: Sendable {
  func accessStatus(path: String) -> UsernotedDatabaseAccessStatus
}

struct LiveUsernotedDatabaseAccessChecker: UsernotedDatabaseAccessChecking {
  func accessStatus(path: String) -> UsernotedDatabaseAccessStatus {
    let descriptor = Darwin.open(path, O_RDONLY)
    if descriptor >= 0 {
      Darwin.close(descriptor)
      return .readable
    }
    if errno == EPERM || errno == EACCES {
      return .denied
    }
    return .missing
  }
}

public struct UsernotedDatabasePathResolver: Sendable {
  private let homeDirectory: String
  private let darwinUserDirectory: String?

  public init(
    homeDirectory: String = NSHomeDirectory(),
    darwinUserDirectory: String? = Self.defaultDarwinUserDirectory()
  ) {
    self.homeDirectory = homeDirectory
    self.darwinUserDirectory = darwinUserDirectory
  }

  public func candidatePaths() -> [String] {
    var paths = [
      URL(fileURLWithPath: homeDirectory)
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        .path
    ]
    if let darwinUserDirectory, !darwinUserDirectory.isEmpty {
      paths.append(
        URL(fileURLWithPath: darwinUserDirectory)
          .appendingPathComponent("com.apple.notificationcenter/db2/db")
          .path
      )
    }
    return paths
  }

  public static func defaultDarwinUserDirectory() -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
    process.arguments = ["DARWIN_USER_DIR"]
    process.standardOutput = output
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    guard process.terminationStatus == 0 else {
      return nil
    }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct UsernotedNotificationStore: Sendable {
  var pathResolver: UsernotedDatabasePathResolver
  var accessChecker: any UsernotedDatabaseAccessChecking
  var snapshotter: any UsernotedNotificationSnapshotting
  var sqliteOpener: any MailSQLiteOpening

  init(
    pathResolver: UsernotedDatabasePathResolver = UsernotedDatabasePathResolver(),
    accessChecker: any UsernotedDatabaseAccessChecking = LiveUsernotedDatabaseAccessChecker(),
    snapshotter: any UsernotedNotificationSnapshotting,
    sqliteOpener: any MailSQLiteOpening = LiveMailSQLiteOpener()
  ) {
    self.pathResolver = pathResolver
    self.accessChecker = accessChecker
    self.snapshotter = snapshotter
    self.sqliteOpener = sqliteOpener
  }

  init(config: AppleGatewayConfig) {
    let fileStore = FileStore(cacheRoot: config.storage.cacheDir.expandingTildeInUsernotedPath)
    self.init(snapshotter: FileStoreUsernotedSnapshotter(fileStore: fileStore))
  }

  func openDatabase() throws -> MailSQLiteDatabase {
    let sourcePath = try resolvedSourcePath()
    let snapshot = try snapshotter.snapshotUsernotedDatabase(
      sourcePath: sourcePath,
      sourceId: Self.sourceId(for: sourcePath)
    )
    let request = MailSQLiteOpenRequest(
      snapshotPath: snapshot.databasePath,
      uri: MailSQLiteDatabase.immutableReadOnlyURI(forSnapshotPath: snapshot.databasePath),
      flags: MailSQLiteOpenFlags.mailReadOnlySnapshot
    )
    do {
      guard let database = try sqliteOpener.open(request) as? MailSQLiteDatabase else {
        throw AppleGatewayError(
          code: .notificationDBUnavailable,
          message: "Notification database opener returned an unsupported handle",
          details: ["path": request.snapshotPath]
        )
      }
      return database
    } catch let error as AppleGatewayError {
      if error.code == .fileOperationFailed {
        throw AppleGatewayError(
          code: .notificationDBUnavailable,
          message: "Could not open Notification Center database snapshot",
          details: error.details
        )
      }
      throw error
    }
  }

  private func resolvedSourcePath() throws -> String {
    let candidates = pathResolver.candidatePaths()
    var deniedPath: String?
    for path in candidates {
      switch accessChecker.accessStatus(path: path) {
      case .readable:
        return path
      case .denied:
        deniedPath = path
      case .missing:
        continue
      }
    }
    if let deniedPath {
      throw AppleGatewayError(
        code: .fullDiskAccessRequired,
        message: "Full Disk Access is required to read the Notification Center database",
        details: ["path": deniedPath]
      )
    }
    throw AppleGatewayError(
      code: .notificationDBUnavailable,
      message: "Notification Center database was not found",
      details: ["paths": candidates.joined(separator: ":")]
    )
  }

  private static func sourceId(for sourcePath: String) -> String {
    let digest = SHA256.hash(data: Data(sourcePath.utf8))
    let hash = digest.map { String(format: "%02x", $0) }.joined()
    return "usernoted-\(hash)"
  }
}

private extension String {
  var expandingTildeInUsernotedPath: String {
    (self as NSString).expandingTildeInPath
  }
}
