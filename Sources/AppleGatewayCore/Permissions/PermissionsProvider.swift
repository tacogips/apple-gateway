import Darwin
import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(EventKit)
import EventKit
#endif

public protocol PermissionStatusProbe: Sendable {
  func calendarStatus() -> PermissionFieldStatus
  func remindersStatus() -> PermissionFieldStatus
  func notesAutomationStatus() -> PermissionFieldStatus
  func mailFullDiskAccessStatus(config: AppleGatewayConfig) -> PermissionFieldStatus
  func notificationDbFullDiskAccessStatus() -> PermissionFieldStatus
  func notificationsHelperStatus(config: AppleGatewayConfig) -> PermissionFieldStatus
  func clockAutomationStatus(config: AppleGatewayConfig) -> PermissionFieldStatus
}

public protocol PermissionRequestProvider: Sendable {
  func requestCalendar(config: AppleGatewayConfig) -> PermissionFieldStatus
  func requestReminders(config: AppleGatewayConfig) -> PermissionFieldStatus
  func requestNotes(config: AppleGatewayConfig) -> PermissionFieldStatus
  func requestNotifications(config: AppleGatewayConfig) -> PermissionFieldStatus
  func requestClockAutomation(config: AppleGatewayConfig) -> PermissionFieldStatus
}

public protocol ResponsibleProcessDetecting: Sendable {
  func responsibleProcessHint() -> String?
}

public struct DefaultResponsibleProcessDetector: ResponsibleProcessDetecting {
  public init() {}

  public func responsibleProcessHint() -> String? {
    ProcessInfo.processInfo.environment["TERM_PROGRAM"]
  }
}

public struct PermissionsService<Probe: PermissionStatusProbe, Requester: PermissionRequestProvider>: PermissionsProviding {
  public var probe: Probe
  public var requester: Requester

  public init(probe: Probe, requester: Requester) {
    self.probe = probe
    self.requester = requester
  }

  public func status(config: AppleGatewayConfig) -> PermissionsStatus {
    let domains = config.domains
    return PermissionsStatus(
      calendars: domains.calendar ? probe.calendarStatus() : disabled("calendar"),
      reminders: domains.reminders ? probe.remindersStatus() : disabled("reminders"),
      notesAutomation: domains.notes ? probe.notesAutomationStatus() : disabled("notes"),
      mailFullDiskAccess: domains.mail ? probe.mailFullDiskAccessStatus(config: config) : disabled("mail"),
      notificationsHelper: domains.notifications ? probe.notificationsHelperStatus(config: config) : disabled("notifications"),
      notificationDbFullDiskAccess: domains.notifications ? probe.notificationDbFullDiskAccessStatus() : disabled("notifications"),
      clockAutomation: domains.clockAlarms ? probe.clockAutomationStatus(config: config) : disabled("clock_alarms")
    )
  }

  public func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    let status: PermissionFieldStatus
    switch domain {
    case .calendar:
      status = config.domains.calendar ? requester.requestCalendar(config: config) : disabled("calendar")
    case .reminders:
      status = config.domains.reminders ? requester.requestReminders(config: config) : disabled("reminders")
    case .notes:
      status = config.domains.notes ? requester.requestNotes(config: config) : disabled("notes")
    case .notifications:
      status = config.domains.notifications ? requester.requestNotifications(config: config) : disabled("notifications")
    case .clockAlarms:
      status = config.domains.clockAlarms ? requester.requestClockAutomation(config: config) : disabled("clock_alarms")
    }
    return PermissionRequestResult(domain: domain, status: status)
  }

  private func disabled(_ domain: String) -> PermissionFieldStatus {
    PermissionFieldStatus(
      state: .notRequired,
      details: ["domain": domain, "reason": "Domain is disabled in config"]
    )
  }
}

public struct LivePermissionsProvider: PermissionsProviding {
  private let service: PermissionsService<LivePermissionProbe, LivePermissionRequester>

  public init() {
    let probe = LivePermissionProbe()
    service = PermissionsService(probe: probe, requester: LivePermissionRequester(probe: probe))
  }

  public func status(config: AppleGatewayConfig) -> PermissionsStatus {
    service.status(config: config)
  }

  public func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    service.request(domain: domain, config: config)
  }
}

