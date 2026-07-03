import Foundation

enum GraphQLRuntime {
  static func execute(
    query: String,
    variables: [String: GraphQLValue],
    role: AppleGatewayRole,
    config: AppleGatewayConfig = .defaultValue,
    permissionsProvider: any PermissionsStatusProviding = LivePermissionsProvider(),
    calendarReadService: CalendarReadService = CalendarReminderServiceFactory.unavailableReadService(),
    calendarWriteService: CalendarWriteService = CalendarReminderServiceFactory.unavailableWriteService(),
    notesReadService: NotesReadService = NotesServiceFactory.unavailableReadService(),
    notesWriteService: NotesWriteService = NotesServiceFactory.unavailableWriteService(),
    mailReadService: MailReadService = MailServiceFactory.unavailableReadService(),
    notificationsService: any NotificationsProviding = NotificationsServiceFactory.unavailableService(),
    clockAlarmsService: any ClockAlarmsProviding = ClockAlarmsServiceFactory.unavailableService(),
    schema: GraphQLSchemaRegistry? = nil,
    pretty: Bool = false
  ) -> Data {
    executeResponse(
      query: query,
      variables: variables,
      role: role,
      config: config,
      permissionsProvider: permissionsProvider,
      calendarReadService: calendarReadService,
      calendarWriteService: calendarWriteService,
      notesReadService: notesReadService,
      notesWriteService: notesWriteService,
      mailReadService: mailReadService,
      notificationsService: notificationsService,
      clockAlarmsService: clockAlarmsService,
      schema: schema,
      pretty: pretty
    ).data
  }

  static func executeResponse(
    query: String,
    variables: [String: GraphQLValue],
    role: AppleGatewayRole,
    config: AppleGatewayConfig = .defaultValue,
    permissionsProvider: any PermissionsStatusProviding = LivePermissionsProvider(),
    calendarReadService: CalendarReadService = CalendarReminderServiceFactory.unavailableReadService(),
    calendarWriteService: CalendarWriteService = CalendarReminderServiceFactory.unavailableWriteService(),
    notesReadService: NotesReadService = NotesServiceFactory.unavailableReadService(),
    notesWriteService: NotesWriteService = NotesServiceFactory.unavailableWriteService(),
    mailReadService: MailReadService = MailServiceFactory.unavailableReadService(),
    notificationsService: any NotificationsProviding = NotificationsServiceFactory.unavailableService(),
    clockAlarmsService: any ClockAlarmsProviding = ClockAlarmsServiceFactory.unavailableService(),
    schema suppliedSchema: GraphQLSchemaRegistry? = nil,
    pretty: Bool = false
  ) -> AppleGatewayJSONResponse {
    do {
      var lexer = GraphQLLexer(query)
      var parser = GraphQLParser(tokens: try lexer.lex())
      let document = try parser.parseDocument()
      let schema = suppliedSchema ?? GraphQLSchemaRegistry.bootstrap(role: role)
      try GraphQLValidator(schema: schema).validate(document)
      let result = try GraphQLExecutor(
        schema: schema,
        context: GraphQLExecutionContext(
          config: config,
          role: role,
          permissionsProvider: permissionsProvider,
          calendarReadService: calendarReadService,
          calendarWriteService: calendarWriteService,
          notesReadService: notesReadService,
          notesWriteService: notesWriteService,
          mailReadService: mailReadService,
          notificationsService: notificationsService,
          clockAlarmsService: clockAlarmsService
        )
      ).execute(document: document, variables: variables)
      return encode(data: Optional(result.data), errors: result.errors, pretty: pretty)
    } catch let runtimeError as GraphQLRuntimeError {
      return encode(
        data: Optional<GraphQLValue>.none,
        errors: [runtimeError.appleGatewayError()],
        pretty: pretty
      )
    } catch let appleGatewayError as AppleGatewayError {
      return encode(
        data: Optional<GraphQLValue>.none,
        errors: [appleGatewayError],
        pretty: pretty
      )
    } catch {
      let appleGatewayError = AppleGatewayError(
        code: .unexpectedError,
        message: String(describing: error)
      )
      return encode(data: Optional<GraphQLValue>.none, errors: [appleGatewayError], pretty: pretty)
    }
  }

  static func schema(role: AppleGatewayRole) -> String {
    GraphQLSDLPrinter(schema: .bootstrap(role: role)).printSchema()
  }

  private static func encode(
    data: GraphQLValue?,
    errors: [AppleGatewayError],
    pretty: Bool
  ) -> AppleGatewayJSONResponse {
    do {
      return try AppleGatewayJSONEnvelope.response(data: data, errors: errors, pretty: pretty)
    } catch {
      let fallback = Data(
        #"{"data":null,"errors":[{"message":"Failed to encode response","extensions":{"code":"UNEXPECTED_ERROR","exitCode":1}}],"extensions":{"requestId":"unavailable"}}"#.utf8
      )
      return AppleGatewayJSONResponse(data: fallback, exitCode: 1)
    }
  }
}

extension GraphQLValue: Encodable {
  func encode(to encoder: Encoder) throws {
    switch self {
    case .int(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .float(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .string(let value), .enumCase(let value), .variable(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case .list(let values):
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }
    case .object(let values):
      var container = encoder.container(keyedBy: DynamicCodingKey.self)
      for key in values.keys.sorted() {
        try container.encode(values[key], forKey: DynamicCodingKey(stringValue: key))
      }
    }
  }
}

private struct DynamicCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

extension GraphQLRuntimeError {
  func appleGatewayError(path: [String]? = nil) -> AppleGatewayError {
    AppleGatewayError(
      code: code,
      message: message,
      locations: location.map {
        [AppleGatewayErrorLocation(line: $0.line, column: $0.column)]
      },
      path: path
    )
  }
}
