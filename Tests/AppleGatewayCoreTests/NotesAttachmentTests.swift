import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notesJXATemplateBehaviorallyNormalizesAttachmentsAndSharedFallbacks() throws {
  let mockApplicationSource = """
  function mockProperty(value) {
    return function() { return value; };
  }
  function unavailableProperty() {
    throw new Error('property unavailable');
  }
  function mockNote(id, shared, isShared) {
    return {
      id: mockProperty(id),
      name: mockProperty('Metadata'),
      passwordProtected: mockProperty(false),
      shared: shared,
      isShared: isShared,
      creationDate: mockProperty(new Date('2026-07-03T10:00:00Z')),
      modificationDate: mockProperty(new Date('2026-07-03T11:00:00Z')),
      attachments: mockProperty([
        { id: mockProperty(''), name: mockProperty('empty') },
        { id: mockProperty('   '), name: mockProperty('whitespace') },
        { id: mockProperty('missing value'), name: mockProperty('missing') },
        { id: mockProperty('null'), name: mockProperty('null') },
        { id: mockProperty('undefined'), name: mockProperty('undefined') },
        {
          id: mockProperty('attachment-fallback'),
          name: mockProperty('   '),
          fileName: mockProperty('missing value'),
          contentIdentifier: mockProperty(' undefined ')
        },
        {
          id: mockProperty(' attachment-trimmed '),
          name: mockProperty(' Receipt.pdf '),
          contentIdentifier: mockProperty(' cid-1 ')
        }
      ])
    };
  }
  const mockNotes = [
    mockNote('explicit-false', mockProperty(false), mockProperty(true)),
    mockNote('fallback-false', unavailableProperty, mockProperty('true'))
  ];
  function mockApplication(name) {
    return {
      accounts: mockProperty([{
        id: mockProperty('icloud'),
        folders: mockProperty([{
          id: mockProperty('inbox'),
          notes: mockProperty(mockNotes)
        }])
      }])
    };
  }
  """
  let templateSource = NotesJXATemplate.probeNoteVisibility.source.replacingOccurrences(
    of: "Application('Notes')",
    with: "mockApplication('Notes')"
  )
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601

  for noteId in ["explicit-false", "fallback-false"] {
    let data = try bridge.runJXA(
      script: mockApplicationSource + "\n" + templateSource,
      argumentsJSON: #"{"noteId":"\#(noteId)"}"#
    )
    let payload = try decoder.decode(NotesTemplateLookupPayload.self, from: data)
    let note = try #require(payload.note)

    #expect(payload.status == "found")
    #expect(note.isShared == false)
    #expect(note.attachments == [
      NoteAttachment(id: "attachment-fallback", name: "Untitled Attachment"),
      NoteAttachment(id: "attachment-trimmed", name: "Receipt.pdf", contentIdentifier: "cid-1")
    ])
  }
}

@Test func notesReadServiceReturnsKeysOnlyForPreparedAttachments() throws {
  let secret = Data("notes-attachment-secret-32-byte-key".utf8)
  let root = try makeNotesTemporaryRoot()
  let cache = root.appendingPathComponent("cache", isDirectory: true)
  let provider = NotesTestProvider()
  provider.attachmentExportData["attachment/1"] = Data("exported attachment".utf8)
  provider.notesBodyResults["x-coredata://attachments"] = [
    .plaintext: notesBodyResult(
      noteId: "x-coredata://attachments",
      kind: .plaintext,
      body: "body",
      attachments: [
        NoteAttachment(id: "attachment/1", name: "receipt.pdf", contentIdentifier: "cid-1"),
        NoteAttachment(id: "", name: "unaddressable")
      ]
    )
  ]
  let service = NotesReadService(
    provider: provider,
    limits: notesTestLimits(maxInlineBodyBytes: 100),
    fileStore: FileStore(cacheRoot: cache.path, secret: secret)
  )

  let note = try #require(try service.note(noteId: "x-coredata://attachments"))
  let keyed = try #require(note.attachments.first)
  let unkeyed = try #require(note.attachments.dropFirst().first)
  let key = try #require(keyed.downloadKey)
  let payload = try FileStoreDownloadKeyCodec(secret: secret).decode(key)

  #expect(payload.domain == .notes)
  #expect(payload.kind == .attachment)
  #expect(payload.filename == "receipt.pdf")
  #expect(try NotesFileStoreIdentifier.decode(payload.sourceId) == "x-coredata://attachments")
  #expect(try NotesFileStoreIdentifier.decode(#require(payload.sourceIds["attachmentId"])) == "attachment/1")
  #expect(unkeyed.downloadKey == nil)

  let materializer = NotesFileMaterializer(
    provider: provider,
    attachmentExportStore: NotesAttachmentExportStore(cacheRoot: cache.path)
  )
  let prepared = try materializer.sourceFile(for: payload)
  #expect(try String(contentsOf: prepared, encoding: .utf8) == "exported attachment")
  #expect(provider.attachmentExportDestinations.count == 1)
}

