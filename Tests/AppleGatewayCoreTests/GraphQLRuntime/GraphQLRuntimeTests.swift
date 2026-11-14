import Foundation
import Testing
@testable import AppleGatewayCore

@Test func lexerAndParserReportErrorPositions() throws {
  do {
    _ = try parseGraphQL("{\n  permissions { status @include }\n}")
    Issue.record("Expected directive rejection")
  } catch let error as GraphQLRuntimeError {
    #expect(error.code == .graphQLParseError)
    #expect(error.location?.line == 2)
    #expect((error.location?.column ?? 0) > 0)
  }
}

@Test func runtimeRejectsUnknownField() throws {
  let envelope = try executeGraphQL("{ missing { status } }")
  let error = try #require(envelope.errors.first)
  #expect(error.code == "GRAPHQL_VALIDATION_ERROR")
  #expect(error.exitCode == 5)
  #expect(error.locations?.first?["line"] as? Int == 1)
  #expect(error.message.contains("Unknown field missing"))
}

@Test func validatorRejectsMissingRequiredArgument() throws {
  let document = try parseGraphQL("{ echo(states: [ALLOWED], filter: { enabled: true }) { status } }")
  do {
    try GraphQLValidator(schema: makeTestSchema()).validate(document)
    Issue.record("Expected missing required argument")
  } catch let error as GraphQLRuntimeError {
    #expect(error.message.contains("Missing required argument state"))
  }
}

@Test func validatorAcceptsEnumListAndInputCoercion() throws {
  let document = try parseGraphQL(
    "{ echo(state: ALLOWED, states: [ALLOWED, DENIED], filter: { enabled: true }) { status } }"
  )
  try GraphQLValidator(schema: makeTestSchema()).validate(document)
}

@Test func validatorRejectsEnumListAndInputCoercionFailures() throws {
  let document = try parseGraphQL(
    "{ echo(state: UNKNOWN, states: [ALLOWED], filter: { enabled: true }) { status } }"
  )
  do {
    try GraphQLValidator(schema: makeTestSchema()).validate(document)
    Issue.record("Expected enum coercion failure")
  } catch let error as GraphQLRuntimeError {
    #expect(error.message.contains("Expected enum PermissionState"))
  }

  let missingInput = try parseGraphQL(
    "{ echo(state: ALLOWED, states: [ALLOWED], filter: { name: \"x\" }) { status } }"
  )
  do {
    try GraphQLValidator(schema: makeTestSchema()).validate(missingInput)
    Issue.record("Expected input coercion failure")
  } catch let error as GraphQLRuntimeError {
    #expect(error.message.contains("Missing required input field enabled"))
  }
}

@Test func validatorRejectsVariableTypeMismatch() throws {
  let document = try parseGraphQL(
    "query($state: String!) { echo(state: $state, states: [ALLOWED], filter: { enabled: true }) { status } }"
  )
  do {
    try GraphQLValidator(schema: makeTestSchema()).validate(document)
    Issue.record("Expected variable mismatch")
  } catch let error as GraphQLRuntimeError {
    #expect(error.message.contains("type does not match"))
  }
}

@Test func variableResolverCoercesJSONEnumListAndInputValues() throws {
  let document = try parseGraphQL(
    """
    query($state: PermissionState!, $states: [PermissionState!]!, $filter: PermissionFilter!) {
      echo(state: $state, states: $states, filter: $filter) { status }
    }
    """
  )
  let schema = makeTestSchema()
  try GraphQLValidator(schema: schema).validate(document)
  let variables: [String: GraphQLValue] = [
    "state": .string("ALLOWED"),
    "states": .list([.string("ALLOWED"), .string("DENIED")]),
    "filter": .object(["enabled": .bool(true), "name": .string("calendar")])
  ]
  let coerced = try GraphQLVariableResolver(schema: schema).coerceJSONVariables(
    variables,
    definitions: document.operation.variableDefinitions
  )
  #expect(coerced["state"] == .enumCase("ALLOWED"))
}

