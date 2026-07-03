import CryptoKit
import Foundation

struct MailEnvelopeIndexQueryService: MailProviding, Sendable {
  private static let cocoaEpochOffset: TimeInterval = 978_307_200
  private let database: MailSQLiteDatabase
  private let accountsPlistURL: URL?
  private let limits: AppleGatewayConfig.Limits
  private let fileResolver: any MailMessageFileResolving

  init(
    database: MailSQLiteDatabase,
    accountsPlistURL: URL? = nil,
    limits: AppleGatewayConfig.Limits = .defaultValue,
    fileResolver: any MailMessageFileResolving = EmptyMailMessageFileResolver()
  ) {
    self.database = database
    self.accountsPlistURL = accountsPlistURL
    self.limits = limits
    self.fileResolver = fileResolver
  }

  func accounts() throws -> [MailAccount] {
    let displayNames = MailAccountsPlistDisplayNames(url: accountsPlistURL).load()
    let grouped = Dictionary(grouping: try mailboxRows(), by: \.info.accountKey)
    return grouped.values.compactMap { rows -> MailAccount? in
      guard let row = rows.first else {
        return nil
      }
      return MailAccount(
        id: row.info.accountId,
        name: displayNames.name(for: row.info) ?? row.info.fallbackAccountName,
        kind: row.info.accountKind
      )
    }
    .sorted { lhs, rhs in
      if lhs.name == rhs.name {
        return lhs.id < rhs.id
      }
      return lhs.name < rhs.name
    }
  }

  func mailboxes() throws -> [Mailbox] {
    try mailboxes(accountId: nil)
  }

  func mailboxes(accountId: String?) throws -> [Mailbox] {
    let counts = try mailboxCounts()
    let mailboxes = try mailboxRows().map { row in
      let count = counts[row.rowId] ?? MailboxCount(total: 0, unread: 0)
      return Mailbox(
        id: row.mailboxId,
        accountId: row.info.accountId,
        name: row.info.name,
        path: row.info.path,
        totalCount: count.total,
        unreadCount: count.unread
      )
    }
    .sorted { lhs, rhs in
      if lhs.accountId == rhs.accountId {
        return lhs.path < rhs.path
      }
      return lhs.accountId < rhs.accountId
    }
    guard let accountId else {
      return mailboxes
    }
    guard try accounts().contains(where: { $0.id == accountId }) else {
      throw invalidArgument("Unknown Mail account id")
    }
    return mailboxes.filter { $0.accountId == accountId }
  }

  func messages(input: MailSearchInput) throws -> MailMessageConnection {
    try validate(input: input)
    let rowsByMailboxId = Dictionary(uniqueKeysWithValues: try mailboxRows().map { ($0.mailboxId, $0) })
    let rowsByAccountId = Dictionary(grouping: rowsByMailboxId.values, by: \.info.accountId)
    let selectedMailboxes = try selectedMailboxRows(
      input: input,
      rowsByMailboxId: rowsByMailboxId,
      rowsByAccountId: rowsByAccountId
    )
    let first = try pageSize(input.first)
    let filterHash = filterHash(for: input)
    let allRows = try messageRows(input: input, mailboxRows: selectedMailboxes)
    let offset = try offset(after: input.after, rows: allRows, filterHash: filterHash)
    let pageRows = Array(allRows.dropFirst(offset).prefix(first))
    let edges = try pageRows.map { row in
      MailMessageEdge(
        cursor: MailCursorCodec.cursor(
          filterHash: filterHash,
          dateReceivedCocoa: row.dateReceivedCocoa,
          rowId: row.rowId
        ),
        node: try message(from: row)
      )
    }
    return MailMessageConnection(
      edges: edges,
      pageInfo: PageInfo(
        hasNextPage: offset + edges.count < allRows.count,
        endCursor: edges.last?.cursor
      ),
      totalCount: allRows.count
    )
  }

  func message(messageId: String) throws -> MailMessage? {
    guard let rowId = MailStableIdentifier.messageRowId(messageId) else {
      return nil
    }
    return try messageRow(rowId: rowId).map(message(from:))
  }

