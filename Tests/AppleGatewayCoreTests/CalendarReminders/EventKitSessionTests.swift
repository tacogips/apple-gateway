import Foundation
import Testing
@testable import AppleGatewayCore

@Test func writeOnlyAccessFailsReadsWithWriteOnlyAccessCode() throws {
  do {
    try EventKitSession.ensureReadAccess(state: .writeOnly, domain: .calendar)
    Issue.record("Expected write-only read failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .writeOnlyAccess)
    #expect(error.details?["domain"] == "calendar")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func notDeterminedAccessFailsReadsWithoutImplicitPrompt() throws {
  let access = StaticEventKitStoreAccess(state: .notDetermined)
  let session = EventKitSession(access: access)

  do {
    try session.ensureReadAccess(for: .reminders)
    Issue.record("Expected not-determined read failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .permissionNotDetermined)
    #expect(error.details?["domain"] == "reminders")
    #expect(access.requestedDomains.isEmpty)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func fullAccessAllowsReadsAndRequestsMapToPermissionState() throws {
  let access = StaticEventKitStoreAccess(state: .fullAccess, requestState: .fullAccess)
  let session = EventKitSession(access: access)

  try session.ensureReadAccess(for: .calendar)

  #expect(try session.requestFullAccess(for: .calendar) == .granted)
  #expect(access.requestedDomains == [.calendar])
}

@Test func dateTimeParsesTimezoneOffsetAndFormatsInRequestedZone() throws {
  let date = try EventKitDateTime.parse("2026-07-03T18:30:00+09:00")
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let utc = try #require(TimeZone(secondsFromGMT: 0))

  #expect(EventKitDateTime.format(date, timeZone: tokyo) == "2026-07-03T18:30:00+09:00")
  #expect(EventKitDateTime.format(date, timeZone: utc) == "2026-07-03T09:30:00Z")
}

@Test func allDayRangeUsesDateOnlyComponentsInTargetTimezone() throws {
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let start = try EventKitDateTime.parse("2026-07-03T00:00:00+09:00")
  let end = try EventKitDateTime.parse("2026-07-04T00:00:00+09:00")

  let range = EventKitDateTime.allDayRange(startDate: start, endDate: end, timeZone: tokyo)

  #expect(range.start.year == 2026)
  #expect(range.start.month == 7)
  #expect(range.start.day == 3)
  #expect(range.end.year == 2026)
  #expect(range.end.month == 7)
  #expect(range.end.day == 4)
}

@Test func dateOnlyDueDateRoundTripsAtLocalMidnight() throws {
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  var components = DateComponents()
  components.year = 2026
  components.month = 7
  components.day = 3

  let date = try EventKitDateTime.date(fromDateOnly: components, timeZone: tokyo)

  #expect(EventKitDateTime.format(date, timeZone: tokyo) == "2026-07-03T00:00:00+09:00")
  #expect(EventKitDateTime.dateOnlyComponents(from: date, timeZone: tokyo).day == 3)
}

private final class StaticEventKitStoreAccess: EventKitStoreAccessing, @unchecked Sendable {
  private let state: EventKitAuthorizationState
  private let requestState: EventKitAuthorizationState
  private(set) var requestedDomains: [EventKitAccessDomain] = []

  init(
    state: EventKitAuthorizationState,
    requestState: EventKitAuthorizationState = .notDetermined
  ) {
    self.state = state
    self.requestState = requestState
  }

  func authorizationState(for domain: EventKitAccessDomain) -> EventKitAuthorizationState {
    state
  }

  func requestFullAccess(for domain: EventKitAccessDomain) throws -> EventKitAuthorizationState {
    requestedDomains.append(domain)
    return requestState
  }
}
