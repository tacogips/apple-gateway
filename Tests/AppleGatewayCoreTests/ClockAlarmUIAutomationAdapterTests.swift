import Foundation
import Testing
@testable import AppleGatewayCore

@Test func clockAlarmAdapterListsThroughInjectedUIAutomation() throws {
  let executor = StubClockAlarmUIAutomationExecutor(
    alarms: [ClockAlarm(label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday])]
  )
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  #expect(try adapter.clockAlarms() == [
    ClockAlarm(label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday])
  ])
}

@Test func clockAlarmAdapterCreatesThroughInjectedUIAutomation() throws {
  let executor = StubClockAlarmUIAutomationExecutor()
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  let result = try adapter.createClockAlarm(
    CreateClockAlarmInput(time: "08:15", label: "Focus", repeatDays: [.monday, .friday])
  )

  #expect(result == ClockAlarmResult(
    success: true,
    alarm: ClockAlarm(label: "Focus", time: "08:15", isEnabled: true, repeatDays: [.monday, .friday])
  ))
}

@Test func clockAlarmAdapterRejectsInvalidTimeBeforeAutomation() {
  let executor = StubClockAlarmUIAutomationExecutor()
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  do {
    _ = try adapter.createClockAlarm(CreateClockAlarmInput(time: "8:15", label: "Focus"))
    Issue.record("Expected invalid time")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func clockAlarmAdapterRejectsAmbiguousLabelsBeforeMutation() {
  let executor = StubClockAlarmUIAutomationExecutor(alarms: [
    ClockAlarm(label: "Wake", time: "07:00", isEnabled: true),
    ClockAlarm(label: "Wake", time: "08:00", isEnabled: false)
  ])
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  do {
    _ = try adapter.toggleClockAlarm(ToggleClockAlarmInput(label: "Wake"))
    Issue.record("Expected ambiguous label")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
    #expect(error.message == "Clock alarm label is ambiguous")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func clockAlarmAdapterRejectsMissingLabelBeforeMutation() {
  let executor = StubClockAlarmUIAutomationExecutor()
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  do {
    _ = try adapter.deleteClockAlarm(DeleteClockAlarmInput(label: "Missing"))
    Issue.record("Expected missing label")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
    #expect(error.message == "Clock alarm label was not found")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func clockAlarmAdapterTogglesUpdatesAndDeletesThroughUIAutomation() throws {
  let executor = StubClockAlarmUIAutomationExecutor(
    alarms: [ClockAlarm(label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday])]
  )
  let adapter = LiveClockAlarmsAdapter(config: .defaultValue, executor: executor)

  let toggled = try adapter.toggleClockAlarm(ToggleClockAlarmInput(label: "Wake", enabled: false))
  #expect(toggled.alarm?.isEnabled == false)

  let updated = try adapter.updateClockAlarm(
    UpdateClockAlarmInput(label: "Wake", time: "08:00", newLabel: "Morning", repeatDays: [.tuesday])
  )
  #expect(updated.alarm == ClockAlarm(label: "Morning", time: "08:00", isEnabled: false, repeatDays: [.tuesday]))

  let deleted = try adapter.deleteClockAlarm(DeleteClockAlarmInput(label: "Morning"))
  #expect(deleted == ClockAlarmResult(success: true))
  #expect(try adapter.clockAlarms().isEmpty)
}

@Test func clockAlarmJXATemplateUsesStableAccessibilityAnchorsWithoutShortcuts() {
  #expect(ClockAlarmJXATemplate.source.contains("Application('System Events')"))
  #expect(ClockAlarmJXATemplate.source.contains("AXMTAAlarmCollectionView"))
  #expect(ClockAlarmJXATemplate.source.contains("AlarmNameLabel"))
  #expect(ClockAlarmJXATemplate.source.contains("AlarmEnableSwitch"))
  #expect(!ClockAlarmJXATemplate.source.contains("shortcuts run"))
}

private final class StubClockAlarmUIAutomationExecutor: ClockAlarmUIAutomationExecuting, @unchecked Sendable {
  private var alarms: [ClockAlarm]

  init(alarms: [ClockAlarm] = []) {
    self.alarms = alarms
  }

  func listAlarms() throws -> [ClockAlarm] {
    alarms
  }

  func createAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarm {
    let alarm = ClockAlarm(
      label: input.label ?? "Alarm",
      time: input.time,
      isEnabled: true,
      repeatDays: input.repeatDays
    )
    alarms.append(alarm)
    return alarm
  }

  func toggleAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarm {
    let index = try alarmIndex(label: input.label)
    alarms[index].isEnabled = input.enabled ?? !alarms[index].isEnabled
    return alarms[index]
  }

  func updateAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarm {
    let index = try alarmIndex(label: input.label)
    alarms[index].time = input.time ?? alarms[index].time
    alarms[index].label = input.newLabel ?? alarms[index].label
    alarms[index].repeatDays = input.repeatDays ?? alarms[index].repeatDays
    return alarms[index]
  }

  func deleteAlarm(_ input: DeleteClockAlarmInput) throws {
    alarms.remove(at: try alarmIndex(label: input.label))
  }

  private func alarmIndex(label: String) throws -> Int {
    guard let index = alarms.firstIndex(where: { $0.label == label }) else {
      throw AppleGatewayError(code: .invalidArgument, message: "Clock alarm label was not found")
    }
    return index
  }
}
