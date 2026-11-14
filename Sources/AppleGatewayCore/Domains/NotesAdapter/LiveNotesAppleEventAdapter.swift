import Foundation

public struct LiveNotesAppleEventAdapter: NotesProviding, NotesWriting {
  private let bridge: AppleEventBridge
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(bridge: AppleEventBridge = AppleEventBridge()) {
    self.bridge = bridge
    encoder = JSONEncoder()
    decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func accounts() throws -> [NoteAccount] {
    try run(template: .listAccounts, arguments: EmptyNotesArguments())
  }

  public func folders(accountId: String?) throws -> [NoteFolder] {
    try run(template: .listFolders, arguments: NotesFoldersArguments(accountId: accountId))
  }

  public func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    let batchSize = max(batchSize, 1)
    var noteIds: [String] = []
    var offset = 0
    while true {
      let page: NotesIDPage = try run(
        template: .listNoteMetadataWindow,
        arguments: NotesWindowArguments(
          accountId: accountId,
          folderId: folderId,
          offset: offset,
          limit: batchSize
        )
      )
      noteIds.append(contentsOf: page.noteIds)
      guard page.hasMore else {
        return noteIds
      }
      offset += batchSize
    }
  }

  public func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] {
    try noteIds.chunked(size: max(batchSize, 1)).reduce(into: []) { notes, chunk in
      let batch: [Note] = try run(
        template: .fetchNoteMetadataBatch,
        arguments: NotesMetadataBatchArguments(noteIds: chunk)
      )
      notes.append(contentsOf: batch)
    }
  }

  public func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] {
    let batchSize = max(batchSize, 1)
    var ids: [String] = []
    var offset = 0
    while true {
      let page: NotesIDPage = try run(
        template: .searchNoteIdsByPlaintext,
        arguments: NotesBodySearchChunkArguments(
          accountId: input.accountId,
          folderId: input.folderId,
          query: input.query,
          offset: offset,
          limit: batchSize
        )
      )
      ids.append(contentsOf: page.noteIds)
      guard page.hasMore else {
        return ids
      }
      offset += batchSize
    }
  }

  public func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    try noteIds.chunked(size: max(batchSize, 1)).reduce(into: [:]) { result, chunk in
      let snippets: [String: String] = try run(
        template: .fetchSearchSnippetsBatch,
        arguments: NotesSnippetBatchArguments(noteIds: chunk, query: query)
      )
      result.merge(snippets, uniquingKeysWith: { current, _ in current })
    }
  }

  public func noteMetadata(noteId: String) throws -> NoteLookupResult {
    let payload: NotesLookupPayload = try run(
      template: .probeNoteVisibility,
      arguments: NotesLookupArguments(noteId: noteId)
    )
    switch payload.status {
    case "found":
      if let note = payload.note {
        return .found(note)
      }
      throw AppleGatewayError(code: .unexpectedError, message: "Notes lookup returned found without a note")
    case "locked":
      return .locked
    case "missing":
      return .missing
    default:
      throw AppleGatewayError(code: .unexpectedError, message: "Notes lookup returned unknown status")
    }
  }

  public func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    let payload: NotesBodyPayload = try run(
      template: .fetchNoteBody,
      arguments: NotesBodyArguments(noteId: noteId, kind: kind)
    )
    switch payload.status {
    case "found":
      if let note = payload.note {
        return .found(NoteBodyFetchResult(note: note, kind: payload.kind, body: payload.body))
      }
      throw AppleGatewayError(code: .unexpectedError, message: "Notes body fetch returned found without a note")
    case "locked":
      return .locked
    case "missing":
      return .missing
    default:
      throw AppleGatewayError(code: .unexpectedError, message: "Notes body fetch returned unknown status")
    }
  }

  public func exportAttachment(
    noteId: String,
    attachmentId: String,
    to destination: URL
  ) throws -> NotesAttachmentExportResult {
    let payload: NotesAttachmentExportPayload = try run(
      template: .exportAttachment,
      arguments: NotesAttachmentExportArguments(
        noteId: noteId,
        attachmentId: attachmentId,
        destinationPath: destination.path
      )
    )
    switch payload.status {
    case "exported":
      guard let path = payload.path else {
        return .unavailable
      }
      return .exported(URL(fileURLWithPath: path))
    case "noteMissing":
      return .noteMissing
    case "attachmentMissing":
      return .attachmentMissing
    case "unavailable":
      return .unavailable
    default:
      throw AppleGatewayError(code: .unexpectedError, message: "Notes attachment export returned unknown status")
    }
  }

  public func createNote(_ request: NotesCreateRequest) throws -> String {
    let payload: NotesWritePayload = try run(
      template: .createNote,
      arguments: request
    )
    return payload.noteId
  }

  public func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String {
    let payload: NotesWritePayload = try run(
      template: .replaceNoteBody,
      arguments: request
    )
    return payload.noteId
  }

  public func deleteNote(noteId: String) throws -> DeleteResult {
    try run(
      template: .deleteNote,
      arguments: NotesDeleteArguments(noteId: noteId)
    )
  }

  public func moveNote(_ request: NotesMoveRequest) throws -> String {
    let payload: NotesWritePayload = try run(
      template: .moveNote,
      arguments: request
    )
    return payload.noteId
  }

  private func run<Response: Decodable, Arguments: Encodable>(
    template: NotesJXATemplate,
    arguments: Arguments
  ) throws -> Response {
    let argumentsData = try encoder.encode(arguments)
    guard let argumentsJSON = String(data: argumentsData, encoding: .utf8) else {
      throw AppleGatewayError(code: .unexpectedError, message: "Failed to encode Notes JXA arguments")
    }
    let data = try bridge.runJXA(script: template.source, argumentsJSON: argumentsJSON)
    return try decoder.decode(Response.self, from: data)
  }
}

private struct EmptyNotesArguments: Encodable {}

private struct NotesFoldersArguments: Encodable {
  var accountId: String?
}

private struct NotesWindowArguments: Encodable {
  var accountId: String?
  var folderId: String?
  var offset: Int
  var limit: Int
}

private struct NotesMetadataBatchArguments: Encodable {
  var noteIds: [String]
}

private struct NotesBodySearchChunkArguments: Encodable {
  var accountId: String?
  var folderId: String?
  var query: String
  var offset: Int
  var limit: Int
}

private struct NotesSnippetBatchArguments: Encodable {
  var noteIds: [String]
  var query: String?
}

private struct NotesLookupArguments: Encodable {
  var noteId: String
}

private struct NotesBodyArguments: Encodable {
  var noteId: String
  var kind: NoteBodyKind
}

private struct NotesAttachmentExportArguments: Encodable {
  var noteId: String
  var attachmentId: String
  var destinationPath: String
}

private struct NotesDeleteArguments: Encodable {
  var noteId: String
}

private struct NotesIDPage: Decodable {
  var noteIds: [String]
  var hasMore: Bool
}

private struct NotesLookupPayload: Decodable {
  var status: String
  var note: Note?
}

private struct NotesBodyPayload: Decodable {
  var status: String
  var note: Note?
  var kind: NoteBodyKind
  var body: String
}

private struct NotesAttachmentExportPayload: Decodable {
  var status: String
  var path: String?
}

private struct NotesWritePayload: Decodable {
  var noteId: String
}

private extension Array {
  func chunked(size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { start in
      Array(self[start..<Swift.min(start + size, count)])
    }
  }
}
