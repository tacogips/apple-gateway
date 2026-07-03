import Foundation

public enum AppleGatewayRole: Sendable {
  case full
  case reader
}

public struct AppleGatewayCommand: Sendable {
  public enum Error: Swift.Error, Equatable, Sendable {
    case unknownArgument(String)
    case invalidUsage(String)
  }

  public let arguments: [String]
  public let environment: [String: String]
  public let role: AppleGatewayRole
  private let permissionsProvider: any PermissionsProviding
  private let responsibleProcessDetector: any ResponsibleProcessDetecting
  private let fileMaterializer: any FileStoreMaterializing
  private let calendarReadService: CalendarReadService
  private let calendarWriteService: CalendarWriteService
  private let notesReadService: NotesReadService
  private let notesWriteService: NotesWriteService

  public init(
    arguments: [String],
    environment: [String: String] = [:],
    role: AppleGatewayRole = .full,
    permissionsProvider: any PermissionsProviding = LivePermissionsProvider(),
    responsibleProcessDetector: any ResponsibleProcessDetecting = DefaultResponsibleProcessDetector(),
    fileMaterializer: any FileStoreMaterializing = UnavailableFileStoreMaterializer(),
    calendarReadService: CalendarReadService? = nil,
    calendarWriteService: CalendarWriteService? = nil,
    notesReadService: NotesReadService? = nil,
    notesWriteService: NotesWriteService? = nil
  ) {
    let liveServices = calendarReadService == nil || calendarWriteService == nil
      ? CalendarReminderServiceFactory.liveServices()
      : nil
    let liveNotesServices = notesReadService == nil || notesWriteService == nil
      ? NotesServiceFactory.liveServices()
      : nil
    self.arguments = arguments
    self.environment = environment
    self.role = role
    self.permissionsProvider = permissionsProvider
    self.responsibleProcessDetector = responsibleProcessDetector
    self.fileMaterializer = fileMaterializer
    self.calendarReadService = calendarReadService ?? liveServices?.readService ?? CalendarReminderServiceFactory.liveReadService()
    self.calendarWriteService = calendarWriteService ?? liveServices?.writeService ?? CalendarReminderServiceFactory.liveWriteService()
    self.notesReadService = notesReadService ?? liveNotesServices?.readService ?? NotesServiceFactory.liveReadService()
    self.notesWriteService = notesWriteService ?? liveNotesServices?.writeService ?? NotesServiceFactory.liveWriteService()
  }

  public func run() throws -> String {
    try runResult().output
  }

  public func runResult() throws -> AppleGatewayCommandResult {
    if arguments.contains("--version") {
      return AppleGatewayCommandResult(output: Version.current)
    }

    if arguments.contains("--help") || arguments.contains("-h") {
      return AppleGatewayCommandResult(output: usage)
    }

    let frame = try parseGlobalFrame(arguments)
    let commandArguments = frame.arguments

    if commandArguments.first == "version" {
      return AppleGatewayCommandResult(output: Version.current)
    }

    if commandArguments.first == "config" {
      return try runConfigCommand(Array(commandArguments.dropFirst()), frame: frame)
    }

    if commandArguments.first == "graphql" {
      return try runGraphQLCommand(Array(commandArguments.dropFirst()), frame: frame)
    }

    if commandArguments.first == "permissions" {
      return try runPermissionsCommand(Array(commandArguments.dropFirst()), frame: frame)
    }

    if commandArguments.first == "file" {
      return try runFileCommand(Array(commandArguments.dropFirst()), frame: frame)
    }

    if commandArguments.first == "cache" {
      return try runCacheCommand(Array(commandArguments.dropFirst()), frame: frame)
    }

    if commandArguments.first == "schema" {
      return AppleGatewayCommandResult(output: try runSchemaCommand(Array(commandArguments.dropFirst())))
    }

    if let firstArgument = commandArguments.first {
      if firstArgument.hasPrefix("-") {
        throw Error.unknownArgument(firstArgument)
      }
      throw Error.invalidUsage("Unknown command: \(firstArgument)")
    }

    if frame.arguments.isEmpty && !arguments.isEmpty {
      throw Error.invalidUsage("Missing command")
    }

    return AppleGatewayCommandResult(output: "Hello from apple-gateway")
  }

