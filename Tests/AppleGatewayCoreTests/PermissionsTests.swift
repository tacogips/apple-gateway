import Foundation
import Testing
@testable import AppleGatewayCore

@Test func permissionRequestDomainParsingIncludesMailAutomation() throws {
  #expect(try PermissionRequestDomain(commandValue: "calendar") == .calendar)
  #expect(try PermissionRequestDomain(commandValue: "mail") == .mail)
  #expect(try PermissionRequestDomain(commandValue: "notifications") == .notifications)
  #expect(try PermissionRequestDomain(commandValue: "clock-alarms") == .clockAlarms)
  #expect(try PermissionRequestDomain(commandValue: "phone-calls") == .phoneCalls)

  #expect(throws: AppleGatewayCommand.Error.self) {
    _ = try PermissionRequestDomain(commandValue: "unknown")
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
  #expect(status.mailAutomation.state == .notRequired)
  #expect(status.mailFullDiskAccess.state == .notRequired)
  #expect(probe.calendarStatusCalls == 0)
  #expect(probe.mailAutomationStatusCalls == 0)
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
  let mailData = root.appendingPathComponent("MailData", isDirectory: true)
  try FileManager.default.createDirectory(at: mailData, withIntermediateDirectories: true)
  let envelopeIndex = mailData.appendingPathComponent("Envelope Index")
  try Data("probe".utf8).write(to: envelopeIndex)
  var config = AppleGatewayConfig.defaultValue
  config.mail.mailRoot = root.path

  let status = LivePermissionProbe().mailFullDiskAccessStatus(config: config)

  #expect(status.state == .granted)
  #expect(status.details["path"] == nil)
}

@Test func requestPathCallsClockAutomationProvider() {
  let requester = CountingPermissionRequester()
  let service = PermissionsService(probe: CountingPermissionProbe(), requester: requester)

  let result = service.request(domain: .clockAlarms, config: .defaultValue)

  #expect(result.domain == .clockAlarms)
  #expect(result.status.state == .granted)
  #expect(requester.requestedDomains == [.clockAlarms])
}

@Test func requestPathCallsPhonePermissionsProvider() {
  let requester = CountingPermissionRequester()
  let service = PermissionsService(probe: CountingPermissionProbe(), requester: requester)

  let result = service.request(domain: .phoneCalls, config: .defaultValue)

  #expect(result.domain == .phoneCalls)
  #expect(result.status.state == .granted)
  #expect(requester.requestedDomains == [.phoneCalls])
}

@Test func requestPathCallsMailAutomationProvider() {
  let requester = CountingPermissionRequester()
  let service = PermissionsService(probe: CountingPermissionProbe(), requester: requester)

  let result = service.request(domain: .mail, config: .defaultValue)

  #expect(result.domain == .mail)
  #expect(result.status.state == .granted)
  #expect(requester.requestedDomains == [.mail])
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
  private(set) var mailAutomationStatusCalls = 0
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

  func mailAutomationStatus() -> PermissionFieldStatus {
    mailAutomationStatusCalls += 1
    return PermissionFieldStatus(state: .granted)
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

  func clockAutomationStatus(config: AppleGatewayConfig) -> PermissionFieldStatus {
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

  func requestMail(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.mail)
    return PermissionFieldStatus(state: .granted)
  }

  func requestNotifications(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.notifications)
    return PermissionFieldStatus(state: .unknown)
  }

  func requestClockAutomation(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.clockAlarms)
    return PermissionFieldStatus(state: .granted)
  }

  func requestPhoneCalls(config: AppleGatewayConfig) -> PermissionFieldStatus {
    requestedDomains.append(.phoneCalls)
    return PermissionFieldStatus(state: .granted)
  }
}
