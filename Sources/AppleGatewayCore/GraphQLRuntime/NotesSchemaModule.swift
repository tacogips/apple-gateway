import Foundation

extension GraphQLSchemaModule {
  static var notes: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: NotesSchema.types,
      queryFields: NotesSchema.queryFields,
      mutationFields: NotesSchema.mutationFields
    )
  }
}

private enum NotesSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      scalar("ID"),
      scalar("DateTime"),
      enumType("NoteBodyKind", NoteBodyKind.allCases.map(\.rawValue)),
      enumType("NoteBodyUpdateMode", ["REPLACE", "APPEND"]),
      object("NoteAccount", fields: [
        field("id", idRequired()),
        field("name", stringRequired()),
        field("isDefault", boolRequired())
      ]),
      object("NoteFolder", fields: [
        field("id", idRequired()),
        field("accountId", idRequired()),
        field("name", stringRequired()),
        field("parentFolderId", id()),
        field("noteCount", intRequired())
      ]),
      object("NoteBodyFile", fields: [
        field("downloadKey", stringRequired()),
        field("kind", nonNull(named("NoteBodyKind"))),
        field("byteSize", intRequired())
      ]),
      object("NoteAttachment", fields: [
        field("id", idRequired()),
        field("name", stringRequired()),
        field("contentIdentifier", string()),
        field("downloadKey", string())
      ]),
      object("Note", fields: [
        field("id", idRequired()),
        field("accountId", idRequired()),
        field("folderId", idRequired()),
        field("name", stringRequired()),
        field("snippet", stringRequired()),
        field("plaintext", string()),
        field("bodyHtml", string()),
        field("bodyFile", named("NoteBodyFile")),
        field("isPasswordProtected", boolRequired()),
        field("isShared", boolRequired()),
        field("creationDate", dateTimeRequired()),
        field("modificationDate", dateTimeRequired()),
        field("attachments", nonNull(list(nonNull(named("NoteAttachment")))))
      ]),
      object("NoteEdge", fields: [
        field("cursor", stringRequired()),
        field("node", nonNull(named("Note")))
      ]),
      object("NoteConnection", fields: [
        field("edges", nonNull(list(nonNull(named("NoteEdge"))))),
        field("pageInfo", nonNull(named("PageInfo"))),
        field("totalCount", intRequired())
      ]),
      input("NoteSearchInput", fields: [
        inputField("accountId", id()),
        inputField("folderId", id()),
        inputField("query", string()),
        inputField("modifiedAfter", dateTime()),
        inputField("modifiedBefore", dateTime()),
        inputField("first", int()),
        inputField("after", string())
      ]),
      input("CreateNoteInput", fields: [
        inputField("accountId", id()),
        inputField("folderId", id()),
        inputField("title", stringRequired()),
        inputField("bodyHtml", string()),
        inputField("bodyText", string())
      ]),
      input("UpdateNoteBodyInput", fields: [
        inputField("noteId", idRequired()),
        inputField("mode", nonNull(named("NoteBodyUpdateMode")), defaultValue: .enumCase("REPLACE")),
        inputField("bodyHtml", string()),
        inputField("bodyText", string())
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "noteAccounts",
        type: nonNull(list(nonNull(named("NoteAccount")))),
        arguments: [],
        resolver: { _, context in
          .list(try context.notesReadService.accounts().map(noteAccountValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "noteFolders",
        type: nonNull(list(nonNull(named("NoteFolder")))),
        arguments: [argument("accountId", id())],
        resolver: { arguments, context in
          .list(try context.notesReadService.folders(
            accountId: try arguments["accountId"]?.notesStringValue()
          ).map(noteFolderValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "notes",
        type: nonNull(named("NoteConnection")),
        arguments: [argument("input", nonNull(named("NoteSearchInput")))],
        resolver: { arguments, context in
          try noteConnectionValue(
            context.notesReadService.notes(input: arguments.notesRequired("input").noteSearchInputValue())
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "note",
        type: named("Note"),
        arguments: [argument("noteId", idRequired())],
        resolver: { arguments, context in
          let note = try context.notesReadService.note(
            noteId: arguments.notesRequired("noteId").notesStringValue()
          )
          return note.map(noteValue) ?? .null
        }
      )
    ]
  }

  static var mutationFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "createNote",
        type: nonNull(named("Note")),
        arguments: [argument("input", nonNull(named("CreateNoteInput")))],
        resolver: { arguments, context in
          try noteValue(context.notesWriteService.createNote(arguments.notesRequired("input").createNoteInputValue()))
        }
      ),
      GraphQLFieldDefinition(
        name: "updateNoteBody",
        type: nonNull(named("Note")),
        arguments: [argument("input", nonNull(named("UpdateNoteBodyInput")))],
        resolver: { arguments, context in
          try noteValue(context.notesWriteService.updateNoteBody(
            arguments.notesRequired("input").updateNoteBodyInputValue()
          ))
        }
      ),
      GraphQLFieldDefinition(
        name: "deleteNote",
        type: nonNull(named("DeleteResult")),
        arguments: [argument("noteId", idRequired())],
        resolver: { arguments, context in
          try deleteResultValue(context.notesWriteService.deleteNote(
            noteId: arguments.notesRequired("noteId").notesStringValue()
          ))
        }
      ),
      GraphQLFieldDefinition(
        name: "moveNote",
        type: nonNull(named("Note")),
        arguments: [
          argument("noteId", idRequired()),
          argument("folderId", idRequired())
        ],
        resolver: { arguments, context in
          try noteValue(context.notesWriteService.moveNote(
            noteId: arguments.notesRequired("noteId").notesStringValue(),
            folderId: arguments.notesRequired("folderId").notesStringValue()
          ))
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

private func dateTimeRequired() -> GraphQLTypeReference {
  .nonNull(dateTime())
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func notesRequired(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  var notesNilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  func notesStringValue() throws -> String {
    switch self {
    case .string(let value), .enumCase(let value):
      return value
    default:
      throw notesInvalidValue("Expected string")
    }
  }

  func notesIntValue() throws -> Int {
    guard case .int(let value) = self else {
      throw notesInvalidValue("Expected int")
    }
    return value
  }

  func notesObjectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw notesInvalidValue("Expected input object")
    }
    return value
  }

  func notesOptionalString(_ key: String) throws -> String? {
    try notesObjectDictionary()[key]?.notesNilIfNull?.notesStringValue()
  }

  func notesOptionalInt(_ key: String) throws -> Int? {
    try notesObjectDictionary()[key]?.notesNilIfNull?.notesIntValue()
  }

  func notesOptionalDate(_ key: String) throws -> Date? {
    guard let value = try notesObjectDictionary()[key]?.notesNilIfNull else {
      return nil
    }
    return try EventKitDateTime.parse(value.notesStringValue())
  }

  func noteBodyUpdateModeValue() throws -> NoteBodyUpdateMode {
    let rawValue = try notesStringValue()
    guard let mode = NoteBodyUpdateMode(rawValue: rawValue) else {
      throw notesInvalidValue("Invalid NoteBodyUpdateMode \(rawValue)")
    }
    return mode
  }

  func noteSearchInputValue() throws -> NoteSearchInput {
    NoteSearchInput(
      accountId: try notesOptionalString("accountId"),
      folderId: try notesOptionalString("folderId"),
      query: try notesOptionalString("query"),
      modifiedAfter: try notesOptionalDate("modifiedAfter"),
      modifiedBefore: try notesOptionalDate("modifiedBefore"),
      first: try notesOptionalInt("first"),
      after: try notesOptionalString("after")
    )
  }

  func createNoteInputValue() throws -> CreateNoteInput {
    CreateNoteInput(
      accountId: try notesOptionalString("accountId"),
      folderId: try notesOptionalString("folderId"),
      title: try notesObjectDictionary().notesRequired("title").notesStringValue(),
      bodyHtml: try notesOptionalString("bodyHtml"),
      bodyText: try notesOptionalString("bodyText")
    )
  }

  func updateNoteBodyInputValue() throws -> UpdateNoteBodyInput {
    UpdateNoteBodyInput(
      noteId: try notesObjectDictionary().notesRequired("noteId").notesStringValue(),
      mode: try notesObjectDictionary()["mode"]?.notesNilIfNull?.noteBodyUpdateModeValue() ?? .replace,
      bodyHtml: try notesOptionalString("bodyHtml"),
      bodyText: try notesOptionalString("bodyText")
    )
  }

  func notesInvalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private func noteAccountValue(_ account: NoteAccount) -> GraphQLValue {
  .object([
    "id": .string(account.id),
    "name": .string(account.name),
    "isDefault": .bool(account.isDefault)
  ])
}

private func noteFolderValue(_ folder: NoteFolder) -> GraphQLValue {
  .object([
    "id": .string(folder.id),
    "accountId": .string(folder.accountId),
    "name": .string(folder.name),
    "parentFolderId": folder.parentFolderId.map(GraphQLValue.string) ?? .null,
    "noteCount": .int(folder.noteCount)
  ])
}

private func noteValue(_ note: Note) -> GraphQLValue {
  .object([
    "id": .string(note.id),
    "accountId": .string(note.accountId),
    "folderId": .string(note.folderId),
    "name": .string(note.name),
    "snippet": .string(note.snippet),
    "plaintext": note.plaintext.map(GraphQLValue.string) ?? .null,
    "bodyHtml": note.bodyHtml.map(GraphQLValue.string) ?? .null,
    "bodyFile": note.bodyFile.map(noteBodyFileValue) ?? .null,
    "isPasswordProtected": .bool(note.isPasswordProtected),
    "isShared": .bool(note.isShared),
    "creationDate": notesDateValue(note.creationDate),
    "modificationDate": notesDateValue(note.modificationDate),
    "attachments": .list(note.attachments.map(noteAttachmentValue))
  ])
}

private func noteBodyFileValue(_ file: NoteBodyFile) -> GraphQLValue {
  .object([
    "downloadKey": .string(file.downloadKey),
    "kind": .enumCase(file.kind.rawValue),
    "byteSize": .int(file.byteSize)
  ])
}

private func noteAttachmentValue(_ attachment: NoteAttachment) -> GraphQLValue {
  .object([
    "id": .string(attachment.id),
    "name": .string(attachment.name),
    "contentIdentifier": attachment.contentIdentifier.map(GraphQLValue.string) ?? .null,
    "downloadKey": attachment.downloadKey.map(GraphQLValue.string) ?? .null
  ])
}

private func noteConnectionValue(_ connection: NoteConnection) -> GraphQLValue {
  .object([
    "edges": .list(connection.edges.map(noteEdgeValue)),
    "pageInfo": notesPageInfoValue(connection.pageInfo),
    "totalCount": .int(connection.totalCount)
  ])
}

private func noteEdgeValue(_ edge: NoteEdge) -> GraphQLValue {
  .object([
    "cursor": .string(edge.cursor),
    "node": noteValue(edge.node)
  ])
}

private func notesPageInfoValue(_ pageInfo: PageInfo) -> GraphQLValue {
  .object([
    "hasNextPage": .bool(pageInfo.hasNextPage),
    "endCursor": pageInfo.endCursor.map(GraphQLValue.string) ?? .null
  ])
}

private func deleteResultValue(_ result: DeleteResult) -> GraphQLValue {
  .object(["success": .bool(result.success)])
}

private let notesGraphQLTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

private func notesDateValue(_ date: Date?) -> GraphQLValue {
  guard let date else {
    return .null
  }
  return .string(EventKitDateTime.format(date, timeZone: notesGraphQLTimeZone))
}
