import Foundation
import Testing
@testable import AppleGatewayCore

@Test func createNoteRequiresExactlyOneBodySource() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  #expect(throws: AppleGatewayError.self) {
    try service.createNote(CreateNoteInput(title: "New"))
  }
  #expect(throws: AppleGatewayError.self) {
    try service.createNote(CreateNoteInput(title: "New", bodyHtml: "<div>A</div>", bodyText: "A"))
  }

  do {
    _ = try service.createNote(CreateNoteInput(title: "New"))
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

@Test func createNoteConvertsBodyTextAndRefetchesResult() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  let note = try service.createNote(
    CreateNoteInput(
      accountId: "icloud",
      folderId: "inbox",
      title: "Escaped",
      bodyText: "A & B\n\n<C> \"quote\" 'single'"
    )
  )

  #expect(note.id == "created-1")
  #expect(note.bodyHtml == "<div>A &amp; B</div><div><br></div><div>&lt;C&gt; &quot;quote&quot; &#39;single&#39;</div>")
  #expect(fake.createRequests == [
    NotesCreateRequest(
      accountId: "icloud",
      folderId: "inbox",
      title: "Escaped",
      bodyHtml: "<div>A &amp; B</div><div><br></div><div>&lt;C&gt; &quot;quote&quot; &#39;single&#39;</div>"
    )
  ])
  #expect(fake.bodyLookups.map(\.noteId) == ["created-1"])
  #expect(fake.bodyLookups.map(\.kind) == [.html])
}

@Test func updateNoteBodyReplaceWritesResolvedHtmlAndRefetches() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  let note = try service.updateNoteBody(
    UpdateNoteBodyInput(noteId: "note-1", mode: .replace, bodyHtml: "<div>Replacement</div>")
  )

  #expect(note.id == "note-1")
  #expect(note.bodyHtml == "<div>Replacement</div>")
  #expect(fake.replaceRequests == [
    NotesBodyWriteRequest(noteId: "note-1", bodyHtml: "<div>Replacement</div>")
  ])
  #expect(fake.bodyLookups.map(\.noteId) == ["note-1"])
  #expect(fake.bodyLookups.map(\.kind) == [.html])
}

@Test func updateNoteBodyAppendReadsCurrentHtmlBeforeWriting() throws {
  let fake = FakeNotesWriteBackend()
  fake.notes["note-1"]?.bodyHtml = "<div>Existing</div>"
  let service = NotesWriteService(provider: fake, writer: fake)

  let note = try service.updateNoteBody(
    UpdateNoteBodyInput(noteId: "note-1", mode: .append, bodyText: "Appended")
  )

  #expect(note.bodyHtml == "<div>Existing</div><div>Appended</div>")
  #expect(fake.replaceRequests == [
    NotesBodyWriteRequest(noteId: "note-1", bodyHtml: "<div>Existing</div><div>Appended</div>")
  ])
  #expect(fake.bodyLookups.map(\.noteId) == ["note-1", "note-1"])
  #expect(fake.bodyLookups.map(\.kind) == [.html, .html])
}

@Test func updateNoteBodyRequiresExactlyOneBodySource() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  do {
    _ = try service.updateNoteBody(UpdateNoteBodyInput(noteId: "note-1", bodyHtml: "<div>A</div>", bodyText: "A"))
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
  do {
    _ = try service.updateNoteBody(UpdateNoteBodyInput(noteId: "note-1"))
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
  #expect(fake.replaceRequests.isEmpty)
}

@Test func deleteNoteChecksExistingNoteAndMovesToRecentlyDeleted() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  let result = try service.deleteNote(noteId: "note-1")

  #expect(result == DeleteResult(success: true))
  #expect(fake.metadataLookups == ["note-1"])
  #expect(fake.deletedNoteIds == ["note-1"])
  #expect(fake.notes["note-1"] == nil)
  #expect(fake.recentlyDeletedNoteIds == ["note-1"])
}