@Test func jsonObjectConversionDistinguishesBooleansFromZeroAndOne() throws {
  let data = Data(#"{"enabled":true,"disabled":false,"zero":0,"one":1}"#.utf8)
  let jsonObject = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  let converted = try jsonObject.mapValues(GraphQLValue.fromJSONObject)

  #expect(converted["enabled"] == .bool(true))
  #expect(converted["disabled"] == .bool(false))
  #expect(converted["zero"] == .int(0))
  #expect(converted["one"] == .int(1))

  let document = try parseGraphQL(
    """
    query($enabled: Boolean!, $disabled: Boolean!, $zero: Int!, $one: Int!) {
      classify(enabled: $enabled, disabled: $disabled, zero: $zero, one: $one)
    }
    """
  )
  let schema = makeScalarClassificationSchema()
  try GraphQLValidator(schema: schema).validate(document)
  let coerced = try GraphQLVariableResolver(schema: schema).coerceJSONVariables(
    converted,
    definitions: document.operation.variableDefinitions
  )

  #expect(coerced == converted)
}

@Test func createEventRecurrenceVariablesMatchInlineLiteral() throws {
  let variableDocument = try parseGraphQL(
    """
    mutation($input: CreateEventInput!) {
      createEvent(input: $input) { id }
    }
    """
  )
  let inlineDocument = try parseGraphQL(
    """
    mutation {
      createEvent(input: {
        title: "Planning"
        startDate: "2026-07-03T09:00:00Z"
        endDate: "2026-07-03T10:00:00Z"
        recurrenceRules: [{
          frequency: WEEKLY
          interval: 1
          daysOfWeek: [3, 4]
          endDate: "2026-12-31T00:00:00Z"
        }]
      }) { id }
    }
    """
  )
  let schema = GraphQLSchemaRegistry.bootstrap(role: .full)
  try GraphQLValidator(schema: schema).validate(variableDocument)
  try GraphQLValidator(schema: schema).validate(inlineDocument)
  let resolver = GraphQLVariableResolver(schema: schema)
  let jsonData = Data(
    """
    {
      "input": {
        "title": "Planning",
        "startDate": "2026-07-03T09:00:00Z",
        "endDate": "2026-07-03T10:00:00Z",
        "recurrenceRules": [{
          "frequency": "WEEKLY",
          "interval": 1,
          "daysOfWeek": [3, 4],
          "endDate": "2026-12-31T00:00:00Z"
        }]
      }
    }
    """.utf8
  )
  let jsonVariables = try #require(
    JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
  )
  let variables = try jsonVariables.mapValues(GraphQLValue.fromJSONObject)
  let coercedVariables = try resolver.coerceJSONVariables(
    variables,
    definitions: variableDocument.operation.variableDefinitions
  )
  let definition = try #require(schema.field(named: "createEvent", on: "Mutation"))
  let variableField = try #require(variableDocument.operation.selectionSet.first)
  let inlineField = try #require(inlineDocument.operation.selectionSet.first)
  let variableArguments = try resolver.resolveArguments(
    field: variableField,
    definition: definition,
    variables: coercedVariables,
    variableDefinitions: variableDocument.operation.variableDefinitions
  )
  let inlineArguments = try resolver.resolveArguments(
    field: inlineField,
    definition: definition,
    variables: [:],
    variableDefinitions: inlineDocument.operation.variableDefinitions
  )
  #expect(variableArguments["input"] == inlineArguments["input"])

  let variableFake = try GraphQLCalendarReminderFake()
  let inlineFake = try GraphQLCalendarReminderFake()
  let variableEnvelope = try executeGraphQL(
    """
    mutation($input: CreateEventInput!) {
      createEvent(input: $input) { id }
    }
    """,
    variables: variables,
    calendarReadService: CalendarReadService(
      calendarProvider: variableFake,
      remindersProvider: variableFake
    ),
    calendarWriteService: CalendarWriteService(
      calendarProvider: variableFake,
      calendarWriter: variableFake,
      remindersProvider: variableFake,
      remindersWriter: variableFake
    )
  )
  let inlineEnvelope = try executeGraphQL(
    """
    mutation {
      createEvent(input: {
        title: "Planning"
        startDate: "2026-07-03T09:00:00Z"
        endDate: "2026-07-03T10:00:00Z"
        recurrenceRules: [{
          frequency: WEEKLY
          interval: 1
          daysOfWeek: [3, 4]
          endDate: "2026-12-31T00:00:00Z"
        }]
      }) { id }
    }
    """,
    calendarReadService: CalendarReadService(
      calendarProvider: inlineFake,
      remindersProvider: inlineFake
    ),
    calendarWriteService: CalendarWriteService(
      calendarProvider: inlineFake,
      calendarWriter: inlineFake,
      remindersProvider: inlineFake,
      remindersWriter: inlineFake
    )
  )
  #expect(variableEnvelope.errors.isEmpty)
  #expect(inlineEnvelope.errors.isEmpty)
  let variableRecurrence = try #require(variableFake.lastCreatedEvent?.recurrenceRules)
  let inlineRecurrence = try #require(inlineFake.lastCreatedEvent?.recurrenceRules)
  let rule = try #require(variableRecurrence.first)
  let expectedEndDate = try EventKitDateTime.parse("2026-12-31T00:00:00Z")

  #expect(variableRecurrence == inlineRecurrence)
  #expect(rule.frequency == .weekly)
  #expect(rule.interval == 1)
  #expect(rule.daysOfWeek == [3, 4])
  #expect(rule.endDate == expectedEndDate)
}

