import Foundation

struct GraphQLSDLPrinter {
  let schema: GraphQLSchemaRegistry

  func printSchema() -> String {
    var lines: [String] = []
    appendRootType(name: "Query", fields: schema.queryFields, to: &lines)
    if !schema.mutationFields.isEmpty {
      lines.append("")
      appendRootType(name: "Mutation", fields: schema.mutationFields, to: &lines)
    }

    for type in schema.types.values.sorted(by: { $0.name < $1.name }) {
      switch type.kind {
      case .scalar where isBuiltInScalar(type.name):
        continue
      case .scalar:
        lines.append("")
        lines.append("scalar \(type.name)")
      case .enumType(let cases):
        lines.append("")
        lines.append("enum \(type.name) {")
        for enumCase in cases {
          lines.append("  \(enumCase)")
        }
        lines.append("}")
      case .inputObject(let fields):
        lines.append("")
        lines.append("input \(type.name) {")
        for field in fields {
          lines.append("  \(field.name): \(format(field.type))")
        }
        lines.append("}")
      case .object(let fields):
        lines.append("")
        lines.append("type \(type.name) {")
        for field in fields {
          lines.append("  \(fieldSignature(field))")
        }
        lines.append("}")
      }
    }

    return lines.joined(separator: "\n")
  }

  private func appendRootType(
    name: String,
    fields: [GraphQLFieldDefinition],
    to lines: inout [String]
  ) {
    lines.append("type \(name) {")
    for field in fields {
      lines.append("  \(fieldSignature(field))")
    }
    lines.append("}")
  }

  private func fieldSignature(_ field: GraphQLFieldDefinition) -> String {
    if field.arguments.isEmpty {
      return "\(field.name): \(format(field.type))"
    }

    let arguments = field.arguments
      .map { "\($0.name): \(format($0.type))" }
      .joined(separator: ", ")
    return "\(field.name)(\(arguments)): \(format(field.type))"
  }

  private func format(_ type: GraphQLTypeReference) -> String {
    switch type {
    case .named(let name):
      return name
    case .list(let inner):
      return "[\(format(inner))]"
    case .nonNull(let inner):
      return "\(format(inner))!"
    }
  }

  private func isBuiltInScalar(_ name: String) -> Bool {
    ["String", "Int", "Float", "Boolean", "ID"].contains(name)
  }
}