@Test func moveNoteValidatesDestinationAndRefetchesMovedNote() throws {
  let fake = FakeNotesWriteBackend()
  let service = NotesWriteService(provider: fake, writer: fake)

  let note = try service.moveNote(noteId: "note-1", folderId: "archive")

  #expect(note.folderId == "archive")
  #expect(fake.moveRequests == [
    NotesMoveRequest(noteId: "note-1", accountId: "icloud", folderId: "archive")
  ])
  #expect(fake.metadataLookups == ["note-1"])
  #expect(fake.folderLookups == [nil])
  #expect(fake.bodyLookups.map(\.noteId) == ["note-1"])
}

@Test func notesWriteDocsMentionLossyHtmlMutationLimit() throws {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let notesSpec = try String(
    contentsOf: root.appendingPathComponent("design-docs/specs/design-apple-notes.md"),
    encoding: .utf8
  )
  let commandSpec = try String(
    contentsOf: root.appendingPathComponent("design-docs/specs/command.md"),
    encoding: .utf8
  )

  #expect(notesSpec.contains("TASK-004 Write-Side Contract"))
  #expect(notesSpec.localizedCaseInsensitiveContains("lossy"))
  #expect(commandSpec.contains("Notes HTML round-tripping is lossy"))
}

private final class FakeNotesWriteBackend: NotesProviding, NotesWriting, @unchecked Sendable {
  var accountsList = [NoteAccount(id: "icloud", name: "iCloud", isDefault: true)]
  var foldersList = [
    NoteFolder(id: "inbox", accountId: "icloud", name: "Notes", noteCount: 1),
    NoteFolder(id: "archive", accountId: "icloud", name: "Archive", noteCount: 0)
  ]
  var notes: [String: Note] = [
    "note-1": noteWriteFixture(id: "note-1", folderId: "inbox", bodyHtml: "<div>Original</div>")
  ]
  var createRequests: [NotesCreateRequest] = []
  var replaceRequests: [NotesBodyWriteRequest] = []
  var moveRequests: [NotesMoveRequest] = []
  var deletedNoteIds: [String] = []
  var recentlyDeletedNoteIds: [String] = []
  var metadataLookups: [String] = []
  var bodyLookups: [(noteId: String, kind: NoteBodyKind)] = []
  var folderLookups: [String?] = []

  func accounts() throws -> [NoteAccount] {
    accountsList
  }

  func folders(accountId: String?) throws -> [NoteFolder] {
    folderLookups.append(accountId)
    return foldersList.filter { folder in
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
    []
  }

  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    [:]
  }

  func noteMetadata(noteId: String) throws -> NoteLookupResult {
    metadataLookups.append(noteId)
    guard let note = notes[noteId] else {
      return .missing
    }
    return .found(note)
  }

  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    bodyLookups.append((noteId: noteId, kind: kind))
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
    let noteId = "created-\(createRequests.count)"
    notes[noteId] = noteWriteFixture(
      id: noteId,
      folderId: request.folderId,
      name: request.title,
      bodyHtml: request.bodyHtml
    )
    return noteId
  }

  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String {
    replaceRequests.append(request)
    guard var note = notes[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.bodyHtml = request.bodyHtml
    notes[request.noteId] = note
    return request.noteId
  }

  func deleteNote(noteId: String) throws -> DeleteResult {
    deletedNoteIds.append(noteId)
    guard notes.removeValue(forKey: noteId) != nil else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    recentlyDeletedNoteIds.append(noteId)
    return DeleteResult(success: true)
  }

  func moveNote(_ request: NotesMoveRequest) throws -> String {
    moveRequests.append(request)
    guard var note = notes[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.accountId = request.accountId
    note.folderId = request.folderId
    notes[request.noteId] = note
    return request.noteId
  }
}

private func noteWriteFixture(
  id: String,
  accountId: String = "icloud",
  folderId: String,
  name: String = "Note",
  bodyHtml: String? = nil
) -> Note {
  Note(
    id: id,
    accountId: accountId,
    folderId: folderId,
    name: name,
    snippet: "",
    bodyHtml: bodyHtml,
    creationDate: Date(timeIntervalSince1970: 10),
    modificationDate: Date(timeIntervalSince1970: 20)
  )
}
