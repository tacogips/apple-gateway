import Foundation
import GatewaySDKKit
import Testing
@testable import AppleGatewayCore

@Test func sdkInvokesCalendarOperationsThroughInjectedServices() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let double = SDKCalendarDouble()
  let services = SDKFixtures.calendarServices(double)
  let sdk = AppleGatewaySDK(
    permissionsProvider: SDKPermissionsProvider(),
    calendarReadService: services.0,
    calendarWriteService: services.1
  )

  let calendarsDocument = try GatewayDocumentBuilder(catalog: sdk.catalog).build(
    GatewayOperationRequest(operation: "calendars")
  )
  #expect(!calendarsDocument.document.contains("$"))
  let calendars = await sdk.invoke(
    GatewayOperationRequest(operation: "calendars"),
    environment: home.environment()
  )
  #expect(calendars.errors.isEmpty)
  #expect(double.calendarRequests == [nil])
  let calendarResults = try #require(sdkEnvelopeData(calendars)["calendars"] as? [[String: Any]])
  #expect(calendarResults.map { $0["id"] as? String } == ["calendar-1", "list-1"])
  #expect(calendarResults.first?["title"] as? String == "Work")

  let variables: [String: GatewayJSONValue] = [
    "input": .object([
      "calendarIds": .array([.string("calendar-1")]),
      "startDate": .string("2026-01-01T10:00:00Z"),
      "endDate": .string("2026-01-01T12:00:00Z"),
      "first": .int(1)
    ])
  ]
  let eventsDocument = try GatewayDocumentBuilder(catalog: sdk.catalog).build(
    GatewayOperationRequest(operation: "events", variables: variables)
  )
  #expect(eventsDocument.document.contains("$input"))
  let events = await sdk.invoke(
    GatewayOperationRequest(operation: "events", variables: variables),
    environment: home.environment()
  )
  #expect(events.errors.isEmpty)
  #expect(double.eventWindows == [
    EventFetchWindow(
      startDate: Date(timeIntervalSince1970: 1_767_261_600),
      endDate: Date(timeIntervalSince1970: 1_767_268_800),
      calendarIds: ["calendar-1"]
    )
  ])
  let eventConnection = try #require(sdkEnvelopeData(events)["events"] as? [String: Any])
  let eventEdges = try #require(eventConnection["edges"] as? [[String: Any]])
  let firstEvent = try #require(eventEdges.first?["node"] as? [String: Any])
  let eventPageInfo = try #require(eventConnection["pageInfo"] as? [String: Any])
  #expect(eventConnection["totalCount"] as? Int == 2)
  #expect(eventEdges.count == 1)
  #expect(firstEvent["id"] as? String == "event-1")
  #expect(firstEvent["title"] as? String == "Planning")
  #expect(eventPageInfo["hasNextPage"] as? Bool == true)
}

@Test func sdkInvokesReminderMutationAndNotesQueryThroughInjectedServices() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let calendarDouble = SDKCalendarDouble()
  let calendarServices = SDKFixtures.calendarServices(calendarDouble)
  let notesDouble = SDKNotesDouble()
  let notesServices = SDKFixtures.notesServices(notesDouble)
  let sdk = AppleGatewaySDK(
    permissionsProvider: SDKPermissionsProvider(),
    calendarReadService: calendarServices.0,
    calendarWriteService: calendarServices.1,
    notesReadService: notesServices.0,
    notesWriteService: notesServices.1
  )

  let reminder = await sdk.invoke(
    GatewayOperationRequest(
      operation: "createReminder",
      variables: ["input": .object(["listId": .string("list-1"), "title": .string("Submit")])]
    ),
    environment: home.environment()
  )
  #expect(reminder.errors.isEmpty)
  #expect(calendarDouble.createdReminders.last?.title == "Submit")
  let createdReminder = try #require(sdkEnvelopeData(reminder)["createReminder"] as? [String: Any])
  #expect(createdReminder["id"] as? String == "reminder-1")
  #expect(createdReminder["listId"] as? String == "list-1")
  #expect(createdReminder["title"] as? String == "Submit")

  let notes = await sdk.invoke(
    GatewayOperationRequest(operation: "notes", variables: ["input": .object(["first": .int(1)])]),
    environment: home.environment()
  )
  #expect(notes.errors.isEmpty)
  #expect(notesDouble.noteIDsRequests == 1)
  let noteConnection = try #require(sdkEnvelopeData(notes)["notes"] as? [String: Any])
  let noteEdges = try #require(noteConnection["edges"] as? [[String: Any]])
  let firstNote = try #require(noteEdges.first?["node"] as? [String: Any])
  #expect(noteConnection["totalCount"] as? Int == 1)
  #expect(noteEdges.count == 1)
  #expect(firstNote["id"] as? String == "note-1")
  #expect(firstNote["name"] as? String == "Release")
}

