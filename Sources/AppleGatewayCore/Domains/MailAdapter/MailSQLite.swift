import Foundation
import SQLite3

struct MailSQLiteOpenFlags {
  static let readOnly = SQLITE_OPEN_READONLY
  static let uri = SQLITE_OPEN_URI
  static let readWrite = SQLITE_OPEN_READWRITE
  static let create = SQLITE_OPEN_CREATE
  static let mailReadOnlySnapshot = readOnly | uri
}

struct MailSQLiteOpenRequest: Equatable, Sendable {
  var snapshotPath: String
  var uri: String
  var flags: Int32
}

protocol MailSQLiteDatabaseHandle: AnyObject, Sendable {}

protocol MailSQLiteOpening: Sendable {
  func open(_ request: MailSQLiteOpenRequest) throws -> any MailSQLiteDatabaseHandle
}

struct LiveMailSQLiteOpener: MailSQLiteOpening {
  func open(_ request: MailSQLiteOpenRequest) throws -> any MailSQLiteDatabaseHandle {
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(request.uri, &handle, request.flags, nil)
    guard result == SQLITE_OK, let handle else {
      let reason = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
      if let handle {
        sqlite3_close(handle)
      }
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Could not open Apple Mail Envelope Index snapshot",
        details: ["path": request.snapshotPath, "reason": reason]
      )
    }
    return MailSQLiteDatabase(handle: handle, path: request.snapshotPath)
  }
}

final class MailSQLiteDatabase: @unchecked Sendable, MailSQLiteDatabaseHandle {
  private var handle: OpaquePointer?
  let path: String

  init(handle: OpaquePointer, path: String) {
    self.handle = handle
    self.path = path
  }

  deinit {
    close()
  }

  static func immutableReadOnlyURI(forSnapshotPath path: String) -> String {
    URL(fileURLWithPath: path).absoluteString + "?mode=ro&immutable=1"
  }

  func prepare(_ sql: String) throws -> MailSQLiteStatement {
    guard let handle else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "SQLite database is closed",
        details: ["path": path]
      )
    }
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else {
      throw sqliteError(message: "Could not prepare SQLite statement")
    }
    return MailSQLiteStatement(database: self, statement: statement)
  }

  func close() {
    if let handle {
      sqlite3_close(handle)
      self.handle = nil
    }
  }

  fileprivate func sqliteError(message: String) -> AppleGatewayError {
    let reason = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite handle is closed"
    return AppleGatewayError(
      code: .fileOperationFailed,
      message: message,
      details: ["path": path, "reason": reason]
    )
  }
}

enum MailSQLiteStepResult: Equatable, Sendable {
  case row
  case done
}

final class MailSQLiteStatement: @unchecked Sendable {
  private let database: MailSQLiteDatabase
  private var statement: OpaquePointer?

  init(database: MailSQLiteDatabase, statement: OpaquePointer) {
    self.database = database
    self.statement = statement
  }

  deinit {
    finalize()
  }

  func step() throws -> MailSQLiteStepResult {
    guard let statement else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "SQLite statement is finalized",
        details: ["path": database.path]
      )
    }
    switch sqlite3_step(statement) {
    case SQLITE_ROW:
      return .row
    case SQLITE_DONE:
      return .done
    default:
      throw database.sqliteError(message: "Could not step SQLite statement")
    }
  }

  func int64(at index: Int32) -> Int64 {
    sqlite3_column_int64(statement, index)
  }

  func double(at index: Int32) -> Double {
    sqlite3_column_double(statement, index)
  }

  func text(at index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else {
      return nil
    }
    return String(cString: value)
  }

  func finalize() {
    if let statement {
      sqlite3_finalize(statement)
      self.statement = nil
    }
  }
}
