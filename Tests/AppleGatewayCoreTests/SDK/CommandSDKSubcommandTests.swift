import Foundation
import GatewaySDKKit
import Testing
@testable import AppleGatewayCore

@Test func schemaSearchReturnsCatalogMatchesAndHonorsFilters() throws {
  let result = try AppleGatewayCommand(arguments: ["schema", "search", "calendars", "--limit", "1"]).runResult()
  let matches = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [[String: Any]]
  #expect(matches?.count == 1)
  #expect(matches?.first?["name"] as? String == "calendars")

  let mutations = try AppleGatewayCommand(
    arguments: ["schema", "search", "calendars", "--kinds", "mutation"]
  ).runResult()
  let mutationMatches = try JSONSerialization.jsonObject(with: Data(mutations.output.utf8)) as? [[String: Any]]
  #expect(mutationMatches?.isEmpty == true)

  let reader = try AppleGatewayCommand(
    arguments: ["schema", "search", "createReminder", "--role", "reader"]
  ).runResult()
  let readerMatches = try JSONSerialization.jsonObject(with: Data(reader.output.utf8)) as? [[String: Any]]
  #expect(readerMatches?.isEmpty == true)

  #expect(throws: AppleGatewayCommand.Error.invalidUsage("Unknown schema search kind: nope")) {
    _ = try AppleGatewayCommand(arguments: ["schema", "search", "x", "--kinds", "nope"]).run()
  }
  #expect(throws: AppleGatewayCommand.Error.invalidUsage("Invalid search pattern: [")) {
    _ = try AppleGatewayCommand(arguments: ["schema", "search", "["]).run()
  }
}

@Test func schemaSearchHonorsPrettyAndLeavesSchemaPrintUnchanged() throws {
  let prettySearch = try AppleGatewayCommand(arguments: ["--pretty", "schema", "search", "calendars"]).run()
  #expect(prettySearch.contains("\n  {"))

  let print = try AppleGatewayCommand(arguments: ["schema", "print"]).run()
  let prettyPrint = try AppleGatewayCommand(arguments: ["--pretty", "schema", "print"]).run()
  #expect(print == prettyPrint)
}

@Test func graphQLOperationMatchesRawGraphQLAndSupportsSelection() throws {
  let operationDouble = SDKCalendarDouble()
  let operationServices = SDKFixtures.calendarServices(operationDouble)
  let rawDouble = SDKCalendarDouble()
  let rawServices = SDKFixtures.calendarServices(rawDouble)
  let document = try GatewayDocumentBuilder(catalog: .apple(role: .full)).build(
    GatewayOperationRequest(operation: "calendars")
  ).document
  let operation = try command(
    ["graphql", "operation", "calendars"], calendarServices: operationServices
  ).runResult()
  let raw = try command(
    ["graphql", "--query", document], calendarServices: rawServices
  ).runResult()
  let operationEnvelope = GatewayEnvelope(parsingCLIOutput: operation.output, exitCode: operation.exitCode)
  let rawEnvelope = GatewayEnvelope(parsingCLIOutput: raw.output, exitCode: raw.exitCode)
  #expect(!(operationEnvelope.requestId ?? "").isEmpty)
  #expect(!(rawEnvelope.requestId ?? "").isEmpty)
  #expect(operation.exitCode == raw.exitCode)
  #expect(SDKFixtures.normalizeRequestID(operation.output) == SDKFixtures.normalizeRequestID(raw.output))

  let selected = try command(
    ["graphql", "operation", "calendars", "--select", "id,title"], calendarServices: operationServices
  ).run()
  #expect(selected.contains("\"id\""))
  #expect(selected.contains("\"title\""))
  #expect(!selected.contains("sourceTitle"))
}

@Test func graphQLOperationReturnsRawCompatibleErrorsAndHelpDocumentsCommands() throws {
  let missingPath = "/tmp/apple-gateway-command-sdk-missing-config.toml"
  let operation = try command(
    ["--config", missingPath, "graphql", "operation", "calendars"]
  ).runResult()
  let raw = try command(
    ["--config", missingPath, "graphql", "--query", "{ calendars { id } }"]
  ).runResult()
  #expect(operation.exitCode == raw.exitCode)
  #expect(SDKFixtures.normalizeRequestID(operation.output) == SDKFixtures.normalizeRequestID(raw.output))

  let unknown = try command(["graphql", "operation", "noSuchOperation"]).runResult()
  let unknownEnvelope = GatewayEnvelope(parsingCLIOutput: unknown.output, exitCode: unknown.exitCode)
  #expect(unknown.exitCode != 0)
  #expect(unknownEnvelope.errors.first?.code == "INVALID_ARGUMENT")

  let help = try command(["--help"]).run()
  #expect(help.contains("schema search"))
  #expect(help.contains("graphql operation"))
}

private func command(
  _ arguments: [String],
  calendarServices: (CalendarReadService, CalendarWriteService)? = nil
) -> AppleGatewayCommand {
  AppleGatewayCommand(
    arguments: arguments,
    environment: SDKFixtures.environment,
    permissionsProvider: CommandSDKPermissionsProvider(),
    calendarReadService: calendarServices?.0,
    calendarWriteService: calendarServices?.1
  )
}

private struct CommandSDKPermissionsProvider: PermissionsProviding {
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
