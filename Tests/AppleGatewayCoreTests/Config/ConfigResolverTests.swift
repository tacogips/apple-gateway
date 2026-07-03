import Foundation
import Testing
@testable import AppleGatewayCore

@Test func missingDefaultConfigYieldsExpandedDefaults() throws {
  let root = try TemporaryConfigDirectory()
  let environment = [
    "HOME": root.home
  ]

  let resolved = try AppleGatewayConfigResolver().resolve(environment: environment)

  #expect(resolved.source.kind == .missingDefault)
  #expect(resolved.source.path == "\(root.home)/.config/apple-gateway/config.toml")
  #expect(resolved.config.storage.cacheDir == "\(root.home)/.cache/apple-gateway")
  #expect(resolved.config.limits.defaultPageSize == 20)
  #expect(resolved.config.domains.mail)
}

@Test func configPathSelectionAndValuePrecedenceUseCliThenFileThenEnvironment() throws {
  let root = try TemporaryConfigDirectory()
  let cliPath = try root.write(
    "cli.toml",
    """
    [limits]
    default_page_size = 10
    max_page_size = 100
    """
  )
  let envPath = try root.write(
    "env.toml",
    """
    [limits]
    default_page_size = 5
    max_page_size = 50
    """
  )
  let environment = [
    "HOME": root.home,
    "APPLE_GATEWAY_CONFIG": envPath,
    "APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE": "30"
  ]

  let resolved = try AppleGatewayConfigResolver().resolve(cliConfigPath: cliPath, environment: environment)

  #expect(resolved.source.path == cliPath)
  #expect(resolved.source.explicit)
  #expect(resolved.config.limits.defaultPageSize == 30)
  #expect(resolved.config.limits.maxPageSize == 100)
}

@Test func configPathFallsBackThroughEnvironmentAndXDGDefault() throws {
  let root = try TemporaryConfigDirectory()
  let envPath = try root.write(
    "env.toml",
    """
    [domains]
    notes = false
    """
  )
  let xdgPath = try root.write(
    "xdg/apple-gateway/config.toml",
    """
    [mail]
    mail_root = "~/Library/Mail"
    """
  )

  let envResolved = try AppleGatewayConfigResolver().resolve(
    environment: [
      "HOME": root.home,
      "APPLE_GATEWAY_CONFIG": envPath,
      "XDG_CONFIG_HOME": root.root.appendingPathComponent("xdg").path
    ]
  )
  let xdgResolved = try AppleGatewayConfigResolver().resolve(
    environment: [
      "HOME": root.home,
      "XDG_CONFIG_HOME": root.root.appendingPathComponent("xdg").path
    ]
  )

  #expect(envResolved.source.path == envPath)
  #expect(envResolved.config.domains.notes == false)
  #expect(xdgResolved.source.path == xdgPath)
  #expect(xdgResolved.config.mail.mailRoot == "\(root.home)/Library/Mail")
}

@Test func parserRejectsUnknownKeysWithLocation() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "bad.toml",
    """
    [storage]
    unknown = "value"
    """
  )

  do {
    _ = try AppleGatewayConfigResolver().resolve(cliConfigPath: path, environment: ["HOME": root.home])
    Issue.record("Expected unknown-key config error")
  } catch AppleGatewayConfigError.parse(let errorPath, let line, let column, let message) {
    #expect(errorPath == path)
    #expect(line == 2)
    #expect(column == 1)
    #expect(message.contains("Unknown config key"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func parserRejectsDuplicateKeys() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "duplicate.toml",
    """
    [domains]
    mail = true
    mail = false
    """
  )

  do {
    _ = try AppleGatewayConfigResolver().resolve(cliConfigPath: path, environment: ["HOME": root.home])
    Issue.record("Expected duplicate-key config error")
  } catch AppleGatewayConfigError.parse(_, let line, _, let message) {
    #expect(line == 3)
    #expect(message.contains("Duplicate config key"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func environmentOverridesRejectKnownSectionTyposButIgnoreUnrelatedVariables() throws {
  let root = try TemporaryConfigDirectory()
  let environment = [
    "HOME": root.home,
    "APPLE_GATEWAY_STORAGE_CACHE_DIRECTORY": "/tmp/wrong",
    "APPLE_GATEWAY_LOG_LEVEL": "debug"
  ]

  do {
    _ = try AppleGatewayConfigResolver().resolve(environment: environment)
    Issue.record("Expected invalid env override error")
  } catch AppleGatewayConfigError.environment(let name, let message) {
    #expect(name == "APPLE_GATEWAY_STORAGE_CACHE_DIRECTORY")
    #expect(message == "Unknown config override")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func pathValuesExpandLeadingTildeAfterEnvironmentPrecedence() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "paths.toml",
    """
    [storage]
    cache_dir = "~/from-file"

    [mail]
    mail_root = "~/Mail"

    [notifications]
    helper_app_path = ""
    """
  )
  let environment = [
    "HOME": root.home,
    "APPLE_GATEWAY_NOTIFICATIONS_HELPER_APP_PATH": "~/Helper.app"
  ]

  let resolved = try AppleGatewayConfigResolver().resolve(cliConfigPath: path, environment: environment)

  #expect(resolved.config.storage.cacheDir == "\(root.home)/from-file")
  #expect(resolved.config.mail.mailRoot == "\(root.home)/Mail")
  #expect(resolved.config.notifications.helperAppPath == "\(root.home)/Helper.app")
}

