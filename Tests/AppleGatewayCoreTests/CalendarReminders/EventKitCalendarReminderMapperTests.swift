import EventKit
import Foundation
import Testing
@testable import AppleGatewayCore

@Test func liveServiceFactoryUsesLiveAdapterWithoutTouchingStores() throws {
  let services = CalendarReminderServiceFactory.liveServices()
  #expect(containsLiveAdapter(services.readService))
  #expect(containsLiveAdapter(services.writeService))
}

@Test func calendarMappingPreservesIdentifierTitleAndDefaultStateWithoutSaving() {
  let store = EKEventStore()
  let calendar = EKCalendar(for: .event, eventStore: store)
  calendar.title = "Scratch"
  let mapped = EventKitCalendarReminderMapper.gatewayCalendar(
    calendar,
    entityType: .event,
    defaultCalendarId: calendar.calendarIdentifier
  )

  #expect(mapped.id == calendar.calendarIdentifier)
  #expect(mapped.title == "Scratch")
  #expect(mapped.entityType == .event)
  #expect(mapped.isDefault)
}

@Test func eventApplyPreservesTimezoneAndCollectionsWithoutSaving() throws {
  let store = EKEventStore()
  let calendar = EKCalendar(for: .event, eventStore: store)
  calendar.title = "Scratch"
  let event = CalendarEvent(
    id: "event-1",
    calendarId: "calendar-1",
    title: "Planning",
    notes: "Notes",
    location: "Office",
    url: "https://example.com/meeting",
    isAllDay: false,
    startDate: try date("2026-07-03T00:00:00Z"),
    endDate: try date("2026-07-04T00:00:00Z"),
    timeZone: "Asia/Tokyo",
    availability: .busy,
    alarms: [Alarm(relativeOffsetSeconds: -600)],
    recurrenceRules: [RecurrenceRule(frequency: .weekly, daysOfWeek: [2])]
  )
  let ekEvent = EKEvent(eventStore: store)

  try EventKitCalendarReminderMapper.apply(event, to: ekEvent, calendar: calendar)

  #expect(ekEvent.title == "Planning")
  #expect(ekEvent.timeZone?.identifier == "Asia/Tokyo")
  #expect(ekEvent.url?.absoluteString == "https://example.com/meeting")
  #expect(ekEvent.alarms?.count == 1)
  #expect(ekEvent.recurrenceRules?.count == 1)
}

@Test func eventApplyPreservesAllDayWithoutSaving() throws {
  let store = EKEventStore()
  let calendar = EKCalendar(for: .event, eventStore: store)
  calendar.title = "Scratch"
  let event = CalendarEvent(
    id: "event-1",
    calendarId: "calendar-1",
    title: "All day",
    isAllDay: true,
    startDate: try date("2026-07-03T00:00:00Z"),
    endDate: try date("2026-07-04T00:00:00Z")
  )
  let ekEvent = EKEvent(eventStore: store)

  try EventKitCalendarReminderMapper.apply(event, to: ekEvent, calendar: calendar)

  #expect(ekEvent.isAllDay)
}

@Test func reminderApplyPreservesDateOnlyDueDatesWithoutSaving() throws {
  let store = EKEventStore()
  let calendar = EKCalendar(for: .reminder, eventStore: store)
  calendar.title = "Scratch"
  let reminder = Reminder(
    id: "reminder-1",
    listId: "list-1",
    title: "Submit report",
    notes: "Notes",
    url: "https://example.com/report",
    priority: 5,
    dueDate: try date("2026-07-03T15:45:00Z"),
    dueDateHasTime: false,
    alarms: [Alarm(relativeOffsetSeconds: -300)],
    recurrenceRules: [RecurrenceRule(frequency: .daily, interval: 2)]
  )
  let ekReminder = EKReminder(eventStore: store)

  try EventKitCalendarReminderMapper.apply(reminder, to: ekReminder, calendar: calendar)

  #expect(ekReminder.title == "Submit report")
  #expect(ekReminder.priority == 5)
  #expect(ekReminder.url?.absoluteString == "https://example.com/report")
  #expect(ekReminder.dueDateComponents?.hour == nil)
  #expect(ekReminder.alarms?.count == 1)
  #expect(ekReminder.recurrenceRules?.count == 1)
}

@Test func alarmMappingRoundTripsRelativeAndAbsoluteTriggers() throws {
  let relative = try EventKitCalendarReminderMapper.makeAlarm(
    Alarm(relativeOffsetSeconds: -600)
  )
  #expect(EventKitCalendarReminderMapper.alarm(relative).relativeOffsetSeconds == -600)

  let absoluteDate = try date("2026-07-03T09:30:00Z")
  let absolute = try EventKitCalendarReminderMapper.makeAlarm(
    Alarm(absoluteDate: absoluteDate)
  )
  #expect(EventKitCalendarReminderMapper.alarm(absolute).absoluteDate == absoluteDate)
}

