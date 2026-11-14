import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notesSchemaPrintsReaderQueriesAndFullMutations() {
  let readerSchema = GraphQLRuntime.schema(role: .reader)
  let fullSchema = GraphQLRuntime.schema(role: .full)

  #expect(readerSchema.contains("  noteAccounts: [NoteAccount!]!"))
  #expect(readerSchema.contains("  noteFolders(accountId: ID): [NoteFolder!]!"))
  #expect(readerSchema.contains("  notes(input: NoteSearchInput!): NoteConnection!"))
  #expect(readerSchema.contains("  note(noteId: ID!): Note"))
  #expect(!readerSchema.contains("type Mutation"))
  #expect(!readerSchema.contains("createNote"))

  #expect(fullSchema.contains("type Mutation {"))
  #expect(fullSchema.contains("  createNote(input: CreateNoteInput!): Note!"))
  #expect(fullSchema.contains("  updateNoteBody(input: UpdateNoteBodyInput!): Note!"))
  #expect(fullSchema.contains("  deleteNote(noteId: ID!): DeleteResult!"))
  #expect(fullSchema.contains("  moveNote(noteId: ID!, folderId: ID!): Note!"))
}

@Test func notesReadSchemaUsesInjectedServices() throws {
  let fake = GraphQLNotesFake()
  let envelope = try notesExecuteGraphQL(
    """
    {
      noteAccounts { id name isDefault }
      noteFolders(accountId: "icloud") { id name noteCount }
      notes(input: { query: "release", first: 5 }) {
        totalCount
        edges { node { id name snippet plaintext bodyHtml bodyFile { kind byteSize } } }
      }
      note(noteId: "note-1") {
        id
        name
        plaintext
        attachments { id name downloadKey }
      }
    }
    """,
    notesReadService: NotesReadService(provider: fake),
    notesWriteService: NotesWriteService(provider: fake, writer: fake)
  )

  #expect(envelope.errors.isEmpty)
  let accounts = try #require(envelope.data?["noteAccounts"] as? [[String: Any]])
  let folders = try #require(envelope.data?["noteFolders"] as? [[String: Any]])
  let notes = try #require(envelope.data?["notes"] as? [String: Any])
  let note = try #require(envelope.data?["note"] as? [String: Any])
  let edges = try #require(notes["edges"] as? [[String: Any]])
  let edgeNode = try #require(edges.first?["node"] as? [String: Any])
  let attachments = try #require(note["attachments"] as? [[String: Any]])

  #expect(accounts.first?["id"] as? String == "icloud")
  #expect(folders.first?["id"] as? String == "inbox")
  #expect(notes["totalCount"] as? Int == 1)
  #expect(edgeNode["id"] as? String == "note-1")
  #expect(edgeNode["snippet"] as? String == "release body snippet")
  #expect(edgeNode["plaintext"] is NSNull)
  #expect(edgeNode["bodyHtml"] is NSNull)
  #expect(edgeNode["bodyFile"] is NSNull)
  #expect(note["plaintext"] as? String == "Release checklist")
  #expect(attachments.first?["downloadKey"] as? String == "attachment-key")
}

@Test func notesMutationsUseInjectedServicesAndReaderRejectsNotesMutation() throws {
  let fake = GraphQLNotesFake()
  let readService = NotesReadService(provider: fake)
  let writeService = NotesWriteService(provider: fake, writer: fake)

  let createEnvelope = try notesExecuteGraphQL(
    """
    mutation {
      createNote(input: { folderId: "inbox", title: "Created", bodyText: "Alpha" }) {
        id
        name
        bodyHtml
      }
    }
    """,
    notesReadService: readService,
    notesWriteService: writeService
  )
  let created = try #require(createEnvelope.data?["createNote"] as? [String: Any])
  #expect(createEnvelope.errors.isEmpty)
  #expect(created["id"] as? String == "note-2")
  #expect(created["bodyHtml"] as? String == "<div>Alpha</div>")

  let appendEnvelope = try notesExecuteGraphQL(
    """
    mutation {
      updateNoteBody(input: { noteId: "note-2", mode: APPEND, bodyHtml: "<div>Beta</div>" }) {
        id
        bodyHtml
      }
    }
    """,
    notesReadService: readService,
    notesWriteService: writeService
  )
  let appended = try #require(appendEnvelope.data?["updateNoteBody"] as? [String: Any])
  #expect(appendEnvelope.errors.isEmpty)
  #expect(appended["bodyHtml"] as? String == "<div>Alpha</div><div>Beta</div>")

  let moveEnvelope = try notesExecuteGraphQL(
    #"mutation { moveNote(noteId: "note-2", folderId: "archive") { id folderId } }"#,
    notesReadService: readService,
    notesWriteService: writeService
  )
  let moved = try #require(moveEnvelope.data?["moveNote"] as? [String: Any])
  #expect(moveEnvelope.errors.isEmpty)
  #expect(moved["folderId"] as? String == "archive")

  let deleteEnvelope = try notesExecuteGraphQL(
    #"mutation { deleteNote(noteId: "note-2") { success } }"#,
    notesReadService: readService,
    notesWriteService: writeService
  )
  let deleted = try #require(deleteEnvelope.data?["deleteNote"] as? [String: Any])
  #expect(deleteEnvelope.errors.isEmpty)
  #expect(deleted["success"] as? Bool == true)
  #expect(fake.deletedNoteIds == ["note-2"])

  let readerEnvelope = try notesExecuteGraphQL(
    #"mutation { createNote(input: { title: "Blocked", bodyText: "No" }) { id } }"#,
    role: .reader,
    notesReadService: readService,
    notesWriteService: writeService
  )
  #expect(readerEnvelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(fake.createRequests.count == 1)
}

