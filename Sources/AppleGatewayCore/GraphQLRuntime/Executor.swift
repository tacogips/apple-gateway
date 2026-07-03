import Foundation

struct GraphQLExecutor {
  let schema: GraphQLSchemaRegistry
  let context: GraphQLExecutionContext

  func execute(
    document: GraphQLDocument,
    variables: [String: GraphQLValue]
  ) throws -> GraphQLExecutionResult {
    var rootObject: [String: GraphQLValue] = [:]
    var errors: [AppleGatewayError] = []
    let operation = document.operation
    let resolver = GraphQLVariableResolver(schema: schema)
    let variableValues = try resolver.coerceJSONVariables(
      variables,
      definitions: operation.variableDefinitions
    )

    for field in operation.selectionSet {
      let responseKey = field.alias ?? field.name
      guard let definition = schema.field(
        named: field.name,
        on: operation.kind == .query ? "Query" : "Mutation"
      ) else {
        throw GraphQLRuntimeError(
          message: "Unknown field \(field.name)",
          location: field.location,
          code: .graphQLValidationError
        )
      }

      do {
        let arguments = try resolver.resolveArguments(
          field: field,
          definition: definition,
          variables: variableValues,
          variableDefinitions: operation.variableDefinitions
        )
        let resolved = try definition.resolver?(arguments, context) ?? .null
        rootObject[responseKey] = GraphQLProjection.project(
          resolved,
          selectionSet: field.selectionSet
        )
      } catch let error as AppleGatewayError {
        rootObject[responseKey] = .null
        errors.append(error.scoped(to: [responseKey]))
      } catch let error as GraphQLRuntimeError {
        rootObject[responseKey] = .null
        errors.append(error.appleGatewayError(path: [responseKey]))
      } catch {
        rootObject[responseKey] = .null
        errors.append(
          AppleGatewayError(
            code: .unexpectedError,
            message: String(describing: error),
            path: [responseKey]
          )
        )
      }
    }

    return GraphQLExecutionResult(data: .object(rootObject), errors: errors)
  }
}

struct GraphQLExecutionResult {
  var data: GraphQLValue
  var errors: [AppleGatewayError]
}