@Test func parserRejectsFragmentsDirectivesAndMultipleOperations() throws {
  for query in [
    "{ permissions { ...Fields } }",
    "{ permissions @skip { calendars } }",
    "{ permissions { calendars } } query Other { permissions { calendars } }"
  ] {
    do {
      _ = try parseGraphQL(query)
      Issue.record("Expected query to be rejected: \(query)")
  } catch let error as GraphQLRuntimeError {
      #expect(error.code == .graphQLParseError)
    }
  }
}

@Test func readerRejectsMutationWithoutScanningStringsOrComments() throws {
  let mutationEnvelope = try executeGraphQL(
    "mutation { permissions { calendars } }",
    role: .reader
  )
  #expect(mutationEnvelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(mutationEnvelope.errors.first?.exitCode == 5)

  let commentEnvelope = try executeGraphQL(
    "# mutation { permissions { calendars } }\n{ permissions { calendars } }",
    role: .reader
  )
  #expect(commentEnvelope.errors.isEmpty)
  let permissions = try #require(commentEnvelope.data?["permissions"] as? [String: Any])
  #expect(permissions["calendars"] as? String == "UNKNOWN")
}

@Test func projectionHonorsAliasesAndNestedSelections() throws {
  let envelope = try executeGraphQL(
    "{ first: permissions { calendars reminders } }"
  )
  #expect(envelope.errors.isEmpty)
  let permissions = try #require(envelope.data?["first"] as? [String: Any])
  #expect(permissions["calendars"] as? String == "UNKNOWN")
  #expect(permissions["reminders"] as? String == "UNKNOWN")
}

@Test func runtimeReturnsAllPermissionsStatusFields() throws {
  let envelope = try executeGraphQL(
    """
    {
      permissions {
        calendars
        reminders
        notesAutomation
        mailFullDiskAccess
        notificationsHelper
        notificationDbFullDiskAccess
        clockAutomation
      }
    }
    """,
    permissionsProvider: FullGraphQLPermissionsProvider()
  )
  let permissions = try #require(envelope.data?["permissions"] as? [String: Any])

  #expect(permissions["calendars"] as? String == "GRANTED")
  #expect(permissions["reminders"] as? String == "DENIED")
  #expect(permissions["notesAutomation"] as? String == "NOT_DETERMINED")
  #expect(permissions["mailFullDiskAccess"] as? String == "UNKNOWN")
  #expect(permissions["notificationsHelper"] as? String == "UNKNOWN")
  #expect(permissions["notificationDbFullDiskAccess"] as? String == "UNKNOWN")
  #expect(permissions["clockAutomation"] as? String == "NOT_REQUIRED")
}