private func notesExecuteGraphQL(
  _ query: String,
  role: AppleGatewayRole = .full,
  notesReadService: NotesReadService,
  notesWriteService: NotesWriteService
) throws -> NotesDecodedEnvelope {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: [:],
    role: role,
    permissionsProvider: NotesGraphQLPermissionsProvider(),
    notesReadService: notesReadService,
    notesWriteService: notesWriteService
  )
  let object = try JSONSerialization.jsonObject(with: data)
  let dictionary = try #require(object as? [String: Any])
  let dataObject = dictionary["data"] as? [String: Any]
  let errorObjects = dictionary["errors"] as? [[String: Any]] ?? []
  return NotesDecodedEnvelope(
    data: dataObject,
    errors: errorObjects.map {
      let extensions = $0["extensions"] as? [String: Any]
      return NotesDecodedError(
        code: extensions?["code"] as? String ?? "",
        exitCode: extensions?["exitCode"] as? Int ?? 0
      )
    }
  )
}

private struct NotesDecodedEnvelope {
  var data: [String: Any]?
  var errors: [NotesDecodedError]
}

private struct NotesDecodedError {
  var code: String
  var exitCode: Int
}

private struct NotesGraphQLPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .unknown),
      reminders: PermissionFieldStatus(state: .unknown),
      notesAutomation: PermissionFieldStatus(state: .unknown),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .unknown)
    )
  }
}

private final class GraphQLNotesFake: NotesProviding, NotesWriting, @unchecked Sendable {
  var notes: [String: Note]
  var createRequests: [NotesCreateRequest] = []
  var deletedNoteIds: [String] = []

  init() {
    notes = [
      "note-1": graphQLNote(
        id: "note-1",
        folderId: "inbox",
        name: "Release",
        snippet: "release body snippet",
        plaintext: "Release checklist",
        bodyHtml: "<div>Release checklist</div>",
        attachments: [
          NoteAttachment(id: "attachment-1", name: "plan.txt", downloadKey: "attachment-key")
        ]
      )
    ]
  }

  func accounts() throws -> [NoteAccount] {
    [NoteAccount(id: "icloud", name: "iCloud", isDefault: true)]
  }

  func folders(accountId: String?) throws -> [NoteFolder] {
    [
      NoteFolder(id: "inbox", accountId: "icloud", name: "Notes", noteCount: notes.count),
      NoteFolder(id: "archive", accountId: "icloud", name: "Archive", noteCount: 0)
    ].filter { folder in
      accountId.map { folder.accountId == $0 } ?? true
    }
  }

  func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    notes.values.filter { note in
      (accountId.map { note.accountId == $0 } ?? true)
        && (folderId.map { note.folderId == $0 } ?? true)
    }
    .map(\.id)
  }

  func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] {
    noteIds.compactMap { notes[$0] }
  }

  func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] {
    notes.values.filter { note in
      (input.accountId.map { note.accountId == $0 } ?? true)
        && (input.folderId.map { note.folderId == $0 } ?? true)
        && ((note.plaintext ?? "").localizedCaseInsensitiveContains(input.query)
          || (note.bodyHtml ?? "").localizedCaseInsensitiveContains(input.query))
    }
    .map(\.id)
  }

  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    Dictionary(uniqueKeysWithValues: noteIds.map { ($0, notes[$0]?.snippet ?? "") })
  }

  func noteMetadata(noteId: String) throws -> NoteLookupResult {
    notes[noteId].map(NoteLookupResult.found) ?? .missing
  }

  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    guard let note = notes[noteId] else {
      return .missing
    }
    let body: String
    switch kind {
    case .plaintext:
      body = note.plaintext ?? ""
    case .html:
      body = note.bodyHtml ?? ""
    }
    return .found(NoteBodyFetchResult(note: note, kind: kind, body: body))
  }

  func exportAttachment(
    noteId: String,
    attachmentId: String,
    to destination: URL
  ) throws -> NotesAttachmentExportResult {
    .unavailable
  }

  func createNote(_ request: NotesCreateRequest) throws -> String {
    createRequests.append(request)
    let noteId = "note-\(notes.count + 1)"
    notes[noteId] = graphQLNote(
      id: noteId,
      folderId: request.folderId,
      name: request.title,
      bodyHtml: request.bodyHtml
    )
    return noteId
  }

  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String {
    guard var note = notes[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.bodyHtml = request.bodyHtml
    notes[request.noteId] = note
    return request.noteId
  }

  func deleteNote(noteId: String) throws -> DeleteResult {
    deletedNoteIds.append(noteId)
    notes.removeValue(forKey: noteId)
    return DeleteResult(success: true)
  }

  func moveNote(_ request: NotesMoveRequest) throws -> String {
    guard var note = notes[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.accountId = request.accountId
    note.folderId = request.folderId
    notes[request.noteId] = note
    return request.noteId
  }
}

private func graphQLNote(
  id: String,
  accountId: String = "icloud",
  folderId: String,
  name: String,
  snippet: String = "",
  plaintext: String? = nil,
  bodyHtml: String? = nil,
  attachments: [NoteAttachment] = []
) -> Note {
  Note(
    id: id,
    accountId: accountId,
    folderId: folderId,
    name: name,
    snippet: snippet,
    plaintext: plaintext,
    bodyHtml: bodyHtml,
    creationDate: Date(timeIntervalSince1970: 10),
    modificationDate: Date(timeIntervalSince1970: 20),
    attachments: attachments
  )
}
