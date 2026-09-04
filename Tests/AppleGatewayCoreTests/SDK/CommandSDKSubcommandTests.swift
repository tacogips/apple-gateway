import Foundation
import Testing
@testable import AppleGatewayCore

@Test func schemaSearchReturnsCatalogMatchesAndHonorsLimit() throws {
  let result = try AppleGatewayCommand(arguments: ["schema", "search", "calendars", "--limit", "1"]).runResult()
  let matches = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [[String: Any]]
  #expect(matches?.count == 1)
  #expect(matches?.first?["name"] as? String == "calendars")
}

@Test func schemaSearchHonorsKindsRolesAndInvalidInput() throws {
  let mutations = try AppleGatewayCommand(
    arguments: ["schema", "search", "calendars", "--kinds", "mutation"]
  ).runResult()
  let matches = try JSONSerialization.jsonObject(with: Data(mutations.output.utf8)) as? [[String: Any]]
  #expect(matches?.isEmpty == true)

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

@Test func graphQLOperationUsesBuilderAndHelpDocumentsNewCommands() throws {
  let command = AppleGatewayCommand(
    arguments: ["graphql", "operation", "permissions"],
    permissionsProvider: CommandSDKPermissionsProvider()
  )
  let result = try command.runResult()
  #expect(result.exitCode == 0)
  #expect(result.output.contains("\"permissions\""))
  #expect(command.usage.contains("schema search"))
  #expect(command.usage.contains("graphql operation"))
}

private struct CommandSDKPermissionsProvider: PermissionsProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted),
      reminders: PermissionFieldStatus(state: .granted),
      notesAutomation: PermissionFieldStatus(state: .granted),
      mailAutomation: PermissionFieldStatus(state: .granted),
      mailFullDiskAccess: PermissionFieldStatus(state: .granted),
      notificationsHelper: PermissionFieldStatus(state: .granted),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .granted),
      clockAutomation: PermissionFieldStatus(state: .granted),
      phoneContacts: PermissionFieldStatus(state: .granted),
      phoneAutomation: PermissionFieldStatus(state: .granted)
    )
  }

  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}