@Test func runtimePreservesPartialDataAndUsesFirstErrorExit() throws {
  let response = GraphQLRuntime.executeResponse(
    query: "{ calendars reminders files }",
    variables: [:],
    role: .full,
    schema: makePartialFailureSchema()
  )
  let object = try #require(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
  let data = try #require(object["data"] as? [String: Any])
  let errors = try #require(object["errors"] as? [[String: Any]])
  let firstExtensions = try #require(errors.first?["extensions"] as? [String: Any])
  let secondExtensions = try #require(errors.dropFirst().first?["extensions"] as? [String: Any])

  #expect(response.exitCode == 4)
  #expect(data["calendars"] is NSNull)
  #expect(data["reminders"] as? String == "Inbox")
  #expect(data["files"] is NSNull)
  #expect(errors.first?["path"] as? [String] == ["calendars"])
  #expect(errors.dropFirst().first?["path"] as? [String] == ["files"])
  #expect(firstExtensions["code"] as? String == "PERMISSION_DENIED")
  #expect(firstExtensions["exitCode"] as? Int == 4)
  #expect(secondExtensions["code"] as? String == "FILE_OPERATION_FAILED")
  #expect(secondExtensions["exitCode"] as? Int == 6)
}

@Test func schemaPrintReaderOmitsMutation() {
  let schema = GraphQLRuntime.schema(role: .reader)
  #expect(schema.contains("type Query {"))
  #expect(schema.contains("  calendars(entityType: CalendarEntityType): [Calendar!]!"))
  #expect(schema.contains("  events(input: EventSearchInput!): EventConnection!"))
  #expect(schema.contains("  reminders(input: ReminderSearchInput!): ReminderConnection!"))
  #expect(schema.contains("scalar DateTime"))
  #expect(!schema.contains("type Mutation"))
  #expect(!schema.contains("createEvent"))
}

@Test func calendarRemindersReadSchemaUsesInjectedServices() throws {
  let fake = try GraphQLCalendarReminderFake()
  let envelope = try executeGraphQL(
    """
    {
      calendars(entityType: EVENT) { id title entityType }
      events(input: {
        startDate: "2026-07-01T00:00:00Z",
        endDate: "2026-07-02T00:00:00Z"
      }) {
        totalCount
        edges { node { id title alarms { relativeOffsetSeconds } } }
      }
      reminderLists { id title }
      reminders(input: { status: INCOMPLETE }) {
        totalCount
        edges { node { id title isCompleted } }
      }
    }
    """,
    calendarReadService: CalendarReadService(calendarProvider: fake, remindersProvider: fake),
    calendarWriteService: CalendarWriteService(
      calendarProvider: fake,
      calendarWriter: fake,
      remindersProvider: fake,
      remindersWriter: fake
    )
  )

  #expect(envelope.errors.isEmpty)
  let calendars = try #require(envelope.data?["calendars"] as? [[String: Any]])
  let events = try #require(envelope.data?["events"] as? [String: Any])
  let reminders = try #require(envelope.data?["reminders"] as? [String: Any])

  #expect(calendars.first?["id"] as? String == "cal-1")
  #expect(events["totalCount"] as? Int == 1)
  #expect(reminders["totalCount"] as? Int == 1)
}

