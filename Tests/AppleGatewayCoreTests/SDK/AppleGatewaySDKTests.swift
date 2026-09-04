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

  let variables: [String: GatewayJSONValue] = [
    "input": .object([
      "calendarIds": .array([.string("calendar-1")]),
      "startDate": .string("2026-01-01T00:00:00Z"),
      "endDate": .string("2026-01-01T01:00:00Z"),
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
  #expect(double.eventWindows.count == 1)
  #expect(double.eventWindows.first?.calendarIds == ["calendar-1"])
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

  let notes = await sdk.invoke(
    GatewayOperationRequest(operation: "notes", variables: ["input": .object(["first": .int(1)])]),
    environment: home.environment()
  )
  #expect(notes.errors.isEmpty)
  #expect(notesDouble.noteIDsRequests == 1)
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
