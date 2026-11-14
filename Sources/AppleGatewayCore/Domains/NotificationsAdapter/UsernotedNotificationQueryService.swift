import Foundation

struct UsernotedNotificationQueryService: Sendable {
  private static let coreFoundationEpochOffset: TimeInterval = 978_307_200
  private let database: MailSQLiteDatabase
  private let limits: AppleGatewayConfig.Limits

  init(database: MailSQLiteDatabase, limits: AppleGatewayConfig.Limits = .defaultValue) {
    self.database = database
    self.limits = limits
  }

  func notifications(input: NotificationSearchInput = NotificationSearchInput()) throws -> DeliveredNotificationConnection {
    try validate(input: input)
    let rows = try notificationRows(schema: try schema()).filter { row in
      if let appBundleId = input.appBundleId, row.appBundleId != appBundleId {
        return false
      }
      if let deliveredAfter = input.deliveredAfter, row.deliveredAt < deliveredAfter {
        return false
      }
      if let deliveredBefore = input.deliveredBefore, row.deliveredAt >= deliveredBefore {
        return false
      }
      return true
    }
    .sorted { lhs, rhs in
      if lhs.deliveredAt == rhs.deliveredAt {
        return lhs.rowId > rhs.rowId
      }
      return lhs.deliveredAt > rhs.deliveredAt
    }

    let offset = try offset(after: input.after, rows: rows)
    let first = try pageSize(input.first)
    var warnings: [NotificationListingWarning] = []
    var edges: [DeliveredNotificationEdge] = []
    var consumedRows = 0
    for row in rows.dropFirst(offset) {
      guard edges.count < first else {
        break
      }
      consumedRows += 1
      do {
        let content = try UsernotedNotificationContentDecoder.decode(row.data)
        edges.append(DeliveredNotificationEdge(
          cursor: cursor(rowId: row.rowId),
          node: DeliveredNotification(
            id: "system-db-\(row.rowId)",
            source: .systemDb,
            appBundleId: row.appBundleId,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            deliveredAt: ISO8601DateFormatter().string(from: row.deliveredAt)
          )
        ))
      } catch {
        warnings.append(NotificationListingWarning(
          id: "system-db-\(row.rowId)",
          message: "Skipped undecodable Notification Center payload"
        ))
      }
    }

    return DeliveredNotificationConnection(
      edges: edges,
      pageInfo: PageInfo(
        hasNextPage: offset + consumedRows < rows.count,
        endCursor: edges.last?.cursor
      ),
      totalCount: rows.count,
      warnings: warnings
    )
  }

