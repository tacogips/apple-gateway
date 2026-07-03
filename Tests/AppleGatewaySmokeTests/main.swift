import AppleGatewayCore
import Foundation

@main
struct AppleGatewaySmokeTests {
  static func main() {
    do {
      try runSmokeTests()
      FileHandle.standardOutput.write(Data("AppleGatewaySmokeTests: passed\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("AppleGatewaySmokeTests: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }

  private static func runSmokeTests() throws {
    try queryAndQueryFileExclusivity()
    try invalidVariablesBecomeBusinessEnvelope()
    try globalPrettyFormatsJSON()
    try readerRejectsMutation()
    try unknownCommandIsUsageError()
    try noConfigPermissionsGraphQLEnvelope()
    try fakeBackedFileDownload()
    try fakeBackedCalendarReminderGraphQLFlows()
    try fakeBackedNotesGraphQLFlows()
  }

  private static func queryAndQueryFileExclusivity() throws {
    let root = try SmokeTemporaryDirectory()
    let queryPath = try root.write("query.graphql", "{ permissions { calendars } }")
    let result = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query", "{ permissions { calendars } }",
        "--query-file", queryPath
      ],
      environment: ["HOME": root.home]
    )

    try expect(result.exitCode == 2, "query/query-file exclusivity exits 2")
    try expect(result.stdout.isEmpty, "usage error leaves stdout empty")
    try expect(result.stderr.contains("Exactly one of --query or --query-file"), "usage diagnostic is on stderr")
  }

  private static func invalidVariablesBecomeBusinessEnvelope() throws {
    let root = try SmokeTemporaryDirectory()
    let result = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query", "query($unused: String = \"default\") { permissions { calendars } }",
        "--variables", "[]"
      ],
      environment: ["HOME": root.home]
    )
    let code = try firstErrorCode(in: result.stdout)

    try expect(result.exitCode == 5, "invalid variables exit 5")
    try expect(result.stderr.isEmpty, "invalid variables keep stderr empty")
    try expect(code == "INVALID_ARGUMENT", "invalid variables use INVALID_ARGUMENT")
  }

