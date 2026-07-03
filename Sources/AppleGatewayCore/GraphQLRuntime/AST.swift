import Foundation

struct GraphQLLocation: Codable, Equatable {
  var line: Int
  var column: Int
}

struct GraphQLRuntimeError: Error, Equatable {
  var message: String
  var location: GraphQLLocation?
  var code: AppleGatewayErrorCode
}

enum GraphQLOperationKind: Equatable {
  case query
  case mutation
}

struct GraphQLDocument: Equatable {
  var operation: GraphQLOperation
}

struct GraphQLOperation: Equatable {
  var kind: GraphQLOperationKind
  var name: String?
  var variableDefinitions: [GraphQLVariableDefinition]
  var selectionSet: [GraphQLField]
  var location: GraphQLLocation
}

struct GraphQLVariableDefinition: Equatable {
  var name: String
  var type: GraphQLTypeReference
  var defaultValue: GraphQLValue?
  var location: GraphQLLocation
}

struct GraphQLField: Equatable {
  var name: String
  var alias: String?
  var arguments: [GraphQLArgument]
  var selectionSet: [GraphQLField]
  var location: GraphQLLocation
}

struct GraphQLArgument: Equatable {
  var name: String
  var value: GraphQLValue
  var location: GraphQLLocation
}

indirect enum GraphQLTypeReference: Equatable {
  case named(String)
  case list(GraphQLTypeReference)
  case nonNull(GraphQLTypeReference)

  var isNonNull: Bool {
    if case .nonNull = self {
      return true
    }
    return false
  }
}

indirect enum GraphQLValue: Equatable {
  case int(Int)
  case float(Double)
  case string(String)
  case bool(Bool)
  case null
  case enumCase(String)
  case list([GraphQLValue])
  case object([String: GraphQLValue])
  case variable(String)

  var objectValue: [String: GraphQLValue]? {
    if case .object(let value) = self {
      return value
    }
    return nil
  }
}
