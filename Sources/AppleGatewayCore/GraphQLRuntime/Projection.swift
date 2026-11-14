import Foundation

enum GraphQLProjection {
  static func project(_ value: GraphQLValue, selectionSet: [GraphQLField]) -> GraphQLValue {
    switch value {
    case .object(let object):
      var projected: [String: GraphQLValue] = [:]
      for field in selectionSet {
        let responseKey = field.alias ?? field.name
        if let fieldValue = object[field.name] {
          projected[responseKey] = project(fieldValue, selectionSet: field.selectionSet)
        } else {
          projected[responseKey] = .null
        }
      }
      return .object(projected)
    case .list(let values):
      return .list(values.map { project($0, selectionSet: selectionSet) })
    default:
      return value
    }
  }
}