@Test func calendarRemindersMutationsUseInjectedWriteServices() throws {
  let fake = try GraphQLCalendarReminderFake()
  let readService = CalendarReadService(calendarProvider: fake, remindersProvider: fake)
  let writeService = CalendarWriteService(
    calendarProvider: fake,
    calendarWriter: fake,
    remindersProvider: fake,
    remindersWriter: fake
  )

  let createEnvelope = try executeGraphQL(
    """
    mutation {
      createEvent(input: {
        title: "Planning",
        startDate: "2026-07-01T09:00:00Z",
        endDate: "2026-07-01T10:00:00Z",
        alarms: [{ relativeOffsetSeconds: -600 }]
      }) {
        id
        title
        alarms { relativeOffsetSeconds }
      }
    }
    """,
    calendarReadService: readService,
    calendarWriteService: writeService
  )
  #expect(createEnvelope.errors.isEmpty)
  let createEvent = try #require(createEnvelope.data?["createEvent"] as? [String: Any])
  #expect(createEvent["id"] as? String == "event-2")

  let updateEnvelope = try executeGraphQL(
    """
    mutation {
      updateEvent(input: {
        eventId: "event-1",
        span: FUTURE_EVENTS,
        title: "Future planning"
      }) { id title }
    }
    """,
    calendarReadService: readService,
    calendarWriteService: writeService
  )
  let updateEvent = try #require(updateEnvelope.data?["updateEvent"] as? [String: Any])
  #expect(updateEnvelope.errors.isEmpty)
  #expect(updateEvent["title"] as? String == "Future planning")
  #expect(fake.lastEventSaveRequest?.span == .futureEvents)

  let completedEnvelope = try executeGraphQL(
    """
    mutation {
      setReminderCompleted(reminderId: "reminder-1", completed: true) {
        id
        isCompleted
      }
    }
    """,
    calendarReadService: readService,
    calendarWriteService: writeService
  )
  let reminder = try #require(completedEnvelope.data?["setReminderCompleted"] as? [String: Any])
  #expect(completedEnvelope.errors.isEmpty)
  #expect(reminder["isCompleted"] as? Bool == true)

  let readerEnvelope = try executeGraphQL(
    #"mutation { createReminder(input: { title: "Blocked" }) { id } }"#,
    role: .reader,
    calendarReadService: readService,
    calendarWriteService: writeService
  )
  #expect(readerEnvelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
}

private func makePartialFailureSchema() -> GraphQLSchemaRegistry {
  GraphQLSchemaRegistry(
    modules: [
      GraphQLSchemaModule(
        types: [
          GraphQLNamedTypeDefinition(name: "String", kind: .scalar)
        ],
        queryFields: [
          GraphQLFieldDefinition(
            name: "calendars",
            type: .named("String"),
            arguments: [],
            resolver: { _, _ in
              throw AppleGatewayError(
                code: .permissionDenied,
                message: "Calendar access denied for this process",
                details: ["domain": "calendar"]
              )
            }
          ),
          GraphQLFieldDefinition(
            name: "reminders",
            type: .named("String"),
            arguments: [],
            resolver: { _, _ in .string("Inbox") }
          ),
          GraphQLFieldDefinition(
            name: "files",
            type: .named("String"),
            arguments: [],
            resolver: { _, _ in
              throw AppleGatewayError(
                code: .fileOperationFailed,
                message: "Could not materialize file",
                details: ["path": "/tmp/out"]
              )
            }
          )
        ],
        mutationFields: []
      )
    ],
    role: .full
  )
}

private func makeTestSchema() -> GraphQLSchemaRegistry {
  GraphQLSchemaRegistry(
    modules: [
      GraphQLSchemaModule(
        types: [
          GraphQLNamedTypeDefinition(name: "String", kind: .scalar),
          GraphQLNamedTypeDefinition(name: "Boolean", kind: .scalar),
          GraphQLNamedTypeDefinition(name: "PermissionState", kind: .enumType(["ALLOWED", "DENIED"])),
          GraphQLNamedTypeDefinition(
            name: "PermissionFilter",
            kind: .inputObject([
              GraphQLInputFieldDefinition(
                name: "enabled",
                type: .nonNull(.named("Boolean")),
                defaultValue: nil
              ),
              GraphQLInputFieldDefinition(name: "name", type: .named("String"), defaultValue: nil)
            ])
          ),
          GraphQLNamedTypeDefinition(
            name: "EchoStatus",
            kind: .object([
              GraphQLFieldDefinition(name: "status", type: .nonNull(.named("String")), arguments: [])
            ])
          )
        ],
        queryFields: [
          GraphQLFieldDefinition(
            name: "echo",
            type: .nonNull(.named("EchoStatus")),
            arguments: [
              GraphQLArgumentDefinition(
                name: "state",
                type: .nonNull(.named("PermissionState")),
                defaultValue: nil
              ),
              GraphQLArgumentDefinition(
                name: "states",
                type: .nonNull(.list(.nonNull(.named("PermissionState")))),
                defaultValue: nil
              ),
              GraphQLArgumentDefinition(
                name: "filter",
                type: .nonNull(.named("PermissionFilter")),
                defaultValue: nil
              )
            ],
            resolver: nil
          )
        ],
        mutationFields: []
      )
    ],
    role: .full
  )
}

