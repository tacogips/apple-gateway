import Foundation
import Testing
@testable import AppleGatewayCore

@Test func eventsRequireStartAndEndDates() throws {
  let service = CalendarReadService(
    calendarProvider: StaticCalendarProvider(),
    remindersProvider: StaticRemindersProvider()
  )

  do {
    _ = try service.events(input: EventSearchInput(startDate: date("2026-01-01T00:00:00Z")))
    Issue.record("Expected missing end date failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
    #expect(error.message.contains("startDate and endDate"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func eventRangesOverFourYearsChunkIntoProviderWindows() throws {
  let provider = StaticCalendarProvider(
    eventsByWindow: { window in
      [
        event(
          id: EventKitDateTime.format(window.startDate, timeZone: TimeZone(secondsFromGMT: 0) ?? .current),
          calendarId: "work",
          title: "Chunk",
          startDate: window.startDate,
          endDate: window.endDate
        )
      ]
    }
  )
  let service = CalendarReadService(
    calendarProvider: provider,
    remindersProvider: StaticRemindersProvider()
  )

  let result = try service.events(
    input: EventSearchInput(
      calendarIds: ["work"],
      startDate: date("2020-01-01T00:00:00Z"),
      endDate: date("2029-01-01T00:00:00Z")
    )
  )

  let expectedStart = try date("2020-01-01T00:00:00Z")
  let expectedFirstEnd = try date("2024-01-01T00:00:00Z")
  let expectedSecondEnd = try date("2028-01-01T00:00:00Z")
  let expectedThirdEnd = try date("2029-01-01T00:00:00Z")

  #expect(provider.capturedWindows.count == 3)
  #expect(provider.capturedWindows.map(\.calendarIds) == [["work"], ["work"], ["work"]])
  #expect(provider.capturedWindows[0].startDate == expectedStart)
  #expect(provider.capturedWindows[0].endDate == expectedFirstEnd)
  #expect(provider.capturedWindows[1].endDate == expectedSecondEnd)
  #expect(provider.capturedWindows[2].endDate == expectedThirdEnd)
  #expect(result.totalCount == 3)
}

@Test func eventPaginationIsStableAndReportsTotalCountAndEndCursor() throws {
  let events = [
    event(id: "later", calendarId: "work", title: "Design", startDate: try date("2026-01-03T09:00:00Z")),
    event(id: "other", calendarId: "home", title: "Design", startDate: try date("2026-01-01T09:00:00Z")),
    event(id: "first", calendarId: "work", title: "Alpha design", startDate: try date("2026-01-01T09:00:00Z")),
    event(
      id: "middle",
      calendarId: "work",
      title: "Beta",
      notes: "contains design note",
      startDate: try date("2026-01-02T09:00:00Z")
    ),
    event(id: "skip", calendarId: "work", title: "No match", startDate: try date("2026-01-04T09:00:00Z"))
  ]
  let service = CalendarReadService(
    calendarProvider: StaticCalendarProvider(events: events),
    remindersProvider: StaticRemindersProvider(),
    limits: testLimits(defaultPageSize: 2, maxPageSize: 10)
  )

  let firstPage = try service.events(
    input: EventSearchInput(
      calendarIds: ["work"],
      startDate: date("2026-01-01T00:00:00Z"),
      endDate: date("2026-01-05T00:00:00Z"),
      query: "design",
      first: 2
    )
  )
  let secondPage = try service.events(
    input: EventSearchInput(
      calendarIds: ["work"],
      startDate: date("2026-01-01T00:00:00Z"),
      endDate: date("2026-01-05T00:00:00Z"),
      query: "design",
      first: 2,
      after: firstPage.pageInfo.endCursor
    )
  )

  #expect(firstPage.totalCount == 3)
  #expect(firstPage.edges.map(\.node.id) == ["first", "middle"])
  #expect(firstPage.pageInfo.hasNextPage)
  #expect(firstPage.pageInfo.endCursor != nil)
  #expect(secondPage.edges.map(\.node.id) == ["later"])
  #expect(!secondPage.pageInfo.hasNextPage)
  #expect(secondPage.totalCount == 3)
}

@Test func invalidEventFiltersFailInvalidArgument() throws {
  let service = CalendarReadService(
    calendarProvider: StaticCalendarProvider(),
    remindersProvider: StaticRemindersProvider()
  )

  do {
    _ = try service.events(
      input: EventSearchInput(
        startDate: date("2026-01-02T00:00:00Z"),
        endDate: date("2026-01-01T00:00:00Z")
      )
    )
    Issue.record("Expected invalid date range")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func reminderFilteringSortingAndPaginationMatchSpec() throws {
  let reminders = [
    reminder(id: "none", title: "No date", dueDate: nil),
    reminder(id: "done", title: "Design done", isCompleted: true, dueDate: try date("2026-01-02T09:00:00Z")),
    reminder(id: "later", title: "Design later", dueDate: try date("2026-01-03T09:00:00Z")),
    reminder(id: "early", title: "Design early", dueDate: try date("2026-01-01T09:00:00Z")),
    reminder(id: "skip-list", listId: "other", title: "Design other", dueDate: try date("2026-01-01T08:00:00Z")),
    reminder(id: "skip-query", title: "Groceries", dueDate: try date("2026-01-01T07:00:00Z"))
  ]
  let service = CalendarReadService(
    calendarProvider: StaticCalendarProvider(),
    remindersProvider: StaticRemindersProvider(reminders: reminders),
    limits: testLimits(defaultPageSize: 2, maxPageSize: 10)
  )

  let firstPage = try service.reminders(
    input: ReminderSearchInput(
      listIds: ["list"],
      status: .incomplete,
      dueAfter: date("2026-01-01T00:00:00Z"),
      dueBefore: date("2026-01-04T00:00:00Z"),
      query: "design",
      first: 2
    )
  )
  let secondPage = try service.reminders(
    input: ReminderSearchInput(
      listIds: ["list"],
      status: .incomplete,
      dueAfter: date("2026-01-01T00:00:00Z"),
      dueBefore: date("2026-01-04T00:00:00Z"),
      query: "design",
      first: 2,
      after: firstPage.pageInfo.endCursor
    )
  )

  #expect(firstPage.totalCount == 2)
  #expect(firstPage.edges.map(\.node.id) == ["early", "later"])
  #expect(!firstPage.pageInfo.hasNextPage)
  #expect(secondPage.edges.isEmpty)
  #expect(secondPage.totalCount == 2)
}

@Test func invalidReminderFiltersFailInvalidArgument() throws {
  let service = CalendarReadService(
    calendarProvider: StaticCalendarProvider(),
    remindersProvider: StaticRemindersProvider()
  )

  do {
    _ = try service.reminders(
      input: ReminderSearchInput(
        dueAfter: date("2026-01-03T00:00:00Z"),
        dueBefore: date("2026-01-02T00:00:00Z")
      )
    )
    Issue.record("Expected invalid due range")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private final class StaticCalendarProvider: CalendarProviding, @unchecked Sendable {
  private let calendarsValue: [GatewayCalendar]
  private let eventsValue: [CalendarEvent]
  private let eventsByWindow: (EventFetchWindow) -> [CalendarEvent]
  private(set) var capturedWindows: [EventFetchWindow] = []

  init(
    calendars: [GatewayCalendar] = [],
    events: [CalendarEvent] = [],
    eventsByWindow: @escaping (EventFetchWindow) -> [CalendarEvent] = { _ in [] }
  ) {
    calendarsValue = calendars
    eventsValue = events
    self.eventsByWindow = eventsByWindow
  }

  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    calendarsValue.filter { entityType == nil || $0.entityType == entityType }
  }

  func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    capturedWindows.append(window)
    let windowEvents = eventsByWindow(window)
    if !windowEvents.isEmpty {
      return windowEvents
    }
    return eventsValue
  }

  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    eventsValue.first { $0.id == eventId }
  }
}

private struct StaticRemindersProvider: RemindersProviding {
  var lists: [GatewayCalendar] = []
  var remindersValue: [Reminder] = []

  init(lists: [GatewayCalendar] = [], reminders: [Reminder] = []) {
    self.lists = lists
    remindersValue = reminders
  }

  func reminderLists() throws -> [GatewayCalendar] {
    lists
  }

  func reminders() throws -> [Reminder] {
    remindersValue
  }

  func reminder(reminderId: String) throws -> Reminder? {
    remindersValue.first { $0.id == reminderId }
  }
}

private func event(
  id: String,
  calendarId: String,
  title: String,
  notes: String? = nil,
  startDate: Date,
  endDate: Date? = nil
) -> CalendarEvent {
  CalendarEvent(
    id: id,
    calendarId: calendarId,
    title: title,
    notes: notes,
    startDate: startDate,
    endDate: endDate ?? startDate.addingTimeInterval(3600)
  )
}

private func reminder(
  id: String,
  listId: String = "list",
  title: String,
  isCompleted: Bool = false,
  dueDate: Date?
) -> Reminder {
  Reminder(
    id: id,
    listId: listId,
    title: title,
    isCompleted: isCompleted,
    dueDate: dueDate
  )
}

private func date(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}

private func testLimits(defaultPageSize: Int, maxPageSize: Int) -> AppleGatewayConfig.Limits {
  AppleGatewayConfig.Limits(
    defaultPageSize: defaultPageSize,
    maxPageSize: maxPageSize,
    maxInlineBodyBytes: 65_536,
    appleEventTimeoutSeconds: 30,
    appleEventBatchSize: 50
  )
}
