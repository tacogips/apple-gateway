import Foundation
import Testing
@testable import AppleGatewayCore

@Test func updateEventWithOmittedFieldsLeavesExistingValuesUnchanged() throws {
  let calendarProvider = WriteCalendarProvider(
    calendars: [calendar(id: "work", entityType: .event, allowsModifications: true)],
    events: [
      event(
        id: "event-1",
        calendarId: "work",
        title: "Original",
        notes: "Keep notes",
        startDate: try date("2026-07-03T09:00:00Z"),
        alarms: [Alarm(relativeOffsetSeconds: -600)]
      )
    ]
  )
  let calendarWriter = WriteCalendarWriter()
  let service = writeService(calendarProvider: calendarProvider, calendarWriter: calendarWriter)

  let result = try service.updateEvent(UpdateEventInput(eventId: "event-1", title: "Updated"))
  let saved = try #require(calendarWriter.updatedEvents.last?.event)
  let expectedStart = try date("2026-07-03T09:00:00Z")

  #expect(result.title == "Updated")
  #expect(saved.title == "Updated")
  #expect(saved.notes == "Keep notes")
  #expect(saved.startDate == expectedStart)
  #expect(saved.alarms == [Alarm(relativeOffsetSeconds: -600)])
}

@Test func eventAlarmsAndRecurrenceRulesReplaceWhenPresent() throws {
  let calendarProvider = WriteCalendarProvider(
    calendars: [calendar(id: "work", entityType: .event, allowsModifications: true)],
    events: [
      event(
        id: "event-1",
        calendarId: "work",
        title: "Recurring",
        startDate: try date("2026-07-03T09:00:00Z"),
        alarms: [Alarm(relativeOffsetSeconds: -600)],
        recurrenceRules: [RecurrenceRule(frequency: .daily)]
      )
    ]
  )
  let calendarWriter = WriteCalendarWriter()
  let service = writeService(calendarProvider: calendarProvider, calendarWriter: calendarWriter)

  _ = try service.updateEvent(
    UpdateEventInput(
      eventId: "event-1",
      alarms: [],
      recurrenceRules: [RecurrenceRule(frequency: .weekly, interval: 2)]
    )
  )
  let saved = try #require(calendarWriter.updatedEvents.last?.event)

  #expect(saved.alarms.isEmpty)
  #expect(saved.recurrenceRules == [RecurrenceRule(frequency: .weekly, interval: 2)])
  #expect(saved.isRecurring)
}

