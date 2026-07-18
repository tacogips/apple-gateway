import Foundation
import Testing
@testable import AppleGatewayCore

private let noteTemplateGoldens: [NotesJXATemplate: String] = [
    .listAccounts: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      return JSON.stringify(app.accounts().map((account, index) => ({
        id: String(account.id()),
        name: String(account.name()),
        isDefault: index === 0
      })));
    }
    """,
    .listFolders: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const accounts = app.accounts();
      const output = [];
      accounts.forEach(account => {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          return;
        }
        account.folders().forEach(folder => {
          output.push({
            id: String(folder.id()),
            accountId: accountId,
            name: String(folder.name()),
            parentFolderId: null,
            noteCount: folder.notes().length
          });
        });
      });
      return JSON.stringify(output);
    }
    """,
    .listNoteMetadataWindow: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const start = input.offset || 0;
      const limit = input.limit || 200;
      const noteIds = [];
      let seen = 0;
      let hasMore = false;
      app.accounts().forEach(account => {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          return;
        }
        account.folders().forEach(folder => {
          const folderId = String(folder.id());
          if (input.folderId && input.folderId !== folderId) {
            return;
          }
          folder.notes().forEach(note => {
            if (note.passwordProtected && note.passwordProtected()) {
              return;
            }
            if (seen < start) {
              seen += 1;
              return;
            }
            if (noteIds.length >= limit) {
              hasMore = true;
              return;
            }
            noteIds.push(String(note.id()));
            seen += 1;
          });
        });
      });
      return JSON.stringify({ noteIds: noteIds, hasMore: hasMore });
    }
    """,
    .fetchNoteMetadataBatch: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const wanted = {};
      input.noteIds.forEach(id => { wanted[id] = true; });
      const app = Application('Notes');
      const notes = [];
      app.accounts().forEach(account => {
        const accountId = String(account.id());
        account.folders().forEach(folder => {
          const folderId = String(folder.id());
          folder.notes().forEach(note => {
            const noteId = String(note.id());
            if (!wanted[noteId]) {
              return;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              return;
            }
            notes.push({
              id: noteId,
              accountId: accountId,
              folderId: folderId,
              name: String(note.name()),
              snippet: '',
              plaintext: null,
              bodyHtml: null,
              bodyFile: null,
              isPasswordProtected: false,
              isShared: false,
              creationDate: note.creationDate().toISOString(),
              modificationDate: note.modificationDate().toISOString(),
              attachments: []
            });
          });
        });
      });
      return JSON.stringify(notes);
    }
    """,
    .searchNoteIdsByPlaintext: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const start = input.offset || 0;
      const limit = input.limit || 200;
      const ids = [];
      let seen = 0;
      let hasMore = false;
      app.accounts().forEach(account => {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          return;
        }
        account.folders().forEach(folder => {
          const folderId = String(folder.id());
          if (input.folderId && input.folderId !== folderId) {
            return;
          }
          folder.notes.whose({ plaintext: { _contains: input.query } })().forEach(note => {
            if (note.passwordProtected && note.passwordProtected()) {
              return;
            }
            if (seen < start) {
              seen += 1;
              return;
            }
            if (ids.length >= limit) {
              hasMore = true;
              return;
            }
            ids.push(String(note.id()));
            seen += 1;
          });
        });
      });
      return JSON.stringify({ noteIds: ids, hasMore: hasMore });
    }
    """,
    .fetchSearchSnippetsBatch: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const wanted = {};
      input.noteIds.forEach(id => { wanted[id] = true; });
      const query = (input.query || '').toLowerCase();
      const app = Application('Notes');
      const snippets = {};
      app.accounts().forEach(account => {
        account.folders().forEach(folder => {
          folder.notes().forEach(note => {
            const noteId = String(note.id());
            if (!wanted[noteId] || (note.passwordProtected && note.passwordProtected())) {
              return;
            }
            const body = String(note.plaintext ? note.plaintext() : '');
            const lower = body.toLowerCase();
            const match = query.length > 0 ? lower.indexOf(query) : 0;
            const center = match >= 0 ? match : 0;
            const start = Math.max(0, center - 120);
            snippets[noteId] = body.slice(start, start + 300);
          });
        });
      });
      return JSON.stringify(snippets);
    }
    """,
    .probeNoteVisibility: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      let lockedCandidate = false;
      for (const account of app.accounts()) {
        const accountId = String(account.id());
        for (const folder of account.folders()) {
          const folderId = String(folder.id());
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              lockedCandidate = true;
              continue;
            }
            return JSON.stringify({
              status: 'found',
              note: {
                id: String(note.id()),
                accountId: accountId,
                folderId: folderId,
                name: String(note.name()),
                snippet: '',
                plaintext: null,
                bodyHtml: null,
                bodyFile: null,
                isPasswordProtected: false,
                isShared: false,
                creationDate: note.creationDate().toISOString(),
                modificationDate: note.modificationDate().toISOString(),
                attachments: []
              }
            });
          }
        }
      }
      return JSON.stringify({ status: lockedCandidate ? 'locked' : 'missing', note: null });
    }
    """
    ,
    .fetchNoteBody: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        const accountId = String(account.id());
        for (const folder of account.folders()) {
          const folderId = String(folder.id());
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              return JSON.stringify({ status: 'locked', note: null, kind: input.kind, body: '' });
            }
            const body = input.kind === 'HTML'
              ? String(note.body ? note.body() : '')
              : String(note.plaintext ? note.plaintext() : '');
            return JSON.stringify({
              status: 'found',
              kind: input.kind,
              body: body,
              note: {
                id: String(note.id()),
                accountId: accountId,
                folderId: folderId,
                name: String(note.name()),
                snippet: '',
                plaintext: null,
                bodyHtml: null,
                bodyFile: null,
                isPasswordProtected: false,
                isShared: false,
                creationDate: note.creationDate().toISOString(),
                modificationDate: note.modificationDate().toISOString(),
                attachments: []
              }
            });
          }
        }
      }
      return JSON.stringify({ status: 'missing', note: null, kind: input.kind, body: '' });
    }
    """,
    .createNote: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        if (String(account.id()) !== input.accountId) {
          continue;
        }
        for (const folder of account.folders()) {
          if (String(folder.id()) !== input.folderId) {
            continue;
          }
          const note = app.Note({
            name: input.title,
            body: input.bodyHtml
          });
          folder.notes.push(note);
          return JSON.stringify({ noteId: String(note.id()) });
        }
      }
      throw new Error('Notes folder not found');
    }
    """,
    .replaceNoteBody: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        for (const folder of account.folders()) {
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              throw new Error('Note is password protected');
            }
            note.body = input.bodyHtml;
            return JSON.stringify({ noteId: String(note.id()) });
          }
        }
      }
      throw new Error('Note not found');
    }
    """,
    .deleteNote: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        for (const folder of account.folders()) {
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              throw new Error('Note is password protected');
            }
            note.delete();
            return JSON.stringify({ success: true });
          }
        }
      }
      throw new Error('Note not found');
    }
    """,
    .moveNote: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      let targetFolder = null;
      for (const account of app.accounts()) {
        if (String(account.id()) !== input.accountId) {
          continue;
        }
        for (const folder of account.folders()) {
          if (String(folder.id()) === input.folderId) {
            targetFolder = folder;
            break;
          }
        }
      }
      if (!targetFolder) {
        throw new Error('Notes folder not found');
      }
      for (const account of app.accounts()) {
        for (const folder of account.folders()) {
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              throw new Error('Note is password protected');
            }
            note.move({ to: targetFolder });
            return JSON.stringify({ noteId: input.noteId });
          }
        }
      }
      throw new Error('Note not found');
    }
    """
]

