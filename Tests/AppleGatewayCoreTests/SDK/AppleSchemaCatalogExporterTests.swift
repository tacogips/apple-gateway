import GatewaySDKKit
import Testing
@testable import AppleGatewayCore

@Test func appleCatalogsValidateAndRespectRoleBoundaries() {
  let full = GatewaySchemaCatalog.apple(role: .full)
  let reader = GatewaySchemaCatalog.apple(role: .reader)

  #expect(full.validate().isEmpty)
  #expect(reader.validate().isEmpty)
  #expect(full.operation(named: "createReminder")?.kind == .mutation)
  #expect(full.operation(named: "createReminder")?.tier == "full")
  #expect(full.operation(named: "createReminder")?.domain == "calendarReminders")
  #expect(full.operation(named: "calendars")?.tier == "reader")
  #expect(full.operation(named: "events")?.tier == "reader")
  #expect(full.operation(named: "deleteEvent")?.isDestructive == true)
  #expect(full.operation(named: "dismissNotifications")?.isDestructive == true)
  #expect(full.operation(named: "createReminder")?.isDestructive == false)
  #expect(reader.operations(of: .mutation).isEmpty)
}

@Test func appleCatalogSDLHasBidirectionalStructuralParityWithRuntime() {
  for role in [AppleGatewayRole.full, .reader] {
    let runtime = comparableSDL(GraphQLRuntime.schema(role: role))
    let catalog = comparableSDL(GatewaySchemaCatalog.apple(role: role).sdl())
    #expect(runtime == catalog)
    #expect(runtime.scalars.contains("DateTime"))
    #expect(catalog.scalars.contains("DateTime"))
    #expect(!runtime.scalars.contains("String"))
    #expect(!catalog.scalars.contains("String"))
    #expect(!runtime.scalars.contains("ID"))
    #expect(!catalog.scalars.contains("ID"))
  }
}

@Test func appleCatalogRequirednessMatchesEveryRuntimeRootArgument() {
  for role in [AppleGatewayRole.full, .reader] {
    let registry = GraphQLSchemaRegistry.bootstrap(role: role)
    let catalog = GatewaySchemaCatalog.apple(role: role)
    for field in registry.queryFields + registry.mutationFields {
      guard let operation = catalog.operation(named: field.name) else {
        Issue.record("Missing catalog operation: \(field.name)")
        continue
      }
      for runtimeArgument in field.arguments {
        guard let exportedArgument = operation.arguments.first(where: { $0.name == runtimeArgument.name }) else {
          Issue.record("Missing catalog argument: \(field.name).\(runtimeArgument.name)")
          continue
        }
        let hasDefault = runtimeArgument.defaultValue != nil
        #expect(exportedArgument.isRequired == (runtimeArgument.type.isNonNull && !hasDefault))
        #expect(
          exportedArgument.type.graphQLString == (
            hasDefault ? runtimeArgument.type.sdl.removingTopLevelNonNull : runtimeArgument.type.sdl
          )
        )
      }
    }
  }
}

private struct ComparableSDL: Equatable {
  var definitions: [String: ComparableDefinition]
  var scalars: Set<String>
}

private struct ComparableDefinition: Equatable {
  var kind: String
  var members: Set<String>
}

private func comparableSDL(_ sdl: String) -> ComparableSDL {
  var definitions: [String: ComparableDefinition] = [:]
  var scalars: Set<String> = []
  var currentName: String?
  var currentKind: String?
  var inDescription = false

  for rawLine in sdl.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line == "\"\"\"" {
      inDescription.toggle()
      continue
    }
    guard !inDescription, !line.isEmpty else { continue }
    if line.hasPrefix("scalar ") {
      scalars.insert(String(line.dropFirst("scalar ".count)))
      continue
    }
    if line.hasPrefix("type ") || line.hasPrefix("input ") || line.hasPrefix("enum ") {
      let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
      guard parts.count >= 2 else { continue }
      currentKind = parts[0]
      currentName = parts[1]
      definitions[parts[1]] = ComparableDefinition(kind: parts[0], members: [])
      continue
    }
    if line == "}" {
      currentName = nil
      currentKind = nil
      continue
    }
    guard let currentName, let currentKind else { continue }
    definitions[currentName]?.members.insert(normalizeMember(line, kind: currentKind))
  }
  return ComparableSDL(definitions: definitions, scalars: scalars)
}

private func normalizeMember(_ line: String, kind: String) -> String {
  guard kind != "enum" else { return line }
  if kind == "input" {
    return normalizeTypeSuffix(in: line)
  }
  guard let closingParenthesis = line.firstIndex(of: ")") else {
    return line
  }
  let arguments = line[line.index(after: line.startIndex)..<closingParenthesis]
  let suffix = line[line.index(after: closingParenthesis)...]
  let normalizedArguments = arguments.split(separator: ",").map { argument in
    normalizeTypeSuffix(in: String(argument))
  }.sorted().joined(separator: ",")
  let name = line[..<line.firstIndex(of: "(")!]
  return "\(name)(\(normalizedArguments))\(suffix)"
}

private func normalizeTypeSuffix(in member: String) -> String {
  guard let separator = member.lastIndex(of: ":") else { return member }
  let name = member[..<separator]
  var type = member[member.index(after: separator)...]
  if type.hasSuffix("!") {
    type.removeLast()
  }
  return "\(name):\(type)"
}

private extension GraphQLTypeReference {
  var sdl: String {
    switch self {
    case .named(let name): name
    case .list(let type): "[\(type.sdl)]"
    case .nonNull(let type): "\(type.sdl)!"
    }
  }
}

private extension String {
  var removingTopLevelNonNull: String {
    hasSuffix("!") ? String(dropLast()) : self
  }
}