private func makeScalarClassificationSchema() -> GraphQLSchemaRegistry {
  GraphQLSchemaRegistry(
    modules: [
      GraphQLSchemaModule(
        types: [
          GraphQLNamedTypeDefinition(name: "Boolean", kind: .scalar),
          GraphQLNamedTypeDefinition(name: "Int", kind: .scalar)
        ],
        queryFields: [
          GraphQLFieldDefinition(
            name: "classify",
            type: .named("Boolean"),
            arguments: [
              GraphQLArgumentDefinition(
                name: "enabled",
                type: .nonNull(.named("Boolean")),
                defaultValue: nil
              ),
              GraphQLArgumentDefinition(
                name: "disabled",
                type: .nonNull(.named("Boolean")),
                defaultValue: nil
              ),
              GraphQLArgumentDefinition(name: "zero", type: .nonNull(.named("Int")), defaultValue: nil),
              GraphQLArgumentDefinition(name: "one", type: .nonNull(.named("Int")), defaultValue: nil)
            ],
            resolver: nil
          )
        ],
        mutationFields: []
      )
    ],
    role: .full
  )
}

private func parseGraphQL(_ query: String) throws -> GraphQLDocument {
  var lexer = GraphQLLexer(query)
  var parser = GraphQLParser(tokens: try lexer.lex())
  return try parser.parseDocument()
}

private func executeGraphQL(
  _ query: String,
  variables: [String: GraphQLValue] = [:],
  role: AppleGatewayRole = .full,
  permissionsProvider: any PermissionsStatusProviding = GraphQLTestPermissionsProvider(),
  calendarReadService: CalendarReadService = CalendarReminderServiceFactory.unavailableReadService(),
  calendarWriteService: CalendarWriteService = CalendarReminderServiceFactory.unavailableWriteService()
) throws -> DecodedEnvelope {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: variables,
    role: role,
    permissionsProvider: permissionsProvider,
    calendarReadService: calendarReadService,
    calendarWriteService: calendarWriteService
  )
  let object = try JSONSerialization.jsonObject(with: data)
  let dictionary = try #require(object as? [String: Any])
  let dataObject = dictionary["data"] as? [String: Any]
  let errorObjects = dictionary["errors"] as? [[String: Any]] ?? []
  let extensions = dictionary["extensions"] as? [String: Any]
  return DecodedEnvelope(
    data: dataObject,
    errors: errorObjects.map {
      let errorExtensions = $0["extensions"] as? [String: Any]
      return DecodedError(
        message: $0["message"] as? String ?? "",
        code: errorExtensions?["code"] as? String ?? "",
        exitCode: errorExtensions?["exitCode"] as? Int ?? 0,
        locations: $0["locations"] as? [[String: Any]],
        path: $0["path"] as? [String]
      )
    },
    requestId: extensions?["requestId"] as? String
  )
}

private struct GraphQLTestPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .unknown),
      reminders: PermissionFieldStatus(state: .unknown),
      notesAutomation: PermissionFieldStatus(state: .unknown),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .unknown)
    )
  }
}

private struct FullGraphQLPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted),
      reminders: PermissionFieldStatus(state: .denied),
      notesAutomation: PermissionFieldStatus(state: .notDetermined),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .notRequired)
    )
  }
}

private final class GraphQLCalendarReminderFake: CalendarProviding, CalendarWriting, RemindersProviding, RemindersWriting, @unchecked Sendable {
  private var calendarsStore: [GatewayCalendar]
  private var eventsStore: [CalendarEvent]
  private var remindersStore: [Reminder]
  var lastEventSaveRequest: CalendarEventSaveRequest?
  var lastCreatedEvent: CalendarEvent?