@Test func readerSDKPreservesNamedAndRawMutationBoundaries() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let sdk = AppleGatewaySDK(role: .reader, permissionsProvider: SDKPermissionsProvider())
  let named = await sdk.invoke(GatewayOperationRequest(operation: "createReminder"))
  #expect(named.exitCode == 2)
  #expect(named.errors.first?.message == "unknown operation 'createReminder'")
  #expect(named.errors.first?.code == nil)
  #expect(named.rawOutput.isEmpty)

  let raw = await sdk.execute(
    document: "mutation { createReminder(input: { title: \"x\" }) { id } }",
    variables: [:],
    environment: home.environment()
  )
  #expect(raw.exitCode == 5)
  #expect(raw.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(raw.errors.first?.message == "Mutations are disabled in reader mode")
}

@Test func sdkRawExecutionIsByteCompatibleWithCLIAfterRequestIDNormalization() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let calendarDouble = SDKCalendarDouble()
  let calendarServices = SDKFixtures.calendarServices(calendarDouble)
  let notesDouble = SDKNotesDouble()
  let notesServices = SDKFixtures.notesServices(notesDouble)
  let document = "query Events($input: EventSearchInput!) { events(input: $input) { totalCount } }"
  let variables: [String: GatewayJSONValue] = [
    "input": .object([
      "startDate": .string("2026-01-01T00:00:00Z"),
      "endDate": .string("2026-01-01T01:00:00Z")
    ])
  ]
  let sdk = AppleGatewaySDK(
    permissionsProvider: SDKPermissionsProvider(), calendarReadService: calendarServices.0,
    calendarWriteService: calendarServices.1, notesReadService: notesServices.0,
    notesWriteService: notesServices.1
  )
  let sdkEnvelope = await sdk.execute(document: document, variables: variables, environment: home.environment())
  let cli = try AppleGatewayCommand(
    arguments: ["graphql", "--query", document, "--variables", try GatewayJSONValue.object(variables).jsonString()],
    environment: home.environment(), permissionsProvider: SDKPermissionsProvider(),
    calendarReadService: calendarServices.0, calendarWriteService: calendarServices.1,
    notesReadService: notesServices.0, notesWriteService: notesServices.1
  ).runResult()
  let cliEnvelope = GatewayEnvelope(parsingCLIOutput: cli.output, exitCode: cli.exitCode)
  #expect(sdkEnvelope.exitCode == cli.exitCode)
  #expect(!(sdkEnvelope.requestId ?? "").isEmpty)
  #expect(!(cliEnvelope.requestId ?? "").isEmpty)
  #expect(SDKFixtures.normalizeRequestID(sdkEnvelope.rawOutput) == SDKFixtures.normalizeRequestID(cli.output))
}

