import Foundation

enum GraphQLNamedTypeKind: Equatable {
  case scalar
  case object([GraphQLFieldDefinition])
  case enumType([String])
  case inputObject([GraphQLInputFieldDefinition])
}

struct GraphQLNamedTypeDefinition: Equatable {
  var name: String
  var kind: GraphQLNamedTypeKind
}

struct GraphQLFieldDefinition: Equatable {
  var name: String
  var type: GraphQLTypeReference
  var arguments: [GraphQLArgumentDefinition]
  var resolver: GraphQLResolver?

  static func == (lhs: GraphQLFieldDefinition, rhs: GraphQLFieldDefinition) -> Bool {
    lhs.name == rhs.name && lhs.type == rhs.type && lhs.arguments == rhs.arguments
  }
}

struct GraphQLArgumentDefinition: Equatable {
  var name: String
  var type: GraphQLTypeReference
  var defaultValue: GraphQLValue?
}

struct GraphQLInputFieldDefinition: Equatable {
  var name: String
  var type: GraphQLTypeReference
  var defaultValue: GraphQLValue?
}

struct GraphQLSchemaModule {
  var types: [GraphQLNamedTypeDefinition]
  var queryFields: [GraphQLFieldDefinition]
  var mutationFields: [GraphQLFieldDefinition]
}

typealias GraphQLResolvedArguments = [String: GraphQLValue]
typealias GraphQLResolver = (GraphQLResolvedArguments, GraphQLExecutionContext) throws -> GraphQLValue

struct GraphQLExecutionContext {
  var config: AppleGatewayConfig
  var role: AppleGatewayRole
  var permissionsProvider: any PermissionsStatusProviding
  var calendarReadService: CalendarReadService
  var calendarWriteService: CalendarWriteService
  var notesReadService: NotesReadService
  var notesWriteService: NotesWriteService
  var mailReadService: MailReadService
  var notificationsService: any NotificationsProviding
  var clockAlarmsService: any ClockAlarmsProviding
}

struct GraphQLSchemaRegistry {
  let role: AppleGatewayRole
  let types: [String: GraphQLNamedTypeDefinition]
  let queryFields: [GraphQLFieldDefinition]
  let mutationFields: [GraphQLFieldDefinition]

  init(modules: [GraphQLSchemaModule], role: AppleGatewayRole) {
    self.role = role
    var collectedTypes: [String: GraphQLNamedTypeDefinition] = [:]
    var queries: [GraphQLFieldDefinition] = []
    var mutations: [GraphQLFieldDefinition] = []

    for module in modules {
      for type in module.types {
        collectedTypes[type.name] = type
      }
      queries.append(contentsOf: module.queryFields)
      mutations.append(contentsOf: module.mutationFields)
    }

    types = collectedTypes
    queryFields = queries
    mutationFields = role == .reader ? [] : mutations
  }

  static func bootstrap(role: AppleGatewayRole) -> GraphQLSchemaRegistry {
    GraphQLSchemaRegistry(
      modules: [.permissions, .calendarReminders, .notes, .mail, .notifications, .clockAlarms],
      role: role
    )
  }

  func rootFields(for kind: GraphQLOperationKind) -> [GraphQLFieldDefinition] {
    switch kind {
    case .query:
      return queryFields
    case .mutation:
      return mutationFields
    }
  }

  func field(named name: String, on typeName: String) -> GraphQLFieldDefinition? {
    if typeName == "Query" {
      return queryFields.first { $0.name == name }
    }

    if typeName == "Mutation" {
      return mutationFields.first { $0.name == name }
    }

    guard
      let definition = types[typeName],
      case .object(let fields) = definition.kind
    else {
      return nil
    }

    return fields.first { $0.name == name }
  }

  func namedType(_ reference: GraphQLTypeReference) -> String {
    switch reference {
    case .named(let name):
      return name
    case .list(let inner), .nonNull(let inner):
      return namedType(inner)
    }
  }

  func typeDefinition(for reference: GraphQLTypeReference) -> GraphQLNamedTypeDefinition? {
    types[namedType(reference)]
  }
}

extension GraphQLSchemaModule {
  static var permissions: GraphQLSchemaModule {
    let permissionsStatus = GraphQLNamedTypeDefinition(
      name: "PermissionsStatus",
      kind: .object([
        GraphQLFieldDefinition(name: "calendars", type: .nonNull(.named("PermissionState")), arguments: []),
        GraphQLFieldDefinition(name: "reminders", type: .nonNull(.named("PermissionState")), arguments: []),
        GraphQLFieldDefinition(name: "notesAutomation", type: .nonNull(.named("PermissionState")), arguments: []),
        GraphQLFieldDefinition(name: "mailFullDiskAccess", type: .nonNull(.named("PermissionState")), arguments: []),
        GraphQLFieldDefinition(name: "notificationsHelper", type: .nonNull(.named("PermissionState")), arguments: []),
        GraphQLFieldDefinition(
          name: "notificationDbFullDiskAccess",
          type: .nonNull(.named("PermissionState")),
          arguments: []
        ),
        GraphQLFieldDefinition(name: "clockAutomation", type: .nonNull(.named("PermissionState")), arguments: [])
      ])
    )

    return GraphQLSchemaModule(
      types: [
        GraphQLNamedTypeDefinition(name: "String", kind: .scalar),
        GraphQLNamedTypeDefinition(name: "Int", kind: .scalar),
        GraphQLNamedTypeDefinition(name: "Float", kind: .scalar),
        GraphQLNamedTypeDefinition(name: "Boolean", kind: .scalar),
        GraphQLNamedTypeDefinition(
          name: "PermissionState",
          kind: .enumType(PermissionState.allCases.map(\.rawValue))
        ),
        permissionsStatus
      ],
      queryFields: [
        GraphQLFieldDefinition(
          name: "permissions",
          type: .nonNull(.named("PermissionsStatus")),
          arguments: [],
          resolver: { _, context in
            context.permissionsProvider.status(config: context.config).graphQLValue
          }
        )
      ],
      mutationFields: []
    )
  }
}