  private func validate(input: MailSearchInput) throws {
    if !input.unsupportedFields.isEmpty {
      throw invalidArgument("Unsupported Mail search filters: \(input.unsupportedFields.sorted().joined(separator: ", "))")
    }
    if let receivedAfter = input.receivedAfter,
       let receivedBefore = input.receivedBefore,
       receivedAfter > receivedBefore {
      throw invalidArgument("mailMessages input receivedAfter must not be after receivedBefore")
    }
  }

  private func selectedMailboxRows(
    input: MailSearchInput,
    rowsByMailboxId: [String: MailboxRow],
    rowsByAccountId: [String: [MailboxRow]]
  ) throws -> [MailboxRow] {
    var rows = Array(rowsByMailboxId.values)
    if let accountId = input.accountId {
      guard let accountRows = rowsByAccountId[accountId] else {
        throw invalidArgument("Unknown Mail account id")
      }
      rows = accountRows
    }
    if let mailboxId = input.mailboxId {
      guard let mailbox = rowsByMailboxId[mailboxId] else {
        throw invalidArgument("Unknown Mail mailbox id")
      }
      guard input.accountId == nil || mailbox.info.accountId == input.accountId else {
        throw invalidArgument("Mail mailbox does not belong to account")
      }
      rows = [mailbox]
    }
    return rows
  }

  private func messageRows(input: MailSearchInput, mailboxRows: [MailboxRow]) throws -> [MessageRow] {
    guard !mailboxRows.isEmpty else {
      return []
    }

    var whereClauses = ["m.mailbox IN (\(mailboxRows.map { _ in "?" }.joined(separator: ", ")))"]
    var bindings = mailboxRows.map { SQLiteBinding.int64($0.rowId) }
    addTextFilter(input.subject, expression: "subj.subject", whereClauses: &whereClauses, bindings: &bindings)
    addAddressFilter(input.from, addressRole: nil, whereClauses: &whereClauses, bindings: &bindings)
    addAddressFilter(input.to, addressRole: "to", whereClauses: &whereClauses, bindings: &bindings)
    addQueryFilter(input.query, whereClauses: &whereClauses, bindings: &bindings)
    if let receivedAfter = input.receivedAfter {
      whereClauses.append("m.date_received >= ?")
      bindings.append(.double(Self.cocoaSeconds(from: receivedAfter)))
    }
    if let receivedBefore = input.receivedBefore {
      whereClauses.append("m.date_received < ?")
      bindings.append(.double(Self.cocoaSeconds(from: receivedBefore)))
    }
    if input.unreadOnly {
      whereClauses.append("(m.flags & \(MailMessageFlag.read.rawValue)) = 0")
    }
    if input.flaggedOnly {
      whereClauses.append("(m.flags & \(MailMessageFlag.flagged.rawValue)) != 0")
    }

    let sql = """
      SELECT m.ROWID, m.message_id, m.mailbox, mb.url, subj.subject,
             sender.address, sender.comment, summaries.summary,
             m.date_sent, m.date_received, m.flags
      FROM messages m
      JOIN mailboxes mb ON mb.ROWID = m.mailbox
      LEFT JOIN subjects subj ON subj.ROWID = m.subject
      LEFT JOIN addresses sender ON sender.ROWID = m.sender
      LEFT JOIN summaries ON summaries.message_id = m.ROWID
      WHERE \(whereClauses.joined(separator: " AND "))
      ORDER BY m.date_received IS NULL ASC, m.date_received DESC, m.ROWID DESC
      """
    return try query(sql, bindings: bindings, map: messageRow(from:))
  }

  private func message(from row: MessageRow) throws -> MailMessage {
    MailMessage(
      id: MailStableIdentifier.messageId(rowId: row.rowId),
      mailboxId: row.mailboxId,
      accountId: row.accountId,
      messageId: row.messageId,
      subject: row.subject,
      snippet: row.snippet,
      from: row.sender,
      to: try recipients(messageRowId: row.rowId, role: "to"),
      cc: try recipients(messageRowId: row.rowId, role: "cc"),
      dateSent: row.dateSentCocoa.map(Self.date(fromCocoaSeconds:)),
      dateReceived: row.dateReceivedCocoa.map(Self.date(fromCocoaSeconds:)),
      isRead: row.hasFlag(.read),
      isFlagged: row.hasFlag(.flagged),
      hasAttachments: row.hasFlag(.attachment),
      files: try fileResolver.files(messageRowId: row.rowId)
    )
  }