@Test func sdkConfigFailureMatchesCLIByteForByteAfterRequestIDNormalization() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let environment = home.environment(["APPLE_GATEWAY_CONFIG": home.url.appendingPathComponent("missing.toml").path])
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let sdkEnvelope = await sdk.execute(document: "{ permissions { calendars } }", variables: [:], environment: environment)
  let cli = try AppleGatewayCommand(
    arguments: ["graphql", "--query", "{ permissions { calendars } }"], environment: environment,
    permissionsProvider: SDKPermissionsProvider()
  ).runResult()
  #expect(sdkEnvelope.errors.first?.code == "CONFIG_INVALID")
  #expect(sdkEnvelope.exitCode == cli.exitCode)
  #expect(SDKFixtures.normalizeRequestID(sdkEnvelope.rawOutput) == SDKFixtures.normalizeRequestID(cli.output))
}

@Test func sdkDefaultServicesUseTheSuppliedEnvironmentInsteadOfAmbientHome() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let suppliedHome = home.url.path
  let ambientHome = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
  #expect(suppliedHome != ambientHome)
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.execute(
    document: "{ mailAccounts { id } }",
    variables: [:],
    environment: home.environment()
  )
  #expect(envelope.errors.first?.code == "MAIL_STORE_NOT_FOUND")
  #expect(envelope.rawOutput.contains(suppliedHome.replacingOccurrences(of: "/", with: "\\/")))
  #expect(!envelope.rawOutput.contains(ambientHome.replacingOccurrences(of: "/", with: "\\/")))
}

@Test func sdkConstructsDefaultNotesServicesFromEachExecutionEnvironment() async throws {
  let firstHome = try SDKTestHome()
  defer { firstHome.remove() }
  let secondHome = try SDKTestHome()
  defer { secondHome.remove() }
  let factory = SDKNotesServicesFactoryProbe()
  let sdk = AppleGatewaySDK(
    permissionsProvider: SDKPermissionsProvider(),
    notesServicesFactory: factory.makeServices(config:environment:)
  )
  let document = "{ notes(input: {}) { totalCount } }"
  let firstEnvironment = firstHome.environment([
    "APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE": "1",
    "APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE": "1"
  ])
  let secondEnvironment = secondHome.environment([
    "APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE": "3",
    "APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE": "3"
  ])

  _ = await sdk.execute(document: document, variables: [:], environment: firstEnvironment)
  _ = await sdk.execute(document: document, variables: [:], environment: secondEnvironment)

  #expect(factory.calls.map(\.environment["HOME"]) == [firstHome.url.path, secondHome.url.path])
  #expect(factory.calls.map(\.limits.defaultPageSize) == [1, 3])
  #expect(factory.calls.map(\.limits.maxPageSize) == [1, 3])
}

@Test func sdkFailsClosedWhenSuppliedEnvironmentOmitsHome() async throws {
  let ambientHome = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.execute(
    document: "{ permissions { calendars } }",
    variables: [:],
    environment: [:]
  )

  #expect(envelope.errors.first?.code == "CONFIG_INVALID")
  #expect(envelope.errors.first?.message == "Invalid environment override HOME: A non-empty HOME is required for SDK execution")
  #expect(!envelope.rawOutput.contains(ambientHome.replacingOccurrences(of: "/", with: "\\/")))
}

@Test func sdkNotificationDatabaseLookupExcludesAmbientDarwinDirectory() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let ambientDarwinDirectory = try #require(UsernotedDatabasePathResolver.defaultDarwinUserDirectory())
  #expect(ambientDarwinDirectory != home.url.path)
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.execute(
    document: "{ notifications(input: { source: SYSTEM_DB }) { totalCount } }",
    variables: [:],
    environment: home.environment()
  )

  #expect(envelope.errors.first?.code == "NOTIFICATION_DB_UNAVAILABLE")
  #expect(envelope.rawOutput.contains(home.url.path.replacingOccurrences(of: "/", with: "\\/")))
  #expect(!envelope.rawOutput.contains(ambientDarwinDirectory.replacingOccurrences(of: "/", with: "\\/")))
}