public struct LivePermissionProbe: PermissionStatusProbe {
  public init() {}

  public func calendarStatus() -> PermissionFieldStatus {
    eventKitStatus(entity: .event)
  }

  public func remindersStatus() -> PermissionFieldStatus {
    eventKitStatus(entity: .reminder)
  }

  public func notesAutomationStatus() -> PermissionFieldStatus {
    notesAutomationStatus(askUserIfNeeded: false)
  }

  public func mailFullDiskAccessStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    let configuredRoot = config.mail.mailRoot
    let mailRoot = configuredRoot.isEmpty
      ? NSHomeDirectory() + "/Library/Mail"
      : configuredRoot
    return readOnlyFileStatus(
      path: mailRoot + "/Envelope Index",
      unavailableReason: "Mail Full Disk Access probe file is unavailable"
    )
  }

  public func notificationDbFullDiskAccessStatus() -> PermissionFieldStatus {
    readOnlyFileStatus(
      path: NSHomeDirectory() + "/Library/Application Support/NotificationCenter",
      unavailableReason: "Notification database probe path is unavailable"
    )
  }

  public func notificationsHelperStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    helperStatus(config: config)
  }

  public func clockAutomationStatus(config _: AppleGatewayConfig) -> PermissionFieldStatus {
    clockAutomationStatus(askUserIfNeeded: false)
  }

  fileprivate func helperStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    guard !config.notifications.helperAppPath.isEmpty else {
      return PermissionFieldStatus(
        state: .unknown,
        details: ["reason": "No notification helper app is configured"]
      )
    }
    guard FileManager.default.fileExists(atPath: config.notifications.helperAppPath) else {
      return PermissionFieldStatus(
        state: .unknown,
        details: ["reason": "Configured notification helper app does not exist"]
      )
    }
    return PermissionFieldStatus(
      state: .unknown,
      details: ["reason": "Notification helper authorization IPC is unavailable"]
    )
  }

  private func eventKitStatus(entity: EKEntityType) -> PermissionFieldStatus {
    #if canImport(EventKit)
    let status = EKEventStore.authorizationStatus(for: entity)
    switch status {
    case .authorized, .fullAccess:
      return PermissionFieldStatus(state: .granted)
    case .denied, .restricted:
      return PermissionFieldStatus(state: .denied)
    case .notDetermined:
      return PermissionFieldStatus(state: .notDetermined)
    case .writeOnly:
      return PermissionFieldStatus(
        state: .writeOnly,
        details: ["reason": "EventKit write-only access is insufficient for reads"]
      )
    @unknown default:
      return PermissionFieldStatus(state: .unknown, details: ["reason": "Unknown EventKit authorization status"])
    }
    #else
    return PermissionFieldStatus(state: .unknown, details: ["reason": "EventKit is unavailable"])
    #endif
  }

  private func readOnlyFileStatus(path: String, unavailableReason: String) -> PermissionFieldStatus {
    let descriptor = Darwin.open(path, O_RDONLY)
    if descriptor >= 0 {
      Darwin.close(descriptor)
      return PermissionFieldStatus(state: .granted)
    }
    if errno == EPERM || errno == EACCES {
      return PermissionFieldStatus(
        state: .denied,
        details: ["path": path, "reason": "Read-only open was denied"]
      )
    }
    return PermissionFieldStatus(
      state: .unknown,
      details: ["path": path, "reason": unavailableReason]
    )
  }

  private func runProcess(executable: String, arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CocoaError(.executableLoad)
    }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }
}

public struct LivePermissionRequester: PermissionRequestProvider {
  private var probe: LivePermissionProbe

  public init(probe: LivePermissionProbe = LivePermissionProbe()) {
    self.probe = probe
  }

  public func requestCalendar(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestEventKit(entity: .event)
  }

  public func requestReminders(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestEventKit(entity: .reminder)
  }

  public func requestNotes(config: AppleGatewayConfig) -> PermissionFieldStatus {
    probe.notesAutomationStatus(askUserIfNeeded: true)
  }

  public func requestNotifications(config: AppleGatewayConfig) -> PermissionFieldStatus {
    probe.helperStatus(config: config)
  }