  private func messageRow(rowId: Int64) throws -> MessageRow? {
    try query(
      """
      SELECT m.ROWID, m.message_id, m.mailbox, mb.url, subj.subject,
             sender.address, sender.comment, summaries.summary,
             m.date_sent, m.date_received, m.flags
      FROM messages m
      JOIN mailboxes mb ON mb.ROWID = m.mailbox
      LEFT JOIN subjects subj ON subj.ROWID = m.subject
      LEFT JOIN addresses sender ON sender.ROWID = m.sender
      LEFT JOIN summaries ON summaries.message_id = m.ROWID
      WHERE m.ROWID = ?
      """,
      bindings: [.int64(rowId)]
    ) { statement in
      self.messageRow(from: statement)
    }
    .first
  }

  private func messageRow(from statement: MailSQLiteStatement) -> MessageRow {
    let rowId = statement.int64(at: 0)
    let mailboxRowId = statement.int64(at: 2)
    let mailboxURL = statement.text(at: 3) ?? ""
    let mailboxInfo = MailboxURLParser.parse(mailboxURL, rowId: mailboxRowId)
    return MessageRow(
      rowId: rowId,
      messageId: statement.text(at: 1),
      mailboxId: MailStableIdentifier.mailboxId(rowId: mailboxRowId, accountKey: mailboxInfo.accountKey),
      accountId: mailboxInfo.accountId,
      subject: statement.text(at: 4),
      sender: address(email: statement.text(at: 5), name: statement.text(at: 6)),
      snippet: statement.text(at: 7),
      dateSentCocoa: statement.isNull(at: 8) ? nil : statement.double(at: 8),
      dateReceivedCocoa: statement.isNull(at: 9) ? nil : statement.double(at: 9),
      flags: statement.int64(at: 10)
    )
  }

  private func addTextFilter(
    _ value: String?,
    expression: String,
    whereClauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) {
    guard let pattern = likePattern(value) else {
      return
    }
    whereClauses.append("\(expression) LIKE ? ESCAPE '\\' COLLATE NOCASE")
    bindings.append(.text(pattern))
  }

  private func addAddressFilter(
    _ value: String?,
    addressRole: String?,
    whereClauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) {
    guard let pattern = likePattern(value) else {
      return
    }
    if let addressRole {
      whereClauses.append("""
        EXISTS (
          SELECT 1 FROM recipients r
          JOIN addresses a ON a.ROWID = r.address_id
          WHERE r.message_id = m.ROWID AND r.type = ?
            AND (a.address LIKE ? ESCAPE '\\' COLLATE NOCASE
                 OR a.comment LIKE ? ESCAPE '\\' COLLATE NOCASE)
        )
        """)
      bindings.append(.text(addressRole))
      bindings.append(.text(pattern))
      bindings.append(.text(pattern))
    } else {
      whereClauses.append("""
        (sender.address LIKE ? ESCAPE '\\' COLLATE NOCASE
         OR sender.comment LIKE ? ESCAPE '\\' COLLATE NOCASE)
        """)
      bindings.append(.text(pattern))
      bindings.append(.text(pattern))
    }
  }

  private func addQueryFilter(
    _ value: String?,
    whereClauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) {
    guard let pattern = likePattern(value) else {
      return
    }
    whereClauses.append("""
      (subj.subject LIKE ? ESCAPE '\\' COLLATE NOCASE
       OR sender.address LIKE ? ESCAPE '\\' COLLATE NOCASE
       OR sender.comment LIKE ? ESCAPE '\\' COLLATE NOCASE
       OR summaries.summary LIKE ? ESCAPE '\\' COLLATE NOCASE)
      """)
    bindings.append(contentsOf: [.text(pattern), .text(pattern), .text(pattern), .text(pattern)])
  }

  private func likePattern(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return "%\(Self.escapeLike(value))%"
  }

  private static func escapeLike(_ value: String) -> String {
    value.reduce(into: "") { result, character in
      if character == "\\" || character == "%" || character == "_" {
        result.append("\\")
      }
      result.append(character)
    }
  }

  private func mailboxRows() throws -> [MailboxRow] {
    try query("SELECT ROWID, url FROM mailboxes ORDER BY ROWID", bindings: []) { statement in
      let rowId = statement.int64(at: 0)
      let url = statement.text(at: 1) ?? ""
      return MailboxRow(rowId: rowId, url: url, info: MailboxURLParser.parse(url, rowId: rowId))
    }
  }

