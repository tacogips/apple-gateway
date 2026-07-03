import Foundation
import Testing
@testable import AppleGatewayCore

@Test func permissionRequestDomainParsingRejectsNonRequestableDomains() throws {
  #expect(try PermissionRequestDomain(commandValue: "calendar") == .calendar)
  #expect(try PermissionRequestDomain(commandValue: "notifications") == .notifications)

  do {
    _ = try PermissionRequestDomain(commandValue: "mail")
    Issue.record("Expected mail to be rejected as non-requestable")
  } catch AppleGatewayCommand.Error.invalidUsage(let message) {
    #expect(message.contains("calendar, reminders, notes, or notifications"))
  }
}

@Test func permissionsStatusDoesNotCallRequestProvider() {
  let probe = CountingPermissionProbe()
  let requester = CountingPermissionRequester()
  let service = PermissionsService(probe: probe, requester: requester)

  let status = service.status(config: .defaultValue)

  #expect(status.calendars.state == .granted)
  #expect(probe.calendarStatusCalls == 1)
  #expect(requester.requestedDomains.isEmpty)
}

@Test func disabledDomainsReturnNotRequiredAndSkipProbes() {
  let probe = CountingPermissionProbe()
  let service = PermissionsService(probe: probe, requester: CountingPermissionRequester())
  var config = AppleGatewayConfig.defaultValue
  config.domains.calendar = false
  config.domains.mail = false

  let status = service.status(config: config)

  #expect(status.calendars.state == .notRequired)
  #expect(status.mailFullDiskAccess.state == .notRequired)
  #expect(probe.calendarStatusCalls == 0)
  #expect(probe.mailStatusCalls == 0)
}

@Test func requestPathCallsOnlySelectedDomain() {
  let requester = CountingPermissionRequester()
  let service = PermissionsService(probe: CountingPermissionProbe(), requester: requester)

  let result = service.request(domain: .calendar, config: .defaultValue)

  #expect(result.domain == .calendar)
  #expect(result.status.state == .granted)
  #expect(requester.requestedDomains == [.calendar])
}

@Test func notificationHelperUnavailableReportsUnknown() {
  let probe = LivePermissionProbe()

  let status = probe.notificationsHelperStatus(config: .defaultValue)

  #expect(status.state == .unknown)
  #expect(status.details["reason"]?.contains("No notification helper app is configured") == true)
}

@Test func fullDiskAccessProbeUsesReadOnlyOpen() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-permissions-tests")
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let envelopeIndex = root.appendingPathComponent("Envelope Index")
  try Data("probe".utf8).write(to: envelopeIndex)
  var config = AppleGatewayConfig.defaultValue
  config.mail.mailRoot = root.path

  let status = LivePermissionProbe().mailFullDiskAccessStatus(config: config)

  #expect(status.state == .granted)
}

@Test func shortcutsClockBridgeRequiresExactExpectedShortcutNames() {
  let output = """
  apple-gateway-get-alarms
  apple-gateway-create-alarm
  apple-gateway-toggle-alarm
  apple-gateway-unrelated
  """
  let status = LivePermissionProbe.shortcutsClockBridgeStatus(
    config: .defaultValue,
    shortcutsListOutput: output,
    osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 0)
  )

  #expect(status.state == .granted)
  #expect(status.details["expectedShortcuts"] == [
    "apple-gateway-get-alarms",
    "apple-gateway-create-alarm",
    "apple-gateway-toggle-alarm"
  ].joined(separator: ","))
}

@Test func shortcutsClockBridgeRejectsPrefixOnlyFalsePositive() {
  let output = """
  apple-gateway-get-alarms
  apple-gateway-random
  """
  let status = LivePermissionProbe.shortcutsClockBridgeStatus(
    config: .defaultValue,
    shortcutsListOutput: output,
    osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 0)
  )

  #expect(status.state == .unknown)
  #expect(status.details["reason"] == "Missing Clock alarm bridge shortcuts")
  #expect(status.details["missingShortcuts"] == "apple-gateway-create-alarm,apple-gateway-toggle-alarm")
}

@Test func shortcutsClockBridgeRequiresUpdateAndDeleteOnMacOS26() {
  let output = """
  apple-gateway-get-alarms
  apple-gateway-create-alarm
  apple-gateway-toggle-alarm
  """
  let status = LivePermissionProbe.shortcutsClockBridgeStatus(
    config: .defaultValue,
    shortcutsListOutput: output,
    osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
  )

  #expect(status.state == .unknown)
  #expect(status.details["missingShortcuts"] == "apple-gateway-update-alarm,apple-gateway-delete-alarm")
}

@Test func shortcutsClockBridgeUsesConfiguredPrefix() {
  var config = AppleGatewayConfig.defaultValue
  config.clockAlarms.shortcutPrefix = "custom"
  let output = """
  custom-get-alarms
  custom-create-alarm
  custom-toggle-alarm
  custom-update-alarm
  custom-delete-alarm
  """
  let status = LivePermissionProbe.shortcutsClockBridgeStatus(
    config: config,
    shortcutsListOutput: output,
    osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
  )

  #expect(status.state == .granted)
}

@Test func permissionFailureFormatterMatchesContractOrdering() {
  let message = PermissionFailureFormatter().message(
    domainName: "Calendar",
    stateDescription: "denied",
    responsibleProcessHint: "iTerm2",
    settingsPane: "System Settings > Privacy & Security > Calendars",
    requestCommand: "apple-gateway permissions request --domain calendar",
    resetCommand: "tccutil reset Calendar"
  )

  #expect(
    message.text == """
    Calendar access is denied for this process tree.
    Responsible app (best effort): iTerm2
    Fix: System Settings > Privacy & Security > Calendars: enable "iTerm2",
    or run: apple-gateway permissions request --domain calendar
    Reset: tccutil reset Calendar
    """
  )
  #expect(message.details["responsibleProcessHint"] == "iTerm2")
}

private final class CountingPermissionProbe: PermissionStatusProbe, @unchecked Sendable {
  private(set) var calendarStatusCalls = 0
  private(set) var mailStatusCalls = 0

  func calendarStatus() -> PermissionFieldStatus {
    calendarStatusCalls += 1
    return PermissionFieldStatus(state: .granted)
  }

  func remindersStatus() -> PermissionFieldStatus {
    PermissionFieldStatus(state: .granted)
  }

  func notesAutomationStatus() -> PermissionFieldStatus {
    PermissionFieldStatus(state: .unknown)
  }

  func mailFullDiskAccessStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    mailStatusCalls += 1
    return PermissionFieldStatus(state: .granted)
  }

  func notificationDbFullDiskAccessStatus() -> PermissionFieldStatus {
    PermissionFieldStatus(state: .unknown)
  }

  func notificationsHelperStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    PermissionFieldStatus(state: .unknown)
  }

  func shortcutsClockBridgeStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
    PermissionFieldStatus(state: .unknown)
  }
}

private final class CountingPermissionRequester: PermissionRequestProvider, @unchecked Sendable {
  private(set) var requestedDomains: [PermissionRequestDomain] = []

  func requestCalendar(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.calendar)
    return PermissionFieldStatus(state: .granted)
  }

  func requestReminders(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.reminders)
    return PermissionFieldStatus(state: .granted)
  }

  func requestNotes(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.notes)
    return PermissionFieldStatus(state: .granted)
  }

  func requestNotifications(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.notifications)
    return PermissionFieldStatus(state: .unknown)
  }
}
