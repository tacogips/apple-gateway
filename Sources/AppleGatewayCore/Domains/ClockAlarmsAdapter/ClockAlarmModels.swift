import Foundation

public enum ClockAlarmWeekday: String, Codable, CaseIterable, Sendable {
  case monday = "MONDAY"
  case tuesday = "TUESDAY"
  case wednesday = "WEDNESDAY"
  case thursday = "THURSDAY"
  case friday = "FRIDAY"
  case saturday = "SATURDAY"
  case sunday = "SUNDAY"
}

public struct ClockAlarm: Codable, Equatable, Sendable {
  public var id: String?
  public var label: String
  public var time: String
  public var isEnabled: Bool
  public var repeatDays: [ClockAlarmWeekday]

  public init(
    id: String? = nil,
    label: String,
    time: String,
    isEnabled: Bool,
    repeatDays: [ClockAlarmWeekday] = []
  ) {
    self.id = id
    self.label = label
    self.time = time
    self.isEnabled = isEnabled
    self.repeatDays = repeatDays
  }
}

public struct CreateClockAlarmInput: Codable, Equatable, Sendable {
  public var time: String
  public var label: String?
  public var repeatDays: [ClockAlarmWeekday]

  public init(time: String, label: String? = nil, repeatDays: [ClockAlarmWeekday] = []) {
    self.time = time
    self.label = label
    self.repeatDays = repeatDays
  }
}

public struct ToggleClockAlarmInput: Codable, Equatable, Sendable {
  public var label: String
  public var enabled: Bool?

  public init(label: String, enabled: Bool? = nil) {
    self.label = label
    self.enabled = enabled
  }
}

public struct UpdateClockAlarmInput: Codable, Equatable, Sendable {
  public var label: String
  public var time: String?
  public var newLabel: String?
  public var repeatDays: [ClockAlarmWeekday]?

  public init(
    label: String,
    time: String? = nil,
    newLabel: String? = nil,
    repeatDays: [ClockAlarmWeekday]? = nil
  ) {
    self.label = label
    self.time = time
    self.newLabel = newLabel
    self.repeatDays = repeatDays
  }
}

public struct DeleteClockAlarmInput: Codable, Equatable, Sendable {
  public var label: String

  public init(label: String) {
    self.label = label
  }
}

public struct ClockAlarmResult: Codable, Equatable, Sendable {
  public var success: Bool
  public var alarm: ClockAlarm?
  public var warning: String?

  public init(success: Bool, alarm: ClockAlarm? = nil, warning: String? = nil) {
    self.success = success
    self.alarm = alarm
    self.warning = warning
  }
}
