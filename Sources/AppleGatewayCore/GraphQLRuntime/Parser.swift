import Foundation

struct GraphQLParser {
  private let tokens: [GraphQLToken]
  private var index = 0

  init(tokens: [GraphQLToken]) {
    self.tokens = tokens
  }

  mutating func parseDocument() throws -> GraphQLDocument {
    let operation = try parseOperation()
    guard isAtEnd else {
      let token = current
      if case .name("fragment") = token.kind {
        throw error("Fragments are not supported", at: token.location)
      }
      throw error("Multiple operations are not supported", at: token.location)
    }
    return GraphQLDocument(operation: operation)
  }

  private mutating func parseOperation() throws -> GraphQLOperation {
    if matchPunctuator("{") {
      return GraphQLOperation(
        kind: .query,
        name: nil,
        variableDefinitions: [],
        selectionSet: try parseSelectionSetBody(),
        location: previous.location
      )
    }

    let operationToken = current
    let operationName = try consumeName("Expected operation")
    let kind: GraphQLOperationKind
    switch operationName {
    case "query":
      kind = .query
    case "mutation":
      kind = .mutation
    case "subscription":
      throw error("Subscriptions are not supported", at: operationToken.location)
    case "fragment":
      throw error("Fragments are not supported", at: operationToken.location)
    default:
      throw error("Expected query or mutation operation", at: operationToken.location)
    }

    var name: String?
    if case .name(let value) = current.kind {
      name = value
      advance()
    }

    let variables = matchPunctuator("(") ? try parseVariableDefinitions() : []
    if matchPunctuator("@") {
      throw error("Directives are not supported", at: previous.location)
    }
    try consumePunctuator("{", "Expected selection set")
    return GraphQLOperation(
      kind: kind,
      name: name,
      variableDefinitions: variables,
      selectionSet: try parseSelectionSetBody(),
      location: operationToken.location
    )
  }

  private mutating func parseVariableDefinitions() throws -> [GraphQLVariableDefinition] {
    var definitions: [GraphQLVariableDefinition] = []

    while !matchPunctuator(")") {
      let location = current.location
      try consumePunctuator("$", "Expected variable name")
      let name = try consumeName("Expected variable name")
      try consumePunctuator(":", "Expected ':' after variable name")
      let type = try parseTypeReference()
      let defaultValue = matchPunctuator("=") ? try parseValue() : nil
      definitions.append(
        GraphQLVariableDefinition(
          name: name,
          type: type,
          defaultValue: defaultValue,
          location: location
        )
      )
    }

    return definitions
  }

  private mutating func parseTypeReference() throws -> GraphQLTypeReference {
    let base: GraphQLTypeReference
    if matchPunctuator("[") {
      base = .list(try parseTypeReference())
      try consumePunctuator("]", "Expected ']' after list type")
    } else {
      base = .named(try consumeName("Expected type name"))
    }

    if matchPunctuator("!") {
      return .nonNull(base)
    }
    return base
  }

  private mutating func parseSelectionSetBody() throws -> [GraphQLField] {
    var fields: [GraphQLField] = []
    while !matchPunctuator("}") {
      guard !isAtEnd else {
        throw error("Unterminated selection set", at: current.location)
      }
      fields.append(try parseField())
    }
    return fields
  }

  private mutating func parseField() throws -> GraphQLField {
    if matchPunctuator("...") {
      throw error("Fragments are not supported", at: previous.location)
    }

    let location = current.location
    let firstName = try consumeName("Expected field name")
    var alias: String?
    var name = firstName

    if matchPunctuator(":") {
      alias = firstName
      name = try consumeName("Expected field name after alias")
    }

    let arguments = matchPunctuator("(") ? try parseArguments() : []
    if matchPunctuator("@") {
      throw error("Directives are not supported", at: previous.location)
    }

    let selectionSet = matchPunctuator("{") ? try parseSelectionSetBody() : []
    return GraphQLField(
      name: name,
      alias: alias,
      arguments: arguments,
      selectionSet: selectionSet,
      location: location
    )
  }

  private mutating func parseArguments() throws -> [GraphQLArgument] {
    var arguments: [GraphQLArgument] = []
    while !matchPunctuator(")") {
      let location = current.location
      let name = try consumeName("Expected argument name")
      try consumePunctuator(":", "Expected ':' after argument name")
      arguments.append(GraphQLArgument(name: name, value: try parseValue(), location: location))
    }
    return arguments
  }

  private mutating func parseValue() throws -> GraphQLValue {
    let token = current
    switch token.kind {
    case .int(let value):
      advance()
      guard let intValue = Int(value) else {
        throw error("Invalid integer literal", at: token.location)
      }
      return .int(intValue)
    case .float(let value):
      advance()
      guard let doubleValue = Double(value) else {
        throw error("Invalid float literal", at: token.location)
      }
      return .float(doubleValue)
    case .string(let value):
      advance()
      return .string(value)
    case .name("true"):
      advance()
      return .bool(true)
    case .name("false"):
      advance()
      return .bool(false)
    case .name("null"):
      advance()
      return .null
    case .name(let value):
      advance()
      return .enumCase(value)
    case .punctuator("$"):
      advance()
      return .variable(try consumeName("Expected variable name"))
    case .punctuator("["):
      return try parseListValue()
    case .punctuator("{"):
      return try parseObjectValue()
    default:
      throw error("Expected value", at: token.location)
    }
  }

  private mutating func parseListValue() throws -> GraphQLValue {
    try consumePunctuator("[", "Expected '['")
    var values: [GraphQLValue] = []
    while !matchPunctuator("]") {
      values.append(try parseValue())
    }
    return .list(values)
  }

  private mutating func parseObjectValue() throws -> GraphQLValue {
    try consumePunctuator("{", "Expected '{'")
    var values: [String: GraphQLValue] = [:]
    while !matchPunctuator("}") {
      let name = try consumeName("Expected input object field")
      try consumePunctuator(":", "Expected ':' after input object field")
      values[name] = try parseValue()
    }
    return .object(values)
  }

  private var current: GraphQLToken {
    tokens[min(index, tokens.count - 1)]
  }

  private var previous: GraphQLToken {
    tokens[max(index - 1, 0)]
  }

  private var isAtEnd: Bool {
    if case .end = current.kind {
      return true
    }
    return false
  }

  @discardableResult
  private mutating func advance() -> GraphQLToken {
    if !isAtEnd {
      index += 1
    }
    return previous
  }

  private mutating func matchPunctuator(_ value: String) -> Bool {
    guard case .punctuator(let currentValue) = current.kind, currentValue == value else {
      return false
    }
    advance()
    return true
  }

  private mutating func consumePunctuator(_ value: String, _ message: String) throws {
    guard matchPunctuator(value) else {
      throw error(message, at: current.location)
    }
  }

  private mutating func consumeName(_ message: String) throws -> String {
    guard case .name(let value) = current.kind else {
      throw error(message, at: current.location)
    }
    advance()
    return value
  }

  private func error(_ message: String, at location: GraphQLLocation) -> GraphQLRuntimeError {
    GraphQLRuntimeError(message: message, location: location, code: .graphQLParseError)
  }
}