  private static func globalPrettyFormatsJSON() throws {
    let root = try SmokeTemporaryDirectory()
    let result = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "--pretty",
        "graphql",
        "--query", "{ permissions { calendars } }"
      ],
      environment: ["HOME": root.home]
    )

    try expect(result.exitCode == 0, "pretty GraphQL succeeds")
    try expect(result.stderr.isEmpty, "pretty GraphQL leaves stderr empty")
    try expect(result.stdout.contains("\n"), "pretty GraphQL contains newlines")
    try expect(result.stdout.contains("\"data\" :"), "pretty GraphQL formats sorted envelope keys")
  }

  private static func readerRejectsMutation() throws {
    let root = try SmokeTemporaryDirectory()
    let result = runCommand(
      role: .reader,
      arguments: [
        "apple-gateway-reader",
        "graphql",
        "--query", "mutation { noop }"
      ],
      environment: ["HOME": root.home]
    )
    let code = try firstErrorCode(in: result.stdout)

    try expect(result.exitCode == 5, "reader mutation rejection exits 5")
    try expect(result.stderr.isEmpty, "reader mutation rejection leaves stderr empty")
    try expect(code == "WRITE_DISABLED_IN_READER", "reader mutation rejection code")
  }

  private static func unknownCommandIsUsageError() throws {
    let root = try SmokeTemporaryDirectory()
    let result = runCommand(
      role: .full,
      arguments: ["apple-gateway", "unknown"],
      environment: ["HOME": root.home]
    )

    try expect(result.exitCode == 2, "unknown command exits 2")
    try expect(result.stdout.isEmpty, "unknown command leaves stdout empty")
    try expect(result.stderr.contains("Unknown command"), "unknown command diagnostic is on stderr")
  }

  private static func noConfigPermissionsGraphQLEnvelope() throws {
    let root = try SmokeTemporaryDirectory()
    let result = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query", "{ permissions { calendars } }"
      ],
      environment: ["HOME": root.home]
    )

    try expect(result.exitCode == 0, "no-config permissions GraphQL succeeds")
    try expect(result.stderr.isEmpty, "no-config permissions GraphQL leaves stderr empty")
    try expect(result.stdout.contains("\"permissions\""), "no-config permissions envelope has data")
    try expect(result.stdout.contains("\"calendars\":\"GRANTED\""), "no-config permissions uses fake provider")
  }

  private static func fakeBackedFileDownload() throws {
    let root = try SmokeTemporaryDirectory()
    let source = root.root.appendingPathComponent("source.txt")
    let cache = root.root.appendingPathComponent("cache")
    try Data("body".utf8).write(to: source)
    let key = try FileStore(cacheRoot: cache.path).issueDownloadKey(
      FileStoreDownloadKeyPayload(
        domain: .mail,
        sourceId: "message-1",
        kind: .bodyText,
        filename: "body.txt"
      )
    )
    let result = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "file",
        "download",
        "--key", key
      ],
      environment: [
        "HOME": root.home,
        "APPLE_GATEWAY_STORAGE_CACHE_DIR": cache.path
      ],
      fileMaterializer: SmokeFileMaterializer(source: source)
    )

    try expect(result.exitCode == 0, "fake-backed file download succeeds")
    try expect(result.stderr.isEmpty, "fake-backed file download leaves stderr empty")
    try expect(result.stdout.contains("\"BODY_TEXT\""), "fake-backed file download returns manifest")
  }

  private static func fakeBackedCalendarReminderGraphQLFlows() throws {
    let root = try SmokeTemporaryDirectory()
    let fake = try SmokeCalendarReminderProvider()
    let readService = CalendarReadService(calendarProvider: fake, remindersProvider: fake)
    let writeService = CalendarWriteService(
      calendarProvider: fake,
      calendarWriter: fake,
      remindersProvider: fake,
      remindersWriter: fake
    )

    let createEvent = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        mutation {
          createEvent(input: {
            title: "Planning",
            startDate: "2026-07-01T09:00:00Z",
            endDate: "2026-07-01T10:00:00Z",
            alarms: [{ relativeOffsetSeconds: -600 }]
          }) { id title alarms { relativeOffsetSeconds } }
        }
        """
      ],
      environment: ["HOME": root.home],
      calendarReadService: readService,
      calendarWriteService: writeService
    )
    try expect(createEvent.exitCode == 0, "fake-backed create event succeeds")
    try expect(createEvent.stdout.contains("\"id\":\"event-2\""), "fake-backed create event returns id")
    try expect(createEvent.stdout.contains("\"relativeOffsetSeconds\":-600"), "fake-backed create event returns alarm")

    let searchEvents = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        {
          events(input: {
            startDate: "2026-07-01T00:00:00Z",
            endDate: "2026-07-02T00:00:00Z"
          }) { totalCount edges { node { id title } } }
        }
        """
      ],
      environment: ["HOME": root.home],
      calendarReadService: readService,
      calendarWriteService: writeService
    )
    try expect(searchEvents.exitCode == 0, "fake-backed event search succeeds")
    try expect(searchEvents.stdout.contains("\"totalCount\":2"), "fake-backed event search sees created event")

    let updateEvent = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        mutation {
          updateEvent(input: {
            eventId: "event-1",
            span: FUTURE_EVENTS,
            title: "Future planning"
          }) { id title }
        }
        """
      ],
      environment: ["HOME": root.home],
      calendarReadService: readService,
      calendarWriteService: writeService
    )
    try expect(updateEvent.exitCode == 0, "fake-backed update event succeeds")
    try expect(updateEvent.stdout.contains("\"title\":\"Future planning\""), "fake-backed update event returns title")
    try expect(fake.lastEventSaveRequest?.span == .futureEvents, "fake-backed update event preserves span")

    let completeReminder = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        mutation {
          setReminderCompleted(reminderId: "reminder-1", completed: true) {
            id
            isCompleted
          }
        }
        """
      ],
      environment: ["HOME": root.home],
      calendarReadService: readService,
      calendarWriteService: writeService
    )
    try expect(completeReminder.exitCode == 0, "fake-backed complete reminder succeeds")
    try expect(completeReminder.stdout.contains("\"isCompleted\":true"), "fake-backed reminder is completed")

    let readerCreate = runCommand(
      role: .reader,
      arguments: [
        "apple-gateway-reader",
        "graphql",
        "--query",
        #"mutation { createReminder(input: { title: "Blocked" }) { id } }"#
      ],
      environment: ["HOME": root.home],
      calendarReadService: readService,
      calendarWriteService: writeService
    )
    let readerCode = try firstErrorCode(in: readerCreate.stdout)
    try expect(readerCreate.exitCode == 5, "reader rejects calendar/reminders mutation")
    try expect(readerCode == "WRITE_DISABLED_IN_READER", "reader domain mutation rejection code")
  }

  private static func fakeBackedNotesGraphQLFlows() throws {
    let root = try SmokeTemporaryDirectory()
    let fake = SmokeNotesProvider()
    let readService = NotesReadService(provider: fake)
    let writeService = NotesWriteService(provider: fake, writer: fake)

    let createNote = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        mutation {
          createNote(input: { folderId: "inbox", title: "Release", bodyText: "Ship" }) {
            id
            name
            bodyHtml
          }
        }
        """
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    try expect(createNote.exitCode == 0, "fake-backed create note succeeds")
    try expect(createNote.stdout.contains("\"id\":\"note-2\""), "fake-backed create note returns id")
    try expect(createNote.stdout.contains("\"bodyHtml\""), "fake-backed create note returns bodyHtml")
    try expect(createNote.stdout.contains("Ship"), "fake-backed create note returns body content")

    let searchNotes = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        {
          notes(input: { query: "Ship", first: 5 }) {
            totalCount
            edges { node { id name snippet plaintext bodyHtml } }
          }
        }
        """
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    try expect(searchNotes.exitCode == 0, "fake-backed notes search succeeds")
    try expect(searchNotes.stdout.contains("\"totalCount\":1"), "fake-backed notes search sees created note")
    try expect(searchNotes.stdout.contains("\"plaintext\":null"), "fake-backed notes search excludes bodies")

    let appendNote = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        mutation {
          updateNoteBody(input: { noteId: "note-2", mode: APPEND, bodyHtml: "<div>Verify</div>" }) {
            id
            bodyHtml
          }
        }
        """
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    try expect(appendNote.exitCode == 0, "fake-backed append note succeeds")
    try expect(appendNote.stdout.contains("Ship"), "fake-backed append note keeps existing body")
    try expect(appendNote.stdout.contains("Verify"), "fake-backed append note returns appended body")

    let moveNote = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        #"mutation { moveNote(noteId: "note-2", folderId: "archive") { id folderId } }"#
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    try expect(moveNote.exitCode == 0, "fake-backed move note succeeds")
    try expect(moveNote.stdout.contains("\"folderId\":\"archive\""), "fake-backed move note returns folder")

    let deleteNote = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        #"mutation { deleteNote(noteId: "note-2") { success } }"#
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    try expect(deleteNote.exitCode == 0, "fake-backed delete note succeeds")
    try expect(deleteNote.stdout.contains("\"success\":true"), "fake-backed delete note returns success")

    let readerCreate = runCommand(
      role: .reader,
      arguments: [
        "apple-gateway-reader",
        "graphql",
        "--query",
        #"mutation { createNote(input: { title: "Blocked", bodyText: "No" }) { id } }"#
      ],
      environment: ["HOME": root.home],
      notesReadService: readService,
      notesWriteService: writeService
    )
    let readerCode = try firstErrorCode(in: readerCreate.stdout)
    try expect(readerCreate.exitCode == 5, "reader rejects notes mutation")
    try expect(readerCode == "WRITE_DISABLED_IN_READER", "reader notes mutation rejection code")
  }

  private static func runCommand(
    role: AppleGatewayRole,
    arguments: [String],
    environment: [String: String],
    fileMaterializer: any FileStoreMaterializing = UnavailableFileStoreMaterializer(),
    calendarReadService: CalendarReadService = CalendarReminderServiceFactory.unavailableReadService(),
    calendarWriteService: CalendarWriteService = CalendarReminderServiceFactory.unavailableWriteService(),
    notesReadService: NotesReadService = NotesServiceFactory.unavailableReadService(),
    notesWriteService: NotesWriteService = NotesServiceFactory.unavailableWriteService()
  ) -> CapturedCommandResult {
    let stdout = Pipe()
    let stderr = Pipe()
    let exitCode = AppleGatewayCommandLine.run(
      role: role,
      arguments: arguments,
      environment: environment,
      permissionsProvider: SmokePermissionsProvider(),
      responsibleProcessDetector: SmokeResponsibleProcessDetector(),
      fileMaterializer: fileMaterializer,
      calendarReadService: calendarReadService,
      calendarWriteService: calendarWriteService,
      notesReadService: notesReadService,
      notesWriteService: notesWriteService,
      standardOutput: stdout.fileHandleForWriting,
      standardError: stderr.fileHandleForWriting
    )
    stdout.fileHandleForWriting.closeFile()
    stderr.fileHandleForWriting.closeFile()
    return CapturedCommandResult(
      exitCode: exitCode,
      stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
      stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
  }

  private static func firstErrorCode(in output: String) throws -> String {
    let object = try JSONSerialization.jsonObject(with: Data(output.utf8))
    guard
      let envelope = object as? [String: Any],
      let errors = envelope["errors"] as? [[String: Any]],
      let extensions = errors.first?["extensions"] as? [String: Any],
      let code = extensions["code"] as? String
    else {
      throw SmokeError("missing error code in envelope")
    }
    return code
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      throw SmokeError(message)
    }
  }
}

private struct CapturedCommandResult {
  var exitCode: Int32
  var stdout: String
  var stderr: String
}

private struct SmokeTemporaryDirectory {
  let root: URL
  let home: String

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-smoke-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    home = root.appendingPathComponent("home").path
    try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
  }

  func write(_ name: String, _ contents: String) throws -> String {
    let path = root.appendingPathComponent(name).path
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }
}

private final class SmokePermissionsProvider: PermissionsProviding, @unchecked Sendable {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted),
      reminders: PermissionFieldStatus(state: .denied),
      notesAutomation: PermissionFieldStatus(state: .notDetermined),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      shortcutsClockBridge: PermissionFieldStatus(state: .notRequired)
    )
  }

  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}

private struct SmokeResponsibleProcessDetector: ResponsibleProcessDetecting {
  func responsibleProcessHint() -> String? {
    "smoke-test"
  }
}

private struct SmokeFileMaterializer: FileStoreMaterializing {
  var source: URL

  func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    source
  }
}

private final class SmokeCalendarReminderProvider: CalendarProviding, CalendarWriting, RemindersProviding, RemindersWriting, @unchecked Sendable {
  private var calendarsStore: [GatewayCalendar]
  private var eventsStore: [CalendarEvent]
  private var remindersStore: [Reminder]
  var lastEventSaveRequest: CalendarEventSaveRequest?

  init() throws {
    let startDate = try EventKitDateTime.parse("2026-07-01T09:00:00Z")
    let endDate = try EventKitDateTime.parse("2026-07-01T10:00:00Z")
    calendarsStore = [
      GatewayCalendar(
        id: "cal-1",
        title: "Work",
        entityType: .event,
        sourceTitle: "iCloud",
        sourceType: "CalDAV",
        allowsModifications: true,
        isSubscribed: false,
        isDefault: true
      ),
      GatewayCalendar(
        id: "list-1",
        title: "Inbox",
        entityType: .reminder,
        sourceTitle: "iCloud",
        sourceType: "CalDAV",
        allowsModifications: true,
        isSubscribed: false,
        isDefault: true
      )
    ]
    eventsStore = [
      CalendarEvent(
        id: "event-1",
        calendarId: "cal-1",
        title: "Planning",
        startDate: startDate,
        endDate: endDate
      )
    ]
    remindersStore = [
      Reminder(id: "reminder-1", listId: "list-1", title: "Submit report")
    ]
  }

  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    calendarsStore.filter { calendar in
      guard let entityType else {
        return calendar.entityType == .event
      }
      return calendar.entityType == entityType
    }
  }

  func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    eventsStore
  }

  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    eventsStore.first { $0.id == eventId }
  }

  func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    throw SmokeError("createCalendar is not used by smoke tests")
  }

  func deleteCalendar(calendarId: String) throws -> DeleteResult {
    throw SmokeError("deleteCalendar is not used by smoke tests")
  }

  func createEvent(_ event: CalendarEvent) throws -> CalendarEvent {
    var created = event
    created.id = "event-\(eventsStore.count + 1)"
    eventsStore.append(created)
    return created
  }

  func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent {
    lastEventSaveRequest = request
    if let index = eventsStore.firstIndex(where: { $0.id == request.event.id }) {
      eventsStore[index] = request.event
    }
    return request.event
  }

  func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult {
    eventsStore.removeAll { $0.id == request.eventId }
    return DeleteResult(success: true)
  }

  func reminderLists() throws -> [GatewayCalendar] {
    calendarsStore.filter { $0.entityType == .reminder }
  }

  func reminders() throws -> [Reminder] {
    remindersStore
  }

  func reminder(reminderId: String) throws -> Reminder? {
    remindersStore.first { $0.id == reminderId }
  }

  func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    throw SmokeError("createReminderList is not used by smoke tests")
  }

  func createReminder(_ reminder: Reminder) throws -> Reminder {
    var created = reminder
    created.id = "reminder-\(remindersStore.count + 1)"
    remindersStore.append(created)
    return created
  }

  func updateReminder(_ reminder: Reminder) throws -> Reminder {
    if let index = remindersStore.firstIndex(where: { $0.id == reminder.id }) {
      remindersStore[index] = reminder
    }
    return reminder
  }

  func deleteReminder(reminderId: String) throws -> DeleteResult {
    remindersStore.removeAll { $0.id == reminderId }
    return DeleteResult(success: true)
  }
}

private final class SmokeNotesProvider: NotesProviding, NotesWriting, @unchecked Sendable {
  private var notesStore: [String: Note] = [
    "note-1": smokeNote(
      id: "note-1",
      folderId: "inbox",
      name: "Planning",
      plaintext: "Initial planning",
      bodyHtml: "<div>Initial planning</div>"
    )
  ]
  private var deletedNoteIds: [String] = []

  func accounts() throws -> [NoteAccount] {
    [NoteAccount(id: "icloud", name: "iCloud", isDefault: true)]
  }

  func folders(accountId: String?) throws -> [NoteFolder] {
    [
      NoteFolder(id: "inbox", accountId: "icloud", name: "Notes", noteCount: notesStore.count),
      NoteFolder(id: "archive", accountId: "icloud", name: "Archive", noteCount: 0)
    ].filter { folder in
      accountId.map { folder.accountId == $0 } ?? true
    }
  }

  func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    notesStore.values.filter { note in
      (accountId.map { note.accountId == $0 } ?? true)
        && (folderId.map { note.folderId == $0 } ?? true)
    }
    .map(\.id)
  }

  func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] {
    noteIds.compactMap { notesStore[$0] }
  }

  func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] {
    notesStore.values.filter { note in
      (input.accountId.map { note.accountId == $0 } ?? true)
        && (input.folderId.map { note.folderId == $0 } ?? true)
        && ((note.plaintext ?? "").localizedCaseInsensitiveContains(input.query)
          || (note.bodyHtml ?? "").localizedCaseInsensitiveContains(input.query))
    }
    .map(\.id)
  }

  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    Dictionary(uniqueKeysWithValues: noteIds.map { ($0, notesStore[$0]?.snippet ?? "") })
  }

  func noteMetadata(noteId: String) throws -> NoteLookupResult {
    notesStore[noteId].map(NoteLookupResult.found) ?? .missing
  }

  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    guard let note = notesStore[noteId] else {
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

  func createNote(_ request: NotesCreateRequest) throws -> String {
    let noteId = "note-\(notesStore.count + deletedNoteIds.count + 1)"
    notesStore[noteId] = smokeNote(
      id: noteId,
      folderId: request.folderId,
      name: request.title,
      plaintext: request.bodyHtml,
      bodyHtml: request.bodyHtml
    )
    return noteId
  }

  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String {
    guard var note = notesStore[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.bodyHtml = request.bodyHtml
    notesStore[request.noteId] = note
    return request.noteId
  }

  func deleteNote(noteId: String) throws -> DeleteResult {
    notesStore.removeValue(forKey: noteId)
    deletedNoteIds.append(noteId)
    return DeleteResult(success: true)
  }

  func moveNote(_ request: NotesMoveRequest) throws -> String {
    guard var note = notesStore[request.noteId] else {
      throw AppleGatewayError(code: .noteNotFound, message: "Note not found")
    }
    note.accountId = request.accountId
    note.folderId = request.folderId
    notesStore[request.noteId] = note
    return request.noteId
  }
}

private func smokeNote(
  id: String,
  accountId: String = "icloud",
  folderId: String,
  name: String,
  plaintext: String? = nil,
  bodyHtml: String? = nil
) -> Note {
  Note(
    id: id,
    accountId: accountId,
    folderId: folderId,
    name: name,
    snippet: plaintext ?? bodyHtml ?? "",
    plaintext: plaintext,
    bodyHtml: bodyHtml,
    creationDate: Date(timeIntervalSince1970: 10),
    modificationDate: Date(timeIntervalSince1970: 20)
  )
}

private struct SmokeError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
