import Foundation
import Testing
@testable import AppleGatewayCore

@Test func commandReportsVersion() throws {
  let command = AppleGatewayCommand(arguments: ["--version"])
  #expect(try command.run() == Version.current)
}

@Test func commandReportsUsage() throws {
  let command = AppleGatewayCommand(arguments: ["--help"])
  let output = try command.run()
  #expect(output.contains("Usage: apple-gateway"))
  #expect(output.contains("calendar|reminders|notes|notifications|clock-alarms"))
}

@Test func commandWithoutArgumentsReportsUsage() throws {
  let command = AppleGatewayCommand(arguments: [])
  #expect(try command.run() == command.usage)
}

@Test func readerCommandReportsReaderUsage() throws {
  let command = AppleGatewayCommand(arguments: ["--help"], role: .reader)
  let output = try command.run()
  #expect(output.hasPrefix("Usage: apple-gateway-reader "))
  #expect(output.contains("       apple-gateway-reader graphql"))
}

@Test func commandPermissionsRequestUsageIncludesClockAlarms() throws {
  let command = AppleGatewayCommand(arguments: ["permissions", "request"])

  do {
    _ = try command.run()
    Issue.record("Expected missing permission domain usage")
  } catch AppleGatewayCommand.Error.invalidUsage(let usage) {
    #expect(usage.contains("calendar|reminders|notes|notifications|clock-alarms"))
  }
}

@Test func commandRejectsUnknownFlags() throws {
  let command = AppleGatewayCommand(arguments: ["--unknown"])
  do {
    _ = try command.run()
    Issue.record("Expected an unknown argument error")
  } catch AppleGatewayCommand.Error.unknownArgument(let argument) {
    #expect(argument == "--unknown")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func commandRunsGraphQLQuery() throws {
  let command = AppleGatewayCommand(
    arguments: ["graphql", "--query", "{ permissions { calendars } }"],
    permissionsProvider: StaticPermissionsProvider()
  )
  let output = try command.run()
  #expect(output.contains("\"permissions\""))
  #expect(output.contains("\"calendars\":\"GRANTED\""))
}

@Test func commandRunsGraphQLQueryFileWithVariablesFileAndPrettyOutput() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-command-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let queryPath = root.appendingPathComponent("query.graphql").path
  let variablesPath = root.appendingPathComponent("variables.json").path
  try """
  query($unused: String = "default") {
    permissions { calendars }
  }
  """.write(toFile: queryPath, atomically: true, encoding: .utf8)
  try #"{"unused":"provided"}"#.write(toFile: variablesPath, atomically: true, encoding: .utf8)

  let command = AppleGatewayCommand(
    arguments: [
      "graphql",
      "--query-file", queryPath,
      "--variables-file", variablesPath,
      "--pretty"
    ],
    permissionsProvider: StaticPermissionsProvider()
  )

  let output = try command.run()
  #expect(output.contains("\n"))
  #expect(output.contains("\"permissions\""))
  #expect(output.contains("\"calendars\" : \"GRANTED\""))
}

@Test func commandRunsGraphQLQueryWithInlineVariables() throws {
  let command = AppleGatewayCommand(
    arguments: [
      "graphql",
      "--query=query($unused: String = \"default\") { permissions { calendars } }",
      "--variables={\"unused\":\"provided\"}"
    ],
    permissionsProvider: StaticPermissionsProvider()
  )

  let output = try command.run()
  #expect(output.contains("\"calendars\":\"GRANTED\""))
}

@Test func commandAcceptsGlobalPrettyBeforeGraphQLCommand() throws {
  let command = AppleGatewayCommand(
    arguments: ["--pretty", "graphql", "--query", "{ permissions { calendars } }"],
    permissionsProvider: StaticPermissionsProvider()
  )

  let output = try command.run()

  #expect(output.contains("\n"))
  #expect(output.contains("\"data\" :"))
  #expect(output.contains("\"calendars\" : \"GRANTED\""))
}

@Test func commandGlobalConfigOverridesEnvironmentConfigPath() throws {
  let root = try CommandTemporaryDirectory()
  let globalPath = try root.write(
    "global.toml",
    """
    [limits]
    default_page_size = 11
    """
  )
  let envPath = try root.write(
    "env.toml",
    """
    [limits]
    default_page_size = 7
    """
  )
  let command = AppleGatewayCommand(
    arguments: ["--config=\(globalPath)", "config", "validate"],
    environment: [
      "HOME": root.home,
      "APPLE_GATEWAY_CONFIG": envPath
    ]
  )

  let output = try command.run()
  let envelope = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
  let data = try #require(envelope["data"] as? [String: Any])
  let source = try #require(data["source"] as? [String: Any])
  let config = try #require(data["config"] as? [String: Any])
  let limits = try #require(config["limits"] as? [String: Any])

  #expect(source["path"] as? String == globalPath)
  #expect(limits["default_page_size"] as? Int == 11)
}