@Test func notesReadServiceReturnsNilAttachmentKeyWhenExportIsUnavailable() throws {
  let provider = NotesTestProvider()
  provider.notesBodyResults["note-1"] = [
    .plaintext: notesBodyResult(
      noteId: "note-1",
      kind: .plaintext,
      body: "body",
      attachments: [NoteAttachment(id: "attachment-1", name: "receipt.pdf")]
    )
  ]
  let service = NotesReadService(
    provider: provider,
    attachmentExportStore: NotesAttachmentExportStore(cacheRoot: try makeNotesTemporaryRoot().path)
  )

  let result = try #require(try service.note(noteId: "note-1"))

  #expect(result.attachments.first?.downloadKey == nil)
  #expect(provider.attachmentExportDestinations.count == 1)
}

@Test func notesAttachmentExportCleansPartialFilesAndRejectsSymlinkContainment() throws {
  let root = try makeNotesTemporaryRoot()
  let partialProvider = NotesTestProvider()
  partialProvider.attachmentPartialData["attachment-1"] = Data("partial".utf8)
  partialProvider.attachmentExportResults["attachment-1"] = .unavailable
  let store = NotesAttachmentExportStore(cacheRoot: root.path)

  let partialResult = try store.export(
    provider: partialProvider,
    noteId: "note-1",
    attachmentId: "attachment-1",
    filename: "receipt.pdf"
  )

  #expect(partialResult == .unavailable)
  #expect(!FileManager.default.fileExists(atPath: try #require(partialProvider.attachmentExportDestinations.first).path))

  let symlinkRoot = try makeNotesTemporaryRoot()
  let preparedRoot = symlinkRoot.appendingPathComponent("snapshots/notes/attachments", isDirectory: true)
  try FileManager.default.createDirectory(at: preparedRoot, withIntermediateDirectories: true)
  let outside = try makeNotesTemporaryRoot()
  let noteDirectory = preparedRoot.appendingPathComponent(NotesFileStoreIdentifier.encode("note-1"))
  try FileManager.default.createSymbolicLink(at: noteDirectory, withDestinationURL: outside)

  do {
    _ = try NotesAttachmentExportStore(cacheRoot: symlinkRoot.path).preparedFile(
      noteId: "note-1",
      attachmentId: "attachment-1",
      filename: "receipt.pdf"
    )
    Issue.record("Expected prepared attachment symlink rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fileOperationFailed)
  }
}

@Test func notesAttachmentExportSanitizesFilenamesAndRejectsCanonicalEscapes() throws {
  let root = try makeNotesTemporaryRoot()
  let store = NotesAttachmentExportStore(cacheRoot: root.path)
  let provider = NotesTestProvider()
  provider.attachmentExportData["attachment-1"] = Data("safe".utf8)

  let result = try store.export(
    provider: provider,
    noteId: "note-1",
    attachmentId: "attachment-1",
    filename: "../../unsafe\\name.pdf"
  )
  guard case .exported(let exported) = result else {
    Issue.record("Expected sanitized attachment export")
    return
  }

  #expect(exported.lastPathComponent == "..-..-unsafe-name.pdf")
  #expect(exported.path.hasPrefix(root.appendingPathComponent("snapshots/notes/attachments").path + "/"))

  let outside = try makeNotesTemporaryRoot().appendingPathComponent("outside.pdf")
  try Data("outside".utf8).write(to: outside)
  let escapingProvider = NotesTestProvider()
  escapingProvider.attachmentExportResults["attachment-escape"] = .exported(outside)

  let escapeResult = try store.export(
    provider: escapingProvider,
    noteId: "note-1",
    attachmentId: "attachment-escape",
    filename: "escape.pdf"
  )

  #expect(escapeResult == .unavailable)
  #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
}

@Test func notesAttachmentExportRejectsPostExportSymlink() throws {
  let root = try makeNotesTemporaryRoot()
  let outside = try makeNotesTemporaryRoot().appendingPathComponent("outside.pdf")
  try Data("outside".utf8).write(to: outside)
  let provider = NotesTestProvider()
  provider.attachmentExportHandler = { destination in
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: outside)
    return .exported(destination)
  }
  let store = NotesAttachmentExportStore(cacheRoot: root.path)

  let result = try store.export(
    provider: provider,
    noteId: "note-1",
    attachmentId: "attachment-1",
    filename: "receipt.pdf"
  )

  #expect(result == .unavailable)
  #expect(!FileManager.default.fileExists(atPath: try #require(provider.attachmentExportDestinations.first).path))
  #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
}

