import Foundation

public struct PermissionsDoctorReport: Sendable {
  public var status: PermissionsStatus

  public init(status: PermissionsStatus) {
    self.status = status
  }

  public var text: String {
    PermissionStatusField.allCases.map { field in
      let fieldStatus = status[field]
      var line = "\(field.rawValue): \(fieldStatus.state.rawValue)"
      if let reason = fieldStatus.details["reason"] {
        line += " - \(reason)"
      }
      if field == .mailFullDiskAccess || field == .notificationDbFullDiskAccess {
        line += " (System Settings > Privacy & Security > Full Disk Access)"
      }
      if field == .clockAutomation {
        line += " (System Settings > Privacy & Security > Accessibility and Automation)"
      }
      return line
    }.joined(separator: "\n")
  }

  public static func requestText(
    result: PermissionRequestResult,
    responsibleProcessHint: String?
  ) -> String {
    let domain = result.domain.displayName
    if result.status.state == .granted || result.status.state == .notRequired {
      return "\(domain) permission state: \(result.status.state.rawValue)"
    }
    let formatter = PermissionFailureFormatter()
    let message = formatter.message(
      domainName: domain,
      stateDescription: result.status.state.failureDescription,
      responsibleProcessHint: responsibleProcessHint,
      settingsPane: result.domain.settingsPane,
      requestCommand: result.domain.requestCommand,
      resetCommand: result.domain.resetCommand
    )
    return message.text
  }
}

private extension PermissionState {
  var failureDescription: String {
    switch self {
    case .denied:
      return "denied"
    case .notDetermined:
      return "not determined"
    case .writeOnly:
      return "write-only"
    case .unknown:
      return "unknown"
    case .granted:
      return "granted"
    case .notRequired:
      return "not required"
    }
  }
}

private extension PermissionRequestDomain {
  var displayName: String {
    switch self {
    case .calendar:
      return "Calendar"
    case .reminders:
      return "Reminders"
    case .notes:
      return "Notes"
    case .notifications:
      return "Notifications"
    case .clockAlarms:
      return "Clock automation"
    }
  }

  var settingsPane: String {
    switch self {
    case .calendar:
      return "System Settings > Privacy & Security > Calendars"
    case .reminders:
      return "System Settings > Privacy & Security > Reminders"
    case .notes:
      return "System Settings > Privacy & Security > Automation"
    case .notifications:
      return "System Settings > Notifications"
    case .clockAlarms:
      return "System Settings > Privacy & Security > Accessibility and Automation"
    }
  }

  var requestCommand: String? {
    "apple-gateway permissions request --domain \(rawValue)"
  }

  var resetCommand: String? {
    switch self {
    case .calendar:
      return "tccutil reset Calendar"
    case .reminders:
      return "tccutil reset Reminders"
    case .notes:
      return "tccutil reset AppleEvents"
    case .notifications:
      return nil
    case .clockAlarms:
      return "tccutil reset AppleEvents"
    }
  }
}
