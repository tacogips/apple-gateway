import Foundation
import Testing
@testable import AppleGatewayCore

@Test func clockAlarmShortcutContractDecodesVersionedAlarmList() throws {
  let data = Data("""
  {
    "contractVersion": 1,
    "alarms": [
      {
        "id": "alarm-1",
        "label": "Wake",
        "time": "07:30",
        "isEnabled": true,
        "repeatDays": ["MONDAY", "FRIDAY"]
      }
    ]
  }
  """.utf8)

  let alarms = try ClockAlarmShortcutContract.decodeAlarms(from: data)

  #expect(alarms == [
    ClockAlarm(id: "alarm-1", label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday, .friday])
  ])
}

@Test func clockAlarmShortcutContractEncodesVersionedMutationPayload() throws {
  let data = try ClockAlarmShortcutContract.encodeInput(CreateClockAlarmInput(
    time: "06:45",
    label: "Run",
    repeatDays: [.tuesday]
  ))
  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
  let payload = object?["payload"] as? [String: Any]

  #expect(object?["contractVersion"] as? Int == 1)
  #expect(payload?["time"] as? String == "06:45")
  #expect(payload?["label"] as? String == "Run")
  #expect(payload?["repeatDays"] as? [String] == ["TUESDAY"])
}

@Test func clockAlarmShortcutContractRejectsVersionMismatch() throws {
  let data = Data(#"{"contractVersion":2,"alarms":[]}"#.utf8)

  do {
    _ = try ClockAlarmShortcutContract.decodeAlarms(from: data)
    Issue.record("Expected version mismatch")
  } catch let error as AppleGatewayError {
    #expect(error.code == .unexpectedError)
    #expect(error.message.contains("version mismatch"))
  }
}