@Test func validationRejectsNonPositiveLimitsAndPageSizeBounds() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "limits.toml",
    """
    [limits]
    default_page_size = 20
    max_page_size = 10
    """
  )

  do {
    _ = try AppleGatewayConfigResolver().resolve(cliConfigPath: path, environment: ["HOME": root.home])
    Issue.record("Expected validation error")
  } catch AppleGatewayConfigError.validation(let message) {
    #expect(message == "limits.default_page_size must not exceed limits.max_page_size")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func configValidatePrintsResolvedSourceAndNormalizedValues() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "valid.toml",
    """
    [limits]
    default_page_size = 15
    """
  )
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: ["apple-gateway", "config", "validate", "--config", path],
    environment: ["HOME": root.home],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
  let envelope = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  let data = try #require(envelope["data"] as? [String: Any])
  let source = try #require(data["source"] as? [String: Any])
  let config = try #require(data["config"] as? [String: Any])
  let limits = try #require(config["limits"] as? [String: Any])
  let storage = try #require(config["storage"] as? [String: Any])
  let extensions = try #require(envelope["extensions"] as? [String: Any])

  #expect(exitCode == 0)
  #expect(errorOutput.isEmpty)
  #expect(source["path"] as? String == path)
  #expect(limits["default_page_size"] as? Int == 15)
  #expect(storage["cache_dir"] as? String == "\(root.home)/.cache/apple-gateway")
  #expect(extensions["requestId"] is String)
}

@Test func configValidateFailurePrintsConfigInvalidEnvelope() throws {
  let root = try TemporaryConfigDirectory()
  let path = try root.write(
    "invalid.toml",
    """
    [limits]
    default_page_size = "wrong"
    """
  )
  let stdout = Pipe()
  let stderr = Pipe()

  let exitCode = AppleGatewayCommandLine.run(
    role: .full,
    arguments: ["apple-gateway", "config", "validate", "--config", path],
    environment: ["HOME": root.home],
    standardOutput: stdout.fileHandleForWriting,
    standardError: stderr.fileHandleForWriting
  )
  stdout.fileHandleForWriting.closeFile()
  stderr.fileHandleForWriting.closeFile()

  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
  let json = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  let errors = try #require(json["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])
  let details = try #require(extensions["details"] as? [String: String])

  let envelopeExtensions = try #require(json["extensions"] as? [String: Any])

  #expect(exitCode == 3)
  #expect(errorOutput.isEmpty)
  #expect(json.keys.contains("data"))
  #expect(extensions["code"] as? String == "CONFIG_INVALID")
  #expect(extensions["exitCode"] as? Int == 3)
  #expect(envelopeExtensions["requestId"] is String)
  #expect(details["path"] == path)
  #expect(details["line"] == "2")
}

private struct TemporaryConfigDirectory {
  let root: URL
  let home: String

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-config-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    home = root.appendingPathComponent("home").path
    try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
  }

  func write(_ name: String, _ contents: String) throws -> String {
    let path = root.appendingPathComponent(name).path
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(name).deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }
}
