import Foundation

public enum PermissionState: String, Codable, CaseIterable, Sendable {
  case granted = "GRANTED"
  case denied = "DENIED"
  case notDetermined = "NOT_DETERMINED"
  case writeOnly = "WRITE_ONLY"
  case notRequired = "NOT_REQUIRED"
  case unknown = "UNKNOWN"

  public var isFailure: Bool {
    switch self {
    case .denied, .notDetermined, .writeOnly:
      return true
    case .granted, .notRequired, .unknown:
      return false
    }
  }
}

public enum PermissionStatusField: String, CaseIterable, Codable, Sendable {
  case calendars
  case reminders
  case notesAutomation
  case mailFullDiskAccess
  case notificationsHelper
  case notificationDbFullDiskAccess
  case clockAutomation
}

public struct PermissionFieldStatus: Codable, Equatable, Sendable {
  public var state: PermissionState
  public var details: [String: String]

  public init(state: PermissionState, details: [String: String] = [:]) {
    self.state = state
    self.details = details
  }
}

public struct PermissionsStatus: Codable, Equatable, Sendable {
  public var calendars: PermissionFieldStatus
  public var reminders: PermissionFieldStatus
  public var notesAutomation: PermissionFieldStatus
  public var mailFullDiskAccess: PermissionFieldStatus
  public var notificationsHelper: PermissionFieldStatus
  public var notificationDbFullDiskAccess: PermissionFieldStatus
  public var clockAutomation: PermissionFieldStatus

  public init(
    calendars: PermissionFieldStatus,
    reminders: PermissionFieldStatus,
    notesAutomation: PermissionFieldStatus,
    mailFullDiskAccess: PermissionFieldStatus,
    notificationsHelper: PermissionFieldStatus,
    notificationDbFullDiskAccess: PermissionFieldStatus,
    clockAutomation: PermissionFieldStatus
  ) {
    self.calendars = calendars
    self.reminders = reminders
    self.notesAutomation = notesAutomation
    self.mailFullDiskAccess = mailFullDiskAccess
    self.notificationsHelper = notificationsHelper
    self.notificationDbFullDiskAccess = notificationDbFullDiskAccess
    self.clockAutomation = clockAutomation
  }

  public subscript(field: PermissionStatusField) -> PermissionFieldStatus {
    switch field {
    case .calendars:
      return calendars
    case .reminders:
      return reminders
    case .notesAutomation:
      return notesAutomation
    case .mailFullDiskAccess:
      return mailFullDiskAccess
    case .notificationsHelper:
      return notificationsHelper
    case .notificationDbFullDiskAccess:
      return notificationDbFullDiskAccess
    case .clockAutomation:
      return clockAutomation
    }
  }

  var graphQLValue: GraphQLValue {
    .object(
      Dictionary(
        uniqueKeysWithValues: PermissionStatusField.allCases.map { field in
          (field.rawValue, GraphQLValue.enumCase(self[field].state.rawValue))
        }
      )
    )
  }

  public var jsonReport: PermissionsStatusJSON {
    PermissionsStatusJSON(status: self)
  }
}

public struct PermissionsStatusJSON: Encodable, Sendable {
  public var calendars: PermissionState
  public var reminders: PermissionState
  public var notesAutomation: PermissionState
  public var mailFullDiskAccess: PermissionState
  public var notificationsHelper: PermissionState
  public var notificationDbFullDiskAccess: PermissionState
  public var clockAutomation: PermissionState
  public var details: [String: [String: String]]

  init(status: PermissionsStatus) {
    calendars = status.calendars.state
    reminders = status.reminders.state
    notesAutomation = status.notesAutomation.state
    mailFullDiskAccess = status.mailFullDiskAccess.state
    notificationsHelper = status.notificationsHelper.state
    notificationDbFullDiskAccess = status.notificationDbFullDiskAccess.state
    clockAutomation = status.clockAutomation.state
    details = Dictionary(
      uniqueKeysWithValues: PermissionStatusField.allCases.compactMap { field in
        let fieldDetails = status[field].details
        guard !fieldDetails.isEmpty else {
          return nil
        }
        return (field.rawValue, fieldDetails)
      }
    )
  }
}

public enum PermissionRequestDomain: String, CaseIterable, Sendable {
  case calendar
  case reminders
  case notes
  case notifications
  case clockAlarms = "clock-alarms"

  public init(commandValue: String) throws {
    guard let domain = PermissionRequestDomain(rawValue: commandValue) else {
      throw AppleGatewayCommand.Error.invalidUsage(
        "Domain must be calendar, reminders, notes, notifications, or clock-alarms"
      )
    }
    self = domain
  }
}

public struct PermissionRequestResult: Equatable, Sendable {
  public var domain: PermissionRequestDomain
  public var status: PermissionFieldStatus

  public init(domain: PermissionRequestDomain, status: PermissionFieldStatus) {
    self.domain = domain
    self.status = status
  }

  var exitCode: Int32 {
    switch status.state {
    case .granted, .notRequired:
      return 0
    case .denied, .notDetermined, .writeOnly:
      return 4
    case .unknown:
      return 6
    }
  }
}

public protocol PermissionsStatusProviding: Sendable {
  func status(config: AppleGatewayConfig) -> PermissionsStatus
}

public protocol PermissionsRequestProviding: Sendable {
  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult
}

public typealias PermissionsProviding = PermissionsStatusProviding & PermissionsRequestProviding
