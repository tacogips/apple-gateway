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
    try fakeBackedMailGraphQLFlows()
    try fakeBackedNotificationsGraphQLFlows()
    try fakeBackedClockAlarmsGraphQLFlows()
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

  private static func fakeBackedMailGraphQLFlows() throws {
    let root = try SmokeTemporaryDirectory()
    let cache = root.root.appendingPathComponent("cache")
    let emlx = root.root.appendingPathComponent("message.emlx")
    try writeEMLX(
      raw: """
      Content-Type: text/plain; charset="utf-8"

      Smoke mail body
      """,
      to: emlx
    )
    let fileStore = FileStore(cacheRoot: cache.path)
    let files = try MailMessageFileFactory(fileStore: fileStore).files(emlxPath: emlx.path)
    let fake = SmokeMailProvider(files: files)
    let readService = MailReadService(provider: fake)
    let mailQuery = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        {
          mailAccounts { id name kind }
          mailboxes(accountId: "mail-account-smoke") { id path }
          mailMessages(input: { first: 5 }) {
            totalCount
            edges { node { id subject files { bodyText { kind downloadKey } } } }
          }
          mailMessage(messageId: "message-smoke") { id files { rawSource { kind } } }
        }
        """
      ],
      environment: [
        "HOME": root.home,
        "APPLE_GATEWAY_STORAGE_CACHE_DIR": cache.path
      ],
      mailReadService: readService
    )

    try expect(mailQuery.exitCode == 0, "fake-backed Mail GraphQL succeeds")
    try expect(mailQuery.stderr.isEmpty, "fake-backed Mail GraphQL leaves stderr empty")
    try expect(mailQuery.stdout.contains("\"mailAccounts\""), "fake-backed Mail GraphQL returns accounts")
    try expect(mailQuery.stdout.contains("\"BODY_TEXT\""), "fake-backed Mail GraphQL returns body key")

    let bodyKey = try requireBodyTextKey(in: files)
    let download = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "file",
        "download",
        "--key", bodyKey
      ],
      environment: [
        "HOME": root.home,
        "APPLE_GATEWAY_STORAGE_CACHE_DIR": cache.path
      ],
      fileMaterializer: MailFileMaterializer()
    )

    try expect(download.exitCode == 0, "fake-backed Mail file download succeeds")
    try expect(download.stderr.isEmpty, "fake-backed Mail file download leaves stderr empty")
    try expect(download.stdout.contains("\"BODY_TEXT\""), "fake-backed Mail file download returns manifest")
  }

  private static func fakeBackedNotificationsGraphQLFlows() throws {
    let root = try SmokeTemporaryDirectory()
    let fake = SmokeNotificationsProvider()
    let query = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        """
        {
          notifications(input: { source: SYSTEM_DB, first: 5 }) {
            totalCount
            edges { node { id source title } }
          }
        }
        """
      ],
      environment: ["HOME": root.home],
      notificationsService: fake
    )
    try expect(query.exitCode == 0, "fake-backed notifications query succeeds")
    try expect(query.stdout.contains("\"source\":\"SYSTEM_DB\""), "fake-backed notifications query returns source")

    let post = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        #"mutation { postNotification(input: { title: "Smoke", allowFallback: true }) { id usedFallback } }"#
      ],
      environment: ["HOME": root.home],
      notificationsService: fake
    )
    try expect(post.exitCode == 0, "fake-backed notification post succeeds")
    try expect(post.stdout.contains("\"id\":\"notification-smoke\""), "fake-backed notification post returns id")

    let invalidDismiss = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        #"mutation { dismissNotifications(ids: ["system-db-1"]) { dismissedCount } }"#
      ],
      environment: ["HOME": root.home],
      notificationsService: fake
    )
    let code = try firstErrorCode(in: invalidDismiss.stdout)
    try expect(invalidDismiss.exitCode == 5, "SYSTEM_DB dismiss rejection exits 5")
    try expect(code == "INVALID_ARGUMENT", "SYSTEM_DB dismiss rejection code")
  }

  private static func fakeBackedClockAlarmsGraphQLFlows() throws {
    let root = try SmokeTemporaryDirectory()
    let fake = SmokeClockAlarmsProvider()
    let query = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        "{ clockAlarms { label time isEnabled repeatDays } }"
      ],
      environment: ["HOME": root.home],
      clockAlarmsService: fake
    )
    try expect(query.exitCode == 0, "fake-backed clock alarms query succeeds")
    try expect(query.stdout.contains("\"clockAlarms\""), "fake-backed clock alarms query returns data")
    try expect(query.stdout.contains("\"MONDAY\""), "fake-backed clock alarms query returns repeat days")

    let create = runCommand(
      role: .full,
      arguments: [
        "apple-gateway",
        "graphql",
        "--query",
        #"mutation { createClockAlarm(input: { time: "09:00", label: "Focus" }) { success alarm { label time } } }"#
      ],
      environment: ["HOME": root.home],
      clockAlarmsService: fake
    )
    try expect(create.exitCode == 0, "fake-backed create clock alarm succeeds")
    try expect(create.stdout.contains("\"label\":\"Focus\""), "fake-backed create clock alarm returns label")

    let readerCreate = runCommand(
      role: .reader,
      arguments: [
        "apple-gateway-reader",
        "graphql",
        "--query",
        #"mutation { createClockAlarm(input: { time: "09:00" }) { success } }"#
      ],
      environment: ["HOME": root.home],
      clockAlarmsService: fake
    )
    let readerCode = try firstErrorCode(in: readerCreate.stdout)
    try expect(readerCreate.exitCode == 5, "reader rejects clock alarm mutation")
    try expect(readerCode == "WRITE_DISABLED_IN_READER", "reader clock alarm mutation rejection code")
  }

  private static func runCommand(
    role: AppleGatewayRole,
    arguments: [String],
    environment: [String: String],
    fileMaterializer: any FileStoreMaterializing = UnavailableFileStoreMaterializer(),
    calendarReadService: CalendarReadService = CalendarReminderServiceFactory.unavailableReadService(),
    calendarWriteService: CalendarWriteService = CalendarReminderServiceFactory.unavailableWriteService(),
    notesReadService: NotesReadService = NotesServiceFactory.unavailableReadService(),
    notesWriteService: NotesWriteService = NotesServiceFactory.unavailableWriteService(),
    mailReadService: MailReadService = MailServiceFactory.unavailableReadService(),
    notificationsService: any NotificationsProviding = SmokeUnavailableNotificationsProvider(),
    clockAlarmsService: any ClockAlarmsProviding = SmokeUnavailableClockAlarmsProvider()
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
      mailReadService: mailReadService,
      notificationsService: notificationsService,
      clockAlarmsService: clockAlarmsService,
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

  private static func writeEMLX(raw: String, to url: URL) throws {
    let data = Data(raw.utf8)
    var emlx = Data("\(data.count)\n".utf8)
    emlx.append(data)
    try emlx.write(to: url)
  }

  private static func requireBodyTextKey(in files: MailMessageFileSet) throws -> String {
    guard let key = files.bodyText?.downloadKey else {
      throw SmokeError("missing Mail BODY_TEXT download key")
    }
    return key
  }
}
