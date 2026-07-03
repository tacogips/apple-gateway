import Foundation
import Testing
@testable import AppleGatewayCore

@Test func clockAlarmsSchemaPrintsReaderQueriesAndFullMutations() {
  let readerSchema = GraphQLRuntime.schema(role: .reader)
  let fullSchema = GraphQLRuntime.schema(role: .full)

  #expect(readerSchema.contains("  clockAlarms: [ClockAlarm!]!"))
  #expect(readerSchema.contains("type ClockAlarm {"))
  #expect(readerSchema.contains("enum Weekday {"))
  #expect(!readerSchema.contains("createClockAlarm"))

  #expect(fullSchema.contains("  createClockAlarm(input: CreateClockAlarmInput!): ClockAlarmResult!"))
  #expect(fullSchema.contains("  toggleClockAlarm(input: ToggleClockAlarmInput!): ClockAlarmResult!"))
  #expect(fullSchema.contains("  updateClockAlarm(input: UpdateClockAlarmInput!): ClockAlarmResult!"))
  #expect(fullSchema.contains("  deleteClockAlarm(input: DeleteClockAlarmInput!): ClockAlarmResult!"))
}

@Test func clockAlarmsQueryUsesInjectedService() throws {
  let fake = GraphQLClockAlarmsFake()
  let envelope = try clockAlarmsExecuteGraphQL(
    "{ clockAlarms { id label time isEnabled repeatDays } }",
    clockAlarmsService: fake
  )

  #expect(envelope.errors.isEmpty)
  let alarms = try #require(envelope.data?["clockAlarms"] as? [[String: Any]])
  let alarm = try #require(alarms.first)

  #expect(fake.listCalls == 1)
  #expect(alarm["id"] as? String == "alarm-1")
  #expect(alarm["label"] as? String == "Wake")
  #expect(alarm["time"] as? String == "07:30")
  #expect(alarm["isEnabled"] as? Bool == true)
  #expect(alarm["repeatDays"] as? [String] == ["MONDAY", "FRIDAY"])
}

@Test func clockAlarmsMutationsUseInjectedServiceAndReaderRejectsWrites() throws {
  let fake = GraphQLClockAlarmsFake()

  let createEnvelope = try clockAlarmsExecuteGraphQL(
    """
    mutation {
      createClockAlarm(input: { time: "08:00", label: "Focus", repeatDays: [TUESDAY] }) {
        success
        alarm { label time repeatDays }
        warning
      }
    }
    """,
    clockAlarmsService: fake
  )
  let createResult = try #require(createEnvelope.data?["createClockAlarm"] as? [String: Any])
  let createdAlarm = try #require(createResult["alarm"] as? [String: Any])

  #expect(createEnvelope.errors.isEmpty)
  #expect(fake.createInputs.first == CreateClockAlarmInput(time: "08:00", label: "Focus", repeatDays: [.tuesday]))
  #expect(createResult["success"] as? Bool == true)
  #expect(createdAlarm["label"] as? String == "Focus")
  #expect(createdAlarm["repeatDays"] as? [String] == ["TUESDAY"])

  let toggleEnvelope = try clockAlarmsExecuteGraphQL(
    #"mutation { toggleClockAlarm(input: { label: "Focus", enabled: false }) { success alarm { isEnabled } } }"#,
    clockAlarmsService: fake
  )
  let toggleResult = try #require(toggleEnvelope.data?["toggleClockAlarm"] as? [String: Any])
  #expect(toggleEnvelope.errors.isEmpty)
  #expect(fake.toggleInputs.first == ToggleClockAlarmInput(label: "Focus", enabled: false))
  #expect((toggleResult["alarm"] as? [String: Any])?["isEnabled"] as? Bool == false)

  let updateEnvelope = try clockAlarmsExecuteGraphQL(
    #"mutation { updateClockAlarm(input: { label: "Focus", newLabel: "Deep Work" }) { success alarm { label } } }"#,
    clockAlarmsService: fake
  )
  let updateResult = try #require(updateEnvelope.data?["updateClockAlarm"] as? [String: Any])
  #expect(updateEnvelope.errors.isEmpty)
  #expect(fake.updateInputs.first == UpdateClockAlarmInput(label: "Focus", newLabel: "Deep Work"))
  #expect((updateResult["alarm"] as? [String: Any])?["label"] as? String == "Deep Work")

  let deleteEnvelope = try clockAlarmsExecuteGraphQL(
    #"mutation { deleteClockAlarm(input: { label: "Deep Work" }) { success warning } }"#,
    clockAlarmsService: fake
  )
  let deleteResult = try #require(deleteEnvelope.data?["deleteClockAlarm"] as? [String: Any])
  #expect(deleteEnvelope.errors.isEmpty)
  #expect(fake.deleteInputs.first == DeleteClockAlarmInput(label: "Deep Work"))
  #expect(deleteResult["success"] as? Bool == true)

  let readerEnvelope = try clockAlarmsExecuteGraphQL(
    #"mutation { createClockAlarm(input: { time: "09:00" }) { success } }"#,
    role: .reader,
    clockAlarmsService: fake
  )
  #expect(readerEnvelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(fake.createInputs.count == 1)
}