  init() throws {
    let startDate = try EventKitDateTime.parse("2026-07-01T09:00:00Z")
    let endDate = try EventKitDateTime.parse("2026-07-01T10:00:00Z")
    calendarsStore = [
      GatewayCalendar(
        id: "cal-1",
        title: "Work",
        entityType: .event,
        sourceTitle: "iCloud",
        sourceType: "CalDAV",
        allowsModifications: true,
        isSubscribed: false,
        isDefault: true
      ),
      GatewayCalendar(
        id: "list-1",
        title: "Inbox",
        entityType: .reminder,
        sourceTitle: "iCloud",
        sourceType: "CalDAV",
        allowsModifications: true,
        isSubscribed: false,
        isDefault: true
      )
    ]
    eventsStore = [
      CalendarEvent(
        id: "event-1",
        calendarId: "cal-1",
        title: "Planning",
        startDate: startDate,
        endDate: endDate,
        alarms: [Alarm(relativeOffsetSeconds: -300)]
      )
    ]
    remindersStore = [
      Reminder(id: "reminder-1", listId: "list-1", title: "Submit report")
    ]
  }

  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    calendarsStore.filter { calendar in
      guard let entityType else {
        return calendar.entityType == .event
      }
      return calendar.entityType == entityType
    }
  }

  func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    eventsStore
  }

  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    eventsStore.first { $0.id == eventId }
  }

  func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    let calendar = GatewayCalendar(
      id: "cal-\(calendarsStore.count + 1)",
      title: input.title,
      entityType: .event,
      sourceTitle: input.sourceTitle ?? "iCloud",
      sourceType: "CalDAV",
      colorHex: input.colorHex,
      allowsModifications: true,
      isSubscribed: false,
      isDefault: false
    )
    calendarsStore.append(calendar)
    return calendar
  }

  func deleteCalendar(calendarId: String) throws -> DeleteResult {
    calendarsStore.removeAll { $0.id == calendarId }
    return DeleteResult(success: true)
  }

  func createEvent(_ event: CalendarEvent) throws -> CalendarEvent {
    lastCreatedEvent = event
    var created = event
    created.id = "event-\(eventsStore.count + 1)"
    eventsStore.append(created)
    return created
  }

  func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent {
    lastEventSaveRequest = request
    if let index = eventsStore.firstIndex(where: { $0.id == request.event.id }) {
      eventsStore[index] = request.event
    }
    return request.event
  }

  func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult {
    eventsStore.removeAll { $0.id == request.eventId }
    return DeleteResult(success: true)
  }

  func reminderLists() throws -> [GatewayCalendar] {
    calendarsStore.filter { $0.entityType == .reminder }
  }

  func reminders() throws -> [Reminder] {
    remindersStore
  }

  func reminder(reminderId: String) throws -> Reminder? {
    remindersStore.first { $0.id == reminderId }
  }

  func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    let list = GatewayCalendar(
      id: "list-\(calendarsStore.count + 1)",
      title: input.title,
      entityType: .reminder,
      sourceTitle: input.sourceTitle ?? "iCloud",
      sourceType: "CalDAV",
      colorHex: input.colorHex,
      allowsModifications: true,
      isSubscribed: false,
      isDefault: false
    )
    calendarsStore.append(list)
    return list
  }

  func createReminder(_ reminder: Reminder) throws -> Reminder {
    var created = reminder
    created.id = "reminder-\(remindersStore.count + 1)"
    remindersStore.append(created)
    return created
  }

  func updateReminder(_ reminder: Reminder) throws -> Reminder {
    if let index = remindersStore.firstIndex(where: { $0.id == reminder.id }) {
      remindersStore[index] = reminder
    }
    return reminder
  }

  func deleteReminder(reminderId: String) throws -> DeleteResult {
    remindersStore.removeAll { $0.id == reminderId }
    return DeleteResult(success: true)
  }
}

private struct DecodedEnvelope {
  var data: [String: Any]?
  var errors: [DecodedError]
  var requestId: String?
}

private struct DecodedError {
  var message: String
  var code: String
  var exitCode: Int
  var locations: [[String: Any]]?
  var path: [String]?
}
