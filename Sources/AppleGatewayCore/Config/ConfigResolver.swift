import Foundation

public struct AppleGatewayConfigResolver {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func resolve(
    cliConfigPath: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ResolvedAppleGatewayConfig {
    let selection = selectConfigPath(cliConfigPath: cliConfigPath, environment: environment)
    var config = AppleGatewayConfig.defaultValue
    let source: AppleGatewayConfigSource

    if fileManager.fileExists(atPath: selection.path) {
      let fileConfig = try loadFile(path: selection.path)
      try apply(file: fileConfig, to: &config)
      source = AppleGatewayConfigSource(kind: .file, path: selection.path, explicit: selection.explicit)
    } else if selection.explicit {
      throw AppleGatewayConfigError.missingExplicitConfig(path: selection.path)
    } else {
      source = AppleGatewayConfigSource(kind: .missingDefault, path: selection.path, explicit: false)
    }

    try applyEnvironment(environment, to: &config)
    config = expandPaths(in: config, environment: environment)
    try validate(config)
    return ResolvedAppleGatewayConfig(source: source, config: config)
  }

  private func selectConfigPath(cliConfigPath: String?, environment: [String: String]) -> (path: String, explicit: Bool) {
    if let cliConfigPath, !cliConfigPath.isEmpty {
      return (expandTilde(cliConfigPath, environment: environment), true)
    }
    if let envPath = environment["APPLE_GATEWAY_CONFIG"], !envPath.isEmpty {
      return (expandTilde(envPath, environment: environment), true)
    }
    if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
      return (expandTilde("\(xdgConfigHome)/apple-gateway/config.toml", environment: environment), false)
    }
    return (expandTilde("~/.config/apple-gateway/config.toml", environment: environment), false)
  }

  private func loadFile(path: String) throws -> ParsedConfigFile {
    do {
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      return try ConfigTOMLParser(path: path).parse(contents)
    } catch let error as AppleGatewayConfigError {
      throw error
    } catch {
      throw AppleGatewayConfigError.fileReadFailed(path: path, message: String(describing: error))
    }
  }

  private func apply(file: ParsedConfigFile, to config: inout AppleGatewayConfig) throws {
    for (section, keys) in file.values {
      for (key, scalar) in keys {
        try apply(section: section, key: key, scalar: scalar, to: &config) {
          "Config key '\(section).\(key)' expects \($0)"
        }
      }
    }
  }

  private func applyEnvironment(_ environment: [String: String], to config: inout AppleGatewayConfig) throws {
    for name in environment.keys.sorted() where name.hasPrefix("APPLE_GATEWAY_") {
      guard name != "APPLE_GATEWAY_CONFIG" else {
        continue
      }

      guard let override = ConfigSchema.envOverrides[name] else {
        if ConfigSchema.envSectionPrefixes.contains(where: { name.hasPrefix($0) }) {
          throw AppleGatewayConfigError.environment(name: name, message: "Unknown config override")
        }
        continue
      }

      let value = environment[name] ?? ""
      let scalar = try scalarFromEnvironment(name: name, value: value, section: override.section, key: override.key)
      try apply(section: override.section, key: override.key, scalar: scalar, to: &config) { expected in
        "Expected \(expected)"
      }
    }
  }

  private func scalarFromEnvironment(name: String, value: String, section: String, key: String) throws -> ConfigScalar {
    guard let expected = ConfigSchema.expectedType(section: section, key: key) else {
      throw AppleGatewayConfigError.environment(name: name, message: "Unknown config override")
    }

    switch expected {
    case .string:
      return .string(value)
    case .integer:
      guard let integer = Int(value) else {
        throw AppleGatewayConfigError.environment(name: name, message: "Expected integer value")
      }
      return .integer(integer)
    case .boolean:
      if value == "true" {
        return .boolean(true)
      }
      if value == "false" {
        return .boolean(false)
      }
      throw AppleGatewayConfigError.environment(name: name, message: "Expected boolean value")
    }
  }

  private func apply(
    section: String,
    key: String,
    scalar: ConfigScalar,
    to config: inout AppleGatewayConfig,
    typeMessage: (String) -> String
  ) throws {
    switch (section, key, scalar) {
    case ("storage", "cache_dir", .string(let value)):
      config.storage.cacheDir = value
    case ("limits", "default_page_size", .integer(let value)):
      config.limits.defaultPageSize = value
    case ("limits", "max_page_size", .integer(let value)):
      config.limits.maxPageSize = value
    case ("limits", "max_inline_body_bytes", .integer(let value)):
      config.limits.maxInlineBodyBytes = value
    case ("limits", "apple_event_timeout_seconds", .integer(let value)):
      config.limits.appleEventTimeoutSeconds = value
    case ("limits", "apple_event_batch_size", .integer(let value)):
      config.limits.appleEventBatchSize = value
    case ("domains", "calendar", .boolean(let value)):
      config.domains.calendar = value
    case ("domains", "reminders", .boolean(let value)):
      config.domains.reminders = value
    case ("domains", "clock_alarms", .boolean(let value)):
      config.domains.clockAlarms = value
    case ("domains", "notes", .boolean(let value)):
      config.domains.notes = value
    case ("domains", "mail", .boolean(let value)):
      config.domains.mail = value
    case ("domains", "notifications", .boolean(let value)):
      config.domains.notifications = value
    case ("mail", "mail_root", .string(let value)):
      config.mail.mailRoot = value
    case ("notifications", "helper_app_path", .string(let value)):
      config.notifications.helperAppPath = value
    default:
      let expected = ConfigSchema.expectedType(section: section, key: key)?.description ?? "known schema value"
      throw AppleGatewayConfigError.validation(message: typeMessage(expected))
    }
  }

  private func expandPaths(in config: AppleGatewayConfig, environment: [String: String]) -> AppleGatewayConfig {
    var expanded = config
    expanded.storage.cacheDir = expandTilde(config.storage.cacheDir, environment: environment)
    if !expanded.mail.mailRoot.isEmpty {
      expanded.mail.mailRoot = expandTilde(config.mail.mailRoot, environment: environment)
    }
    if !expanded.notifications.helperAppPath.isEmpty {
      expanded.notifications.helperAppPath = expandTilde(config.notifications.helperAppPath, environment: environment)
    }
    return expanded
  }

  private func expandTilde(_ path: String, environment: [String: String]) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
      return path
    }
    let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    if path == "~" {
      return home
    }
    return home + path.dropFirst()
  }

  private func validate(_ config: AppleGatewayConfig) throws {
    guard !config.storage.cacheDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppleGatewayConfigError.validation(message: "storage.cache_dir must not be empty")
    }

    let positiveLimits = [
      ("limits.default_page_size", config.limits.defaultPageSize),
      ("limits.max_page_size", config.limits.maxPageSize),
      ("limits.max_inline_body_bytes", config.limits.maxInlineBodyBytes),
      ("limits.apple_event_timeout_seconds", config.limits.appleEventTimeoutSeconds),
      ("limits.apple_event_batch_size", config.limits.appleEventBatchSize)
    ]
    for (name, value) in positiveLimits where value <= 0 {
      throw AppleGatewayConfigError.validation(message: "\(name) must be positive")
    }

    guard config.limits.defaultPageSize <= config.limits.maxPageSize else {
      throw AppleGatewayConfigError.validation(message: "limits.default_page_size must not exceed limits.max_page_size")
    }
  }
}
