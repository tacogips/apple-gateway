import Foundation

extension GraphQLSchemaModule {
  static var notifications: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: NotificationsSchema.types,
      queryFields: NotificationsSchema.queryFields,
      mutationFields: NotificationsSchema.mutationFields
    )
  }
}

private enum NotificationsSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      scalar("DateTime"),
      enumType("NotificationSource", ["GATEWAY_HELPER", "SYSTEM_DB"]),
      enumType("NotificationActivationKind", ["CLICKED", "ACTION", "REPLIED", "TIMEOUT", "DISMISSED"]),
      object("DeliveredNotification", fields: [
        field("id", idRequired()),
        field("source", nonNull(named("NotificationSource"))),
        field("appBundleId", string()),
        field("title", string()),
        field("subtitle", string()),
        field("body", string()),
        field("deliveredAt", dateTime())
      ]),
      object("DeliveredNotificationEdge", fields: [
        field("cursor", stringRequired()),
        field("node", nonNull(named("DeliveredNotification")))
      ]),
      object("DeliveredNotificationConnection", fields: [
        field("edges", nonNull(list(nonNull(named("DeliveredNotificationEdge"))))),
        field("pageInfo", nonNull(named("PageInfo"))),
        field("totalCount", intRequired())
      ]),
      object("PostedNotification", fields: [
        field("id", idRequired()),
        field("delivered", boolRequired()),
        field("usedFallback", boolRequired()),
        field("activation", named("NotificationActivation"))
      ]),
      object("NotificationActivation", fields: [
        field("kind", nonNull(named("NotificationActivationKind"))),
        field("actionLabel", string()),
        field("replyText", string())
      ]),
      object("DismissResult", fields: [
        field("dismissedCount", intRequired())
      ]),
      input("NotificationSearchInput", fields: [
        inputField("source", named("NotificationSource"), defaultValue: .enumCase("SYSTEM_DB")),
        inputField("appBundleId", string()),
        inputField("deliveredAfter", dateTime()),
        inputField("deliveredBefore", dateTime()),
        inputField("first", int()),
        inputField("after", string())
      ]),
      input("PostNotificationInput", fields: [
        inputField("title", stringRequired()),
        inputField("subtitle", string()),
        inputField("body", string()),
        inputField("sound", named("Boolean"), defaultValue: .bool(true)),
        inputField("actions", list(nonNull(string()))),
        inputField("allowReply", named("Boolean"), defaultValue: .bool(false)),
        inputField("waitSeconds", int()),
        inputField("allowFallback", named("Boolean"), defaultValue: .bool(false))
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "notifications",
        type: nonNull(named("DeliveredNotificationConnection")),
        arguments: [argument("input", named("NotificationSearchInput"))],
        resolver: { arguments, context in
          try deliveredNotificationConnectionValue(
            context.notificationsService.notifications(
              input: try arguments["input"]?.notificationsNilIfNull?.notificationSearchInputValue()
                ?? NotificationSearchInput()
            )
          )
        }
      )
    ]
  }

  static var mutationFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "postNotification",
        type: nonNull(named("PostedNotification")),
        arguments: [argument("input", nonNull(named("PostNotificationInput")))],
        resolver: { arguments, context in
          try postedNotificationValue(context.notificationsService.postNotification(
            arguments.notificationsRequired("input").postNotificationInputValue()
          ))
        }
      ),
      GraphQLFieldDefinition(
        name: "dismissNotifications",
        type: nonNull(named("DismissResult")),
        arguments: [argument("ids", nonNull(list(nonNull(id()))))],
        resolver: { arguments, context in
          let ids = try arguments.notificationsRequired("ids").notificationStringListValue()
          if ids.contains(where: { $0.hasPrefix("system-db-") }) {
            throw AppleGatewayError(
              code: .invalidArgument,
              message: "macOS offers no supported system-wide notification dismissal; SYSTEM_DB ids cannot be dismissed"
            )
          }
          return try dismissResultValue(context.notificationsService.dismissNotifications(ids: ids))
        }
      ),
      GraphQLFieldDefinition(
        name: "dismissAllGatewayNotifications",
        type: nonNull(named("DismissResult")),
        arguments: [],
        resolver: { _, context in
          try dismissResultValue(context.notificationsService.dismissAllGatewayNotifications())
        }
      )
    ]
  }

  private static func scalar(_ name: String) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .scalar)
  }

  private static func enumType(_ name: String, _ cases: [String]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .enumType(cases))
  }

  private static func object(_ name: String, fields: [GraphQLFieldDefinition]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .object(fields))
  }

  private static func input(_ name: String, fields: [GraphQLInputFieldDefinition]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .inputObject(fields))
  }

  private static func field(_ name: String, _ type: GraphQLTypeReference) -> GraphQLFieldDefinition {
    GraphQLFieldDefinition(name: name, type: type, arguments: [])
  }

  private static func inputField(
    _ name: String,
    _ type: GraphQLTypeReference,
    defaultValue: GraphQLValue? = nil
  ) -> GraphQLInputFieldDefinition {
    GraphQLInputFieldDefinition(name: name, type: type, defaultValue: defaultValue)
  }

  private static func argument(
    _ name: String,
    _ type: GraphQLTypeReference,
    defaultValue: GraphQLValue? = nil
  ) -> GraphQLArgumentDefinition {
    GraphQLArgumentDefinition(name: name, type: type, defaultValue: defaultValue)
  }
}

