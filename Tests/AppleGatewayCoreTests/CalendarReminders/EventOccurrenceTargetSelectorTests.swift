import Foundation
import Testing
@testable import AppleGatewayCore

// Exact regression test names are part of the issue #2 verification contract.
// swiftlint:disable inclusive_language

@Test func detachedMasterIdMatchesResolvedSeriesIdentity() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let candidates = [
    selectorCandidate(
      eventIdentifiers: ["detached-event-id"],
      calendarItemIdentifiers: ["detached-calendar-item-id"],
      externalIdentifiers: ["series-external-id"],
      occurrenceDate: occurrenceDate
    )
  ]

  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(
      eventIdentifiers: ["master-id", "resolved-event-id"],
      calendarItemIdentifiers: ["master-calendar-item-id"],
      externalIdentifiers: ["series-external-id"]
    ),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: candidates
  )

  #expect(selection == .selected(index: 0, match: .external))
}

@Test func detachedMasterIdPrefersUniqueLocalIdentity() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(
      eventIdentifiers: ["master-id"],
      externalIdentifiers: ["series-external-id"]
    ),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["master-id"],
        externalIdentifiers: ["series-external-id"],
        occurrenceDate: occurrenceDate
      ),
      selectorCandidate(
        eventIdentifiers: ["other-event-id"],
        externalIdentifiers: ["series-external-id"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .selected(index: 0, match: .local))
}

@Test func detachedMasterIdMatchesRidSuffixedLocalIdentity() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(
      eventIdentifiers: ["calendar-uid:series-external-id"],
      calendarItemIdentifiers: ["master-calendar-item-id"],
      externalIdentifiers: ["series-external-id"]
    ),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["calendar-uid:series-external-id/RID=807279718"],
        calendarItemIdentifiers: ["detached-calendar-item-id"],
        externalIdentifiers: ["series-external-id/RID=807279718"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .selected(index: 0, match: .local))
}