@Test func sdkDefaultPermissionsProviderUsesSuppliedHomeAndExcludesAmbientDarwinDirectory() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let mailData = home.url
    .appendingPathComponent("Library/Mail/V11/MailData", isDirectory: true)
  try FileManager.default.createDirectory(at: mailData, withIntermediateDirectories: true)
  try Data("probe".utf8).write(to: mailData.appendingPathComponent("Envelope Index"))
  let notificationDatabase = home.url
    .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2", isDirectory: true)
  try FileManager.default.createDirectory(at: notificationDatabase, withIntermediateDirectories: true)
  try Data().write(to: notificationDatabase.appendingPathComponent("db"))

  let ambientHome = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
  let ambientDarwinDirectory = try #require(UsernotedDatabasePathResolver.defaultDarwinUserDirectory())
  #expect(home.url.path != ambientHome)
  #expect(home.url.path != ambientDarwinDirectory)
  let environment = home.environment([
    "APPLE_GATEWAY_DOMAINS_CALENDAR": "false",
    "APPLE_GATEWAY_DOMAINS_REMINDERS": "false",
    "APPLE_GATEWAY_DOMAINS_CLOCK_ALARMS": "false",
    "APPLE_GATEWAY_DOMAINS_NOTES": "false",
    "APPLE_GATEWAY_DOMAINS_PHONE_CALLS": "false"
  ])
  let envelope = await AppleGatewaySDK().execute(
    document: "{ permissions { mailFullDiskAccess notificationDbFullDiskAccess } }",
    variables: [:],
    environment: environment
  )

  #expect(envelope.errors.isEmpty)
  #expect(envelope.rawOutput.contains(#""mailFullDiskAccess":"GRANTED""#))
  #expect(envelope.rawOutput.contains(#""notificationDbFullDiskAccess":"GRANTED""#))
}

@Test func sdkRawExecutionRejectsUnsafeDoubleVariables() async throws {
  let home = try SDKTestHome()
  defer { home.remove() }
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())

  let nonFinite = await sdk.execute(
    document: "{ permissions { calendars } }",
    variables: ["value": .double(.infinity)],
    environment: home.environment()
  )
  #expect(nonFinite.errors.first?.code == "INVALID_ARGUMENT")
  #expect(nonFinite.errors.first?.message == "Variables must not contain non-finite numbers")

  let outOfRange = await sdk.execute(
    document: "{ permissions { calendars } }",
    variables: ["value": .double(.greatestFiniteMagnitude)],
    environment: home.environment()
  )
  #expect(outOfRange.errors.first?.code == "INVALID_ARGUMENT")
  #expect(outOfRange.errors.first?.message == "Integer variable is outside the supported range")
}

private func sdkEnvelopeData(_ envelope: GatewayEnvelope) throws -> [String: Any] {
  let object = try #require(JSONSerialization.jsonObject(with: Data(envelope.rawOutput.utf8)) as? [String: Any])
  return try #require(object["data"] as? [String: Any])
}

private final class SDKNotesServicesFactoryProbe: @unchecked Sendable {
  struct Call: Equatable {
    let environment: [String: String]
    let limits: AppleGatewayConfig.Limits
  }

  private let lock = NSLock()
  private var recordedCalls: [Call] = []

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls
  }

  func makeServices(config: AppleGatewayConfig, environment: [String: String]) -> NotesServices {
    lock.lock()
    recordedCalls.append(Call(environment: environment, limits: config.limits))
    lock.unlock()
    return NotesServices(
      readService: NotesServiceFactory.unavailableReadService(),
      writeService: NotesServiceFactory.unavailableWriteService(),
      fileMaterializer: NotesFileMaterializer(provider: UnavailableNotesProvider())
    )
  }
}

private struct SDKPermissionsProvider: PermissionsProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted), reminders: PermissionFieldStatus(state: .granted),
      notesAutomation: PermissionFieldStatus(state: .granted), mailAutomation: PermissionFieldStatus(state: .granted),
      mailFullDiskAccess: PermissionFieldStatus(state: .granted), notificationsHelper: PermissionFieldStatus(state: .granted),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .granted), clockAutomation: PermissionFieldStatus(state: .granted),
      phoneContacts: PermissionFieldStatus(state: .granted), phoneAutomation: PermissionFieldStatus(state: .granted)
    )
  }

  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}