private func named(_ name: String) -> GraphQLTypeReference {
  .named(name)
}

private func nonNull(_ reference: GraphQLTypeReference) -> GraphQLTypeReference {
  .nonNull(reference)
}

private func list(_ reference: GraphQLTypeReference) -> GraphQLTypeReference {
  .list(reference)
}

private func id() -> GraphQLTypeReference {
  .named("ID")
}

private func idRequired() -> GraphQLTypeReference {
  .nonNull(id())
}

private func string() -> GraphQLTypeReference {
  .named("String")
}

private func stringRequired() -> GraphQLTypeReference {
  .nonNull(string())
}

private func int() -> GraphQLTypeReference {
  .named("Int")
}

private func intRequired() -> GraphQLTypeReference {
  .nonNull(int())
}

private func boolRequired() -> GraphQLTypeReference {
  .nonNull(.named("Boolean"))
}

private func dateTime() -> GraphQLTypeReference {
  .named("DateTime")
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func notificationsRequired(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  var notificationsNilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  func notificationsObjectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw notificationsInvalidValue("Expected input object")
    }
    return value
  }

  func notificationsStringValue() throws -> String {
    switch self {
    case .string(let value), .enumCase(let value):
      return value
    default:
      throw notificationsInvalidValue("Expected string")
    }
  }

  func notificationsBoolValue() throws -> Bool {
    guard case .bool(let value) = self else {
      throw notificationsInvalidValue("Expected boolean")
    }
    return value
  }

  func notificationsIntValue() throws -> Int {
    guard case .int(let value) = self else {
      throw notificationsInvalidValue("Expected int")
    }
    return value
  }

  func notificationStringListValue() throws -> [String] {
    guard case .list(let values) = self else {
      throw notificationsInvalidValue("Expected string list")
    }
    return try values.map { try $0.notificationsStringValue() }
  }

  func notificationSearchInputValue() throws -> NotificationSearchInput {
    let object = try notificationsObjectDictionary()
    return NotificationSearchInput(
      source: try object["source"]?.notificationsNilIfNull?.notificationSourceValue() ?? .systemDb,
      appBundleId: try object.notificationsOptionalString("appBundleId"),
      deliveredAfter: try object.notificationsOptionalDate("deliveredAfter"),
      deliveredBefore: try object.notificationsOptionalDate("deliveredBefore"),
      first: try object.notificationsOptionalInt("first"),
      after: try object.notificationsOptionalString("after")
    )
  }

  func postNotificationInputValue() throws -> PostNotificationInput {
    let object = try notificationsObjectDictionary()
    return PostNotificationInput(
      title: try object.notificationsRequired("title").notificationsStringValue(),
      subtitle: try object.notificationsOptionalString("subtitle"),
      body: try object.notificationsOptionalString("body"),
      sound: try object["sound"]?.notificationsNilIfNull?.notificationsBoolValue() ?? true,
      actions: try object["actions"]?.notificationsNilIfNull?.notificationStringListValue() ?? [],
      allowReply: try object["allowReply"]?.notificationsNilIfNull?.notificationsBoolValue() ?? false,
      waitSeconds: try object.notificationsOptionalInt("waitSeconds"),
      allowFallback: try object["allowFallback"]?.notificationsNilIfNull?.notificationsBoolValue() ?? false
    )
  }

  func notificationSourceValue() throws -> NotificationSource {
    let rawValue = try notificationsStringValue()
    guard let source = NotificationSource(rawValue: rawValue) else {
      throw notificationsInvalidValue("Invalid NotificationSource \(rawValue)")
    }
    return source
  }

  func notificationsInvalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func notificationsOptionalString(_ key: String) throws -> String? {
    try self[key]?.notificationsNilIfNull?.notificationsStringValue()
  }

  func notificationsOptionalInt(_ key: String) throws -> Int? {
    try self[key]?.notificationsNilIfNull?.notificationsIntValue()
  }

  func notificationsOptionalDate(_ key: String) throws -> Date? {
    guard let value = try notificationsOptionalString(key) else {
      return nil
    }
    return try EventKitDateTime.parse(value)
  }
}