  public func requestClockAutomation(config _: AppleGatewayConfig) -> PermissionFieldStatus {
    probe.clockAutomationStatus(askUserIfNeeded: true)
  }

  private func requestEventKit(entity: EKEntityType) -> PermissionFieldStatus {
    #if canImport(EventKit)
    let store = EKEventStore()
    let semaphore = DispatchSemaphore(value: 0)
    let result = EventKitRequestResultBox()

    let completion: @Sendable (Bool, Error?) -> Void = { allowed, error in
      result.set(granted: allowed, errorDescription: error.map { String(describing: $0) })
      semaphore.signal()
    }
    if #available(macOS 14.0, *) {
      if entity == .event {
        store.requestFullAccessToEvents(completion: completion)
      } else {
        store.requestFullAccessToReminders(completion: completion)
      }
    } else {
      store.requestAccess(to: entity, completion: completion)
    }
    semaphore.wait()
    let requestResult = result.value()
    if requestResult.granted {
      return PermissionFieldStatus(state: .granted)
    }
    if let requestErrorDescription = requestResult.errorDescription {
      return PermissionFieldStatus(
        state: .denied,
        details: ["reason": requestErrorDescription]
      )
    }
    return PermissionFieldStatus(state: .denied)
    #else
    return PermissionFieldStatus(state: .unknown, details: ["reason": "EventKit is unavailable"])
    #endif
  }
}

private extension LivePermissionProbe {
  func notesAutomationStatus(askUserIfNeeded: Bool) -> PermissionFieldStatus {
    automationStatus(
      bundleID: "com.apple.Notes",
      targetName: "Notes",
      askUserIfNeeded: askUserIfNeeded
    )
  }

  func clockAutomationStatus(askUserIfNeeded: Bool) -> PermissionFieldStatus {
    #if canImport(ApplicationServices)
    let accessibilityOptions = [
      "AXTrustedCheckOptionPrompt": askUserIfNeeded
    ] as CFDictionary
    guard AXIsProcessTrustedWithOptions(accessibilityOptions) else {
      return PermissionFieldStatus(
        state: askUserIfNeeded ? .denied : .notDetermined,
        details: [
          "reason": "Accessibility access is required to automate Clock",
          "target": "Clock"
        ]
      )
    }
    return automationStatus(
      bundleID: "com.apple.systemevents",
      targetName: "System Events",
      askUserIfNeeded: askUserIfNeeded
    )
    #else
    return PermissionFieldStatus(
      state: .unknown,
      details: ["reason": "ApplicationServices is unavailable"]
    )
    #endif
  }

  func automationStatus(
    bundleID: String,
    targetName: String,
    askUserIfNeeded: Bool
  ) -> PermissionFieldStatus {
    #if canImport(ApplicationServices)
    var target = AEAddressDesc()
    let createStatus = bundleID.withCString { pointer in
      AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &target)
    }
    guard createStatus == noErr else {
      return PermissionFieldStatus(
        state: .unknown,
        details: ["reason": "Could not create \(targetName) automation target descriptor"]
      )
    }
    defer { AEDisposeDesc(&target) }
    let status = AEDeterminePermissionToAutomateTarget(
      &target,
      typeWildCard,
      typeWildCard,
      askUserIfNeeded
    )
    switch status {
    case noErr:
      return PermissionFieldStatus(state: .granted)
    case OSStatus(errAEEventWouldRequireUserConsent):
      return PermissionFieldStatus(state: .notDetermined)
    case OSStatus(errAEEventNotPermitted):
      return PermissionFieldStatus(state: .denied)
    default:
      return PermissionFieldStatus(
        state: .unknown,
        details: ["reason": "\(targetName) automation status \(status)"]
      )
    }
    #else
    return PermissionFieldStatus(
      state: .unknown,
      details: ["reason": "ApplicationServices is unavailable"]
    )
    #endif
  }
}

private final class EventKitRequestResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var granted = false
  private var errorDescription: String?

  func set(granted: Bool, errorDescription: String?) {
    lock.lock()
    self.granted = granted
    self.errorDescription = errorDescription
    lock.unlock()
  }

  func value() -> (granted: Bool, errorDescription: String?) {
    lock.lock()
    defer { lock.unlock() }
    return (granted, errorDescription)
  }
}
