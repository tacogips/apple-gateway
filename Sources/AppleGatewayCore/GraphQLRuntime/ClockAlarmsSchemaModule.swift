import Foundation

extension GraphQLSchemaModule {
  static var clockAlarms: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: ClockAlarmsSchema.types,
      queryFields: ClockAlarmsSchema.queryFields,
      mutationFields: ClockAlarmsSchema.mutationFields
    )
  }
}

private enum ClockAlarmsSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      scalar("ID"),
      enumType("Weekday", ClockAlarmWeekday.allCases.map(\.rawValue)),
      object("ClockAlarm", fields: [
        field("id", id()),
        field("label", stringRequired()),
        field("time", stringRequired()),
        field("isEnabled", boolRequired()),
        field("repeatDays", nonNull(list(nonNull(named("Weekday")))))
      ]),
      object("ClockAlarmResult", fields: [
        field("success", boolRequired()),
        field("alarm", named("ClockAlarm")),
        field("warning", string())
      ]),
      input("CreateClockAlarmInput", fields: [
        inputField("time", stringRequired()),
        inputField("label", string()),
        inputField("repeatDays", list(nonNull(named("Weekday"))))
      ]),
      input("ToggleClockAlarmInput", fields: [
        inputField("label", stringRequired()),
        inputField("enabled", named("Boolean"))
      ]),
      input("UpdateClockAlarmInput", fields: [
        inputField("label", stringRequired()),
        inputField("time", string()),
        inputField("newLabel", string()),
        inputField("repeatDays", list(nonNull(named("Weekday"))))
      ]),
      input("DeleteClockAlarmInput", fields: [
        inputField("label", stringRequired())
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "clockAlarms",
        type: nonNull(list(nonNull(named("ClockAlarm")))),
        arguments: [],
        resolver: { _, context in
          .list(try context.clockAlarmsService.clockAlarms().map(clockAlarmValue))
        }
      )
    ]
  }

  static var mutationFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "createClockAlarm",
        type: nonNull(named("ClockAlarmResult")),
        arguments: [argument("input", nonNull(named("CreateClockAlarmInput")))],
        resolver: { arguments, context in
          try clockAlarmResultValue(
            context.clockAlarmsService.createClockAlarm(
              arguments.clockAlarmsRequired("input").createClockAlarmInputValue()
            )
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "toggleClockAlarm",
        type: nonNull(named("ClockAlarmResult")),
        arguments: [argument("input", nonNull(named("ToggleClockAlarmInput")))],
        resolver: { arguments, context in
          try clockAlarmResultValue(
            context.clockAlarmsService.toggleClockAlarm(
              arguments.clockAlarmsRequired("input").toggleClockAlarmInputValue()
            )
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "updateClockAlarm",
        type: nonNull(named("ClockAlarmResult")),
        arguments: [argument("input", nonNull(named("UpdateClockAlarmInput")))],
        resolver: { arguments, context in
          try clockAlarmResultValue(
            context.clockAlarmsService.updateClockAlarm(
              arguments.clockAlarmsRequired("input").updateClockAlarmInputValue()
            )
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "deleteClockAlarm",
        type: nonNull(named("ClockAlarmResult")),
        arguments: [argument("input", nonNull(named("DeleteClockAlarmInput")))],
        resolver: { arguments, context in
          try clockAlarmResultValue(
            context.clockAlarmsService.deleteClockAlarm(
              arguments.clockAlarmsRequired("input").deleteClockAlarmInputValue()
            )
          )
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

private func string() -> GraphQLTypeReference {
  .named("String")
}

private func stringRequired() -> GraphQLTypeReference {
  .nonNull(string())
}

private func boolRequired() -> GraphQLTypeReference {
  .nonNull(.named("Boolean"))
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func clockAlarmsRequired(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  var clockAlarmsNilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  func clockAlarmsObjectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw clockAlarmsInvalidValue("Expected input object")
    }
    return value
  }

  func clockAlarmsStringValue() throws -> String {
    switch self {
    case .string(let value), .enumCase(let value):
      return value
    default:
      throw clockAlarmsInvalidValue("Expected string")
    }
  }

  func clockAlarmsBoolValue() throws -> Bool {
    guard case .bool(let value) = self else {
      throw clockAlarmsInvalidValue("Expected boolean")
    }
    return value
  }

  func clockAlarmsOptionalString(_ key: String) throws -> String? {
    try clockAlarmsObjectDictionary()[key]?.clockAlarmsNilIfNull?.clockAlarmsStringValue()
  }

  func clockAlarmsOptionalBool(_ key: String) throws -> Bool? {
    try clockAlarmsObjectDictionary()[key]?.clockAlarmsNilIfNull?.clockAlarmsBoolValue()
  }

  func clockAlarmsWeekdayListValue() throws -> [ClockAlarmWeekday] {
    guard case .list(let values) = self else {
      throw clockAlarmsInvalidValue("Expected weekday list")
    }
    return try values.map { value in
      let raw = try value.clockAlarmsStringValue()
      guard let weekday = ClockAlarmWeekday(rawValue: raw) else {
        throw clockAlarmsInvalidValue("Unknown weekday \(raw)")
      }
      return weekday
    }
  }

  func clockAlarmsOptionalWeekdays(_ key: String) throws -> [ClockAlarmWeekday]? {
    try clockAlarmsObjectDictionary()[key]?.clockAlarmsNilIfNull?.clockAlarmsWeekdayListValue()
  }

  func createClockAlarmInputValue() throws -> CreateClockAlarmInput {
    CreateClockAlarmInput(
      time: try clockAlarmsObjectDictionary()["time"]?.clockAlarmsStringValue()
        ?? { throw clockAlarmsInvalidValue("Missing required field time") }(),
      label: try clockAlarmsOptionalString("label"),
      repeatDays: try clockAlarmsOptionalWeekdays("repeatDays") ?? []
    )
  }

  func toggleClockAlarmInputValue() throws -> ToggleClockAlarmInput {
    ToggleClockAlarmInput(
      label: try clockAlarmsObjectDictionary()["label"]?.clockAlarmsStringValue()
        ?? { throw clockAlarmsInvalidValue("Missing required field label") }(),
      enabled: try clockAlarmsOptionalBool("enabled")
    )
  }

  func updateClockAlarmInputValue() throws -> UpdateClockAlarmInput {
    UpdateClockAlarmInput(
      label: try clockAlarmsObjectDictionary()["label"]?.clockAlarmsStringValue()
        ?? { throw clockAlarmsInvalidValue("Missing required field label") }(),
      time: try clockAlarmsOptionalString("time"),
      newLabel: try clockAlarmsOptionalString("newLabel"),
      repeatDays: try clockAlarmsOptionalWeekdays("repeatDays")
    )
  }

  func deleteClockAlarmInputValue() throws -> DeleteClockAlarmInput {
    DeleteClockAlarmInput(
      label: try clockAlarmsObjectDictionary()["label"]?.clockAlarmsStringValue()
        ?? { throw clockAlarmsInvalidValue("Missing required field label") }()
    )
  }

  func clockAlarmsInvalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private func clockAlarmValue(_ alarm: ClockAlarm) -> GraphQLValue {
  .object([
    "id": alarm.id.map(GraphQLValue.string) ?? .null,
    "label": .string(alarm.label),
    "time": .string(alarm.time),
    "isEnabled": .bool(alarm.isEnabled),
    "repeatDays": .list(alarm.repeatDays.map { .enumCase($0.rawValue) })
  ])
}

private func clockAlarmResultValue(_ result: ClockAlarmResult) -> GraphQLValue {
  .object([
    "success": .bool(result.success),
    "alarm": result.alarm.map(clockAlarmValue) ?? .null,
    "warning": result.warning.map(GraphQLValue.string) ?? .null
  ])
}
