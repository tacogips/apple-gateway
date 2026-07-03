import Foundation

public struct NotesReadService: Sendable {
  private let provider: any NotesProviding
  private let limits: AppleGatewayConfig.Limits
  private let fileStore: FileStore

  public init(
    provider: any NotesProviding,
    limits: AppleGatewayConfig.Limits = .defaultValue,
    fileStore: FileStore = FileStore(cacheRoot: AppleGatewayConfig.Storage.defaultValue.cacheDir)
  ) {
    self.provider = provider
    self.limits = limits
    self.fileStore = fileStore
  }

  public func accounts() throws -> [NoteAccount] {
    try provider.accounts()
  }

  public func folders(accountId: String? = nil) throws -> [NoteFolder] {
    try provider.folders(accountId: accountId)
  }

  public func noteMetadata(noteId: String) throws -> Note? {
    switch try provider.noteMetadata(noteId: noteId) {
    case .found(let note):
      return note.withoutBodies()
    case .locked:
      throw AppleGatewayError(code: .noteLocked, message: "Note is password protected")
    case .missing:
      return nil
    }
  }

  public func note(noteId: String, bodyKind: NoteBodyKind = .plaintext) throws -> Note? {
    switch try provider.noteBody(noteId: noteId, kind: bodyKind) {
    case .found(let result):
      return try note(from: result)
    case .locked:
      throw AppleGatewayError(code: .noteLocked, message: "Note is password protected")
    case .missing:
      return nil
    }
  }

  public func notes(input: NoteSearchInput) throws -> NoteConnection {
    if let modifiedAfter = input.modifiedAfter,
       let modifiedBefore = input.modifiedBefore,
       modifiedAfter > modifiedBefore {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "notes input modifiedAfter must not be after modifiedBefore"
      )
    }

    try validateScope(accountId: input.accountId, folderId: input.folderId)
    let first = try pageSize(input.first)
    let offset = try NotesCursorCodec.offset(after: input.after)
    let query = input.query?.trimmingCharacters(in: .whitespacesAndNewlines)
    let batchSize = limits.appleEventBatchSize
    let bodyMatches = try bodyMatchIds(
      query: query,
      accountId: input.accountId,
      folderId: input.folderId
    )
    let candidateIds = try provider.noteIds(
      accountId: input.accountId,
      folderId: input.folderId,
      batchSize: batchSize
    )
    let notes = try provider.noteMetadata(noteIds: candidateIds, batchSize: batchSize)
    .filter { note in
      Self.matchesMetadataFilters(note, input: input)
        && Self.matchesQuery(query, note: note, bodyMatchIds: bodyMatches)
    }
    .map { $0.withoutBodies() }
    .sorted(by: Self.sortNotes)

    var connection = NoteConnection.paginating(notes, first: first, offset: offset)
    if let query, !query.isEmpty {
      let pageIds = connection.edges.map(\.node.id)
      let snippets = try provider.searchSnippets(noteIds: pageIds, query: query, batchSize: batchSize)
      connection.edges = connection.edges.map { edge in
        var note = edge.node
        note.snippet = snippets[note.id] ?? note.snippet
        return NoteEdge(cursor: edge.cursor, node: note)
      }
    }
    return connection
  }

  private func validateScope(accountId: String?, folderId: String?) throws {
    if let accountId {
      let accountExists = try provider.accounts().contains { $0.id == accountId }
      guard accountExists else {
        throw AppleGatewayError(code: .invalidArgument, message: "Unknown Notes account id")
      }
    }

    if let folderId {
      let folderExists = try provider.folders(accountId: accountId).contains { $0.id == folderId }
      guard folderExists else {
        throw AppleGatewayError(code: .noteFolderNotFound, message: "Notes folder not found")
      }
    }
  }

  private func pageSize(_ requested: Int?) throws -> Int {
    let value = requested ?? limits.defaultPageSize
    guard value > 0 else {
      throw AppleGatewayError(code: .invalidArgument, message: "first must be positive")
    }
    return min(value, limits.maxPageSize)
  }

  private func note(from result: NoteBodyFetchResult) throws -> Note {
    var note = result.note.withoutBodies()
    note.attachments = try note.attachments.map { try attachmentWithBestEffortKey($0, noteId: note.id) }
    let byteSize = Data(result.body.utf8).count
    if byteSize <= limits.maxInlineBodyBytes {
      switch result.kind {
      case .plaintext:
        note.plaintext = result.body
      case .html:
        note.bodyHtml = result.body
      }
      return note
    }

    note.bodyFile = NoteBodyFile(
      downloadKey: try bodyDownloadKey(noteId: note.id, kind: result.kind),
      kind: result.kind,
      byteSize: byteSize
    )
    return note
  }

  private func bodyDownloadKey(noteId: String, kind: NoteBodyKind) throws -> String {
    try fileStore.issueDownloadKey(
      FileStoreDownloadKeyPayload(
        domain: .notes,
        sourceId: NotesFileStoreIdentifier.encode(noteId),
        kind: kind.fileStoreKind,
        filename: kind.defaultFilename
      )
    )
  }

  private func attachmentWithBestEffortKey(_ attachment: NoteAttachment, noteId: String) throws -> NoteAttachment {
    guard attachment.downloadKey == nil, !attachment.id.isEmpty else {
      return attachment
    }
    var keyed = attachment
    keyed.downloadKey = try? fileStore.issueDownloadKey(
      FileStoreDownloadKeyPayload(
        domain: .notes,
        sourceId: NotesFileStoreIdentifier.encode(noteId),
        sourceIds: ["attachmentId": NotesFileStoreIdentifier.encode(attachment.id)],
        kind: .attachment,
        filename: NotesFileStoreIdentifier.sanitizedFilename(attachment.name, fallback: "attachment.bin")
      )
    )
    return keyed
  }

  private func bodyMatchIds(query: String?, accountId: String?, folderId: String?) throws -> Set<String> {
    guard let query, !query.isEmpty else {
      return []
    }
    let ids = try provider.bodySearchNoteIds(
      input: NotesBodySearchInput(accountId: accountId, folderId: folderId, query: query),
      batchSize: limits.appleEventBatchSize
    )
    return Set(ids)
  }

  private static func matchesMetadataFilters(_ note: Note, input: NoteSearchInput) -> Bool {
    if note.isPasswordProtected {
      return false
    }
    if let accountId = input.accountId, note.accountId != accountId {
      return false
    }
    if let folderId = input.folderId, note.folderId != folderId {
      return false
    }
    if let modifiedAfter = input.modifiedAfter, note.modificationDate < modifiedAfter {
      return false
    }
    if let modifiedBefore = input.modifiedBefore, note.modificationDate >= modifiedBefore {
      return false
    }
    return true
  }

  private static func matchesQuery(_ query: String?, note: Note, bodyMatchIds: Set<String>) -> Bool {
    guard let query, !query.isEmpty else {
      return true
    }
    return note.name.localizedCaseInsensitiveContains(query) || bodyMatchIds.contains(note.id)
  }

  private static func sortNotes(_ lhs: Note, _ rhs: Note) -> Bool {
    if lhs.modificationDate == rhs.modificationDate {
      return lhs.id < rhs.id
    }
    return lhs.modificationDate > rhs.modificationDate
  }
}

