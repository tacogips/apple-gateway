import Foundation
import GatewaySDKKit

extension AppleGatewayCommand {
  func runSchemaSearchCommand(
    _ arguments: [String],
    pretty: Bool
  ) throws -> AppleGatewayCommandResult {
    guard let pattern = arguments.first, !pattern.hasPrefix("-") else {
      throw Error.invalidUsage("Usage: apple-gateway schema search <regex> [--role full|reader] [--kinds a,b] [--include-referenced-types] [--limit N]")
    }
    var index = 1
    var role = self.role
    var kinds = Set(GatewayDefinitionKind.allCases)
    var includeReferencedTypes = false
    var limit: Int?

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--role" {
        role = try parseRole(readOptionValue(arguments, index: &index, name: "--role"))
      } else if argument.hasPrefix("--role=") {
        role = try parseRole(String(argument.dropFirst("--role=".count)))
        index += 1
      } else if argument == "--kinds" {
        kinds = try parseSearchKinds(readOptionValue(arguments, index: &index, name: "--kinds"))
      } else if argument.hasPrefix("--kinds=") {
        kinds = try parseSearchKinds(String(argument.dropFirst("--kinds=".count)))
        index += 1
      } else if argument == "--include-referenced-types" {
        includeReferencedTypes = true
        index += 1
      } else if argument == "--limit" {
        limit = try parseSearchLimit(readOptionValue(arguments, index: &index, name: "--limit"))
      } else if argument.hasPrefix("--limit=") {
        limit = try parseSearchLimit(String(argument.dropFirst("--limit=".count)))
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown schema search argument: \(argument)")
      }
    }

    let matches: [GatewaySchemaSearch.Match]
    do {
      matches = try GatewaySchemaSearch(catalog: .apple(role: role)).search(
        pattern,
        options: .init(
          kinds: kinds,
          includeReferencedTypes: includeReferencedTypes,
          limit: limit
        )
      )
    } catch {
      throw Error.invalidUsage("Invalid search pattern: \(pattern)")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let output = String(bytes: try encoder.encode(matches), encoding: .utf8) ?? ""
    return AppleGatewayCommandResult(output: output)
  }

  func runGraphQLOperationCommand(
    _ arguments: [String],
    configPath: String?,
    pretty: Bool
  ) throws -> AppleGatewayCommandResult {
    guard let operation = arguments.first, !operation.hasPrefix("-") else {
      throw Error.invalidUsage("Usage: apple-gateway graphql operation <name> [--variables <json> | --variables-file <path>] [--select a.b,c]")
    }
    var index = 1
    var variablesText: String?
    var variablesFile: String?
    var selection: GatewaySelection = .default
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--variables" {
        guard variablesText == nil else { throw Error.invalidUsage("Duplicate --variables") }
        variablesText = try readOptionValue(arguments, index: &index, name: "--variables")
      } else if argument.hasPrefix("--variables=") {
        guard variablesText == nil else { throw Error.invalidUsage("Duplicate --variables") }
        variablesText = String(argument.dropFirst("--variables=".count))
        index += 1
      } else if argument == "--variables-file" {
        guard variablesFile == nil else { throw Error.invalidUsage("Duplicate --variables-file") }
        variablesFile = try readOptionValue(arguments, index: &index, name: "--variables-file")
      } else if argument.hasPrefix("--variables-file=") {
        guard variablesFile == nil else { throw Error.invalidUsage("Duplicate --variables-file") }
        variablesFile = String(argument.dropFirst("--variables-file=".count))
        index += 1
      } else if argument == "--select" {
        selection = .fields(try readOptionValue(arguments, index: &index, name: "--select").split(separator: ",").map(String.init))
      } else if argument.hasPrefix("--select=") {
        selection = .fields(String(argument.dropFirst("--select=".count)).split(separator: ",").map(String.init))
        index += 1
      } else if argument.hasPrefix("-") {
        throw Error.unknownArgument(argument)
      } else {
        throw Error.invalidUsage("Unknown graphql operation argument: \(argument)")
      }
    }
    guard !(variablesText != nil && variablesFile != nil) else {
      throw Error.invalidUsage("At most one of --variables or --variables-file is allowed")
    }

    let source = try variablesFile.map { try String(contentsOfFile: $0, encoding: .utf8) } ?? variablesText
    let variables: [String: GatewayJSONValue]
    do {
      guard let source else { variables = [:]; return try executeOperation(operation, variables: variables, selection: selection, configPath: configPath, pretty: pretty) }
      guard case .object(let value) = try GatewayJSONValue.parse(source) else {
        return try operationError("GraphQL variables must decode to a JSON object", pretty: pretty)
      }
      variables = value
    } catch {
      return try operationError("GraphQL variables must be valid JSON", pretty: pretty)
    }
    return try executeOperation(operation, variables: variables, selection: selection, configPath: configPath, pretty: pretty)
  }

  private func executeOperation(
    _ operation: String,
    variables: [String: GatewayJSONValue],
    selection: GatewaySelection,
    configPath: String?,
    pretty: Bool
  ) throws -> AppleGatewayCommandResult {
    let built: GatewayBuiltDocument
    do {
      built = try GatewayDocumentBuilder(catalog: .apple(role: role)).build(
        GatewayOperationRequest(operation: operation, variables: variables, selection: selection)
      )
    } catch {
      return try operationError(String(describing: error), pretty: pretty)
    }
    let runtimeVariables: [String: GraphQLValue]
    do {
      runtimeVariables = try GraphQLValue.gatewayVariables(built.variables)
    } catch let error as GraphQLRuntimeError {
      return try operationError(error.message, pretty: pretty)
    }
    let config: AppleGatewayConfig
    do {
      config = try resolveConfig(configPath: configPath).config
    } catch let error as AppleGatewayConfigError {
      return try configErrorResult(error, pretty: pretty)
    }
    let response = serviceComposition.executeResponse(
      query: built.document,
      variables: runtimeVariables,
      config: config,
      pretty: pretty
    )
    return AppleGatewayCommandResult(
      output: String(bytes: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func operationError(_ message: String, pretty: Bool) throws -> AppleGatewayCommandResult {
    let response = try AppleGatewayJSONEnvelope.response(
      data: Optional<GraphQLValue>.none,
      errors: [AppleGatewayError(code: .invalidArgument, message: message)],
      pretty: pretty
    )
    return AppleGatewayCommandResult(
      output: String(bytes: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func parseSearchKinds(_ source: String) throws -> Set<GatewayDefinitionKind> {
    let names = source.split(separator: ",").map(String.init)
    guard !names.isEmpty else { throw Error.invalidUsage("Unknown schema search kind: \(source)") }
    var kinds: Set<GatewayDefinitionKind> = []
    for name in names {
      guard let kind = GatewayDefinitionKind(rawValue: name) else {
        throw Error.invalidUsage("Unknown schema search kind: \(name)")
      }
      kinds.insert(kind)
    }
    return kinds
  }

  private func parseSearchLimit(_ source: String) throws -> Int {
    guard let limit = Int(source), limit > 0 else {
      throw Error.invalidUsage("Schema search limit must be a positive integer")
    }
    return limit
  }
}
