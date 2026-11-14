import Foundation

extension GraphQLSchemaModule {
  static var mail: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: MailSchema.types,
      queryFields: MailSchema.queryFields,
      mutationFields: []
    )
  }
}

private enum MailSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      scalar("ID"),
      scalar("DateTime"),
      enumType("MailFileKind", MailFileKind.allCases.map(\.rawValue)),
      object("MailAccount", fields: [
        field("id", idRequired()),
        field("name", stringRequired()),
        field("kind", stringRequired())
      ]),
      object("Mailbox", fields: [
        field("id", idRequired()),
        field("accountId", idRequired()),
        field("name", stringRequired()),
        field("path", stringRequired()),
        field("totalCount", intRequired()),
        field("unreadCount", intRequired())
      ]),
      object("MailAddress", fields: [
        field("raw", stringRequired()),
        field("name", string()),
        field("email", string())
      ]),
      object("MailMessageFile", fields: [
        field("downloadKey", stringRequired()),
        field("kind", nonNull(named("MailFileKind"))),
        field("filename", string()),
        field("mimeType", string()),
        field("byteSize", int())
      ]),
      object("MailMessageFileSet", fields: [
        field("bodyText", named("MailMessageFile")),
        field("bodyHtml", named("MailMessageFile")),
        field("rawSource", named("MailMessageFile")),
        field("attachments", nonNull(list(nonNull(named("MailMessageFile")))))
      ]),
      object("MailMessage", fields: [
        field("id", idRequired()),
        field("mailboxId", idRequired()),
        field("accountId", idRequired()),
        field("messageId", string()),
        field("subject", string()),
        field("snippet", string()),
        field("from", named("MailAddress")),
        field("to", nonNull(list(nonNull(named("MailAddress"))))),
        field("cc", nonNull(list(nonNull(named("MailAddress"))))),
        field("dateSent", dateTime()),
        field("dateReceived", dateTime()),
        field("isRead", boolRequired()),
        field("isFlagged", boolRequired()),
        field("hasAttachments", boolRequired()),
        field("files", nonNull(named("MailMessageFileSet")))
      ]),
      object("MailMessageEdge", fields: [
        field("cursor", stringRequired()),
        field("node", nonNull(named("MailMessage")))
      ]),
      object("MailMessageConnection", fields: [
        field("edges", nonNull(list(nonNull(named("MailMessageEdge"))))),
        field("pageInfo", nonNull(named("PageInfo"))),
        field("totalCount", intRequired())
      ]),
      input("MailSearchInput", fields: [
        inputField("accountId", id()),
        inputField("mailboxId", id()),
        inputField("query", string()),
        inputField("from", string()),
        inputField("to", string()),
        inputField("subject", string()),
        inputField("receivedAfter", dateTime()),
        inputField("receivedBefore", dateTime()),
        inputField("unreadOnly", named("Boolean")),
        inputField("flaggedOnly", named("Boolean")),
        inputField("first", int()),
        inputField("after", string())
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "mailAccounts",
        type: nonNull(list(nonNull(named("MailAccount")))),
        arguments: [],
        resolver: { _, context in
          .list(try context.mailReadService.accounts().map(mailAccountValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "mailboxes",
        type: nonNull(list(nonNull(named("Mailbox")))),
        arguments: [argument("accountId", id())],
        resolver: { arguments, context in
          .list(try context.mailReadService.mailboxes(
            accountId: try arguments["accountId"]?.mailNilIfNull?.mailStringValue()
          ).map(mailboxValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "mailMessages",
        type: nonNull(named("MailMessageConnection")),
        arguments: [argument("input", nonNull(named("MailSearchInput")))],
        resolver: { arguments, context in
          try mailMessageConnectionValue(
            context.mailReadService.messages(input: arguments.mailRequired("input").mailSearchInputValue())
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "mailMessage",
        type: named("MailMessage"),
        arguments: [argument("messageId", idRequired())],
        resolver: { arguments, context in
          let message = try context.mailReadService.message(
            messageId: arguments.mailRequired("messageId").mailStringValue()
          )
          return message.map(mailMessageValue) ?? .null
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

  private static func inputField(_ name: String, _ type: GraphQLTypeReference) -> GraphQLInputFieldDefinition {
    GraphQLInputFieldDefinition(name: name, type: type)
  }

  private static func argument(_ name: String, _ type: GraphQLTypeReference) -> GraphQLArgumentDefinition {
    GraphQLArgumentDefinition(name: name, type: type)
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
  func mailRequired(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  var mailNilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  func mailStringValue() throws -> String {
    switch self {
    case .string(let value), .enumCase(let value):
      return value
    default:
      throw mailInvalidValue("Expected string")
    }
  }

  func mailIntValue() throws -> Int {
    guard case .int(let value) = self else {
      throw mailInvalidValue("Expected int")
    }
    return value
  }

  func mailBoolValue() throws -> Bool {
    guard case .bool(let value) = self else {
      throw mailInvalidValue("Expected boolean")
    }
    return value
  }

  func mailObjectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw mailInvalidValue("Expected input object")
    }
    return value
  }

  func mailOptionalString(_ key: String) throws -> String? {
    try mailObjectDictionary()[key]?.mailNilIfNull?.mailStringValue()
  }

  func mailOptionalInt(_ key: String) throws -> Int? {
    try mailObjectDictionary()[key]?.mailNilIfNull?.mailIntValue()
  }

  func mailOptionalBool(_ key: String) throws -> Bool {
    try mailObjectDictionary()[key]?.mailNilIfNull?.mailBoolValue() ?? false
  }

  func mailOptionalDate(_ key: String) throws -> Date? {
    guard let value = try mailObjectDictionary()[key]?.mailNilIfNull else {
      return nil
    }
    return try EventKitDateTime.parse(value.mailStringValue())
  }

  func mailSearchInputValue() throws -> MailSearchInput {
    MailSearchInput(
      accountId: try mailOptionalString("accountId"),
      mailboxId: try mailOptionalString("mailboxId"),
      query: try mailOptionalString("query"),
      from: try mailOptionalString("from"),
      to: try mailOptionalString("to"),
      subject: try mailOptionalString("subject"),
      receivedAfter: try mailOptionalDate("receivedAfter"),
      receivedBefore: try mailOptionalDate("receivedBefore"),
      unreadOnly: try mailOptionalBool("unreadOnly"),
      flaggedOnly: try mailOptionalBool("flaggedOnly"),
      first: try mailOptionalInt("first"),
      after: try mailOptionalString("after")
    )
  }

  func mailInvalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private func mailAccountValue(_ account: MailAccount) -> GraphQLValue {
  .object([
    "id": .string(account.id),
    "name": .string(account.name),
    "kind": .string(account.kind.rawValue)
  ])
}

private func mailboxValue(_ mailbox: Mailbox) -> GraphQLValue {
  .object([
    "id": .string(mailbox.id),
    "accountId": .string(mailbox.accountId),
    "name": .string(mailbox.name),
    "path": .string(mailbox.path),
    "totalCount": .int(mailbox.totalCount),
    "unreadCount": .int(mailbox.unreadCount)
  ])
}

private func mailAddressValue(_ address: MailAddress) -> GraphQLValue {
  .object([
    "raw": .string(address.raw),
    "name": address.name.map(GraphQLValue.string) ?? .null,
    "email": address.email.map(GraphQLValue.string) ?? .null
  ])
}

private func mailMessageValue(_ message: MailMessage) -> GraphQLValue {
  .object([
    "id": .string(message.id),
    "mailboxId": .string(message.mailboxId),
    "accountId": .string(message.accountId),
    "messageId": message.messageId.map(GraphQLValue.string) ?? .null,
    "subject": message.subject.map(GraphQLValue.string) ?? .null,
    "snippet": message.snippet.map(GraphQLValue.string) ?? .null,
    "from": message.from.map(mailAddressValue) ?? .null,
    "to": .list(message.to.map(mailAddressValue)),
    "cc": .list(message.cc.map(mailAddressValue)),
    "dateSent": mailDateValue(message.dateSent),
    "dateReceived": mailDateValue(message.dateReceived),
    "isRead": .bool(message.isRead),
    "isFlagged": .bool(message.isFlagged),
    "hasAttachments": .bool(message.hasAttachments),
    "files": mailMessageFileSetValue(message.files)
  ])
}

private func mailMessageFileSetValue(_ files: MailMessageFileSet) -> GraphQLValue {
  .object([
    "bodyText": files.bodyText.map(mailMessageFileValue) ?? .null,
    "bodyHtml": files.bodyHtml.map(mailMessageFileValue) ?? .null,
    "rawSource": files.rawSource.map(mailMessageFileValue) ?? .null,
    "attachments": .list(files.attachments.map(mailMessageFileValue))
  ])
}

private func mailMessageFileValue(_ file: MailMessageFile) -> GraphQLValue {
  .object([
    "downloadKey": .string(file.downloadKey),
    "kind": .enumCase(file.kind.rawValue),
    "filename": file.filename.map(GraphQLValue.string) ?? .null,
    "mimeType": file.mimeType.map(GraphQLValue.string) ?? .null,
    "byteSize": file.byteSize.map(GraphQLValue.int) ?? .null
  ])
}

private func mailMessageConnectionValue(_ connection: MailMessageConnection) -> GraphQLValue {
  .object([
    "edges": .list(connection.edges.map(mailMessageEdgeValue)),
    "pageInfo": mailPageInfoValue(connection.pageInfo),
    "totalCount": .int(connection.totalCount)
  ])
}

private func mailMessageEdgeValue(_ edge: MailMessageEdge) -> GraphQLValue {
  .object([
    "cursor": .string(edge.cursor),
    "node": mailMessageValue(edge.node)
  ])
}

private func mailPageInfoValue(_ pageInfo: PageInfo) -> GraphQLValue {
  .object([
    "hasNextPage": .bool(pageInfo.hasNextPage),
    "endCursor": pageInfo.endCursor.map(GraphQLValue.string) ?? .null
  ])
}

private let mailGraphQLTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

private func mailDateValue(_ date: Date?) -> GraphQLValue {
  guard let date else {
    return .null
  }
  return .string(EventKitDateTime.format(date, timeZone: mailGraphQLTimeZone))
}