@Test func detachedMasterIdMatchesRidSuffixedExternalIdentity() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(externalIdentifiers: ["series-external-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["detached-event-id"],
        externalIdentifiers: ["series-external-id/RID=807279718"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .selected(index: 0, match: .external))
}

@Test func detachedMasterIdRejectsRidSuffixOfDifferentSeries() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["calendar-uid:series-a"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["calendar-uid:series-b/RID=807279718"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdRejectsDifferentCalendar() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["resolved-series-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["resolved-series-id"],
        calendarId: "personal",
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdRejectsDifferentSeries() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["resolved-series-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["other-series-id"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdRejectsNonExactOccurrenceDate() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["resolved-series-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["resolved-series-id"],
        occurrenceDate: occurrenceDate.addingTimeInterval(1)
      )
    ]
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdDatedMissDoesNotUseMaster() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(
      eventIdentifiers: ["master-id", "resolved-series-id"]
    ),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: []
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdRejectsAmbiguousExternalIdentity() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(externalIdentifiers: ["series-external-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        eventIdentifiers: ["detached-a"],
        externalIdentifiers: ["series-external-id"],
        occurrenceDate: occurrenceDate
      ),
      selectorCandidate(
        eventIdentifiers: ["detached-b"],
        externalIdentifiers: ["series-external-id"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .ambiguous)
}

@Test func detachedMasterIdDoesNotCrossIdentifierCategories() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let selection = EventOccurrenceTargetSelector.select(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["opaque-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    candidates: [
      selectorCandidate(
        externalIdentifiers: ["opaque-id"],
        occurrenceDate: occurrenceDate
      )
    ]
  )

  #expect(selection == .notFound)
}

@Test func detachedMasterIdResolverReturnsUniqueNarrowExternalWithoutFallback() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  let fallbackWindows = EventOccurrenceSearchWindowPlanner.fallbackWindows(
    around: occurrenceDate
  )
  var requestedWindows: [EventOccurrenceSearchWindow] = []

  let resolution: EventOccurrenceResolution<String> = EventOccurrenceResolver.resolve(
    acceptedIdentity: selectorIdentity(externalIdentifiers: ["series-external-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    externalIdentityStatus: .unique,
    windows: [narrowWindow] + fallbackWindows,
    candidatesInWindow: { window in
      requestedWindows.append(window)
      guard window == narrowWindow else {
        return []
      }
      return [
        selectorSearchCandidate(
          value: "narrow-external",
          externalIdentifiers: ["series-external-id"],
          occurrenceDate: occurrenceDate
        )
      ]
    }
  )

  guard case let .selected(value) = resolution else {
    Issue.record("Expected a unique narrow external-identity selection")
    return
  }
  #expect(value == "narrow-external")
  #expect(requestedWindows == [narrowWindow])
}

@Test func detachedMasterIdResolverUsesBoundedFallbackForMovedOccurrence() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  let fallbackWindows = EventOccurrenceSearchWindowPlanner.fallbackWindows(
    around: occurrenceDate
  )
  let firstFallbackWindow = try #require(fallbackWindows.first)
  var requestedWindows: [EventOccurrenceSearchWindow] = []

  let resolution: EventOccurrenceResolution<String> = EventOccurrenceResolver.resolve(
    acceptedIdentity: selectorIdentity(externalIdentifiers: ["series-external-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    externalIdentityStatus: .unique,
    windows: [narrowWindow] + fallbackWindows,
    candidatesInWindow: { window in
      requestedWindows.append(window)
      guard window == firstFallbackWindow else {
        return []
      }
      return [
        selectorSearchCandidate(
          value: "moved-detached",
          externalIdentifiers: ["series-external-id"],
          occurrenceDate: occurrenceDate
        )
      ]
    }
  )

  guard case let .selected(value) = resolution else {
    Issue.record("Expected the first bounded fallback window to resolve the moved occurrence")
    return
  }
  #expect(value == "moved-detached")
  #expect(requestedWindows == [narrowWindow, firstFallbackWindow])
  #expect(firstFallbackWindow.endDate == narrowWindow.startDate)
  #expect(
    ([narrowWindow] + fallbackWindows).count
      <= EventOccurrenceSearchPolicy.defaultValue.maximumWindowCount
  )
}

@Test func detachedMasterIdResolverRejectsAmbiguousExternalSeries() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  let resolution: EventOccurrenceResolution<String> = EventOccurrenceResolver.resolve(
    acceptedIdentity: selectorIdentity(externalIdentifiers: ["series-external-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    externalIdentityStatus: .ambiguous,
    windows: [narrowWindow],
    candidatesInWindow: { _ in
      [
        selectorSearchCandidate(
          value: "unsafe-external",
          externalIdentifiers: ["series-external-id"],
          occurrenceDate: occurrenceDate
        )
      ]
    }
  )

  guard case .ambiguous = resolution else {
    Issue.record("Expected direct external-identity ambiguity to fail closed")
    return
  }
}

@Test func detachedMasterIdResolverStopsAtCandidateLimit() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  var requestedWindowCount = 0
  let resolution: EventOccurrenceResolution<String> = EventOccurrenceResolver.resolve(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["master-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    externalIdentityStatus: .unavailable,
    windows: [narrowWindow, narrowWindow],
    policy: EventOccurrenceSearchPolicy(maximumWindowCount: 2, maximumCandidateCount: 1),
    candidatesInWindow: { _ in
      requestedWindowCount += 1
      return [
        selectorSearchCandidate(
          value: "unrelated-a",
          eventIdentifiers: ["other-a"],
          occurrenceDate: occurrenceDate
        ),
        selectorSearchCandidate(
          value: "unrelated-b",
          eventIdentifiers: ["other-b"],
          occurrenceDate: occurrenceDate
        )
      ]
    }
  )

  guard case .resourceLimitExceeded = resolution else {
    Issue.record("Expected candidate-limit failure")
    return
  }
  #expect(requestedWindowCount == 1)
}

@Test func detachedMasterIdResolverStopsAtWindowLimit() throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  var requestedWindowCount = 0
  let resolution: EventOccurrenceResolution<String> = EventOccurrenceResolver.resolve(
    acceptedIdentity: selectorIdentity(eventIdentifiers: ["master-id"]),
    calendarId: "work",
    occurrenceDate: occurrenceDate,
    externalIdentityStatus: .unavailable,
    windows: [narrowWindow, narrowWindow],
    policy: EventOccurrenceSearchPolicy(maximumWindowCount: 1, maximumCandidateCount: 10),
    candidatesInWindow: { _ in
      requestedWindowCount += 1
      return []
    }
  )

  guard case .resourceLimitExceeded = resolution else {
    Issue.record("Expected window-limit failure")
    return
  }
  #expect(requestedWindowCount == 1)
}

@Test func detachedMasterIdResolverStopsWhenTaskCancelled() async throws {
  let occurrenceDate = try selectorDate("2026-07-10T09:00:00Z")
  let narrowWindow = EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)
  let task = Task { () -> EventOccurrenceResolution<String> in
    withUnsafeCurrentTask { $0?.cancel() }
    return EventOccurrenceResolver.resolve(
      acceptedIdentity: selectorIdentity(eventIdentifiers: ["master-id"]),
      calendarId: "work",
      occurrenceDate: occurrenceDate,
      externalIdentityStatus: .unavailable,
      windows: [narrowWindow],
      candidatesInWindow: { _ in
        Issue.record("Cancelled resolution must not query any window")
        return []
      }
    )
  }

  guard case .cancelled = await task.value else {
    Issue.record("Expected the resolver to short-circuit after task cancellation")
    return
  }
}

private func selectorCandidate(
  eventIdentifiers: Set<String> = [],
  calendarItemIdentifiers: Set<String> = [],
  externalIdentifiers: Set<String> = [],
  calendarId: String = "work",
  occurrenceDate: Date
) -> EventOccurrenceTargetCandidate {
  EventOccurrenceTargetCandidate(
    identity: selectorIdentity(
      eventIdentifiers: eventIdentifiers,
      calendarItemIdentifiers: calendarItemIdentifiers,
      externalIdentifiers: externalIdentifiers
    ),
    calendarId: calendarId,
    occurrenceDate: occurrenceDate
  )
}

private func selectorSearchCandidate<Value>(
  value: Value,
  eventIdentifiers: Set<String> = [],
  calendarItemIdentifiers: Set<String> = [],
  externalIdentifiers: Set<String> = [],
  calendarId: String = "work",
  occurrenceDate: Date
) -> EventOccurrenceSearchCandidate<Value> {
  EventOccurrenceSearchCandidate(
    target: selectorCandidate(
      eventIdentifiers: eventIdentifiers,
      calendarItemIdentifiers: calendarItemIdentifiers,
      externalIdentifiers: externalIdentifiers,
      calendarId: calendarId,
      occurrenceDate: occurrenceDate
    ),
    value: value
  )
}

private func selectorIdentity(
  eventIdentifiers: Set<String> = [],
  calendarItemIdentifiers: Set<String> = [],
  externalIdentifiers: Set<String> = []
) -> EventOccurrenceTargetIdentity {
  EventOccurrenceTargetIdentity(
    eventIdentifiers: eventIdentifiers,
    calendarItemIdentifiers: calendarItemIdentifiers,
    externalIdentifiers: externalIdentifiers
  )
}

private func selectorDate(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}

// swiftlint:enable inclusive_language
