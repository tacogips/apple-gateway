import Foundation
import Testing
@testable import AppleGatewayCore

@Suite("NotesHydration")
struct NotesHydrationTests {
  @Test func hydratesOnlyEachSelectedPageAndPreservesConnectionMetadata() throws {
    let provider = NotesTestProvider()
    provider.notes = [
      hydrationNote(id: "note-1", name: "Plan One", modified: 10),
      hydrationNote(id: "note-2", name: "Plan Two", modified: 20),
      hydrationNote(id: "note-3", name: "Plan Three", modified: 30),
      hydrationNote(id: "note-4", name: "Plan Four", modified: 40)
    ]
    provider.snippetsById = [
      "note-1": "snippet one",
      "note-2": "snippet two",
      "note-3": "snippet three",
      "note-4": "snippet four"
    ]
    provider.hydrationDetailsById = Dictionary(uniqueKeysWithValues: provider.notes.map { summary in
      (
        summary.id,
        hydrationNote(
          id: summary.id,
          name: summary.name,
          modified: summary.modificationDate.timeIntervalSince1970,
          snippet: "detail snippet must not replace search snippet",
          isShared: true,
          attachments: [NoteAttachment(id: "attachment-\(summary.id)", name: "detail.pdf")]
        )
      )
    })
    let service = NotesReadService(
      provider: provider,
      limits: notesTestLimits(defaultPageSize: 2, batchSize: 2)
    )

    let firstPage = try service.notes(input: NoteSearchInput(query: "plan"))
    let secondPage = try service.notes(input: NoteSearchInput(
      query: "plan",
      after: firstPage.pageInfo.endCursor
    ))

    #expect(firstPage.edges.map(\.node.id) == ["note-4", "note-3"])
    #expect(secondPage.edges.map(\.node.id) == ["note-2", "note-1"])
    #expect(firstPage.edges.map(\.node.name) == ["Plan Four", "Plan Three"])
    #expect(firstPage.edges.map(\.node.snippet) == ["snippet four", "snippet three"])
    #expect(firstPage.edges.allSatisfy { $0.node.isShared })
    #expect(firstPage.edges.flatMap(\.node.attachments).map(\.id) == [
      "attachment-note-4",
      "attachment-note-3"
    ])
    #expect(firstPage.totalCount == 4)
    #expect(firstPage.pageInfo.hasNextPage)
    #expect(secondPage.totalCount == 4)
    #expect(!secondPage.pageInfo.hasNextPage)
    #expect(provider.metadataSummaryRequests.map(\.noteIds) == [
      ["note-1", "note-2", "note-3", "note-4"],
      ["note-1", "note-2", "note-3", "note-4"]
    ])
    #expect(provider.metadataSummaryRequests.map(\.batchSize) == [2, 2])
    #expect(provider.hydrationRequests.map(\.noteIds) == [
      ["note-4", "note-3"],
      ["note-2", "note-1"]
    ])
    #expect(provider.hydrationRequests.map(\.batchSize) == [2, 2])
  }

  @Test func skipsHydrationForAnEmptyPage() throws {
    let provider = NotesTestProvider()
    provider.notes = [hydrationNote(id: "only-note", name: "Only", modified: 10)]
    let service = NotesReadService(
      provider: provider,
      limits: notesTestLimits(defaultPageSize: 1, batchSize: 2)
    )
    let firstPage = try service.notes(input: NoteSearchInput())
    provider.hydrationRequests.removeAll()

    let emptyPage = try service.notes(input: NoteSearchInput(after: firstPage.pageInfo.endCursor))

    #expect(emptyPage.edges.isEmpty)
    #expect(emptyPage.totalCount == 1)
    #expect(provider.hydrationRequests.isEmpty)
  }

  @Test func rejectsMissingOrChangedHydrationResults() throws {
    let summary = hydrationNote(id: "stale-note", name: "Original", modified: 10)
    var locked = summary
    locked.isPasswordProtected = true
    var moved = summary
    moved.folderId = "archive"

    for hydrationResult in [[], [locked], [moved]] {
      let provider = NotesTestProvider()
      provider.notes = [summary]
      provider.hydrationResultOverride = hydrationResult
      let service = NotesReadService(provider: provider)

      do {
        _ = try service.notes(input: NoteSearchInput())
        Issue.record("Expected stale hydration to fail")
      } catch let error as AppleGatewayError {
        #expect(error.code == .unexpectedError)
        #expect(error.details?["noteId"] == summary.id)
      }
    }
  }

  @Test func detailTemplateHydratesSelectedNotesWithPerNoteFallbacks() throws {
    let source = NotesJXATemplate.fetchNoteMetadataBatch.source
      .replacingOccurrences(of: "Application('Notes')", with: "mockApplication('Notes')")
    let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let summaryData = try bridge.runJXA(
      script: notesHydrationMockSource + "\n" + source,
      argumentsJSON: #"{"noteIds":["selected-good","selected-fallback","unselected"],"includeDetails":false}"#
    )
    let summaries = try decoder.decode([Note].self, from: summaryData)
    let detailData = try bridge.runJXA(
      script: notesHydrationMockSource + "\n" + source,
      argumentsJSON: #"{"noteIds":["selected-good","selected-fallback","selected-enumeration-fallback"],"includeDetails":true}"#
    )
    let details = try decoder.decode([Note].self, from: detailData)
    let detailsById = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })

    #expect(summaries.count == 3)
    #expect(summaries.allSatisfy { !$0.isShared && $0.attachments.isEmpty })
    #expect(details.map(\.id) == ["selected-good", "selected-fallback", "selected-enumeration-fallback"])
    #expect(detailsById["selected-good"]?.isShared == true)
    #expect(detailsById["selected-good"]?.attachments == [
      NoteAttachment(id: "attachment-1", name: "Receipt.pdf", contentIdentifier: "cid-1")
    ])
    #expect(detailsById["selected-fallback"]?.isShared == false)
    #expect(detailsById["selected-fallback"]?.attachments.isEmpty == true)
    #expect(detailsById["selected-enumeration-fallback"]?.isShared == true)
    #expect(detailsById["selected-enumeration-fallback"]?.attachments.isEmpty == true)
    #expect(!NotesJXATemplate.fetchNoteMetadataBatch.source.contains("folderNotes.shared()"))
    #expect(!NotesJXATemplate.fetchNoteMetadataBatch.source.contains("folderNotes.attachments()"))
  }

  @Test func detailTemplatePreservesBridgePermissionTimeoutAndUnavailableErrors() throws {
    let source = NotesJXATemplate.fetchNoteMetadataBatch.source
      .replacingOccurrences(of: "Application('Notes')", with: "mockApplication('Notes')")
    let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)

    do {
      _ = try bridge.runJXA(
        script: notesHydrationMockSource + "\n" + source,
        argumentsJSON: #"{"noteIds":["permission-failure"],"includeDetails":true}"#
      )
      Issue.record("Expected selected-note hydration permission failure")
    } catch AppleEventBridgeError.automationDenied {
      // Expected bridge-level classification.
    }

    do {
      _ = try bridge.runJXA(
        script: notesHydrationMockSource + "\n" + source,
        argumentsJSON: #"{"noteIds":["timeout-failure"],"includeDetails":true}"#
      )
      Issue.record("Expected selected-note hydration timeout")
    } catch AppleEventBridgeError.timeout {
      // Expected bridge-level classification.
    }

    do {
      _ = try bridge.runJXA(
        script: notesHydrationMockSource + "\n" + source,
        argumentsJSON: #"{"noteIds":["app-unavailable"],"includeDetails":true}"#
      )
      Issue.record("Expected selected-note hydration app-unavailable failure")
    } catch AppleEventBridgeError.appUnavailable {
      // Expected bridge-level classification.
    }

    for noteId in ["connection-invalid-sharing", "connection-invalid-attachments"] {
      do {
        _ = try bridge.runJXA(
          script: notesHydrationMockSource + "\n" + source,
          argumentsJSON: "{\"noteIds\":[\"\(noteId)\"],\"includeDetails\":true}"
        )
        Issue.record("Expected selected-note hydration connection-invalid failure for \(noteId)")
      } catch AppleEventBridgeError.appUnavailable {
        // Expected bridge-level classification.
      }
    }
  }
}