@Test func commandLineRejectsGlobalAndLocalConfigValidateFlags() throws {
  let root = try CommandTemporaryDirectory()
  let globalPath = try root.write("global.toml", "")
  let localPath = try root.write("local.toml", "")
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: [
      "apple-gateway",
      "--config", globalPath,
      "config", "validate",
      "--config", localPath
    ],
    environment: ["HOME": root.home],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

  #expect(exitCode == 2)
  #expect(output.isEmpty)
  #expect(String(data: errorOutput, encoding: .utf8)?.contains("Duplicate --config") == true)
}

@Test func commandLineWritesConfigFailureEnvelopeToStdoutForSelectedJSONCommand() throws {
  let root = try CommandTemporaryDirectory()
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: [
      "apple-gateway",
      "--config", root.root.appendingPathComponent("missing.toml").path,
      "graphql",
      "--query", "{ permissions { calendars } }"
    ],
    environment: ["HOME": root.home],
    permissionsProvider: StaticPermissionsProvider(),
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
  let envelope = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  let errors = try #require(envelope["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])

  #expect(exitCode == 3)
  #expect(errorOutput.isEmpty)
  #expect(extensions["code"] as? String == "CONFIG_INVALID")
}

@Test func commandGlobalPrettyAppliesToPermissionsStatusJSON() throws {
  let command = AppleGatewayCommand(
    arguments: ["--pretty", "permissions", "status", "--json"],
    permissionsProvider: StaticPermissionsProvider()
  )

  let output = try command.run()

  #expect(output.contains("\n"))
  #expect(output.contains("\"calendars\" : \"GRANTED\""))
}

@Test func commandLineReturnsGraphQLEnvelopeExitCode() throws {
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: ["apple-gateway", "graphql", "--query", "{ missing { status } }"],
    environment: [:],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
  let envelope = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  let errors = try #require(envelope["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])

  #expect(exitCode == 5)
  #expect(errorOutput.isEmpty)
  #expect(extensions["code"] as? String == "GRAPHQL_VALIDATION_ERROR")
  #expect(extensions["exitCode"] as? Int == 5)
}

@Test func commandLineKeepsUnknownCommandAsUsageExit() {
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: ["apple-gateway", "unknown"],
    environment: [:],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

  #expect(exitCode == 2)
  #expect(output.isEmpty)
  #expect(String(data: errorOutput, encoding: .utf8)?.contains("Unknown command") == true)
}

@Test func commandLineReportsInvalidGraphQLVariablesAsBusinessEnvelope() throws {
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: [
      "apple-gateway",
      "graphql",
      "--query",
      "query($unused: String = \"default\") { permissions { calendars } }",
      "--variables",
      "[]"
    ],
    environment: [:],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
  let envelope = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  let errors = try #require(envelope["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])

  #expect(exitCode == 5)
  #expect(errorOutput.isEmpty)
  #expect(extensions["code"] as? String == "INVALID_ARGUMENT")
}

@Test func commandRunsPermissionsStatusJSON() throws {
  let command = AppleGatewayCommand(
    arguments: ["permissions", "status", "--json"],
    permissionsProvider: StaticPermissionsProvider()
  )
  let output = try command.run()
  let envelope = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
  let data = try #require(envelope["data"] as? [String: Any])

  #expect(data["calendars"] as? String == "GRANTED")
  #expect(data["notificationsHelper"] as? String == "UNKNOWN")
}

@Test func commandRunsPermissionsRequestWithDomainIsolation() throws {
  let provider = StaticPermissionsProvider()
  let command = AppleGatewayCommand(
    arguments: ["permissions", "request", "--domain=calendar"],
    permissionsProvider: provider,
    responsibleProcessDetector: StaticResponsibleProcessDetector()
  )
  let result = try command.runResult()

  #expect(result.exitCode == 0)
  #expect(result.output.contains("Calendar permission state: GRANTED"))
  #expect(provider.requestedDomains == [.calendar])
}

@Test func commandPrintsReaderSchema() throws {
  let command = AppleGatewayCommand(arguments: ["schema", "print", "--role", "reader"])
  let output = try command.run()
  #expect(output.contains("type Query"))
  #expect(!output.contains("type Mutation"))
}

private final class StaticPermissionsProvider: PermissionsProviding, @unchecked Sendable {
  private(set) var requestedDomains: [PermissionRequestDomain] = []

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
    requestedDomains.append(domain)
    return PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}

private struct StaticResponsibleProcessDetector: ResponsibleProcessDetecting {
  func responsibleProcessHint() -> String? {
    "iTerm2"
  }
}

private struct CommandTemporaryDirectory {
  let root: URL
  let home: String

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-command-tests")
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
