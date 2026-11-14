import Foundation

extension GraphQLSchemaModule {
  static var calendarReminders: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: CalendarRemindersSchema.types,
      queryFields: CalendarRemindersSchema.queryFields,
      mutationFields: CalendarRemindersSchema.mutationFields
    )
  }
}

private enum CalendarRemindersSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      scalar("ID"),
      scalar("DateTime"),
      enumType("CalendarEntityType", ["EVENT", "REMINDER"]),
      enumType("EventStatus", ["NONE", "CONFIRMED", "TENTATIVE", "CANCELED"]),
      enumType("EventAvailability", ["NOT_SUPPORTED", "BUSY", "FREE", "TENTATIVE", "UNAVAILABLE"]),
      enumType("AttendeeStatus", [
        "UNKNOWN",
        "PENDING",
        "ACCEPTED",
        "DECLINED",
        "TENTATIVE",
        "DELEGATED",
        "COMPLETED",
        "IN_PROCESS"
      ]),
      enumType("RecurrenceFrequency", ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]),
      enumType("RecurrenceSpan", ["THIS_EVENT", "FUTURE_EVENTS"]),
      enumType("ReminderStatusFilter", ["ALL", "INCOMPLETE", "COMPLETED"]),
      object("Calendar", fields: [
        field("id", .idRequired),
        field("title", .stringRequired),
        field("entityType", .nonNull(.named("CalendarEntityType"))),
        field("sourceTitle", .stringRequired),
        field("sourceType", .stringRequired),
        field("colorHex", .string),
        field("allowsModifications", .boolRequired),
        field("isSubscribed", .boolRequired),
        field("isDefault", .boolRequired)
      ]),
      object("EventParticipant", fields: [
        field("name", .string),
        field("email", .string),
        field("isCurrentUser", .boolRequired),
        field("status", .nonNull(.named("AttendeeStatus")))
      ]),
      object("Alarm", fields: [
        field("relativeOffsetSeconds", .int),
        field("absoluteDate", .dateTime)
      ]),
      object("RecurrenceRule", fields: [
        field("frequency", .nonNull(.named("RecurrenceFrequency"))),
        field("interval", .intRequired),
        field("daysOfWeek", .intListRequired),
        field("daysOfMonth", .intListRequired),
        field("monthsOfYear", .intListRequired),
        field("weeksOfYear", .intListRequired),
        field("daysOfYear", .intListRequired),
        field("setPositions", .intListRequired),
        field("endDate", .dateTime),
        field("occurrenceCount", .int)
      ]),
      object("CalendarEvent", fields: [
        field("id", .idRequired),
        field("calendarId", .idRequired),
        field("title", .stringRequired),
        field("notes", .string),
        field("location", .string),
        field("url", .string),
        field("isAllDay", .boolRequired),
        field("startDate", .dateTimeRequired),
        field("endDate", .dateTimeRequired),
        field("timeZone", .string),
        field("status", .nonNull(.named("EventStatus"))),
        field("availability", .nonNull(.named("EventAvailability"))),
        field("organizer", .named("EventParticipant")),
        field("attendees", .nonNull(.list(.nonNull(.named("EventParticipant"))))),
        field("alarms", .nonNull(.list(.nonNull(.named("Alarm"))))),
        field("recurrenceRules", .nonNull(.list(.nonNull(.named("RecurrenceRule"))))),
        field("isRecurring", .boolRequired),
        field("occurrenceDate", .dateTime),
        field("isDetached", .boolRequired),
        field("creationDate", .dateTime),
        field("lastModifiedDate", .dateTime)
      ]),
      object("Reminder", fields: [
        field("id", .idRequired),
        field("listId", .idRequired),
        field("title", .stringRequired),
        field("notes", .string),
        field("url", .string),
        field("priority", .intRequired),
        field("isCompleted", .boolRequired),
        field("completionDate", .dateTime),
        field("startDate", .dateTime),
        field("dueDate", .dateTime),
        field("dueDateHasTime", .boolRequired),
        field("alarms", .nonNull(.list(.nonNull(.named("Alarm"))))),
        field("recurrenceRules", .nonNull(.list(.nonNull(.named("RecurrenceRule"))))),
        field("creationDate", .dateTime),
        field("lastModifiedDate", .dateTime)
      ]),
      object("PageInfo", fields: [
        field("hasNextPage", .boolRequired),
        field("endCursor", .string)
      ]),
      object("EventEdge", fields: [
        field("cursor", .stringRequired),
        field("node", .nonNull(.named("CalendarEvent")))
      ]),
      object("EventConnection", fields: [
        field("edges", .nonNull(.list(.nonNull(.named("EventEdge"))))),
        field("pageInfo", .nonNull(.named("PageInfo"))),
        field("totalCount", .intRequired)
      ]),
      object("ReminderEdge", fields: [
        field("cursor", .stringRequired),
        field("node", .nonNull(.named("Reminder")))
      ]),
      object("ReminderConnection", fields: [
        field("edges", .nonNull(.list(.nonNull(.named("ReminderEdge"))))),
        field("pageInfo", .nonNull(.named("PageInfo"))),
        field("totalCount", .intRequired)
      ]),
      object("DeleteResult", fields: [
        field("success", .boolRequired)
      ]),
      input("EventSearchInput", fields: [
        inputField("calendarIds", .nonNull(.list(.nonNull(.named("ID")))), defaultValue: .list([])),
        inputField("startDate", .dateTime),
        inputField("endDate", .dateTime),
        inputField("query", .string),
        inputField("first", .int),
        inputField("after", .string)
      ]),
      input("ReminderSearchInput", fields: [
        inputField("listIds", .nonNull(.list(.nonNull(.named("ID")))), defaultValue: .list([])),
        inputField("status", .nonNull(.named("ReminderStatusFilter")), defaultValue: .enumCase("ALL")),
        inputField("dueAfter", .dateTime),
        inputField("dueBefore", .dateTime),
        inputField("query", .string),
        inputField("first", .int),
        inputField("after", .string)
      ]),
      input("CreateCalendarInput", fields: [
        inputField("title", .stringRequired),
        inputField("sourceTitle", .string),
        inputField("colorHex", .string)
      ]),
      input("CreateReminderListInput", fields: [
        inputField("title", .stringRequired),
        inputField("sourceTitle", .string),
        inputField("colorHex", .string)
      ]),
      input("AlarmInput", fields: [
        inputField("relativeOffsetSeconds", .int),
        inputField("absoluteDate", .dateTime)
      ]),
      input("RecurrenceRuleInput", fields: [
        inputField("frequency", .nonNull(.named("RecurrenceFrequency"))),
        inputField("interval", .intRequired, defaultValue: .int(1)),
        inputField("daysOfWeek", .intListRequired, defaultValue: .list([])),
        inputField("daysOfMonth", .intListRequired, defaultValue: .list([])),
        inputField("monthsOfYear", .intListRequired, defaultValue: .list([])),
        inputField("weeksOfYear", .intListRequired, defaultValue: .list([])),
        inputField("daysOfYear", .intListRequired, defaultValue: .list([])),
        inputField("setPositions", .intListRequired, defaultValue: .list([])),
        inputField("endDate", .dateTime),
        inputField("occurrenceCount", .int)
      ]),
      input("CreateEventInput", fields: [
        inputField("calendarId", .id),
        inputField("title", .stringRequired),
        inputField("startDate", .dateTimeRequired),
        inputField("endDate", .dateTimeRequired),
        inputField("isAllDay", .boolRequired, defaultValue: .bool(false)),
        inputField("notes", .string),
        inputField("location", .string),
        inputField("url", .string),
        inputField("timeZone", .string),
        inputField("availability", .named("EventAvailability")),
        inputField("alarms", .list(.nonNull(.named("AlarmInput")))),
        inputField("recurrenceRules", .list(.nonNull(.named("RecurrenceRuleInput"))))
      ]),
      input("UpdateEventInput", fields: [
        inputField("eventId", .idRequired),
        inputField("occurrenceDate", .dateTime),
        inputField("span", .nonNull(.named("RecurrenceSpan")), defaultValue: .enumCase("THIS_EVENT")),
        inputField("title", .string),
        inputField("startDate", .dateTime),
        inputField("endDate", .dateTime),
        inputField("isAllDay", .named("Boolean")),
        inputField("notes", .string),
        inputField("location", .string),
        inputField("url", .string),
        inputField("timeZone", .string),
        inputField("availability", .named("EventAvailability")),
        inputField("calendarId", .id),
        inputField("alarms", .list(.nonNull(.named("AlarmInput")))),
        inputField("recurrenceRules", .list(.nonNull(.named("RecurrenceRuleInput"))))
      ]),
      input("CreateReminderInput", fields: [
        inputField("listId", .id),
        inputField("title", .stringRequired),
        inputField("notes", .string),
        inputField("url", .string),
        inputField("priority", .intRequired, defaultValue: .int(0)),
        inputField("startDate", .dateTime),
        inputField("dueDate", .dateTime),
        inputField("dueDateHasTime", .boolRequired, defaultValue: .bool(true)),
        inputField("alarms", .list(.nonNull(.named("AlarmInput")))),
        inputField("recurrenceRules", .list(.nonNull(.named("RecurrenceRuleInput"))))
      ]),
      input("UpdateReminderInput", fields: [
        inputField("reminderId", .idRequired),
        inputField("title", .string),
        inputField("notes", .string),
        inputField("url", .string),
        inputField("priority", .int),
        inputField("startDate", .dateTime),
        inputField("dueDate", .dateTime),
        inputField("dueDateHasTime", .named("Boolean")),
        inputField("listId", .id),
        inputField("alarms", .list(.nonNull(.named("AlarmInput")))),
        inputField("recurrenceRules", .list(.nonNull(.named("RecurrenceRuleInput"))))
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "calendars",
        type: .nonNull(.list(.nonNull(.named("Calendar")))),
        arguments: [argument("entityType", .named("CalendarEntityType"))],
        resolver: { arguments, context in
          let entityType = try arguments["entityType"]?.calendarEntityTypeValue()
          return .list(try context.calendarReadService.calendars(entityType: entityType).map(\.graphQLValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "events",
        type: .nonNull(.named("EventConnection")),
        arguments: [argument("input", .nonNull(.named("EventSearchInput")))],
        resolver: { arguments, context in
          try context.calendarReadService.events(input: arguments.required("input").eventSearchInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "event",
        type: .named("CalendarEvent"),
        arguments: [
          argument("eventId", .idRequired),
          argument("occurrenceDate", .dateTime)
        ],
        resolver: { arguments, context in
          let event = try context.calendarReadService.event(
            eventId: arguments.required("eventId").stringValue(),
            occurrenceDate: try arguments["occurrenceDate"]?.dateValue()
          )
          return event?.graphQLValue ?? .null
        }
      ),
      GraphQLFieldDefinition(
        name: "reminderLists",
        type: .nonNull(.list(.nonNull(.named("Calendar")))),
        arguments: [],
        resolver: { _, context in
          .list(try context.calendarReadService.reminderLists().map(\.graphQLValue))
        }
      ),
      GraphQLFieldDefinition(
        name: "reminders",
        type: .nonNull(.named("ReminderConnection")),
        arguments: [argument("input", .nonNull(.named("ReminderSearchInput")))],
        resolver: { arguments, context in
          try context.calendarReadService.reminders(input: arguments.required("input").reminderSearchInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "reminder",
        type: .named("Reminder"),
        arguments: [argument("reminderId", .idRequired)],
        resolver: { arguments, context in
          let reminder = try context.calendarReadService.reminder(
            reminderId: arguments.required("reminderId").stringValue()
          )
          return reminder?.graphQLValue ?? .null
        }
      )
    ]
  }

  static var mutationFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "createCalendar",
        type: .nonNull(.named("Calendar")),
        arguments: [argument("input", .nonNull(.named("CreateCalendarInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.createCalendar(arguments.required("input").createCalendarInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "deleteCalendar",
        type: .nonNull(.named("DeleteResult")),
        arguments: [argument("calendarId", .idRequired)],
        resolver: { arguments, context in
          try context.calendarWriteService.deleteCalendar(calendarId: arguments.required("calendarId").stringValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "createEvent",
        type: .nonNull(.named("CalendarEvent")),
        arguments: [argument("input", .nonNull(.named("CreateEventInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.createEvent(arguments.required("input").createEventInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "updateEvent",
        type: .nonNull(.named("CalendarEvent")),
        arguments: [argument("input", .nonNull(.named("UpdateEventInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.updateEvent(arguments.required("input").updateEventInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "deleteEvent",
        type: .nonNull(.named("DeleteResult")),
        arguments: [
          argument("eventId", .idRequired),
          argument("span", .nonNull(.named("RecurrenceSpan")), defaultValue: .enumCase("THIS_EVENT")),
          argument("occurrenceDate", .dateTime)
        ],
        resolver: { arguments, context in
          try context.calendarWriteService.deleteEvent(
            eventId: arguments.required("eventId").stringValue(),
            span: arguments.required("span").recurrenceSpanValue(),
            occurrenceDate: try arguments["occurrenceDate"]?.dateValue()
          ).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "setEventAlarms",
        type: .nonNull(.named("CalendarEvent")),
        arguments: [
          argument("eventId", .idRequired),
          argument("alarms", .nonNull(.list(.nonNull(.named("AlarmInput"))))),
          argument("span", .nonNull(.named("RecurrenceSpan")), defaultValue: .enumCase("THIS_EVENT")),
          argument("occurrenceDate", .dateTime)
        ],
        resolver: { arguments, context in
          try context.calendarWriteService.setEventAlarms(
            eventId: arguments.required("eventId").stringValue(),
            alarms: arguments.required("alarms").alarmListValue(),
            span: arguments.required("span").recurrenceSpanValue(),
            occurrenceDate: try arguments["occurrenceDate"]?.dateValue()
          ).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "createReminderList",
        type: .nonNull(.named("Calendar")),
        arguments: [argument("input", .nonNull(.named("CreateReminderListInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.createReminderList(
            arguments.required("input").createReminderListInputValue()
          ).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "createReminder",
        type: .nonNull(.named("Reminder")),
        arguments: [argument("input", .nonNull(.named("CreateReminderInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.createReminder(arguments.required("input").createReminderInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "updateReminder",
        type: .nonNull(.named("Reminder")),
        arguments: [argument("input", .nonNull(.named("UpdateReminderInput")))],
        resolver: { arguments, context in
          try context.calendarWriteService.updateReminder(arguments.required("input").updateReminderInputValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "deleteReminder",
        type: .nonNull(.named("DeleteResult")),
        arguments: [argument("reminderId", .idRequired)],
        resolver: { arguments, context in
          try context.calendarWriteService.deleteReminder(reminderId: arguments.required("reminderId").stringValue()).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "setReminderCompleted",
        type: .nonNull(.named("Reminder")),
        arguments: [
          argument("reminderId", .idRequired),
          argument("completed", .boolRequired)
        ],
        resolver: { arguments, context in
          try context.calendarWriteService.setReminderCompleted(
            reminderId: arguments.required("reminderId").stringValue(),
            completed: arguments.required("completed").boolValue()
          ).graphQLValue
        }
      ),
      GraphQLFieldDefinition(
        name: "setReminderAlarms",
        type: .nonNull(.named("Reminder")),
        arguments: [
          argument("reminderId", .idRequired),
          argument("alarms", .nonNull(.list(.nonNull(.named("AlarmInput")))))
        ],
        resolver: { arguments, context in
          try context.calendarWriteService.setReminderAlarms(
            reminderId: arguments.required("reminderId").stringValue(),
            alarms: arguments.required("alarms").alarmListValue()
          ).graphQLValue
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

private extension GraphQLTypeReference {
  static var id: GraphQLTypeReference { .named("ID") }
  static var idRequired: GraphQLTypeReference { .nonNull(.id) }
  static var string: GraphQLTypeReference { .named("String") }
  static var stringRequired: GraphQLTypeReference { .nonNull(.string) }
  static var int: GraphQLTypeReference { .named("Int") }
  static var intRequired: GraphQLTypeReference { .nonNull(.int) }
  static var intListRequired: GraphQLTypeReference { .nonNull(.list(.nonNull(.int))) }
  static var boolRequired: GraphQLTypeReference { .nonNull(.named("Boolean")) }
  static var dateTime: GraphQLTypeReference { .named("DateTime") }
  static var dateTimeRequired: GraphQLTypeReference { .nonNull(.dateTime) }
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func required(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  func stringValue() throws -> String {
    switch self {
    case .string(let value), .enumCase(let value):
      return value
    default:
      throw invalidValue("Expected string")
    }
  }

  func intValue() throws -> Int {
    guard case .int(let value) = self else {
      throw invalidValue("Expected int")
    }
    return value
  }

  func boolValue() throws -> Bool {
    guard case .bool(let value) = self else {
      throw invalidValue("Expected boolean")
    }
    return value
  }

  func objectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw invalidValue("Expected input object")
    }
    return value
  }

  func optionalString(_ key: String) throws -> String? {
    try objectDictionary()[key]?.nilIfNull?.stringValue()
  }

  func optionalInt(_ key: String) throws -> Int? {
    try objectDictionary()[key]?.nilIfNull?.intValue()
  }

  func optionalBool(_ key: String) throws -> Bool? {
    try objectDictionary()[key]?.nilIfNull?.boolValue()
  }

  func optionalDate(_ key: String) throws -> Date? {
    try objectDictionary()[key]?.nilIfNull?.dateValue()
  }

  func dateValue() throws -> Date {
    try EventKitDateTime.parse(stringValue())
  }

  func stringListValue(_ key: String) throws -> [String] {
    guard let value = try objectDictionary()[key]?.nilIfNull else {
      return []
    }
    guard case .list(let values) = value else {
      throw invalidValue("Expected string list")
    }
    return try values.map { try $0.stringValue() }
  }

  func intListValue(_ key: String) throws -> [Int] {
    guard let value = try objectDictionary()[key]?.nilIfNull else {
      return []
    }
    guard case .list(let values) = value else {
      throw invalidValue("Expected int list")
    }
    return try values.map { try $0.intValue() }
  }

  func calendarEntityTypeValue() throws -> CalendarEntityType {
    try enumValue(CalendarEntityType.self)
  }

  func eventAvailabilityValue() throws -> EventAvailability {
    try enumValue(EventAvailability.self)
  }

  func recurrenceFrequencyValue() throws -> RecurrenceFrequency {
    try enumValue(RecurrenceFrequency.self)
  }

  func recurrenceSpanValue() throws -> RecurrenceSpan {
    try enumValue(RecurrenceSpan.self)
  }

  func reminderStatusFilterValue() throws -> ReminderStatusFilter {
    try enumValue(ReminderStatusFilter.self)
  }

  func eventSearchInputValue() throws -> EventSearchInput {
    EventSearchInput(
      calendarIds: try stringListValue("calendarIds"),
      startDate: try optionalDate("startDate"),
      endDate: try optionalDate("endDate"),
      query: try optionalString("query"),
      first: try optionalInt("first"),
      after: try optionalString("after")
    )
  }

  func reminderSearchInputValue() throws -> ReminderSearchInput {
    ReminderSearchInput(
      listIds: try stringListValue("listIds"),
      status: try objectDictionary()["status"]?.nilIfNull?.reminderStatusFilterValue() ?? .all,
      dueAfter: try optionalDate("dueAfter"),
      dueBefore: try optionalDate("dueBefore"),
      query: try optionalString("query"),
      first: try optionalInt("first"),
      after: try optionalString("after")
    )
  }

  func createCalendarInputValue() throws -> CreateCalendarInput {
    CreateCalendarInput(
      title: try objectDictionary().required("title").stringValue(),
      sourceTitle: try optionalString("sourceTitle"),
      colorHex: try optionalString("colorHex")
    )
  }

  func createReminderListInputValue() throws -> CreateReminderListInput {
    CreateReminderListInput(
      title: try objectDictionary().required("title").stringValue(),
      sourceTitle: try optionalString("sourceTitle"),
      colorHex: try optionalString("colorHex")
    )
  }

  func createEventInputValue() throws -> CreateEventInput {
    CreateEventInput(
      calendarId: try optionalString("calendarId"),
      title: try objectDictionary().required("title").stringValue(),
      startDate: try objectDictionary().required("startDate").dateValue(),
      endDate: try objectDictionary().required("endDate").dateValue(),
      isAllDay: try objectDictionary()["isAllDay"]?.nilIfNull?.boolValue() ?? false,
      notes: try optionalString("notes"),
      location: try optionalString("location"),
      url: try optionalString("url"),
      timeZone: try optionalString("timeZone"),
      availability: try objectDictionary()["availability"]?.nilIfNull?.eventAvailabilityValue(),
      alarms: try optionalAlarmList("alarms"),
      recurrenceRules: try optionalRecurrenceRuleList("recurrenceRules")
    )
  }

  func updateEventInputValue() throws -> UpdateEventInput {
    UpdateEventInput(
      eventId: try objectDictionary().required("eventId").stringValue(),
      occurrenceDate: try optionalDate("occurrenceDate"),
      span: try objectDictionary()["span"]?.nilIfNull?.recurrenceSpanValue() ?? .thisEvent,
      title: try optionalString("title"),
      startDate: try optionalDate("startDate"),
      endDate: try optionalDate("endDate"),
      isAllDay: try optionalBool("isAllDay"),
      notes: try optionalString("notes"),
      location: try optionalString("location"),
      url: try optionalString("url"),
      timeZone: try optionalString("timeZone"),
      availability: try objectDictionary()["availability"]?.nilIfNull?.eventAvailabilityValue(),
      calendarId: try optionalString("calendarId"),
      alarms: try optionalAlarmList("alarms"),
      recurrenceRules: try optionalRecurrenceRuleList("recurrenceRules")
    )
  }

  func createReminderInputValue() throws -> CreateReminderInput {
    CreateReminderInput(
      listId: try optionalString("listId"),
      title: try objectDictionary().required("title").stringValue(),
      notes: try optionalString("notes"),
      url: try optionalString("url"),
      priority: try objectDictionary()["priority"]?.nilIfNull?.intValue() ?? 0,
      startDate: try optionalDate("startDate"),
      dueDate: try optionalDate("dueDate"),
      dueDateHasTime: try objectDictionary()["dueDateHasTime"]?.nilIfNull?.boolValue() ?? true,
      alarms: try optionalAlarmList("alarms"),
      recurrenceRules: try optionalRecurrenceRuleList("recurrenceRules")
    )
  }

  func updateReminderInputValue() throws -> UpdateReminderInput {
    UpdateReminderInput(
      reminderId: try objectDictionary().required("reminderId").stringValue(),
      title: try optionalString("title"),
      notes: try optionalString("notes"),
      url: try optionalString("url"),
      priority: try optionalInt("priority"),
      startDate: try optionalDate("startDate"),
      dueDate: try optionalDate("dueDate"),
      dueDateHasTime: try optionalBool("dueDateHasTime"),
      listId: try optionalString("listId"),
      alarms: try optionalAlarmList("alarms"),
      recurrenceRules: try optionalRecurrenceRuleList("recurrenceRules")
    )
  }

  func alarmListValue() throws -> [Alarm] {
    guard case .list(let values) = self else {
      throw invalidValue("Expected alarm list")
    }
    return try values.map { try $0.alarmValue() }
  }

  func alarmValue() throws -> Alarm {
    Alarm(
      relativeOffsetSeconds: try optionalInt("relativeOffsetSeconds"),
      absoluteDate: try optionalDate("absoluteDate")
    )
  }

  func recurrenceRuleValue() throws -> RecurrenceRule {
    RecurrenceRule(
      frequency: try objectDictionary().required("frequency").recurrenceFrequencyValue(),
      interval: try objectDictionary()["interval"]?.nilIfNull?.intValue() ?? 1,
      daysOfWeek: try intListValue("daysOfWeek"),
      daysOfMonth: try intListValue("daysOfMonth"),
      monthsOfYear: try intListValue("monthsOfYear"),
      weeksOfYear: try intListValue("weeksOfYear"),
      daysOfYear: try intListValue("daysOfYear"),
      setPositions: try intListValue("setPositions"),
      endDate: try optionalDate("endDate"),
      occurrenceCount: try optionalInt("occurrenceCount")
    )
  }

  private var nilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  private func optionalAlarmList(_ key: String) throws -> [Alarm]? {
    guard let value = try objectDictionary()[key]?.nilIfNull else {
      return nil
    }
    return try value.alarmListValue()
  }

  private func optionalRecurrenceRuleList(_ key: String) throws -> [RecurrenceRule]? {
    guard let value = try objectDictionary()[key]?.nilIfNull else {
      return nil
    }
    guard case .list(let values) = value else {
      throw invalidValue("Expected recurrence rule list")
    }
    return try values.map { try $0.recurrenceRuleValue() }
  }

  private func enumValue<EnumType: RawRepresentable>(
    _ type: EnumType.Type
  ) throws -> EnumType where EnumType.RawValue == String {
    let rawValue = try stringValue()
    guard let value = EnumType(rawValue: rawValue) else {
      throw invalidValue("Invalid enum value \(rawValue)")
    }
    return value
  }

  private func invalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private let graphQLTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

private func dateValue(_ date: Date?) -> GraphQLValue {
  guard let date else {
    return .null
  }
  return .string(EventKitDateTime.format(date, timeZone: graphQLTimeZone))
}

private extension GatewayCalendar {
  var graphQLValue: GraphQLValue {
    .object([
      "id": .string(id),
      "title": .string(title),
      "entityType": .enumCase(entityType.rawValue),
      "sourceTitle": .string(sourceTitle),
      "sourceType": .string(sourceType),
      "colorHex": colorHex.map(GraphQLValue.string) ?? .null,
      "allowsModifications": .bool(allowsModifications),
      "isSubscribed": .bool(isSubscribed),
      "isDefault": .bool(isDefault)
    ])
  }
}

private extension EventParticipant {
  var graphQLValue: GraphQLValue {
    .object([
      "name": name.map(GraphQLValue.string) ?? .null,
      "email": email.map(GraphQLValue.string) ?? .null,
      "isCurrentUser": .bool(isCurrentUser),
      "status": .enumCase(status.rawValue)
    ])
  }
}

private extension Alarm {
  var graphQLValue: GraphQLValue {
    .object([
      "relativeOffsetSeconds": relativeOffsetSeconds.map(GraphQLValue.int) ?? .null,
      "absoluteDate": dateValue(absoluteDate)
    ])
  }
}

private extension RecurrenceRule {
  var graphQLValue: GraphQLValue {
    .object([
      "frequency": .enumCase(frequency.rawValue),
      "interval": .int(interval),
      "daysOfWeek": .list(daysOfWeek.map(GraphQLValue.int)),
      "daysOfMonth": .list(daysOfMonth.map(GraphQLValue.int)),
      "monthsOfYear": .list(monthsOfYear.map(GraphQLValue.int)),
      "weeksOfYear": .list(weeksOfYear.map(GraphQLValue.int)),
      "daysOfYear": .list(daysOfYear.map(GraphQLValue.int)),
      "setPositions": .list(setPositions.map(GraphQLValue.int)),
      "endDate": dateValue(endDate),
      "occurrenceCount": occurrenceCount.map(GraphQLValue.int) ?? .null
    ])
  }
}

private extension CalendarEvent {
  var graphQLValue: GraphQLValue {
    .object([
      "id": .string(id),
      "calendarId": .string(calendarId),
      "title": .string(title),
      "notes": notes.map(GraphQLValue.string) ?? .null,
      "location": location.map(GraphQLValue.string) ?? .null,
      "url": url.map(GraphQLValue.string) ?? .null,
      "isAllDay": .bool(isAllDay),
      "startDate": dateValue(startDate),
      "endDate": dateValue(endDate),
      "timeZone": timeZone.map(GraphQLValue.string) ?? .null,
      "status": .enumCase(status.rawValue),
      "availability": .enumCase(availability.rawValue),
      "organizer": organizer?.graphQLValue ?? .null,
      "attendees": .list(attendees.map(\.graphQLValue)),
      "alarms": .list(alarms.map(\.graphQLValue)),
      "recurrenceRules": .list(recurrenceRules.map(\.graphQLValue)),
      "isRecurring": .bool(isRecurring),
      "occurrenceDate": dateValue(occurrenceDate),
      "isDetached": .bool(isDetached),
      "creationDate": dateValue(creationDate),
      "lastModifiedDate": dateValue(lastModifiedDate)
    ])
  }
}

private extension Reminder {
  var graphQLValue: GraphQLValue {
    .object([
      "id": .string(id),
      "listId": .string(listId),
      "title": .string(title),
      "notes": notes.map(GraphQLValue.string) ?? .null,
      "url": url.map(GraphQLValue.string) ?? .null,
      "priority": .int(priority),
      "isCompleted": .bool(isCompleted),
      "completionDate": dateValue(completionDate),
      "startDate": dateValue(startDate),
      "dueDate": dateValue(dueDate),
      "dueDateHasTime": .bool(dueDateHasTime),
      "alarms": .list(alarms.map(\.graphQLValue)),
      "recurrenceRules": .list(recurrenceRules.map(\.graphQLValue)),
      "creationDate": dateValue(creationDate),
      "lastModifiedDate": dateValue(lastModifiedDate)
    ])
  }
}

private extension PageInfo {
  var graphQLValue: GraphQLValue {
    .object([
      "hasNextPage": .bool(hasNextPage),
      "endCursor": endCursor.map(GraphQLValue.string) ?? .null
    ])
  }
}

private extension EventConnection {
  var graphQLValue: GraphQLValue {
    .object([
      "edges": .list(edges.map(\.graphQLValue)),
      "pageInfo": pageInfo.graphQLValue,
      "totalCount": .int(totalCount)
    ])
  }
}

private extension EventEdge {
  var graphQLValue: GraphQLValue {
    .object([
      "cursor": .string(cursor),
      "node": node.graphQLValue
    ])
  }
}

private extension ReminderConnection {
  var graphQLValue: GraphQLValue {
    .object([
      "edges": .list(edges.map(\.graphQLValue)),
      "pageInfo": pageInfo.graphQLValue,
      "totalCount": .int(totalCount)
    ])
  }
}

private extension ReminderEdge {
  var graphQLValue: GraphQLValue {
    .object([
      "cursor": .string(cursor),
      "node": node.graphQLValue
    ])
  }
}

private extension DeleteResult {
  var graphQLValue: GraphQLValue {
    .object(["success": .bool(success)])
  }
}
