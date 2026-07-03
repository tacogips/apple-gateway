import EventKit
import Foundation

public enum EventKitAccessDomain: String, Sendable {
  case calendar
  case reminders

  var entityType: EKEntityType {
    switch self {
    case .calendar:
      return .event
    case .reminders:
      return .reminder
    }
  }

  var displayName: String {
    switch self {
    case .calendar:
      return "Calendar"
    case .reminders:
      return "Reminders"
    }
  }
}

public enum EventKitAuthorizationState: Equatable, Sendable {
  case notDetermined
  case denied
  case fullAccess
  case writeOnly
  case unknown

  public var permissionState: PermissionState {
    switch self {
    case .fullAccess:
      return .granted
    case .writeOnly:
      return .writeOnly
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .unknown:
      return .unknown
    }
  }
}

public protocol EventKitStoreAccessing: Sendable {
  func authorizationState(for domain: EventKitAccessDomain) -> EventKitAuthorizationState
  func requestFullAccess(for domain: EventKitAccessDomain) throws -> EventKitAuthorizationState
}

public final class EventKitSession: @unchecked Sendable {
  private let access: any EventKitStoreAccessing

  public init(access: any EventKitStoreAccessing = LiveEventKitStoreAccess()) {
    self.access = access
  }

  public func permissionState(for domain: EventKitAccessDomain) -> PermissionState {
    access.authorizationState(for: domain).permissionState
  }

  public func ensureReadAccess(for domain: EventKitAccessDomain) throws {
    try Self.ensureReadAccess(state: access.authorizationState(for: domain), domain: domain)
  }

  public func requestFullAccess(for domain: EventKitAccessDomain) throws -> PermissionState {
    try access.requestFullAccess(for: domain).permissionState
  }

  public static func ensureReadAccess(
    state: EventKitAuthorizationState,
    domain: EventKitAccessDomain
  ) throws {
    switch state {
    case .fullAccess:
      return
    case .writeOnly:
      throw AppleGatewayError(
        code: .writeOnlyAccess,
        message: "\(domain.displayName) has write-only EventKit access; read access is required",
        details: ["domain": domain.rawValue]
      )
    case .notDetermined:
      throw AppleGatewayError(
        code: .permissionNotDetermined,
        message: "\(domain.displayName) access has not been requested",
        details: [
          "domain": domain.rawValue,
          "hint": "Run apple-gateway permissions request --domain \(domain.rawValue)"
        ]
      )
    case .denied:
      throw AppleGatewayError(
        code: .permissionDenied,
        message: "\(domain.displayName) access denied for this process",
        details: ["domain": domain.rawValue]
      )
    case .unknown:
      throw AppleGatewayError(
        code: .permissionDenied,
        message: "\(domain.displayName) access is unavailable",
        details: ["domain": domain.rawValue]
      )
    }
  }
}

public final class LiveEventKitStoreAccess: EventKitStoreAccessing, @unchecked Sendable {
  private let store: EKEventStore

  public init(store: EKEventStore = EKEventStore()) {
    self.store = store
  }

  public func authorizationState(for domain: EventKitAccessDomain) -> EventKitAuthorizationState {
    Self.authorizationState(EKEventStore.authorizationStatus(for: domain.entityType))
  }

  public func requestFullAccess(for domain: EventKitAccessDomain) throws -> EventKitAuthorizationState {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = EventKitRequestResultBox()

    switch domain {
    case .calendar:
      store.requestFullAccessToEvents { granted, error in
        resultBox.set(granted: granted, error: error)
        semaphore.signal()
      }
    case .reminders:
      store.requestFullAccessToReminders { granted, error in
        resultBox.set(granted: granted, error: error)
        semaphore.signal()
      }
    }

    semaphore.wait()
    let result = resultBox.result()
    if let error = result.error {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "EventKit access request failed",
        details: ["domain": domain.rawValue, "reason": String(describing: error)]
      )
    }
    guard result.granted else {
      return authorizationState(for: domain)
    }
    return .fullAccess
  }

  static func authorizationState(_ status: EKAuthorizationStatus) -> EventKitAuthorizationState {
    switch status {
    case .notDetermined:
      return .notDetermined
    case .restricted, .denied:
      return .denied
    case .authorized, .fullAccess:
      return .fullAccess
    case .writeOnly:
      return .writeOnly
    @unknown default:
      return .unknown
    }
  }
}

private final class EventKitRequestResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = EventKitRequestResult(granted: false, error: nil)

  func set(granted: Bool, error: (any Error)?) {
    lock.withLock {
      storage = EventKitRequestResult(granted: granted, error: error)
    }
  }

  func result() -> EventKitRequestResult {
    lock.withLock {
      storage
    }
  }
}

private struct EventKitRequestResult {
  var granted: Bool
  var error: (any Error)?
}