private enum NotesCursorCodec {
  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  static func cursor(for index: Int, note: Note) -> String {
    let payload = NotesCursorPayload(
      index: index,
      id: note.id,
      modificationDate: note.modificationDate.timeIntervalSince1970
    )
    let data = (try? encoder.encode(payload)) ?? Data()
    return data.base64URLEncodedString()
  }

  static func offset(after cursor: String?) throws -> Int {
    guard let cursor else {
      return 0
    }
    guard
      let data = Data(base64URLEncoded: cursor),
      let payload = try? decoder.decode(NotesCursorPayload.self, from: data),
      payload.index >= 0,
      !payload.id.isEmpty
    else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid pagination cursor")
    }
    return payload.index + 1
  }
}

private struct NotesCursorPayload: Codable {
  var index: Int
  var id: String
  var modificationDate: TimeInterval
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  init?(base64URLEncoded string: String) {
    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = base64.count % 4
    if padding > 0 {
      base64 += String(repeating: "=", count: 4 - padding)
    }
    self.init(base64Encoded: base64)
  }
}

private extension NoteConnection {
  static func paginating(_ notes: [Note], first: Int, offset: Int) -> NoteConnection {
    let page = notes.dropFirst(offset).prefix(first)
    let edges = page.enumerated().map { index, note in
      NoteEdge(cursor: NotesCursorCodec.cursor(for: offset + index, note: note), node: note)
    }
    return NoteConnection(
      edges: edges,
      pageInfo: PageInfo(
        hasNextPage: offset + edges.count < notes.count,
        endCursor: edges.last?.cursor
      ),
      totalCount: notes.count
    )
  }
}

private extension Note {
  func withoutBodies() -> Note {
    var note = self
    note.plaintext = nil
    note.bodyHtml = nil
    note.bodyFile = nil
    return note
  }
}

extension NoteBodyKind {
  var fileStoreKind: FileStoreFileKind {
    switch self {
    case .plaintext:
      return .plaintext
    case .html:
      return .html
    }
  }

  var defaultFilename: String {
    switch self {
    case .plaintext:
      return "body.txt"
    case .html:
      return "body.html"
    }
  }
}

enum NotesFileStoreIdentifier {
  private static let prefix = "n_"

  static func encode(_ value: String) -> String {
    prefix + Data(value.utf8).base64URLEncodedString()
  }

  static func decode(_ value: String) throws -> String {
    guard value.hasPrefix(prefix) else {
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Invalid Notes source identifier",
        details: ["reason": "Invalid Notes source identifier"]
      )
    }
    let encoded = String(value.dropFirst(prefix.count))
    guard
      let data = Data(base64URLEncoded: encoded),
      let decoded = String(data: data, encoding: .utf8),
      !decoded.isEmpty
    else {
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Invalid Notes source identifier",
        details: ["reason": "Invalid Notes source identifier"]
      )
    }
    return decoded
  }

  static func sanitizedFilename(_ value: String, fallback: String) -> String {
    let sanitized = value
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "\\", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty, sanitized != ".", sanitized != "..", !sanitized.hasPrefix("~") else {
      return fallback
    }
    return sanitized
  }
}