private func clockAlarmsExecuteGraphQL(
  _ query: String,
  role: AppleGatewayRole = .full,
  clockAlarmsService: any ClockAlarmsProviding
) throws -> ClockAlarmsDecodedEnvelope {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: [:],
    role: role,
    permissionsProvider: ClockAlarmsGraphQLPermissionsProvider(),
    clockAlarmsService: clockAlarmsService
  )
  let object = try JSONSerialization.jsonObject(with: data)
  let dictionary = try #require(object as? [String: Any])
  let dataObject = dictionary["data"] as? [String: Any]
  let errorObjects = dictionary["errors"] as? [[String: Any]] ?? []
  return ClockAlarmsDecodedEnvelope(
    data: dataObject,
    errors: errorObjects.map {
      let extensions = $0["extensions"] as? [String: Any]
      return ClockAlarmsDecodedError(
        message: $0["message"] as? String ?? "",
        code: extensions?["code"] as? String ?? "",
        exitCode: extensions?["exitCode"] as? Int ?? 0
      )
    }
  )
}

private struct ClockAlarmsDecodedEnvelope {
  var data: [String: Any]?
  var errors: [ClockAlarmsDecodedError]
}

private struct ClockAlarmsDecodedError {
  var message: String
  var code: String
  var exitCode: Int
}

private struct ClockAlarmsGraphQLPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .unknown),
      reminders: PermissionFieldStatus(state: .unknown),
      notesAutomation: PermissionFieldStatus(state: .unknown),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      shortcutsClockBridge: PermissionFieldStatus(state: .unknown)
    )
  }
}

private final class GraphQLClockAlarmsFake: ClockAlarmsProviding, @unchecked Sendable {
  var listCalls = 0
  var createInputs: [CreateClockAlarmInput] = []
  var toggleInputs: [ToggleClockAlarmInput] = []
  var updateInputs: [UpdateClockAlarmInput] = []
  var deleteInputs: [DeleteClockAlarmInput] = []

  func clockAlarms() throws -> [ClockAlarm] {
    listCalls += 1
    return [ClockAlarm(id: "alarm-1", label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday, .friday])]
  }

  func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    createInputs.append(input)
    return ClockAlarmResult(
      success: true,
      alarm: ClockAlarm(label: input.label ?? "", time: input.time, isEnabled: true, repeatDays: input.repeatDays)
    )
  }

  func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    toggleInputs.append(input)
    return ClockAlarmResult(
      success: true,
      alarm: ClockAlarm(label: input.label, time: "08:00", isEnabled: input.enabled ?? false)
    )
  }

  func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    updateInputs.append(input)
    return ClockAlarmResult(
      success: true,
      alarm: ClockAlarm(label: input.newLabel ?? input.label, time: input.time ?? "08:00", isEnabled: true)
    )
  }

  func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    deleteInputs.append(input)
    return ClockAlarmResult(success: true)
  }
}