private func deliveredNotificationConnectionValue(_ connection: DeliveredNotificationConnection) -> GraphQLValue {
  .object([
    "edges": .list(connection.edges.map(deliveredNotificationEdgeValue)),
    "pageInfo": notificationsPageInfoValue(connection.pageInfo),
    "totalCount": .int(connection.totalCount)
  ])
}

private func deliveredNotificationEdgeValue(_ edge: DeliveredNotificationEdge) -> GraphQLValue {
  .object([
    "cursor": .string(edge.cursor),
    "node": deliveredNotificationValue(edge.node)
  ])
}

private func deliveredNotificationValue(_ notification: DeliveredNotification) -> GraphQLValue {
  .object([
    "id": .string(notification.id),
    "source": .enumCase(notification.source.rawValue),
    "appBundleId": notification.appBundleId.map(GraphQLValue.string) ?? .null,
    "title": notification.title.map(GraphQLValue.string) ?? .null,
    "subtitle": notification.subtitle.map(GraphQLValue.string) ?? .null,
    "body": notification.body.map(GraphQLValue.string) ?? .null,
    "deliveredAt": notification.deliveredAt.map(GraphQLValue.string) ?? .null
  ])
}

private func postedNotificationValue(_ notification: PostedNotification) -> GraphQLValue {
  .object([
    "id": .string(notification.id),
    "delivered": .bool(notification.delivered),
    "usedFallback": .bool(notification.usedFallback),
    "activation": notification.activation.map(notificationActivationValue) ?? .null
  ])
}

private func notificationActivationValue(_ activation: NotificationActivation) -> GraphQLValue {
  .object([
    "kind": .enumCase(activation.kind.graphQLRawValue),
    "actionLabel": activation.actionLabel.map(GraphQLValue.string) ?? .null,
    "replyText": activation.replyText.map(GraphQLValue.string) ?? .null
  ])
}

private func dismissResultValue(_ result: DismissResult) -> GraphQLValue {
  .object(["dismissedCount": .int(result.dismissedCount)])
}

private func notificationsPageInfoValue(_ pageInfo: PageInfo) -> GraphQLValue {
  .object([
    "hasNextPage": .bool(pageInfo.hasNextPage),
    "endCursor": pageInfo.endCursor.map(GraphQLValue.string) ?? .null
  ])
}

private extension NotificationActivationKind {
  var graphQLRawValue: String {
    switch self {
    case .clicked:
      "CLICKED"
    case .action:
      "ACTION"
    case .replied:
      "REPLIED"
    case .timeout:
      "TIMEOUT"
    case .dismissed:
      "DISMISSED"
    }
  }
}