@Test func readOnlyCalendarBlocksEventSaveBeforeWriterCall() throws {
  let calendarProvider = WriteCalendarProvider(
    calendars: [calendar(id: "readonly", entityType: .event, allowsModifications: false)],
    events: [
      event(
        id: "event-1",
        calendarId: "readonly",
        title: "Locked",
        startDate: try date("2026-07-03T09:00:00Z")
      )
    ]
  )
  let calendarWriter = WriteCalendarWriter()
  let service = writeService(calendarProvider: calendarProvider, calendarWriter: calendarWriter)

  do {
    _ = try service.updateEvent(UpdateEventInput(eventId: "event-1", title: "Should fail"))
    Issue.record("Expected read-only calendar failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .calendarReadOnly)
    #expect(error.details?["calendarId"] == "readonly")
    #expect(calendarWriter.updatedEvents.isEmpty)
    #expect(calendarWriter.createdEvents.isEmpty)
    #expect(calendarWriter.deletedEvents.isEmpty)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func eventSpanSemanticsArePassedToUpdateAndDelete() throws {
  let occurrence = try date("2026-07-10T09:00:00Z")
  let calendarProvider = WriteCalendarProvider(
    calendars: [calendar(id: "work", entityType: .event, allowsModifications: true)],
    events: [
      event(
        id: "event-1",
        calendarId: "work",
        title: "Series",
        startDate: try date("2026-07-03T09:00:00Z"),
        recurrenceRules: [RecurrenceRule(frequency: .weekly)]
      )
    ]
  )
  let calendarWriter = WriteCalendarWriter()
  let service = writeService(calendarProvider: calendarProvider, calendarWriter: calendarWriter)

  _ = try service.updateEvent(
    UpdateEventInput(
      eventId: "event-1",
      occurrenceDate: occurrence,
      span: .futureEvents,
      title: "Future"
    )
  )
  _ = try service.deleteEvent(eventId: "event-1", span: .futureEvents, occurrenceDate: occurrence)

  #expect(calendarWriter.updatedEvents.last?.span == .futureEvents)
  #expect(calendarWriter.updatedEvents.last?.occurrenceDate == occurrence)
  #expect(calendarWriter.deletedEvents.last?.span == .futureEvents)
  #expect(calendarWriter.deletedEvents.last?.occurrenceDate == occurrence)
}

@Test func updateReminderWithOmittedFieldsLeavesExistingValuesUnchanged() throws {
  let remindersProvider = WriteRemindersProvider(
    lists: [calendar(id: "list", entityType: .reminder, allowsModifications: true)],
    reminders: [
      reminder(
        id: "reminder-1",
        listId: "list",
        title: "Original",
        notes: "Keep notes",
        priority: 5,
        alarms: [Alarm(relativeOffsetSeconds: -300)]
      )
    ]
  )
  let remindersWriter = WriteRemindersWriter()
  let service = writeService(remindersProvider: remindersProvider, remindersWriter: remindersWriter)

  _ = try service.updateReminder(UpdateReminderInput(reminderId: "reminder-1", title: "Updated"))
  let saved = try #require(remindersWriter.updatedReminders.last)

  #expect(saved.title == "Updated")
  #expect(saved.notes == "Keep notes")
  #expect(saved.priority == 5)
  #expect(saved.alarms == [Alarm(relativeOffsetSeconds: -300)])
}

@Test func reminderAlarmsAndRecurrenceRulesReplaceWhenPresent() throws {
  let remindersProvider = WriteRemindersProvider(
    lists: [calendar(id: "list", entityType: .reminder, allowsModifications: true)],
    reminders: [
      reminder(
        id: "reminder-1",
        listId: "list",
        title: "Recurring",
        alarms: [Alarm(relativeOffsetSeconds: -300)],
        recurrenceRules: [RecurrenceRule(frequency: .daily)]
      )
    ]
  )
  let remindersWriter = WriteRemindersWriter()
  let service = writeService(remindersProvider: remindersProvider, remindersWriter: remindersWriter)

  _ = try service.updateReminder(
    UpdateReminderInput(
      reminderId: "reminder-1",
      alarms: [],
      recurrenceRules: [RecurrenceRule(frequency: .monthly)]
    )
  )
  let saved = try #require(remindersWriter.updatedReminders.last)

  #expect(saved.alarms.isEmpty)
  #expect(saved.recurrenceRules == [RecurrenceRule(frequency: .monthly)])
}

@Test func readOnlyReminderListBlocksSaveBeforeWriterCall() throws {
  let remindersProvider = WriteRemindersProvider(
    lists: [calendar(id: "readonly", entityType: .reminder, allowsModifications: false)],
    reminders: [
      reminder(id: "reminder-1", listId: "readonly", title: "Locked")
    ]
  )
  let remindersWriter = WriteRemindersWriter()
  let service = writeService(remindersProvider: remindersProvider, remindersWriter: remindersWriter)

  do {
    _ = try service.setReminderCompleted(reminderId: "reminder-1", completed: true)
    Issue.record("Expected read-only reminder list failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .calendarReadOnly)
    #expect(error.details?["calendarId"] == "readonly")
    #expect(remindersWriter.updatedReminders.isEmpty)
    #expect(remindersWriter.createdReminders.isEmpty)
    #expect(remindersWriter.deletedReminderIds.isEmpty)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private final class WriteCalendarProvider: CalendarProviding, @unchecked Sendable {
  var calendarsValue: [GatewayCalendar]
  var eventsValue: [CalendarEvent]

  init(calendars: [GatewayCalendar] = [], events: [CalendarEvent] = []) {
    calendarsValue = calendars
    eventsValue = events
  }

  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    calendarsValue.filter { entityType == nil || $0.entityType == entityType }
  }

  func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    eventsValue
  }

  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    eventsValue.first { $0.id == eventId }
  }
}

private final class WriteCalendarWriter: CalendarWriting, @unchecked Sendable {
  private(set) var createdCalendars: [CreateCalendarInput] = []
  private(set) var deletedCalendarIds: [String] = []
  private(set) var createdEvents: [CalendarEvent] = []
  private(set) var updatedEvents: [CalendarEventSaveRequest] = []
  private(set) var deletedEvents: [CalendarEventDeleteRequest] = []

  func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    createdCalendars.append(input)
    return calendar(id: "calendar-created", title: input.title, entityType: .event, allowsModifications: true)
  }

  func deleteCalendar(calendarId: String) throws -> DeleteResult {
    deletedCalendarIds.append(calendarId)
    return DeleteResult(success: true)
  }

  func createEvent(_ event: CalendarEvent) throws -> CalendarEvent {
    createdEvents.append(event)
    var created = event
    created.id = "event-created"
    return created
  }

  func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent {
    updatedEvents.append(request)
    return request.event
  }

  func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult {
    deletedEvents.append(request)
    return DeleteResult(success: true)
  }
}

