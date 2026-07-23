import Foundation
import Testing
@testable import AppleGatewayCore

// Exact regression terminology and test name follow issue #2.
// swiftlint:disable inclusive_language

private let liveEventKitRecurringMasterTestsEnabled =
  ProcessInfo.processInfo.environment["APPLE_GATEWAY_RUN_LIVE_EVENTKIT_TESTS"] == "1"

@Test(
  "live EventKit recurring master lookup in an isolated scratch calendar",
  .enabled(if: liveEventKitRecurringMasterTestsEnabled)
)
func liveEventKitRecurringMasterScratchCalendarRoundTrip() throws {
  let adapter = LiveEventKitCalendarReminderAdapter()
  let service = CalendarWriteService(
    calendarProvider: adapter,
    calendarWriter: adapter,
    remindersProvider: adapter,
    remindersWriter: adapter
  )
  let scratchCalendar = try service.createCalendar(
    CreateCalendarInput(title: "apple-gateway integration \(UUID().uuidString)")
  )
  defer {
    do {
      // Delete through the calendar-domain adapter directly: the service-level
      // deleteCalendar resolves ids across both domains and therefore needs
      // Reminders access, which this calendar-only test must not require.
      let cleanup = try adapter.deleteCalendar(calendarId: scratchCalendar.id)
      if !cleanup.success {
        Issue.record("Scratch-calendar cleanup reported failure: \(scratchCalendar.id)")
      }
    } catch {
      Issue.record(
        "Scratch-calendar cleanup failed for \(scratchCalendar.id): \(error)"
      )
    }
  }

  let day: TimeInterval = 86_400
  let startDate = Date(
    timeIntervalSince1970: floor(Date().addingTimeInterval(7 * day).timeIntervalSince1970)
  )
  let created = try service.createEvent(
    CreateEventInput(
      calendarId: scratchCalendar.id,
      title: "Recurring master integration",
      startDate: startDate,
      endDate: startDate.addingTimeInterval(3_600),
      timeZone: "UTC",
      recurrenceRules: [
        RecurrenceRule(frequency: .daily, interval: 1, occurrenceCount: 10)
      ]
    )
  )
  let masterId = created.id
  let deletedOccurrenceDate = startDate.addingTimeInterval(day)
  let detachedOccurrenceDate = startDate.addingTimeInterval(2 * day)
  let retainedOccurrenceDate = startDate.addingTimeInterval(3 * day)
  let futureOccurrenceDate = startDate.addingTimeInterval(4 * day)
  let laterFutureOccurrenceDate = startDate.addingTimeInterval(5 * day)
  let controlEvent = try service.createEvent(
    CreateEventInput(
      calendarId: scratchCalendar.id,
      title: "Unrelated integration control",
      startDate: laterFutureOccurrenceDate,
      endDate: laterFutureOccurrenceDate.addingTimeInterval(3_600),
      timeZone: "UTC"
    )
  )

  let deleted = try service.deleteEvent(
    eventId: masterId,
    span: .thisEvent,
    occurrenceDate: deletedOccurrenceDate
  )
  #expect(deleted.success)

  let movedStartDate = detachedOccurrenceDate.addingTimeInterval(-3 * day)
  _ = try service.updateEvent(
    UpdateEventInput(
      eventId: masterId,
      occurrenceDate: detachedOccurrenceDate,
      span: .thisEvent,
      title: "Moved detached occurrence",
      startDate: movedStartDate,
      endDate: movedStartDate.addingTimeInterval(3_600)
    )
  )
  let movedOccurrence = try #require(
    try adapter.event(eventId: masterId, occurrenceDate: detachedOccurrenceDate)
  )
  #expect(movedOccurrence.occurrenceDate == detachedOccurrenceDate)
  #expect(movedOccurrence.isDetached)
  #expect(movedOccurrence.startDate == movedStartDate)

  let futureDeleted = try service.deleteEvent(
    eventId: masterId,
    span: .futureEvents,
    occurrenceDate: futureOccurrenceDate
  )
  #expect(futureDeleted.success)

  let retainedOccurrence = try adapter.event(
    eventId: masterId,
    occurrenceDate: retainedOccurrenceDate
  )
  let removedCutoffOccurrence = try adapter.event(
    eventId: masterId,
    occurrenceDate: futureOccurrenceDate
  )
  let removedLaterOccurrence = try adapter.event(
    eventId: masterId,
    occurrenceDate: laterFutureOccurrenceDate
  )
  let retainedControl = try adapter.event(eventId: controlEvent.id, occurrenceDate: nil)

  #expect(retainedOccurrence != nil)
  #expect(removedCutoffOccurrence == nil)
  #expect(removedLaterOccurrence == nil)
  #expect(retainedControl?.id == controlEvent.id)
}

// swiftlint:enable inclusive_language