@Test func notesFileMaterializerClassifiesAttachmentExportOutcomes() throws {
  let root = try makeNotesTemporaryRoot()
  let payload = FileStoreDownloadKeyPayload(
    domain: .notes,
    sourceId: NotesFileStoreIdentifier.encode("note-1"),
    sourceIds: ["attachmentId": NotesFileStoreIdentifier.encode("attachment-1")],
    kind: .attachment,
    filename: "receipt.pdf"
  )
  let expected: [(NotesAttachmentExportResult, AppleGatewayErrorCode)] = [
    (.noteMissing, .noteNotFound),
    (.attachmentMissing, .invalidDownloadKey),
    (.unavailable, .invalidDownloadKey)
  ]

  for (index, expectation) in expected.enumerated() {
    let provider = NotesTestProvider()
    provider.attachmentExportResults["attachment-1"] = expectation.0
    let materializer = NotesFileMaterializer(
      provider: provider,
      attachmentExportStore: NotesAttachmentExportStore(
        cacheRoot: root.appendingPathComponent(String(index)).path
      )
    )
    do {
      _ = try materializer.sourceFile(for: payload)
      Issue.record("Expected Notes attachment materialization failure")
    } catch let error as AppleGatewayError {
      #expect(error.code == expectation.1)
    }
  }

  let fileCache = root.appendingPathComponent("not-a-directory")
  try Data("file".utf8).write(to: fileCache)
  do {
    _ = try NotesFileMaterializer(
      provider: NotesTestProvider(),
      attachmentExportStore: NotesAttachmentExportStore(cacheRoot: fileCache.path)
    ).sourceFile(for: payload)
    Issue.record("Expected genuine Notes attachment filesystem failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .fileOperationFailed)
  }
}

@Test func notesFileMaterializerPreservesAppleEventExportErrors() throws {
  let payload = FileStoreDownloadKeyPayload(
    domain: .notes,
    sourceId: NotesFileStoreIdentifier.encode("note-1"),
    sourceIds: ["attachmentId": NotesFileStoreIdentifier.encode("attachment-1")],
    kind: .attachment,
    filename: "receipt.pdf"
  )
  let provider = NotesTestProvider()
  provider.attachmentExportError = AppleEventBridgeError.automationDenied(message: "denied")
  let materializer = NotesFileMaterializer(
    provider: provider,
    attachmentExportStore: NotesAttachmentExportStore(cacheRoot: try makeNotesTemporaryRoot().path)
  )

  do {
    _ = try materializer.sourceFile(for: payload)
    Issue.record("Expected Notes attachment Automation error")
  } catch AppleEventBridgeError.automationDenied(let message) {
    #expect(message == "denied")
  }
}

@Test func notesFileMaterializerPreservesAttachmentExportTimeout() throws {
  let payload = FileStoreDownloadKeyPayload(
    domain: .notes,
    sourceId: NotesFileStoreIdentifier.encode("note-1"),
    sourceIds: ["attachmentId": NotesFileStoreIdentifier.encode("attachment-1")],
    kind: .attachment,
    filename: "receipt.pdf"
  )
  let provider = NotesTestProvider()
  provider.attachmentExportError = AppleEventBridgeError.timeout(message: "timed out")
  let materializer = NotesFileMaterializer(
    provider: provider,
    attachmentExportStore: NotesAttachmentExportStore(cacheRoot: try makeNotesTemporaryRoot().path)
  )

  do {
    _ = try materializer.sourceFile(for: payload)
    Issue.record("Expected Notes attachment timeout")
  } catch AppleEventBridgeError.timeout(let message) {
    #expect(message == "timed out")
  }
}

private struct NotesTemplateLookupPayload: Decodable {
  var status: String
  var note: Note?
}