@Test func alarmMappingRejectsAmbiguousTriggers() throws {
  do {
    _ = try EventKitCalendarReminderMapper.makeAlarm(Alarm())
    Issue.record("Expected missing alarm trigger rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }

  do {
    _ = try EventKitCalendarReminderMapper.makeAlarm(
      Alarm(relativeOffsetSeconds: -60, absoluteDate: try date("2026-07-03T09:30:00Z"))
    )
    Issue.record("Expected ambiguous alarm trigger rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

@Test func recurrenceRuleMappingRoundTripsAdvancedFields() throws {
  let endDate = try date("2026-12-31T00:00:00Z")
  let rule = RecurrenceRule(
    frequency: .monthly,
    interval: 2,
    daysOfWeek: [2, 4],
    daysOfMonth: [1, -1],
    monthsOfYear: [1, 7],
    weeksOfYear: [1, -1],
    daysOfYear: [30, -30],
    setPositions: [1, -1],
    endDate: endDate
  )

  let mapped = EventKitCalendarReminderMapper.recurrenceRule(
    try EventKitCalendarReminderMapper.makeRecurrenceRule(rule)
  )

  #expect(mapped.frequency == .monthly)
  #expect(mapped.interval == 2)
  #expect(mapped.daysOfWeek == [2, 4])
  #expect(mapped.daysOfMonth == [1, -1])
  #expect(mapped.monthsOfYear == [1, 7])
  #expect(mapped.weeksOfYear == [1, -1])
  #expect(mapped.daysOfYear == [30, -30])
  #expect(mapped.setPositions == [1, -1])
  #expect(mapped.endDate == endDate)
  #expect(mapped.occurrenceCount == nil)
}

@Test func weeklyRecurrenceRuleMappingUsesNilForUnusedComponents() throws {
  let endDate = try date("2026-12-31T00:00:00Z")
  let rule = RecurrenceRule(
    frequency: .weekly,
    interval: 1,
    daysOfWeek: [3, 4],
    endDate: endDate
  )

  let ekRule = try EventKitCalendarReminderMapper.makeRecurrenceRule(rule)
  let roundTrip = EventKitCalendarReminderMapper.recurrenceRule(ekRule)
  let emptyRule = try EventKitCalendarReminderMapper.makeRecurrenceRule(
    RecurrenceRule(frequency: .daily)
  )

  #expect(ekRule.frequency == .weekly)
  #expect(ekRule.interval == 1)
  #expect(ekRule.daysOfTheWeek?.map { Int($0.dayOfTheWeek.rawValue) } == [3, 4])
  #expect(ekRule.daysOfTheMonth == nil)
  #expect(ekRule.monthsOfTheYear == nil)
  #expect(ekRule.weeksOfTheYear == nil)
  #expect(ekRule.daysOfTheYear == nil)
  #expect(ekRule.setPositions == nil)
  #expect(ekRule.recurrenceEnd?.endDate == endDate)
  #expect(emptyRule.daysOfTheWeek == nil)
  #expect(roundTrip == rule)
}

@Test func recurrenceRuleMappingRejectsInvalidWeekdays() throws {
  for value in [0, 8] {
    do {
      _ = try EventKitCalendarReminderMapper.makeRecurrenceRule(
        RecurrenceRule(frequency: .weekly, daysOfWeek: [value])
      )
      Issue.record("Expected invalid weekday rejection for \(value)")
    } catch let error as AppleGatewayError {
      #expect(error.code == .invalidArgument)
      #expect(error.details?["dayOfWeek"] == String(value))
    }
  }
}

@Test func recurrenceRuleMappingRejectsInvalidEndSemantics() throws {
  do {
    _ = try EventKitCalendarReminderMapper.makeRecurrenceRule(
      RecurrenceRule(frequency: .daily, interval: 0)
    )
    Issue.record("Expected invalid interval rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }

  do {
    _ = try EventKitCalendarReminderMapper.makeRecurrenceRule(
      RecurrenceRule(
        frequency: .daily,
        endDate: try date("2026-12-31T00:00:00Z"),
        occurrenceCount: 3
      )
    )
    Issue.record("Expected ambiguous recurrence end rejection")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

@Test func reminderDateComponentsPreserveDateOnlyFlag() throws {
  let dueDate = try date("2026-07-03T15:45:00Z")
  let dateOnlyComponents = EventKitCalendarReminderMapper.dateComponents(
    from: dueDate,
    hasTime: false
  )
  let timedComponents = EventKitCalendarReminderMapper.dateComponents(
    from: dueDate,
    hasTime: true
  )

  #expect(dateOnlyComponents?.year == timedComponents?.year)
  #expect(dateOnlyComponents?.month == timedComponents?.month)
  #expect(dateOnlyComponents?.day == timedComponents?.day)
  #expect(dateOnlyComponents?.hour == nil)
  #expect(timedComponents?.hour != nil)
}

private func date(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}

private func containsLiveAdapter(_ value: some Any) -> Bool {
  if value is LiveEventKitCalendarReminderAdapter {
    return true
  }
  return Mirror(reflecting: value).children.contains { child in
    containsLiveAdapter(child.value)
  }
}