private func hydrationNote(
  id: String,
  name: String,
  modified: TimeInterval,
  snippet: String = "",
  isShared: Bool = false,
  attachments: [NoteAttachment] = []
) -> Note {
  Note(
    id: id,
    accountId: "icloud",
    folderId: "inbox",
    name: name,
    snippet: snippet,
    isShared: isShared,
    creationDate: Date(timeIntervalSince1970: 0),
    modificationDate: Date(timeIntervalSince1970: modified),
    attachments: attachments
  )
}

private let notesHydrationMockSource = """
function mockProperty(value) {
  return function() { return value; };
}

function failingProperty(message, number) {
  return function() {
    const error = new Error(message);
    if (number !== null) {
      error.errorNumber = number;
    }
    throw error;
  };
}

function failingAttachmentCollection(number) {
  return {
    forEach: function() {
      const error = new Error('attachment enumeration unavailable');
      if (number !== null && number !== undefined) {
        error.errorNumber = number;
      }
      throw error;
    }
  };
}

function mockNote(id, shared, isShared, attachments) {
  return {
    id: mockProperty(id),
    name: mockProperty('Metadata ' + id),
    passwordProtected: mockProperty(false),
    shared: shared,
    isShared: isShared,
    creationDate: mockProperty(new Date('2026-07-03T10:00:00Z')),
    modificationDate: mockProperty(new Date('2026-07-03T11:00:00Z')),
    attachments: attachments
  };
}

const mockNotes = [
  mockNote(
    'selected-good',
    mockProperty(true),
    mockProperty(false),
    mockProperty([{
      id: mockProperty('attachment-1'),
      name: mockProperty('Receipt.pdf'),
      contentIdentifier: mockProperty('cid-1')
    }])
  ),
  mockNote(
    'selected-fallback',
    failingProperty('shared unavailable', null),
    failingProperty('isShared unavailable', null),
    failingProperty('attachments unavailable', null)
  ),
  mockNote(
    'selected-enumeration-fallback',
    mockProperty(true),
    mockProperty(false),
    mockProperty(failingAttachmentCollection())
  ),
  mockNote(
    'unselected',
    failingProperty('unselected shared must not be touched', -1712),
    failingProperty('unselected isShared must not be touched', -1712),
    failingProperty('unselected attachments must not be touched', -1743)
  ),
  mockNote(
    'permission-failure',
    failingProperty('not authorized for Notes automation -1743', -1743),
    mockProperty(false),
    mockProperty([])
  ),
  mockNote(
    'timeout-failure',
    failingProperty('Notes Apple Event timed out -1712', -1712),
    mockProperty(false),
    mockProperty([])
  ),
  mockNote(
    'app-unavailable',
    failingProperty('Notes application is not running -600', -600),
    mockProperty(false),
    mockProperty([])
  ),
  mockNote(
    'connection-invalid-sharing',
    failingProperty('Notes connection is invalid -609', -609),
    mockProperty(false),
    mockProperty([])
  ),
  mockNote(
    'connection-invalid-attachments',
    mockProperty(true),
    mockProperty(false),
    mockProperty(failingAttachmentCollection(-609))
  )
];

function mockNotesCollection(notes) {
  const collection = {};
  notes.forEach((note, index) => { collection[index] = note; });
  collection.id = function() { return notes.map(note => note.id()); };
  collection.passwordProtected = function() { return notes.map(note => note.passwordProtected()); };
  collection.name = function() { return notes.map(note => note.name()); };
  collection.creationDate = function() { return notes.map(note => note.creationDate()); };
  collection.modificationDate = function() { return notes.map(note => note.modificationDate()); };
  collection.shared = failingProperty('folder-wide shared access is forbidden', -1712);
  collection.attachments = failingProperty('folder-wide attachment access is forbidden', -1743);
  return collection;
}

function mockApplication(name) {
  return {
    accounts: mockProperty([{
      id: mockProperty('icloud'),
      folders: mockProperty([{
        id: mockProperty('inbox'),
        notes: mockNotesCollection(mockNotes)
      }])
    }])
  };
}
"""
