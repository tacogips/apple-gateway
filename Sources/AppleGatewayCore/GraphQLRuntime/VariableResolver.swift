import Foundation

struct GraphQLVariableResolver {
  let schema: GraphQLSchemaRegistry

  func resolveArguments(
    field: GraphQLField,
    definition: GraphQLFieldDefinition,
    variables: [String: GraphQLValue],
    variableDefinitions: [GraphQLVariableDefinition]
  ) throws -> GraphQLResolvedArguments {
    var resolved: GraphQLResolvedArguments = [:]
    let suppliedArguments = Dictionary(uniqueKeysWithValues: field.arguments.map { ($0.name, $0.value) })
    let variableDefinitionByName = Dictionary(uniqueKeysWithValues: variableDefinitions.map { ($0.name, $0) })

    for argumentDefinition in definition.arguments {
      if let supplied = suppliedArguments[argumentDefinition.name] {
        resolved[argumentDefinition.name] = try resolveValue(
          supplied,
          expectedType: argumentDefinition.type,
          variables: variables,
          variableDefinitions: variableDefinitionByName,
          location: field.location
        )
      } else if let defaultValue = argumentDefinition.defaultValue {
        resolved[argumentDefinition.name] = try coerce(defaultValue, to: argumentDefinition.type)
      }
    }

    return resolved
  }

  func coerceJSONVariables(
    _ variables: [String: GraphQLValue],
    definitions: [GraphQLVariableDefinition]
  ) throws -> [String: GraphQLValue] {
    var coerced: [String: GraphQLValue] = [:]

    for definition in definitions {
      if let supplied = variables[definition.name] {
        coerced[definition.name] = try coerce(supplied, to: definition.type)
      } else if let defaultValue = definition.defaultValue {
        coerced[definition.name] = try coerce(defaultValue, to: definition.type)
      } else if definition.type.isNonNull {
        throw GraphQLRuntimeError(
          message: "Missing required variable $\(definition.name)",
          location: definition.location,
          code: .graphQLValidationError
        )
      }
    }

    return coerced
  }

  private func resolveValue(
    _ value: GraphQLValue,
    expectedType: GraphQLTypeReference,
    variables: [String: GraphQLValue],
    variableDefinitions: [String: GraphQLVariableDefinition],
    location: GraphQLLocation
  ) throws -> GraphQLValue {
    if case .variable(let name) = value {
      guard let supplied = variables[name] else {
        throw GraphQLRuntimeError(
          message: "Variable $\(name) was not provided",
          location: variableDefinitions[name]?.location ?? location,
          code: .graphQLValidationError
        )
      }
      return try coerce(supplied, to: expectedType)
    }
    return try coerce(value, to: expectedType)
  }

  func coerce(_ value: GraphQLValue, to type: GraphQLTypeReference) throws -> GraphQLValue {
    switch type {
    case .nonNull(let inner):
      if value == .null {
        throw coercionError("Expected non-null value")
      }
      return try coerce(value, to: inner)
    case .list(let inner):
      if value == .null {
        return .null
      }
      guard case .list(let values) = value else {
        return .list([try coerce(value, to: inner)])
      }
      return .list(try values.map { try coerce($0, to: inner) })
    case .named(let name):
      return try coerceNamed(value, to: name)
    }
  }

  private func coerceNamed(_ value: GraphQLValue, to name: String) throws -> GraphQLValue {
    if value == .null {
      return .null
    }

    guard let typeDefinition = schema.types[name] else {
      throw coercionError("Unknown type \(name)")
    }

    switch typeDefinition.kind {
    case .scalar:
      return try coerceScalar(value, to: name)
    case .enumType(let cases):
      if case .enumCase(let value) = value, cases.contains(value) {
        return .enumCase(value)
      }
      if case .string(let value) = value, cases.contains(value) {
        return .enumCase(value)
      }
      throw coercionError("Expected enum \(name)")
    case .inputObject(let fields):
      return try coerceInputObject(value, fields: fields, name: name)
    case .object:
      return value
    }
  }

  private func coerceScalar(_ value: GraphQLValue, to name: String) throws -> GraphQLValue {
    switch (name, value) {
    case ("String", .string), ("Int", .int), ("Float", .float), ("Boolean", .bool):
      return value
    case ("ID", .string):
      return value
    case ("DateTime", .string(let stringValue)):
      guard (try? EventKitDateTime.parse(stringValue)) != nil else {
        throw coercionError("Expected scalar DateTime")
      }
      return value
    case ("Float", .int(let intValue)):
      return .float(Double(intValue))
    default:
      throw coercionError("Expected scalar \(name)")
    }
  }

  private func coerceInputObject(
    _ value: GraphQLValue,
    fields: [GraphQLInputFieldDefinition],
    name: String
  ) throws -> GraphQLValue {
    guard case .object(let object) = value else {
      throw coercionError("Expected input object \(name)")
    }

    let knownFields = Set(fields.map(\.name))
    for suppliedField in object.keys where !knownFields.contains(suppliedField) {
      throw coercionError("Unknown input field \(suppliedField)")
    }

    var coerced: [String: GraphQLValue] = [:]
    for field in fields {
      if let supplied = object[field.name] {
        coerced[field.name] = try coerce(supplied, to: field.type)
      } else if let defaultValue = field.defaultValue {
        coerced[field.name] = try coerce(defaultValue, to: field.type)
      } else if field.type.isNonNull {
        throw coercionError("Missing required input field \(field.name)")
      }
    }
    return .object(coerced)
  }

  private func coercionError(_ message: String) -> GraphQLRuntimeError {
    GraphQLRuntimeError(message: message, location: nil, code: .graphQLValidationError)
  }
}

extension GraphQLValue {
  static func fromJSONObject(_ object: Any) throws -> GraphQLValue {
    switch object {
    case is NSNull:
      return .null
    case let value as Bool:
      return .bool(value)
    case let value as Int:
      return .int(value)
    case let value as Double:
      if value.rounded() == value {
        return .int(Int(value))
      }
      return .float(value)
    case let value as String:
      return .string(value)
    case let value as [Any]:
      return .list(try value.map { try GraphQLValue.fromJSONObject($0) })
    case let value as [String: Any]:
      return .object(try value.mapValues { try GraphQLValue.fromJSONObject($0) })
    default:
      throw GraphQLRuntimeError(
        message: "Variables must contain JSON values",
        location: nil,
        code: .graphQLValidationError
      )
    }
  }
}