@Test func notesJXATemplatesMatchGoldens() {
  let metadataTemplates: Set<NotesJXATemplate> = [
    .fetchNoteMetadataBatch,
    .probeNoteVisibility,
    .fetchNoteBody,
    .exportAttachment
  ]
  for template in NotesJXATemplate.allCases where !metadataTemplates.contains(template) {
    #expect(template.source == noteTemplateGoldens[template])
  }

  let helperMarker = "\n\nfunction run(argv) {"
  let helperPrefix = NotesJXATemplate.fetchNoteMetadataBatch.source.components(separatedBy: helperMarker)[0]
  for template in [
    NotesJXATemplate.fetchNoteMetadataBatch,
    .probeNoteVisibility,
    .fetchNoteBody,
    .exportAttachment
  ] {
    #expect(template.source.hasPrefix(helperPrefix + helperMarker))
  }
  for template in [
    NotesJXATemplate.fetchNoteMetadataBatch,
    .probeNoteVisibility,
    .fetchNoteBody
  ] {
    #expect(template.source.contains("isShared: notesSharedState(note)"))
    #expect(template.source.contains("attachments: notesAttachmentMetadata(note)"))
    #expect(!template.source.contains("isShared: false"))
    #expect(!template.source.contains("attachments: []"))
  }

  let expectedExportRun = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    for (const account of app.accounts()) {
      for (const folder of account.folders()) {
        for (const note of folder.notes()) {
          if (String(note.id()) !== input.noteId) {
            continue;
          }
          let attachments;
          try {
            attachments = note.attachments();
          } catch (error) {
            if (error && (error.number === -1743 || error.number === -1712)) {
              throw error;
            }
            return JSON.stringify({ status: 'unavailable', path: null });
          }
          for (const attachment of attachments) {
            const attachmentId = normalizedNotesValue(guardedNotesProperty(attachment, 'id'));
            if (attachmentId !== input.attachmentId) {
              continue;
            }
            try {
              app.save(attachment, { in: Path(input.destinationPath) });
              return JSON.stringify({ status: 'exported', path: input.destinationPath });
            } catch (error) {
              if (error && (error.number === -1743 || error.number === -1712)) {
                throw error;
              }
              return JSON.stringify({ status: 'unavailable', path: null });
            }
          }
          return JSON.stringify({ status: 'attachmentMissing', path: null });
        }
      }
    }
    return JSON.stringify({ status: 'noteMissing', path: null });
  }
  """
  #expect(NotesJXATemplate.exportAttachment.source == helperPrefix + "\n\n" + expectedExportRun)
}

@Test func liveNotesAdapterDecodesAttachmentsAndKeepsExportArgumentsOutOfSource() throws {
  let metadataResponse = """
  {
    "status": "found",
    "note": {
      "id": "note-1",
      "accountId": "icloud",
      "folderId": "inbox",
      "name": "Shared",
      "snippet": "",
      "plaintext": null,
      "bodyHtml": null,
      "bodyFile": null,
      "isPasswordProtected": false,
      "isShared": true,
      "creationDate": "2026-07-03T10:00:00Z",
      "modificationDate": "2026-07-03T11:00:00Z",
      "attachments": [
        {
          "id": "attachment-1",
          "name": "Receipt.pdf",
          "contentIdentifier": "cid-1",
          "downloadKey": null
        },
        {
          "id": "attachment-2",
          "name": "Untitled Attachment",
          "contentIdentifier": null,
          "downloadKey": null
        }
      ]
    }
  }
  """
  let metadataFixture = try NotesOsascriptFixture(response: metadataResponse)
  let metadataAdapter = LiveNotesAppleEventAdapter(
    bridge: AppleEventBridge(osascriptPath: metadataFixture.executablePath, environment: metadataFixture.environment)
  )

  let lookup = try metadataAdapter.noteMetadata(noteId: "note-1")
  guard case .found(let note) = lookup else {
    Issue.record("Expected canned Notes metadata")
    return
  }
  #expect(note.isShared)
  #expect(note.attachments == [
    NoteAttachment(id: "attachment-1", name: "Receipt.pdf", contentIdentifier: "cid-1"),
    NoteAttachment(id: "attachment-2", name: "Untitled Attachment")
  ])

  let adversarialNoteId = #"note-\"; throw new Error('injected')"#
  let adversarialAttachmentId = #"attachment-\\-\""#
  let destination = try makeNotesTemporaryRoot().appendingPathComponent("quoted-\"-attachment.bin")
  let exportObject: [String: Any] = ["status": "exported", "path": destination.path]
  let exportData = try JSONSerialization.data(withJSONObject: exportObject)
  let exportFixture = try NotesOsascriptFixture(response: try #require(String(data: exportData, encoding: .utf8)))
  let exportAdapter = LiveNotesAppleEventAdapter(
    bridge: AppleEventBridge(osascriptPath: exportFixture.executablePath, environment: exportFixture.environment)
  )

  let exportResult = try exportAdapter.exportAttachment(
    noteId: adversarialNoteId,
    attachmentId: adversarialAttachmentId,
    to: destination
  )
  let captured = try exportFixture.capturedArguments()
  let argumentsJSON = try #require(captured.last)

  #expect(exportResult == .exported(destination))
  #expect(captured[3] == NotesJXATemplate.exportAttachment.source)
  #expect(!captured[3].contains(adversarialNoteId))
  #expect(!captured[3].contains(adversarialAttachmentId))
  #expect(!captured[3].contains(destination.path))
  #expect(argumentsJSON.contains("injected"))
  #expect(argumentsJSON.contains("destinationPath"))
}

@Test func notesReadServiceSearchesNamesAndBodiesWithoutReturningBodies() throws {
  let provider = NotesTestProvider()
  provider.notes = [
    note(id: "note-title", name: "Project Plan", modified: 20, plaintext: "body"),
    note(id: "note-body", name: "Weekly", modified: 30, bodyHtml: "<p>body</p>"),
    note(id: "note-other", name: "Archive", modified: 10)
  ]
  provider.bodySearchIdsByQuery["plan"] = ["note-body"]
  provider.snippetsById = ["note-body": "body matched snippet", "note-title": "planning"]
  let service = NotesReadService(provider: provider, limits: notesTestLimits(batchSize: 3))

  let result = try service.notes(input: NoteSearchInput(query: "plan"))

  #expect(result.edges.map(\.node.id) == ["note-body", "note-title"])
  #expect(result.edges.map(\.node.snippet) == ["body matched snippet", "planning"])
  #expect(result.edges.allSatisfy { $0.node.plaintext == nil && $0.node.bodyHtml == nil && $0.node.bodyFile == nil })
  #expect(provider.bodySearchInputs == [NotesBodySearchInput(query: "plan")])
  #expect(provider.noteIDBatchSizes == [3])
  #expect(provider.metadataBatchSizes == [3])
  #expect(provider.snippetRequests.map(\.noteIds) == [["note-body", "note-title"]])
}

@Test func notesReadServiceAppliesDateFolderFiltersAndPaginates() throws {
  let provider = NotesTestProvider()
  provider.notes = [
    note(id: "outside-account", accountId: "other", folderId: "inbox", name: "Other", modified: 50),
    note(id: "too-old", folderId: "inbox", name: "Old", modified: 5),
    note(id: "second", folderId: "inbox", name: "Second", modified: 20),
    note(id: "first", folderId: "inbox", name: "First", modified: 30),
    note(id: "upper-bound", folderId: "inbox", name: "Boundary", modified: 35),
    note(id: "wrong-folder", folderId: "archive", name: "Archive", modified: 40)
  ]
  let service = NotesReadService(provider: provider, limits: notesTestLimits(defaultPageSize: 1, batchSize: 2))

  let firstPage = try service.notes(input: NoteSearchInput(
    accountId: "icloud",
    folderId: "inbox",
    modifiedAfter: testDate(10),
    modifiedBefore: testDate(35)
  ))
  let secondPage = try service.notes(input: NoteSearchInput(
    accountId: "icloud",
    folderId: "inbox",
    modifiedAfter: testDate(10),
    modifiedBefore: testDate(35),
    after: firstPage.pageInfo.endCursor
  ))

  #expect(firstPage.totalCount == 2)
  #expect(firstPage.edges.map(\.node.id) == ["first"])
  #expect(firstPage.pageInfo.hasNextPage)
  #expect(secondPage.edges.map(\.node.id) == ["second"])
  #expect(!secondPage.pageInfo.hasNextPage)
  #expect(provider.noteIDRequests.map(\.accountId) == ["icloud", "icloud"])
  #expect(provider.noteIDRequests.map(\.folderId) == ["inbox", "inbox"])
  #expect(provider.noteIDBatchSizes == [2, 2])
}

@Test func notesReadServiceRejectsUnknownScopeBeforeEnumeration() throws {
  let provider = NotesTestProvider()
  let service = NotesReadService(provider: provider, limits: notesTestLimits())

  do {
    _ = try service.notes(input: NoteSearchInput(accountId: "missing"))
    Issue.record("Expected invalid account id")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    _ = try service.notes(input: NoteSearchInput(folderId: "missing-folder"))
    Issue.record("Expected missing folder")
  } catch let error as AppleGatewayError {
    #expect(error.code == .noteFolderNotFound)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(provider.noteIDRequests.isEmpty)
}

@Test func notesReadServiceOmitsLockedNotesAndReportsStaleLockedIds() throws {
  let provider = NotesTestProvider()
  provider.notes = [
    note(id: "visible", name: "Visible", modified: 20),
    note(id: "locked", name: "Locked", modified: 30, isPasswordProtected: true)
  ]
  provider.lookupResults["locked"] = .locked
  let service = NotesReadService(provider: provider, limits: notesTestLimits())

  let result = try service.notes(input: NoteSearchInput())
  #expect(result.edges.map(\.node.id) == ["visible"])

  do {
    _ = try service.noteMetadata(noteId: "locked")
    Issue.record("Expected NOTE_LOCKED")
  } catch let error as AppleGatewayError {
    #expect(error.code == .noteLocked)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func notesReadServiceAppliesBodyInlineBoundary() throws {
  let secret = Data("notes-body-boundary-secret-32-byte".utf8)
  let provider = NotesTestProvider()
  provider.notesBodyResults["x-coredata://under"] = [
    .plaintext: notesBodyResult(noteId: "x-coredata://under", kind: .plaintext, body: "abc")
  ]
  provider.notesBodyResults["x-coredata://equal"] = [
    .plaintext: notesBodyResult(noteId: "x-coredata://equal", kind: .plaintext, body: "1234")
  ]
  provider.notesBodyResults["x-coredata://over"] = [
    .plaintext: notesBodyResult(noteId: "x-coredata://over", kind: .plaintext, body: "12345")
  ]
  let service = NotesReadService(
    provider: provider,
    limits: notesTestLimits(maxInlineBodyBytes: 4),
    fileStore: FileStore(cacheRoot: try makeNotesTemporaryRoot().path, secret: secret)
  )

  let under = try #require(try service.note(noteId: "x-coredata://under"))
  let equal = try #require(try service.note(noteId: "x-coredata://equal"))
  let over = try #require(try service.note(noteId: "x-coredata://over"))
  let bodyFile = try #require(over.bodyFile)
  let payload = try FileStoreDownloadKeyCodec(secret: secret).decode(bodyFile.downloadKey)

  #expect(under.plaintext == "abc")
  #expect(under.bodyFile == nil)
  #expect(equal.plaintext == "1234")
  #expect(equal.bodyFile == nil)
  #expect(over.plaintext == nil)
  #expect(bodyFile.kind == .plaintext)
  #expect(bodyFile.byteSize == 5)
  #expect(payload.domain == .notes)
  #expect(payload.kind == .plaintext)
  #expect(try NotesFileStoreIdentifier.decode(payload.sourceId) == "x-coredata://over")
}

@Test func notesReadServiceValidatesHTMLBodyFileKey() throws {
  let secret = Data("notes-html-body-secret-32-byte-key".utf8)
  let provider = NotesTestProvider()
  provider.notesBodyResults["x-coredata://html"] = [
    .html: notesBodyResult(noteId: "x-coredata://html", kind: .html, body: "<p>12345</p>")
  ]
  let service = NotesReadService(
    provider: provider,
    limits: notesTestLimits(maxInlineBodyBytes: 4),
    fileStore: FileStore(cacheRoot: try makeNotesTemporaryRoot().path, secret: secret)
  )

  let note = try #require(try service.note(noteId: "x-coredata://html", bodyKind: .html))
  let bodyFile = try #require(note.bodyFile)
  let payload = try FileStoreDownloadKeyCodec(secret: secret).decode(bodyFile.downloadKey)

  #expect(note.bodyHtml == nil)
  #expect(bodyFile.kind == .html)
  #expect(payload.domain == .notes)
  #expect(payload.kind == .html)
  #expect(payload.filename == "body.html")
  #expect(try NotesFileStoreIdentifier.decode(payload.sourceId) == "x-coredata://html")
}

@Test func notesFileDownloadMaterializesBodyFiles() throws {
  let secret = Data("notes-file-download-secret-32-by".utf8)
  let root = try makeNotesTemporaryRoot()
  let provider = NotesTestProvider()
  provider.notesBodyResults["x-coredata://plain"] = [
    .plaintext: notesBodyResult(noteId: "x-coredata://plain", kind: .plaintext, body: "plain body")
  ]
  provider.notesBodyResults["x-coredata://html"] = [
    .html: notesBodyResult(noteId: "x-coredata://html", kind: .html, body: "<p>html body</p>")
  ]
  let store = FileStore(cacheRoot: root.appendingPathComponent("cache").path, secret: secret)
  let service = NotesReadService(provider: provider, limits: notesTestLimits(maxInlineBodyBytes: 4), fileStore: store)
  let plain = try #require(try service.note(noteId: "x-coredata://plain")?.bodyFile)
  let html = try #require(try service.note(noteId: "x-coredata://html", bodyKind: .html)?.bodyFile)

  let manifest = try store.download(
    keys: [plain.downloadKey, html.downloadKey],
    outputDirectory: nil,
    materializer: NotesFileMaterializer(
      provider: provider,
      scratchDirectory: root.appendingPathComponent("scratch", isDirectory: true)
    )
  )
  let filesByKind = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.kind, $0.path) })

  #expect(try String(contentsOfFile: #require(filesByKind["PLAINTEXT"]), encoding: .utf8) == "plain body")
  #expect(try String(contentsOfFile: #require(filesByKind["HTML"]), encoding: .utf8) == "<p>html body</p>")
}

final class NotesTestProvider: NotesProviding, @unchecked Sendable {
  var accountsValue: [NoteAccount] = [
    NoteAccount(id: "icloud", name: "iCloud", isDefault: true),
    NoteAccount(id: "other", name: "Other", isDefault: false)
  ]
  var foldersValue: [NoteFolder] = [
    NoteFolder(id: "inbox", accountId: "icloud", name: "Inbox", noteCount: 0),
    NoteFolder(id: "archive", accountId: "icloud", name: "Archive", noteCount: 0)
  ]
  var notes: [Note] = []
  var bodySearchIdsByQuery: [String: [String]] = [:]
  var snippetsById: [String: String] = [:]
  var lookupResults: [String: NoteLookupResult] = [:]
  var notesBodyResults: [String: [NoteBodyKind: NoteBodyLookupResult]] = [:]
  var noteIDRequests: [(accountId: String?, folderId: String?)] = []
  var noteIDBatchSizes: [Int] = []
  var metadataBatchSizes: [Int] = []
  var bodySearchInputs: [NotesBodySearchInput] = []
  var snippetRequests: [(noteIds: [String], query: String?)] = []
  var attachmentExportResults: [String: NotesAttachmentExportResult] = [:]
  var attachmentExportData: [String: Data] = [:]
  var attachmentPartialData: [String: Data] = [:]
  var attachmentExportDestinations: [URL] = []
  var attachmentExportError: Error?
  var attachmentExportHandler: ((URL) throws -> NotesAttachmentExportResult)?

  func accounts() throws -> [NoteAccount] {
    accountsValue
  }

  func folders(accountId: String?) throws -> [NoteFolder] {
    foldersValue.filter { accountId == nil || $0.accountId == accountId }
  }

  func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    noteIDRequests.append((accountId: accountId, folderId: folderId))
    noteIDBatchSizes.append(batchSize)
    return notes.map(\.id)
  }

  func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] {
    metadataBatchSizes.append(batchSize)
    return notes.filter { noteIds.contains($0.id) }
  }

  func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] {
    bodySearchInputs.append(input)
    return bodySearchIdsByQuery[input.query] ?? []
  }

  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    snippetRequests.append((noteIds: noteIds, query: query))
    return snippetsById.filter { noteIds.contains($0.key) }
  }

  func noteMetadata(noteId: String) throws -> NoteLookupResult {
    if let result = lookupResults[noteId] {
      return result
    }
    if let note = notes.first(where: { $0.id == noteId }) {
      return .found(note)
    }
    return .missing
  }

  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    if let result = notesBodyResults[noteId]?[kind] {
      return result
    }
    if let result = lookupResults[noteId] {
      switch result {
      case .found(let note):
        return .found(NoteBodyFetchResult(note: note, kind: kind, body: ""))
      case .locked:
        return .locked
      case .missing:
        return .missing
      }
    }
    if let note = notes.first(where: { $0.id == noteId }) {
      return .found(NoteBodyFetchResult(note: note, kind: kind, body: ""))
    }
    return .missing
  }

  func exportAttachment(
    noteId: String,
    attachmentId: String,
    to destination: URL
  ) throws -> NotesAttachmentExportResult {
    attachmentExportDestinations.append(destination)
    if let attachmentExportError {
      throw attachmentExportError
    }
    if let attachmentExportHandler {
      return try attachmentExportHandler(destination)
    }
    if let partialData = attachmentPartialData[attachmentId] {
      try partialData.write(to: destination)
    }
    if let data = attachmentExportData[attachmentId] {
      try data.write(to: destination)
      return .exported(destination)
    }
    return attachmentExportResults[attachmentId] ?? .unavailable
  }
}

private func note(
  id: String,
  accountId: String = "icloud",
  folderId: String = "inbox",
  name: String,
  snippet: String = "",
  modified: TimeInterval,
  plaintext: String? = nil,
  bodyHtml: String? = nil,
  isPasswordProtected: Bool = false,
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
    isPasswordProtected: isPasswordProtected,
    creationDate: testDate(0),
    modificationDate: testDate(modified),
    attachments: attachments
  )
}

func notesBodyResult(
  noteId: String,
  kind: NoteBodyKind,
  body: String,
  attachments: [NoteAttachment] = []
) -> NoteBodyLookupResult {
  .found(
    NoteBodyFetchResult(
      note: note(
        id: noteId,
        name: "Body Note",
        modified: 10,
        attachments: attachments
      ),
      kind: kind,
      body: body
    )
  )
}

private func testDate(_ seconds: TimeInterval) -> Date {
  Date(timeIntervalSince1970: seconds)
}

func notesTestLimits(
  defaultPageSize: Int = 20,
  maxPageSize: Int = 200,
  maxInlineBodyBytes: Int = 65_536,
  batchSize: Int = 200
) -> AppleGatewayConfig.Limits {
  AppleGatewayConfig.Limits(
    defaultPageSize: defaultPageSize,
    maxPageSize: maxPageSize,
    maxInlineBodyBytes: maxInlineBodyBytes,
    appleEventTimeoutSeconds: 30,
    appleEventBatchSize: batchSize
  )
}

func makeNotesTemporaryRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-notes-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private struct NotesOsascriptFixture {
  let executablePath: String
  let environment: [String: String]
  private let capturePath: String

  init(response: String) throws {
    let root = try makeNotesTemporaryRoot()
    let executable = root.appendingPathComponent("osascript-stub")
    let capture = root.appendingPathComponent("argv.txt")
    try Self.stubSource.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    executablePath = executable.path
    capturePath = capture.path
    environment = [
      "APPLE_GATEWAY_NOTES_STUB_CAPTURE": capture.path,
      "APPLE_GATEWAY_NOTES_STUB_RESPONSE": response,
      "PATH": "/usr/bin:/bin"
    ]
  }

  func capturedArguments() throws -> [String] {
    try String(contentsOfFile: capturePath, encoding: .utf8)
      .split(separator: "\n")
      .compactMap { Data(base64Encoded: String($0)) }
      .compactMap { String(data: $0, encoding: .utf8) }
  }

  private static let stubSource = """
  #!/usr/bin/env bash
  set -euo pipefail
  : > "${APPLE_GATEWAY_NOTES_STUB_CAPTURE:?}"
  for argument in "$@"; do
    printf '%s' "$argument" | /usr/bin/base64 | /usr/bin/tr -d '\n' >> "${APPLE_GATEWAY_NOTES_STUB_CAPTURE:?}"
    printf '\n' >> "${APPLE_GATEWAY_NOTES_STUB_CAPTURE:?}"
  done
  printf '%s\n' "${APPLE_GATEWAY_NOTES_STUB_RESPONSE:?}"
  """
}