  private func validate(input: NotificationSearchInput) throws {
    guard input.source == .systemDb else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Usernoted notification listing only supports SYSTEM_DB source"
      )
    }
    if let deliveredAfter = input.deliveredAfter,
       let deliveredBefore = input.deliveredBefore,
       deliveredAfter > deliveredBefore {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "notifications input deliveredAfter must not be after deliveredBefore"
      )
    }
  }

  private func notificationRows(schema: UsernotedSchema) throws -> [UsernotedNotificationRow] {
    let sql = """
      SELECT r.\(schema.recordIdColumn.sql), a.\(schema.appBundleColumn.sql),
             r.\(schema.deliveredDateColumn.sql), r.\(schema.dataColumn.sql)
      FROM record r
      LEFT JOIN app a ON a.\(schema.appJoinColumn.sql) = r.\(schema.recordAppColumn.sql)
      WHERE r.\(schema.deliveredDateColumn.sql) IS NOT NULL
      ORDER BY r.\(schema.deliveredDateColumn.sql) DESC, r.\(schema.recordIdColumn.sql) DESC
      """
    let statement = try unavailableOnSQLiteError {
      try database.prepare(sql)
    }
    var rows: [UsernotedNotificationRow] = []
    while try unavailableOnSQLiteError({ try statement.step() }) == .row {
      guard let data = statement.blob(at: 3) else {
        continue
      }
      rows.append(UsernotedNotificationRow(
        rowId: statement.int64(at: 0),
        appBundleId: statement.text(at: 1),
        deliveredAt: Self.date(fromCoreFoundationSeconds: statement.double(at: 2)),
        data: data
      ))
    }
    return rows
  }

  private func schema() throws -> UsernotedSchema {
    let appColumns = try tableColumns("app")
    let recordColumns = try tableColumns("record")
    guard
      let appJoin = firstColumn(["app_id", "ROWID"], in: appColumns),
      let appBundle = firstColumn(["identifier", "bundleid", "bundle_id", "bundle"], in: appColumns),
      let recordId = firstColumn(["record_id", "rec_id", "ROWID"], in: recordColumns),
      let recordApp = firstColumn(["app_id", "app", "appId"], in: recordColumns),
      let deliveredDate = firstColumn(["delivered_date", "deliveredDate", "date"], in: recordColumns),
      let data = firstColumn(["data", "plist", "payload"], in: recordColumns)
    else {
      throw AppleGatewayError(
        code: .notificationDBUnavailable,
        message: "Notification Center database schema is unsupported",
        details: [
          "appColumns": appColumns.sorted().joined(separator: ","),
          "recordColumns": recordColumns.sorted().joined(separator: ",")
        ]
      )
    }
    return UsernotedSchema(
      appJoinColumn: appJoin,
      appBundleColumn: appBundle,
      recordIdColumn: recordId,
      recordAppColumn: recordApp,
      deliveredDateColumn: deliveredDate,
      dataColumn: data
    )
  }

  private func tableColumns(_ table: String) throws -> Set<String> {
    let statement = try unavailableOnSQLiteError {
      try database.prepare("PRAGMA table_info(\(table))")
    }
    var columns = Set<String>()
    while try unavailableOnSQLiteError({ try statement.step() }) == .row {
      if let name = statement.text(at: 1) {
        columns.insert(name)
      }
    }
    return columns
  }

  private func firstColumn(_ candidates: [String], in columns: Set<String>) -> UsernotedColumn? {
    candidates.first { columns.contains($0) }.map(UsernotedColumn.init(name:))
  }

  private func pageSize(_ requested: Int?) throws -> Int {
    let value = requested ?? limits.defaultPageSize
    guard value > 0 else {
      throw AppleGatewayError(code: .invalidArgument, message: "first must be positive")
    }
    return min(value, limits.maxPageSize)
  }

  private func offset(after cursor: String?, rows: [UsernotedNotificationRow]) throws -> Int {
    guard let cursor else {
      return 0
    }
    guard let rowId = rowId(fromCursor: cursor),
          let index = rows.firstIndex(where: { $0.rowId == rowId }) else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid pagination cursor")
    }
    return index + 1
  }

  private func cursor(rowId: Int64) -> String {
    "notification:\(rowId)"
  }

  private func rowId(fromCursor cursor: String) -> Int64? {
    guard cursor.hasPrefix("notification:") else {
      return nil
    }
    return Int64(cursor.dropFirst("notification:".count))
  }

  private func unavailableOnSQLiteError<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as AppleGatewayError where error.code == .fileOperationFailed {
      throw AppleGatewayError(
        code: .notificationDBUnavailable,
        message: "Notification Center database schema is unavailable",
        details: error.details
      )
    }
  }

  private static func date(fromCoreFoundationSeconds seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds + coreFoundationEpochOffset)
  }
}

private struct UsernotedSchema: Sendable {
  var appJoinColumn: UsernotedColumn
  var appBundleColumn: UsernotedColumn
  var recordIdColumn: UsernotedColumn
  var recordAppColumn: UsernotedColumn
  var deliveredDateColumn: UsernotedColumn
  var dataColumn: UsernotedColumn
}

private struct UsernotedColumn: Sendable {
  var name: String

  var sql: String {
    "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

private struct UsernotedNotificationRow: Sendable {
  var rowId: Int64
  var appBundleId: String?
  var deliveredAt: Date
  var data: Data
}

private struct UsernotedNotificationContent: Sendable {
  var title: String?
  var subtitle: String?
  var body: String?
}

private enum UsernotedNotificationContentDecoder {
  static func decode(_ data: Data) throws -> UsernotedNotificationContent {
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return UsernotedNotificationContent(
      title: findString(in: plist, keys: ["title", "titl"]),
      subtitle: findString(in: plist, keys: ["subtitle", "subtitl"]),
      body: findString(in: plist, keys: ["body", "message", "informativetext", "text"])
    )
  }

  private static func findString(in value: Any, keys: Set<String>) -> String? {
    if let dictionary = value as? [String: Any] {
      for (key, child) in dictionary {
        if keys.contains(key.lowercased()), let string = child as? String {
          return string
        }
      }
      for child in dictionary.values {
        if let found = findString(in: child, keys: keys) {
          return found
        }
      }
    }
    if let array = value as? [Any] {
      for child in array {
        if let found = findString(in: child, keys: keys) {
          return found
        }
      }
    }
    return nil
  }
}