private struct WriteRemindersProvider: RemindersProviding {
  var lists: [GatewayCalendar]
  var remindersValue: [Reminder]

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

private final class WriteRemindersWriter: RemindersWriting, @unchecked Sendable {
  private(set) var createdLists: [CreateReminderListInput] = []
  private(set) var createdReminders: [Reminder] = []
  private(set) var updatedReminders: [Reminder] = []
  private(set) var deletedReminderIds: [String] = []

  func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    createdLists.append(input)
    return calendar(id: "list-created", title: input.title, entityType: .reminder, allowsModifications: true)
  }

  func createReminder(_ reminder: Reminder) throws -> Reminder {
    createdReminders.append(reminder)
    var created = reminder
    created.id = "reminder-created"
    return created
  }

  func updateReminder(_ reminder: Reminder) throws -> Reminder {
    updatedReminders.append(reminder)
    return reminder
  }

  func deleteReminder(reminderId: String) throws -> DeleteResult {
    deletedReminderIds.append(reminderId)
    return DeleteResult(success: true)
  }
}

private func writeService(
  calendarProvider: WriteCalendarProvider = WriteCalendarProvider(),
  calendarWriter: WriteCalendarWriter = WriteCalendarWriter(),
  remindersProvider: WriteRemindersProvider = WriteRemindersProvider(),
  remindersWriter: WriteRemindersWriter = WriteRemindersWriter()
) -> CalendarWriteService {
  CalendarWriteService(
    calendarProvider: calendarProvider,
    calendarWriter: calendarWriter,
    remindersProvider: remindersProvider,
    remindersWriter: remindersWriter
  )
}

private func calendar(
  id: String,
  title: String = "Calendar",
  entityType: CalendarEntityType,
  allowsModifications: Bool,
  isDefault: Bool = true
) -> GatewayCalendar {
  GatewayCalendar(
    id: id,
    title: title,
    entityType: entityType,
    sourceTitle: "iCloud",
    sourceType: "caldav",
    allowsModifications: allowsModifications,
    isSubscribed: false,
    isDefault: isDefault
  )
}

private func event(
  id: String,
  calendarId: String,
  title: String,
  notes: String? = nil,
  startDate: Date,
  alarms: [Alarm] = [],
  recurrenceRules: [RecurrenceRule] = []
) -> CalendarEvent {
  CalendarEvent(
    id: id,
    calendarId: calendarId,
    title: title,
    notes: notes,
    startDate: startDate,
    endDate: startDate.addingTimeInterval(3600),
    alarms: alarms,
    recurrenceRules: recurrenceRules,
    isRecurring: !recurrenceRules.isEmpty
  )
}

private func reminder(
  id: String,
  listId: String,
  title: String,
  notes: String? = nil,
  priority: Int = 0,
  alarms: [Alarm] = [],
  recurrenceRules: [RecurrenceRule] = []
) -> Reminder {
  Reminder(
    id: id,
    listId: listId,
    title: title,
    notes: notes,
    priority: priority,
    alarms: alarms,
    recurrenceRules: recurrenceRules
  )
}

private func date(_ value: String) throws -> Date {
  try EventKitDateTime.parse(value)
}
