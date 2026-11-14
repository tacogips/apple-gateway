import Foundation

struct GraphQLValidator {
  let schema: GraphQLSchemaRegistry

  func validate(_ document: GraphQLDocument) throws {
    let operation = document.operation

    if schema.role == .reader, operation.kind == .mutation {
      throw GraphQLRuntimeError(
        message: "Mutations are disabled in reader mode",
        location: operation.location,
        code: .writeDisabledInReader
      )
    }

    try validateVariableDefinitions(operation.variableDefinitions)
    let rootType = operation.kind == .query ? "Query" : "Mutation"
    try validateSelectionSet(
      operation.selectionSet,
      parentTypeName: rootType,
      variableDefinitions: operation.variableDefinitions
    )
  }

  private func validateVariableDefinitions(_ definitions: [GraphQLVariableDefinition]) throws {
    var names: Set<String> = []
    for definition in definitions {
      guard names.insert(definition.name).inserted else {
        throw error("Duplicate variable $\(definition.name)", at: definition.location)
      }
      try validateTypeReference(definition.type, at: definition.location, inputOnly: true)
      if let defaultValue = definition.defaultValue {
        _ = try GraphQLVariableResolver(schema: schema).coerce(defaultValue, to: definition.type)
      }
    }
  }

  private func validateSelectionSet(
    _ fields: [GraphQLField],
    parentTypeName: String,
    variableDefinitions: [GraphQLVariableDefinition]
  ) throws {
    for field in fields {
      guard let definition = schema.field(named: field.name, on: parentTypeName) else {
        throw error("Unknown field \(field.name) on \(parentTypeName)", at: field.location)
      }
      try validateArguments(
        field.arguments,
        definitions: definition.arguments,
        variableDefinitions: variableDefinitions
      )
      try validateSelectionShape(field: field, definition: definition)

      if !field.selectionSet.isEmpty {
        try validateSelectionSet(
          field.selectionSet,
          parentTypeName: schema.namedType(definition.type),
          variableDefinitions: variableDefinitions
        )
      }
    }
  }

  private func validateArguments(
    _ arguments: [GraphQLArgument],
    definitions: [GraphQLArgumentDefinition],
    variableDefinitions: [GraphQLVariableDefinition]
  ) throws {
    let definitionByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
    let variableDefinitionByName = Dictionary(uniqueKeysWithValues: variableDefinitions.map { ($0.name, $0) })
    var suppliedNames: Set<String> = []

    for argument in arguments {
      guard suppliedNames.insert(argument.name).inserted else {
        throw error("Duplicate argument \(argument.name)", at: argument.location)
      }

      guard let definition = definitionByName[argument.name] else {
        throw error("Unknown argument \(argument.name)", at: argument.location)
      }

      try validateValue(
        argument.value,
        expectedType: definition.type,
        variableDefinitions: variableDefinitionByName,
        location: argument.location
      )
    }

    for definition in definitions where definition.type.isNonNull && definition.defaultValue == nil {
      if !suppliedNames.contains(definition.name) {
        throw error("Missing required argument \(definition.name)", at: nil)
      }
    }
  }

  private func validateValue(
    _ value: GraphQLValue,
    expectedType: GraphQLTypeReference,
    variableDefinitions: [String: GraphQLVariableDefinition],
    location: GraphQLLocation
  ) throws {
    if case .variable(let name) = value {
      guard let variableDefinition = variableDefinitions[name] else {
        throw error("Unknown variable $\(name)", at: location)
      }
      guard variableType(variableDefinition.type, canFlowInto: expectedType) else {
        throw error(
          "Variable $\(name) type does not match expected argument type",
          at: variableDefinition.location
        )
      }
      return
    }

    do {
      _ = try GraphQLVariableResolver(schema: schema).coerce(value, to: expectedType)
    } catch let runtimeError as GraphQLRuntimeError {
      throw GraphQLRuntimeError(
        message: runtimeError.message,
        location: location,
        code: runtimeError.code
      )
    }
  }

  private func validateSelectionShape(
    field: GraphQLField,
    definition: GraphQLFieldDefinition
  ) throws {
    guard let typeDefinition = schema.typeDefinition(for: definition.type) else {
      throw error("Unknown result type \(schema.namedType(definition.type))", at: field.location)
    }

    switch typeDefinition.kind {
    case .object:
      if field.selectionSet.isEmpty {
        throw error("Field \(field.name) requires a selection set", at: field.location)
      }
    case .scalar, .enumType:
      if !field.selectionSet.isEmpty {
        throw error("Field \(field.name) must not have a selection set", at: field.location)
      }
    case .inputObject:
      throw error("Input object cannot be a result type", at: field.location)
    }
  }

  private func validateTypeReference(
    _ type: GraphQLTypeReference,
    at location: GraphQLLocation,
    inputOnly: Bool
  ) throws {
    switch type {
    case .nonNull(let inner), .list(let inner):
      try validateTypeReference(inner, at: location, inputOnly: inputOnly)
    case .named(let name):
      guard let definition = schema.types[name] else {
        throw error("Unknown type \(name)", at: location)
      }
      if inputOnly, case .object = definition.kind {
        throw error("Variables cannot use output object type \(name)", at: location)
      }
    }
  }

  private func variableType(
    _ variableType: GraphQLTypeReference,
    canFlowInto expectedType: GraphQLTypeReference
  ) -> Bool {
    variableType == expectedType || stripNonNull(variableType) == stripNonNull(expectedType)
  }

  private func stripNonNull(_ type: GraphQLTypeReference) -> GraphQLTypeReference {
    if case .nonNull(let inner) = type {
      return inner
    }
    return type
  }

  private func error(_ message: String, at location: GraphQLLocation?) -> GraphQLRuntimeError {
    GraphQLRuntimeError(message: message, location: location, code: .graphQLValidationError)
  }
}
