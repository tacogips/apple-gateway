import Foundation

public protocol ClockAlarmsProviding: Sendable {
  func clockAlarms() throws -> [ClockAlarm]
  func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult
  func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult
  func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult
  func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult
}

public enum ClockAlarmsServiceFactory {
  public static func unavailableService() -> any ClockAlarmsProviding {
    UnavailableClockAlarmsService()
  }

  public static func liveService(config: AppleGatewayConfig) -> any ClockAlarmsProviding {
    LiveClockAlarmsAdapter(config: config)
  }
}

private struct UnavailableClockAlarmsService: ClockAlarmsProviding {
  func clockAlarms() throws -> [ClockAlarm] {
    throw unavailable()
  }

  func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Clock alarms provider is unavailable")
  }
}
