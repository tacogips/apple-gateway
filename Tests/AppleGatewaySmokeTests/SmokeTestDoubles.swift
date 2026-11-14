import AppleGatewayCore
import Foundation

struct CapturedCommandResult {
  var exitCode: Int32
  var stdout: String
  var stderr: String
}

struct SmokeTemporaryDirectory {
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

final class SmokePermissionsProvider: PermissionsProviding, @unchecked Sendable {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted),
      reminders: PermissionFieldStatus(state: .denied),
      notesAutomation: PermissionFieldStatus(state: .notDetermined),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .notRequired)
    )
  }

  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}

struct SmokeResponsibleProcessDetector: ResponsibleProcessDetecting {
  func responsibleProcessHint() -> String? {
    "smoke-test"
  }
}

struct SmokeFileMaterializer: FileStoreMaterializing {
  var source: URL

  func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    source
  }
}

final class SmokeMailProvider: MailProviding, @unchecked Sendable {
  private let files: MailMessageFileSet

  init(files: MailMessageFileSet) {
    self.files = files
  }

  func accounts() throws -> [MailAccount] {
    [MailAccount(id: "mail-account-smoke", name: "Smoke Mail", kind: .imap)]
  }

  func mailboxes(accountId: String?) throws -> [Mailbox] {
    guard accountId == nil || accountId == "mail-account-smoke" else {
      throw AppleGatewayError(code: .invalidArgument, message: "Unknown Mail account id")
    }
    return [
      Mailbox(
        id: "mailbox-smoke",
        accountId: "mail-account-smoke",
        name: "INBOX",
        path: "INBOX",
        totalCount: 1,
        unreadCount: 0
      )
    ]
  }

  func messages(input: MailSearchInput) throws -> MailMessageConnection {
    MailMessageConnection(
      edges: [MailMessageEdge(cursor: "mail-cursor-smoke", node: message)],
      pageInfo: PageInfo(hasNextPage: false, endCursor: "mail-cursor-smoke"),
      totalCount: 1
    )
  }

  func message(messageId: String) throws -> MailMessage? {
    messageId == "message-smoke" ? message : nil
  }

  private var message: MailMessage {
    MailMessage(
      id: "message-smoke",
      mailboxId: "mailbox-smoke",
      accountId: "mail-account-smoke",
      messageId: "rfc-smoke",
      subject: "Smoke Mail",
      snippet: "Smoke snippet",
      from: MailAddress(raw: "Smoke <smoke@example.com>", name: "Smoke", email: "smoke@example.com"),
      to: [MailAddress(raw: "QA <qa@example.com>", name: "QA", email: "qa@example.com")],
      cc: [],
      dateSent: Date(timeIntervalSince1970: 1_783_000_000),
      dateReceived: Date(timeIntervalSince1970: 1_783_000_060),
      isRead: true,
      isFlagged: false,
      hasAttachments: false,
      files: files
    )
  }
}

final class SmokeNotificationsProvider: NotificationsProviding, @unchecked Sendable {
  func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    DeliveredNotificationConnection(
      edges: [
        DeliveredNotificationEdge(
          cursor: "notification-smoke-cursor",
          node: DeliveredNotification(
            id: "system-db-1",
            source: .systemDb,
            appBundleId: "com.example.smoke",
            title: "Smoke notification",
            deliveredAt: "2026-07-03T12:00:00Z"
          )
        )
      ],
      pageInfo: PageInfo(hasNextPage: false, endCursor: "notification-smoke-cursor"),
      totalCount: 1
    )
  }

  func postNotification(_ input: PostNotificationInput) throws -> PostedNotification {
    PostedNotification(id: "notification-smoke", delivered: true, usedFallback: input.allowFallback)
  }

  func listGatewayNotifications() throws -> [DeliveredNotification] {
    []
  }

  func dismissNotifications(ids: [String]) throws -> DismissResult {
    DismissResult(dismissedCount: ids.count)
  }

  func dismissAllGatewayNotifications() throws -> DismissResult {
    DismissResult(dismissedCount: 0)
  }
}

struct SmokeUnavailableNotificationsProvider: NotificationsProviding {
  func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    throw unavailable()
  }

  func postNotification(_ input: PostNotificationInput) throws -> PostedNotification {
    throw unavailable()
  }

  func listGatewayNotifications() throws -> [DeliveredNotification] {
    throw unavailable()
  }

  func dismissNotifications(ids: [String]) throws -> DismissResult {
    throw unavailable()
  }

  func dismissAllGatewayNotifications() throws -> DismissResult {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Smoke notifications provider is unavailable")
  }
}

final class SmokeClockAlarmsProvider: ClockAlarmsProviding, @unchecked Sendable {
  func clockAlarms() throws -> [ClockAlarm] {
    [ClockAlarm(label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday])]
  }

  func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    ClockAlarmResult(
      success: true,
      alarm: ClockAlarm(label: input.label ?? "", time: input.time, isEnabled: true, repeatDays: input.repeatDays)
    )
  }

  func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    ClockAlarmResult(success: true, alarm: ClockAlarm(label: input.label, time: "07:30", isEnabled: input.enabled ?? false))
  }

  func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    ClockAlarmResult(success: true, alarm: ClockAlarm(label: input.newLabel ?? input.label, time: input.time ?? "07:30", isEnabled: true))
  }

  func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    ClockAlarmResult(success: true)
  }
}

struct SmokeUnavailableClockAlarmsProvider: ClockAlarmsProviding {
  func clockAlarms() throws -> [ClockAlarm] {
    throw unavailable()
  }

  func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Smoke clock alarms provider is unavailable")
  }
}

final class SmokeCalendarReminderProvider: CalendarProviding, CalendarWriting, RemindersProviding, RemindersWriting, @unchecked Sendable {
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

final class SmokeNotesProvider: NotesProviding, NotesWriting, @unchecked Sendable {
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

  func exportAttachment(
    noteId: String,
    attachmentId: String,
    to destination: URL
  ) throws -> NotesAttachmentExportResult {
    .unavailable
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

func smokeNote(
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

struct SmokeError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
