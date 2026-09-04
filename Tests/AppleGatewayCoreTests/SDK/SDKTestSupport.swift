import Foundation
@testable import AppleGatewayCore

final class SDKCalendarDouble: CalendarProviding, CalendarWriting, RemindersProviding, RemindersWriting, @unchecked Sendable {
  private(set) var calendarRequests: [CalendarEntityType?] = []
  private(set) var eventWindows: [EventFetchWindow] = []
  private(set) var createdReminders: [Reminder] = []

  let eventCalendar = GatewayCalendar(
    id: "calendar-1", title: "Work", entityType: .event, sourceTitle: "iCloud",
    sourceType: "CalDAV", allowsModifications: true, isSubscribed: false, isDefault: true
  )
  let reminderList = GatewayCalendar(
    id: "list-1", title: "Inbox", entityType: .reminder, sourceTitle: "iCloud",
    sourceType: "CalDAV", allowsModifications: true, isSubscribed: false, isDefault: true
  )
  let event = CalendarEvent(
    id: "event-1", calendarId: "calendar-1", title: "Planning",
    startDate: SDKFixtures.startDate, endDate: SDKFixtures.endDate
  )

  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    calendarRequests.append(entityType)
    switch entityType {
    case .event: return [eventCalendar]
    case .reminder: return [reminderList]
    case nil: return [eventCalendar, reminderList]
    }
  }

  func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    eventWindows.append(window)
    return [event]
  }

  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    eventId == event.id ? event : nil
  }

  func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar { eventCalendar }
  func deleteCalendar(calendarId: String) throws -> DeleteResult { DeleteResult(success: true) }
  func createEvent(_ event: CalendarEvent) throws -> CalendarEvent { event }
  func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent { request.event }
  func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult { DeleteResult(success: true) }

  func reminderLists() throws -> [GatewayCalendar] { [reminderList] }
  func reminders() throws -> [Reminder] { createdReminders }
  func reminder(reminderId: String) throws -> Reminder? { createdReminders.first { $0.id == reminderId } }
  func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar { reminderList }

  func createReminder(_ reminder: Reminder) throws -> Reminder {
    var created = reminder
    created.id = "reminder-\(createdReminders.count + 1)"
    createdReminders.append(created)
    return created
  }

  func updateReminder(_ reminder: Reminder) throws -> Reminder { reminder }
  func deleteReminder(reminderId: String) throws -> DeleteResult { DeleteResult(success: true) }
}

final class SDKNotesDouble: NotesProviding, NotesWriting, @unchecked Sendable {
  private(set) var noteIDsRequests = 0
  let note = Note(
    id: "note-1", accountId: "icloud", folderId: "inbox", name: "Release",
    snippet: "release checklist", plaintext: "release checklist",
    bodyHtml: "<div>release checklist</div>",
    creationDate: Date(timeIntervalSince1970: 1), modificationDate: Date(timeIntervalSince1970: 2)
  )

  func accounts() throws -> [NoteAccount] { [NoteAccount(id: "icloud", name: "iCloud", isDefault: true)] }
  func folders(accountId: String?) throws -> [NoteFolder] {
    [NoteFolder(id: "inbox", accountId: "icloud", name: "Notes", noteCount: 1)]
  }
  func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    noteIDsRequests += 1
    return [note.id]
  }
  func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] { [note] }
  func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] { [note.id] }
  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    [note.id: note.snippet]
  }
  func noteMetadata(noteId: String) throws -> NoteLookupResult { noteId == note.id ? .found(note) : .missing }
  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    noteId == note.id ? .found(NoteBodyFetchResult(note: note, kind: kind, body: note.plaintext ?? "")) : .missing
  }
  func exportAttachment(noteId: String, attachmentId: String, to destination: URL) throws -> NotesAttachmentExportResult { .unavailable }
  func createNote(_ request: NotesCreateRequest) throws -> String { note.id }
  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String { note.id }
  func deleteNote(noteId: String) throws -> DeleteResult { DeleteResult(success: true) }
  func moveNote(_ request: NotesMoveRequest) throws -> String { note.id }
}

enum SDKFixtures {
  static let startDate = Date(timeIntervalSince1970: 1_767_262_400)
  static let endDate = Date(timeIntervalSince1970: 1_767_266_000)

  static func calendarServices(_ double: SDKCalendarDouble) -> (CalendarReadService, CalendarWriteService) {
    (
      CalendarReadService(calendarProvider: double, remindersProvider: double),
      CalendarWriteService(
        calendarProvider: double, calendarWriter: double,
        remindersProvider: double, remindersWriter: double
      )
    )
  }

  static func notesServices(_ double: SDKNotesDouble) -> (NotesReadService, NotesWriteService) {
    (NotesReadService(provider: double), NotesWriteService(provider: double, writer: double))
  }

  static func normalizeRequestID(_ output: String) -> String {
    output.replacingOccurrences(
      of: #""requestId":"[^"]+""#,
      with: #""requestId":"REQUEST_ID""#,
      options: .regularExpression
    )
  }
}

struct SDKTestHome {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "apple-gateway-sdk-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func environment(_ overrides: [String: String] = [:]) -> [String: String] {
    ["HOME": url.path].merging(overrides, uniquingKeysWith: { _, override in override })
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}