  private func mailboxCounts() throws -> [Int64: MailboxCount] {
    let rows: [MailboxCountRow] = try query(
      """
      SELECT mailbox,
             COUNT(*) AS total_count,
             SUM(CASE WHEN (flags & \(MailMessageFlag.read.rawValue)) = 0 THEN 1 ELSE 0 END) AS unread_count
      FROM messages
      GROUP BY mailbox
      """,
      bindings: []
    ) { statement in
      MailboxCountRow(
        mailboxRowId: statement.int64(at: 0),
        count: MailboxCount(total: statement.int(at: 1), unread: statement.int(at: 2))
      )
    }
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.mailboxRowId, $0.count) })
  }

  private func recipients(messageRowId: Int64, role: String) throws -> [MailAddress] {
    try query(
      """
      SELECT a.address, a.comment
      FROM recipients r
      JOIN addresses a ON a.ROWID = r.address_id
      WHERE r.message_id = ? AND r.type = ?
      ORDER BY r.ROWID
      """,
      bindings: [.int64(messageRowId), .text(role)]
    ) { statement in
      address(email: statement.text(at: 0), name: statement.text(at: 1))
    }
    .compactMap { $0 }
  }

  private func address(email: String?, name: String?) -> MailAddress? {
    let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmedEmail, !trimmedEmail.isEmpty {
      let raw = if let trimmedName, !trimmedName.isEmpty {
        "\(trimmedName) <\(trimmedEmail)>"
      } else {
        trimmedEmail
      }
      return MailAddress(raw: raw, name: trimmedName?.nilIfEmpty, email: trimmedEmail)
    }
    if let trimmedName, !trimmedName.isEmpty {
      return MailAddress(raw: trimmedName, name: trimmedName)
    }
    return nil
  }

  private func offset(after cursor: String?, rows: [MessageRow], filterHash: String) throws -> Int {
    guard let cursor else {
      return 0
    }
    let payload = try MailCursorCodec.payload(from: cursor)
    guard payload.filterHash == filterHash else {
      throw invalidArgument("Invalid pagination cursor")
    }
    guard let index = rows.firstIndex(where: {
      $0.rowId == payload.rowId && $0.dateReceivedCocoa == payload.dateReceivedCocoa
    }) else {
      throw invalidArgument("Invalid pagination cursor")
    }
    return index + 1
  }

  private func pageSize(_ requested: Int?) throws -> Int {
    let value = requested ?? limits.defaultPageSize
    guard value > 0 else {
      throw invalidArgument("first must be positive")
    }
    return min(value, limits.maxPageSize)
  }

  private func filterHash(for input: MailSearchInput) -> String {
    let values = [
      input.accountId ?? "",
      input.mailboxId ?? "",
      input.query ?? "",
      input.from ?? "",
      input.to ?? "",
      input.subject ?? "",
      input.receivedAfter.map { String($0.timeIntervalSince1970) } ?? "",
      input.receivedBefore.map { String($0.timeIntervalSince1970) } ?? "",
      String(input.unreadOnly),
      String(input.flaggedOnly)
    ].joined(separator: "\u{1f}")
    return SHA256.hash(data: Data(values.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func date(fromCocoaSeconds value: Double) -> Date {
    Date(timeIntervalSince1970: value + cocoaEpochOffset)
  }

  private static func cocoaSeconds(from date: Date) -> Double {
    date.timeIntervalSince1970 - cocoaEpochOffset
  }

  private func query<T>(
    _ sql: String,
    bindings: [SQLiteBinding],
    map: (MailSQLiteStatement) throws -> T
  ) throws -> [T] {
    let statement = try database.prepare(sql)
    defer {
      statement.finalize()
    }
    for (index, binding) in bindings.enumerated() {
      try binding.bind(to: statement, at: Int32(index + 1))
    }
    var rows: [T] = []
    while try statement.step() == .row {
      rows.append(try map(statement))
    }
    return rows
  }

  private func invalidArgument(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private enum MailMessageFlag: Int64 {
  case read = 1
  case flagged = 16
  case attachment = 1_024
}

private enum SQLiteBinding {
  case text(String)
  case int64(Int64)
  case double(Double)
  case null

  func bind(to statement: MailSQLiteStatement, at index: Int32) throws {
    switch self {
    case .text(let value):
      try statement.bind(value, at: index)
    case .int64(let value):
      try statement.bind(value, at: index)
    case .double(let value):
      try statement.bind(value, at: index)
    case .null:
      try statement.bindNull(at: index)
    }
  }
}

private struct MailboxRow: Sendable {
  var rowId: Int64
  var url: String
  var info: MailboxURLInfo

  var mailboxId: String {
    MailStableIdentifier.mailboxId(rowId: rowId, accountKey: info.accountKey)
  }
}

private struct MailboxCount: Sendable {
  var total: Int
  var unread: Int
}

private struct MailboxCountRow: Sendable {
  var mailboxRowId: Int64
  var count: MailboxCount
}

private struct MessageRow: Sendable {
  var rowId: Int64
  var messageId: String?
  var mailboxId: String
  var accountId: String
  var subject: String?
  var sender: MailAddress?
  var snippet: String?
  var dateSentCocoa: Double?
  var dateReceivedCocoa: Double?
  var flags: Int64

  func hasFlag(_ flag: MailMessageFlag) -> Bool {
    (flags & flag.rawValue) != 0
  }
}

private enum MailCursorCodec {
  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  static func cursor(filterHash: String, dateReceivedCocoa: Double?, rowId: Int64) -> String {
    let payload = MailCursorPayload(
      filterHash: filterHash,
      dateReceivedCocoa: dateReceivedCocoa,
      rowId: rowId
    )
    let data = (try? encoder.encode(payload)) ?? Data()
    return data.base64EncodedString()
  }

  static func payload(from cursor: String) throws -> MailCursorPayload {
    guard
      let data = Data(base64Encoded: cursor),
      let payload = try? decoder.decode(MailCursorPayload.self, from: data),
      !payload.filterHash.isEmpty,
      payload.rowId > 0
    else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid pagination cursor")
    }
    return payload
  }
}

private struct MailCursorPayload: Codable {
  var filterHash: String
  var dateReceivedCocoa: Double?
  var rowId: Int64
}

private struct MailAccountsPlistDisplayNames {
  var url: URL?

  func load() -> MailAccountDisplayNames {
    guard
      let url,
      let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    else {
      return MailAccountDisplayNames(namesByKey: [:])
    }
    var names: [String: String] = [:]
    collectNames(from: plist, names: &names)
    return MailAccountDisplayNames(namesByKey: names)
  }

  private func collectNames(from value: Any, names: inout [String: String]) {
    if let array = value as? [Any] {
      array.forEach { collectNames(from: $0, names: &names) }
      return
    }
    guard let dictionary = value as? [String: Any] else {
      return
    }
    let displayName = string(in: dictionary, keys: ["AccountName", "DisplayName", "Name", "FullUserName"])
    let host = string(in: dictionary, keys: ["Hostname", "HostName", "ServerName"])
    let username = string(in: dictionary, keys: ["Username", "UserName", "EmailAddress"])
    if let displayName {
      [host, username, username.flatMap { user in host.map { "\(user)@\($0)" } }, displayName]
        .compactMap { $0?.lowercased() }
        .forEach { names[$0] = displayName }
    }
    dictionary.values.forEach { collectNames(from: $0, names: &names) }
  }

  private func string(in dictionary: [String: Any], keys: [String]) -> String? {
    keys.lazy.compactMap { dictionary[$0] as? String }.first?.nilIfEmpty
  }
}

private struct MailAccountDisplayNames {
  var namesByKey: [String: String]

  func name(for info: MailboxURLInfo) -> String? {
    lookupKeys(for: info).lazy.compactMap { namesByKey[$0.lowercased()] }.first
  }

  private func lookupKeys(for info: MailboxURLInfo) -> [String] {
    let accountPart = info.accountKey.split(separator: "://", maxSplits: 1).last.map(String.init) ?? info.accountKey
    var keys = [accountPart, info.fallbackAccountName]
    if let host = accountPart.split(separator: "@").last {
      keys.append(String(host))
    }
    if info.accountKind == .local {
      keys.append("local")
      keys.append("On My Mac")
    }
    return keys
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