  public var usage: String {
    """
    Usage: apple-gateway [--help] [--version]
           apple-gateway [--config <path>] [--pretty] <command>
           apple-gateway config validate [--config <path>]
           apple-gateway graphql --query <query> | --query-file <path>
                         [--variables <json> | --variables-file <path>] [--pretty]
           apple-gateway permissions status [--json]
           apple-gateway permissions request --domain calendar|reminders|notes|notifications
           apple-gateway file download --key <key> [--key <key> ...] [--output-dir <dir>]
           apple-gateway cache prune [--all]
           apple-gateway schema print [--role full|reader]
    """
  }

  private func parseGlobalFrame(_ arguments: [String]) throws -> GlobalCommandFrame {
    var index = 0
    var configPath: String?
    var pretty = false

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--config" {
        guard configPath == nil else {
          throw Error.invalidUsage("Duplicate --config")
        }
        configPath = try readOptionValue(arguments, index: &index, name: "--config")
      } else if argument.hasPrefix("--config=") {
        guard configPath == nil else {
          throw Error.invalidUsage("Duplicate --config")
        }
        let value = String(argument.dropFirst("--config=".count))
        guard !value.isEmpty else {
          throw Error.invalidUsage("Missing value for --config")
        }
        configPath = value
        index += 1
      } else if argument == "--pretty" {
        pretty = true
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        break
      }
    }

    return GlobalCommandFrame(
      arguments: Array(arguments.dropFirst(index)),
      configPath: configPath,
      pretty: pretty
    )
  }

  private func runConfigCommand(_ arguments: [String], frame: GlobalCommandFrame) throws -> AppleGatewayCommandResult {
    guard arguments.first == "validate" else {
      throw Error.invalidUsage("Usage: apple-gateway config validate [--config <path>]")
    }

    let remaining = Array(arguments.dropFirst())
    let localConfigPath = try parseConfigValidateArguments(remaining)
    if frame.configPath != nil && localConfigPath != nil {
      throw Error.invalidUsage("Duplicate --config")
    }
    let configPath = frame.configPath ?? localConfigPath
    let resolved: ResolvedAppleGatewayConfig
    do {
      resolved = try resolveConfig(configPath: configPath)
    } catch let error as AppleGatewayConfigError {
      let response = try ConfigValidationJSON.errorResponse(error, pretty: frame.pretty)
      return AppleGatewayCommandResult(
        output: String(data: response.data, encoding: .utf8) ?? "",
        exitCode: response.exitCode
      )
    }
    let data = try ConfigValidationJSON.successData(resolved, pretty: frame.pretty)
    return AppleGatewayCommandResult(output: String(data: data, encoding: .utf8) ?? "")
  }

  private func parseConfigValidateArguments(_ arguments: [String]) throws -> String? {
    var index = 0
    var configPath: String?

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--config" {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
          throw Error.invalidUsage("Missing value for --config")
        }
        guard configPath == nil else {
          throw Error.invalidUsage("Duplicate --config")
        }
        configPath = arguments[valueIndex]
        index += 2
      } else if argument.hasPrefix("--config=") {
        guard configPath == nil else {
          throw Error.invalidUsage("Duplicate --config")
        }
        configPath = String(argument.dropFirst("--config=".count))
        guard configPath?.isEmpty == false else {
          throw Error.invalidUsage("Missing value for --config")
        }
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown config validate argument: \(argument)")
      }
    }

    return configPath
  }

  private func runGraphQLCommand(
    _ arguments: [String],
    frame: GlobalCommandFrame
  ) throws -> AppleGatewayCommandResult {
    var options = try parseGraphQLArguments(arguments)
    options.pretty = options.pretty || frame.pretty
    let query: String
    if let queryValue = options.query {
      query = queryValue
    } else if let queryFile = options.queryFile {
      query = try String(contentsOfFile: queryFile, encoding: .utf8)
    } else {
      throw Error.invalidUsage("Exactly one of --query or --query-file is required")
    }

    let variables: [String: GraphQLValue]
    do {
      variables = try loadVariables(options)
    } catch let error as AppleGatewayError {
      let response = try AppleGatewayJSONEnvelope.response(
        data: Optional<GraphQLValue>.none,
        errors: [error],
        pretty: options.pretty
      )
      return AppleGatewayCommandResult(
        output: String(data: response.data, encoding: .utf8) ?? "",
        exitCode: response.exitCode
      )
    }

    let config: AppleGatewayConfig
    do {
      config = try resolveConfig(configPath: frame.configPath).config
    } catch let error as AppleGatewayConfigError {
      return try configErrorResult(error, pretty: options.pretty)
    }

    let response = GraphQLRuntime.executeResponse(
      query: query,
      variables: variables,
      role: role,
      config: config,
      permissionsProvider: permissionsProvider,
      calendarReadService: calendarReadService,
      calendarWriteService: calendarWriteService,
      notesReadService: notesReadService,
      notesWriteService: notesWriteService,
      pretty: options.pretty
    )
    return AppleGatewayCommandResult(
      output: String(data: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func parseGraphQLArguments(_ arguments: [String]) throws -> GraphQLOptions {
    var options = GraphQLOptions()
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--query":
        options.query = try readOptionValue(arguments, index: &index, name: "--query")
      case "--query-file":
        options.queryFile = try readOptionValue(arguments, index: &index, name: "--query-file")
      case "--variables":
        options.variables = try readOptionValue(arguments, index: &index, name: "--variables")
      case "--variables-file":
        options.variablesFile = try readOptionValue(arguments, index: &index, name: "--variables-file")
      case "--pretty":
        options.pretty = true
        index += 1
      default:
        if argument.hasPrefix("--query=") {
          options.query = String(argument.dropFirst("--query=".count))
        } else if argument.hasPrefix("--query-file=") {
          options.queryFile = String(argument.dropFirst("--query-file=".count))
        } else if argument.hasPrefix("--variables=") {
          options.variables = String(argument.dropFirst("--variables=".count))
        } else if argument.hasPrefix("--variables-file=") {
          options.variablesFile = String(argument.dropFirst("--variables-file=".count))
        } else if argument.hasPrefix("-") {
          throw Error.unknownArgument(argument)
        } else {
          throw Error.invalidUsage("Unknown graphql argument: \(argument)")
        }
        index += 1
      }
    }

    guard (options.query == nil) != (options.queryFile == nil) else {
      throw Error.invalidUsage("Exactly one of --query or --query-file is required")
    }
    guard !(options.variables != nil && options.variablesFile != nil) else {
      throw Error.invalidUsage("At most one of --variables or --variables-file is allowed")
    }
    return options
  }

  private func readOptionValue(
    _ arguments: [String],
    index: inout Int,
    name: String
  ) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
      throw Error.invalidUsage("Missing value for \(name)")
    }
    index += 2
    return arguments[valueIndex]
  }

  private func loadVariables(_ options: GraphQLOptions) throws -> [String: GraphQLValue] {
    let variablesText: String
    if let variables = options.variables {
      variablesText = variables
    } else if let variablesFile = options.variablesFile {
      variablesText = try String(contentsOfFile: variablesFile, encoding: .utf8)
    } else {
      return [:]
    }

    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: Data(variablesText.utf8))
    } catch {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "GraphQL variables must be valid JSON",
        details: ["reason": String(describing: error)]
      )
    }
    guard let dictionary = object as? [String: Any] else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "GraphQL variables must decode to a JSON object"
      )
    }
    do {
      return try dictionary.mapValues { try GraphQLValue.fromJSONObject($0) }
    } catch let error as GraphQLRuntimeError {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: error.message
      )
    }
  }

  private func runPermissionsCommand(
    _ arguments: [String],
    frame: GlobalCommandFrame
  ) throws -> AppleGatewayCommandResult {
    guard let subcommand = arguments.first else {
      throw Error.invalidUsage("Usage: apple-gateway permissions status [--json]")
    }
    switch subcommand {
    case "status":
      let statusOptions = try parsePermissionsStatusArguments(Array(arguments.dropFirst()))
      let config: AppleGatewayConfig
      do {
        config = try resolveConfig(configPath: frame.configPath).config
      } catch let error as AppleGatewayConfigError {
        if statusOptions.json {
          return try configErrorResult(error, pretty: frame.pretty)
        }
        throw error
      }
      return try runPermissionsStatus(statusOptions, config: config, pretty: frame.pretty)
    case "request":
      let config = try resolveConfig(configPath: frame.configPath).config
      return try runPermissionsRequest(Array(arguments.dropFirst()), config: config)
    default:
      throw Error.invalidUsage("Unknown permissions command: \(subcommand)")
    }
  }

  private func runFileCommand(_ arguments: [String], frame: GlobalCommandFrame) throws -> AppleGatewayCommandResult {
    guard arguments.first == "download" else {
      throw Error.invalidUsage("Usage: apple-gateway file download --key <key> [--key <key> ...] [--output-dir <dir>]")
    }
    let options = try parseFileDownloadArguments(Array(arguments.dropFirst()))
    let config: AppleGatewayConfig
    do {
      config = try resolveConfig(configPath: frame.configPath).config
    } catch let error as AppleGatewayConfigError {
      return try configErrorResult(error, pretty: frame.pretty)
    }
    do {
      let manifest = try FileStore(cacheRoot: config.storage.cacheDir).download(
        keys: options.keys,
        outputDirectory: options.outputDirectory,
        materializer: fileMaterializer
      )
      let data = try AppleGatewayJSONEnvelope.successData(manifest, pretty: frame.pretty)
      return AppleGatewayCommandResult(output: String(data: data, encoding: .utf8) ?? "")
    } catch let error as AppleGatewayError {
      return try jsonErrorResult(error, pretty: frame.pretty)
    }
  }

  private func parseFileDownloadArguments(_ arguments: [String]) throws -> FileDownloadOptions {
    var index = 0
    var options = FileDownloadOptions()
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--key" {
        options.keys.append(try readOptionValue(arguments, index: &index, name: "--key"))
      } else if argument.hasPrefix("--key=") {
        let value = String(argument.dropFirst("--key=".count))
        guard !value.isEmpty else {
          throw Error.invalidUsage("Missing value for --key")
        }
        options.keys.append(value)
        index += 1
      } else if argument == "--output-dir" {
        guard options.outputDirectory == nil else {
          throw Error.invalidUsage("Duplicate --output-dir")
        }
        options.outputDirectory = try readOptionValue(arguments, index: &index, name: "--output-dir")
      } else if argument.hasPrefix("--output-dir=") {
        guard options.outputDirectory == nil else {
          throw Error.invalidUsage("Duplicate --output-dir")
        }
        let value = String(argument.dropFirst("--output-dir=".count))
        guard !value.isEmpty else {
          throw Error.invalidUsage("Missing value for --output-dir")
        }
        options.outputDirectory = value
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown file download argument: \(argument)")
      }
    }
    guard !options.keys.isEmpty else {
      throw Error.invalidUsage("At least one --key is required")
    }
    return options
  }

  private func runCacheCommand(_ arguments: [String], frame: GlobalCommandFrame) throws -> AppleGatewayCommandResult {
    guard arguments.first == "prune" else {
      throw Error.invalidUsage("Usage: apple-gateway cache prune [--all]")
    }
    let all = try parseCachePruneArguments(Array(arguments.dropFirst()))
    let config: AppleGatewayConfig
    do {
      config = try resolveConfig(configPath: frame.configPath).config
    } catch let error as AppleGatewayConfigError {
      return try configErrorResult(error, pretty: frame.pretty)
    }
    do {
      let report = try FileStore(cacheRoot: config.storage.cacheDir).prune(all: all)
      let data = try AppleGatewayJSONEnvelope.successData(report, pretty: frame.pretty)
      return AppleGatewayCommandResult(output: String(data: data, encoding: .utf8) ?? "")
    } catch let error as AppleGatewayError {
      return try jsonErrorResult(error, pretty: frame.pretty)
    }
  }

  private func parseCachePruneArguments(_ arguments: [String]) throws -> Bool {
    var all = false
    for argument in arguments {
      if argument == "--all" {
        all = true
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown cache prune argument: \(argument)")
      }
    }
    return all
  }

  private func jsonErrorResult(_ error: AppleGatewayError, pretty: Bool) throws -> AppleGatewayCommandResult {
    let response = try AppleGatewayJSONEnvelope.response(
      data: Optional<String>.none,
      errors: [error],
      pretty: pretty
    )
    return AppleGatewayCommandResult(
      output: String(data: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func configErrorResult(
    _ error: AppleGatewayConfigError,
    pretty: Bool
  ) throws -> AppleGatewayCommandResult {
    let response = try ConfigValidationJSON.errorResponse(error, pretty: pretty)
    return AppleGatewayCommandResult(
      output: String(data: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func runPermissionsStatus(
    _ options: PermissionsStatusOptions,
    config: AppleGatewayConfig,
    pretty: Bool
  ) throws -> AppleGatewayCommandResult {
    let status = permissionsProvider.status(config: config)
    if options.json {
      let data = try AppleGatewayJSONEnvelope.successData(status.jsonReport, pretty: pretty)
      return AppleGatewayCommandResult(output: String(data: data, encoding: .utf8) ?? "")
    }
    return AppleGatewayCommandResult(output: PermissionsDoctorReport(status: status).text)
  }

  private func parsePermissionsStatusArguments(_ arguments: [String]) throws -> PermissionsStatusOptions {
    var json = false
    for argument in arguments {
      if argument == "--json" {
        json = true
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown permissions status argument: \(argument)")
      }
    }
    return PermissionsStatusOptions(json: json)
  }

  private func runPermissionsRequest(
    _ arguments: [String],
    config: AppleGatewayConfig
  ) throws -> AppleGatewayCommandResult {
    let domain = try parsePermissionsRequestArguments(arguments)
    let result = permissionsProvider.request(domain: domain, config: config)
    let output = PermissionsDoctorReport.requestText(
      result: result,
      responsibleProcessHint: responsibleProcessDetector.responsibleProcessHint()
    )
    return AppleGatewayCommandResult(output: output, exitCode: result.exitCode)
  }

  private func parsePermissionsRequestArguments(_ arguments: [String]) throws -> PermissionRequestDomain {
    var index = 0
    var domain: PermissionRequestDomain?
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--domain" {
        let value = try readOptionValue(arguments, index: &index, name: "--domain")
        guard domain == nil else {
          throw Error.invalidUsage("Duplicate --domain")
        }
        domain = try PermissionRequestDomain(commandValue: value)
      } else if argument.hasPrefix("--domain=") {
        guard domain == nil else {
          throw Error.invalidUsage("Duplicate --domain")
        }
        domain = try PermissionRequestDomain(commandValue: String(argument.dropFirst("--domain=".count)))
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown permissions request argument: \(argument)")
      }
    }
    guard let domain else {
      throw Error.invalidUsage("Usage: apple-gateway permissions request --domain calendar|reminders|notes|notifications")
    }
    return domain
  }

  private func runSchemaCommand(_ arguments: [String]) throws -> String {
    guard arguments.first == "print" else {
      throw Error.invalidUsage("Usage: apple-gateway schema print [--role full|reader]")
    }
    let role = try parseSchemaPrintArguments(Array(arguments.dropFirst()))
    return GraphQLRuntime.schema(role: role ?? self.role)
  }

  private func parseSchemaPrintArguments(_ arguments: [String]) throws -> AppleGatewayRole? {
    var index = 0
    var role: AppleGatewayRole?

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--role" {
        let value = try readOptionValue(arguments, index: &index, name: "--role")
        role = try parseRole(value)
      } else if argument.hasPrefix("--role=") {
        role = try parseRole(String(argument.dropFirst("--role=".count)))
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown schema print argument: \(argument)")
      }
    }

    return role
  }

  private func parseRole(_ value: String) throws -> AppleGatewayRole {
    switch value {
    case "full":
      return .full
    case "reader":
      return .reader
    default:
      throw Error.invalidUsage("Role must be full or reader")
    }
  }

  private func resolveConfig(configPath: String?) throws -> ResolvedAppleGatewayConfig {
    try AppleGatewayConfigResolver().resolve(
      cliConfigPath: configPath,
      environment: environment
    )
  }
}

public struct AppleGatewayCommandResult: Equatable, Sendable {
  public var output: String
  public var exitCode: Int32

  public init(output: String, exitCode: Int32 = 0) {
    self.output = output
    self.exitCode = exitCode
  }
}

private struct GraphQLOptions {
  var query: String?
  var queryFile: String?
  var variables: String?
  var variablesFile: String?
  var pretty = false
}

private struct GlobalCommandFrame {
  var arguments: [String]
  var configPath: String?
  var pretty: Bool
}

private struct PermissionsStatusOptions {
  var json: Bool
}

private struct FileDownloadOptions {
  var keys: [String] = []
  var outputDirectory: String?
}

public enum AppleGatewayCommandLine {
  public static func run(
    role: AppleGatewayRole,
    arguments: [String],
    environment: [String: String],
    permissionsProvider: any PermissionsProviding = LivePermissionsProvider(),
    responsibleProcessDetector: any ResponsibleProcessDetecting = DefaultResponsibleProcessDetector(),
    fileMaterializer: any FileStoreMaterializing = UnavailableFileStoreMaterializer(),
    calendarReadService: CalendarReadService? = nil,
    calendarWriteService: CalendarWriteService? = nil,
    notesReadService: NotesReadService? = nil,
    notesWriteService: NotesWriteService? = nil,
    standardOutput: FileHandle = .standardOutput,
    standardError: FileHandle = .standardError
  ) -> Int32 {
    let command = AppleGatewayCommand(
      arguments: Array(arguments.dropFirst()),
      environment: environment,
      role: role,
      permissionsProvider: permissionsProvider,
      responsibleProcessDetector: responsibleProcessDetector,
      fileMaterializer: fileMaterializer,
      calendarReadService: calendarReadService,
      calendarWriteService: calendarWriteService,
      notesReadService: notesReadService,
      notesWriteService: notesWriteService
    )

    do {
      let result = try command.runResult()
      if !result.output.isEmpty {
        standardOutput.write(Data("\(result.output)\n".utf8))
      }
      return result.exitCode
    } catch AppleGatewayCommand.Error.unknownArgument(let argument) {
      standardError.write(Data("Unknown argument: \(argument)\n".utf8))
      return 2
    } catch AppleGatewayCommand.Error.invalidUsage(let message) {
      standardError.write(Data("\(message)\n".utf8))
      return 2
    } catch let error as AppleGatewayConfigError {
      do {
        let response = try ConfigValidationJSON.errorResponse(error)
        standardError.write(response.data)
        standardError.write(Data("\n".utf8))
        return response.exitCode
      } catch {
        standardError.write(Data("Error: \(error)\n".utf8))
        return 1
      }
    } catch {
      standardError.write(Data("Error: \(error)\n".utf8))
      return 1
    }
  }
}
