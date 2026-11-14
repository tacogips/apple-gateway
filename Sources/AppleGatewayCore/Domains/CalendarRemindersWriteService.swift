import Foundation

public struct CalendarWriteService: Sendable {
  private let calendarProvider: any CalendarProviding
  private let calendarWriter: any CalendarWriting
  private let remindersProvider: any RemindersProviding
  private let remindersWriter: any RemindersWriting

  public init(
    calendarProvider: any CalendarProviding,
    calendarWriter: any CalendarWriting,
    remindersProvider: any RemindersProviding,
    remindersWriter: any RemindersWriting
  ) {
    self.calendarProvider = calendarProvider
    self.calendarWriter = calendarWriter
    self.remindersProvider = remindersProvider
    self.remindersWriter = remindersWriter
  }

  public func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    try calendarWriter.createCalendar(input)
  }

  public func deleteCalendar(calendarId: String) throws -> DeleteResult {
    let calendar = try calendar(id: calendarId, entityType: nil)
    try ensureWritable(calendar)
    return try calendarWriter.deleteCalendar(calendarId: calendarId)
  }

  public func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    try remindersWriter.createReminderList(input)
  }

  public func createEvent(_ input: CreateEventInput) throws -> CalendarEvent {
    let targetCalendar = try input.calendarId.map {
      try calendar(id: $0, entityType: .event)
    } ?? defaultCalendar(entityType: .event)
    try ensureWritable(targetCalendar)
    let event = CalendarEvent(
      id: "",
      calendarId: targetCalendar.id,
      title: input.title,
      notes: input.notes,
      location: input.location,
      url: input.url,
      isAllDay: input.isAllDay,
      startDate: input.startDate,
      endDate: input.endDate,
      timeZone: input.timeZone,
      availability: input.availability ?? .notSupported,
      alarms: input.alarms ?? [],
      recurrenceRules: input.recurrenceRules ?? [],
      isRecurring: !(input.recurrenceRules ?? []).isEmpty
    )
    return try calendarWriter.createEvent(event)
  }

  public func updateEvent(_ input: UpdateEventInput) throws -> CalendarEvent {
    let current = try existingEvent(id: input.eventId, occurrenceDate: input.occurrenceDate)
    let targetCalendarId = input.calendarId ?? current.calendarId
    let targetCalendar = try calendar(id: targetCalendarId, entityType: .event)
    try ensureWritable(targetCalendar)
    let updated = apply(input, to: current, targetCalendarId: targetCalendarId)
    return try calendarWriter.updateEvent(
      CalendarEventSaveRequest(
        event: updated,
        span: input.span,
        occurrenceDate: input.occurrenceDate
      )
    )
  }

  public func deleteEvent(
    eventId: String,
    span: RecurrenceSpan = .thisEvent,
    occurrenceDate: Date? = nil
  ) throws -> DeleteResult {
    let current = try existingEvent(id: eventId, occurrenceDate: occurrenceDate)
    let targetCalendar = try calendar(id: current.calendarId, entityType: .event)
    try ensureWritable(targetCalendar)
    return try calendarWriter.deleteEvent(
      CalendarEventDeleteRequest(eventId: eventId, span: span, occurrenceDate: occurrenceDate)
    )
  }

  public func setEventAlarms(
    eventId: String,
    alarms: [Alarm],
    span: RecurrenceSpan = .thisEvent,
    occurrenceDate: Date? = nil
  ) throws -> CalendarEvent {
    try updateEvent(
      UpdateEventInput(
        eventId: eventId,
        occurrenceDate: occurrenceDate,
        span: span,
        alarms: alarms
      )
    )
  }

  public func createReminder(_ input: CreateReminderInput) throws -> Reminder {
    let targetList = try input.listId.map {
      try calendar(id: $0, entityType: .reminder)
    } ?? defaultCalendar(entityType: .reminder)
    try ensureWritable(targetList)
    let reminder = Reminder(
      id: "",
      listId: targetList.id,
      title: input.title,
      notes: input.notes,
      url: input.url,
      priority: input.priority,
      startDate: input.startDate,
      dueDate: input.dueDate,
      dueDateHasTime: input.dueDateHasTime,
      alarms: input.alarms ?? [],
      recurrenceRules: input.recurrenceRules ?? []
    )
    return try remindersWriter.createReminder(reminder)
  }

  public func updateReminder(_ input: UpdateReminderInput) throws -> Reminder {
    let current = try existingReminder(id: input.reminderId)
    let targetListId = input.listId ?? current.listId
    let targetList = try calendar(id: targetListId, entityType: .reminder)
    try ensureWritable(targetList)
    let updated = apply(input, to: current, targetListId: targetListId)
    return try remindersWriter.updateReminder(updated)
  }

  public func deleteReminder(reminderId: String) throws -> DeleteResult {
    let current = try existingReminder(id: reminderId)
    let targetList = try calendar(id: current.listId, entityType: .reminder)
    try ensureWritable(targetList)
    return try remindersWriter.deleteReminder(reminderId: reminderId)
  }

  public func setReminderCompleted(reminderId: String, completed: Bool) throws -> Reminder {
    var current = try existingReminder(id: reminderId)
    let targetList = try calendar(id: current.listId, entityType: .reminder)
    try ensureWritable(targetList)
    current.isCompleted = completed
    current.completionDate = completed ? Date() : nil
    return try remindersWriter.updateReminder(current)
  }

  public func setReminderAlarms(reminderId: String, alarms: [Alarm]) throws -> Reminder {
    try updateReminder(UpdateReminderInput(reminderId: reminderId, alarms: alarms))
  }

  private func apply(
    _ input: UpdateEventInput,
    to current: CalendarEvent,
    targetCalendarId: String
  ) -> CalendarEvent {
    var updated = current
    updated.calendarId = targetCalendarId
    updated.title = input.title ?? updated.title
    updated.startDate = input.startDate ?? updated.startDate
    updated.endDate = input.endDate ?? updated.endDate
    updated.isAllDay = input.isAllDay ?? updated.isAllDay
    updated.notes = input.notes ?? updated.notes
    updated.location = input.location ?? updated.location
    updated.url = input.url ?? updated.url
    updated.timeZone = input.timeZone ?? updated.timeZone
    updated.availability = input.availability ?? updated.availability
    if let alarms = input.alarms {
      updated.alarms = alarms
    }
    if let recurrenceRules = input.recurrenceRules {
      updated.recurrenceRules = recurrenceRules
      updated.isRecurring = !recurrenceRules.isEmpty
    }
    return updated
  }

  private func apply(
    _ input: UpdateReminderInput,
    to current: Reminder,
    targetListId: String
  ) -> Reminder {
    var updated = current
    updated.listId = targetListId
    updated.title = input.title ?? updated.title
    updated.notes = input.notes ?? updated.notes
    updated.url = input.url ?? updated.url
    updated.priority = input.priority ?? updated.priority
    updated.startDate = input.startDate ?? updated.startDate
    updated.dueDate = input.dueDate ?? updated.dueDate
    updated.dueDateHasTime = input.dueDateHasTime ?? updated.dueDateHasTime
    if let alarms = input.alarms {
      updated.alarms = alarms
    }
    if let recurrenceRules = input.recurrenceRules {
      updated.recurrenceRules = recurrenceRules
    }
    return updated
  }

  private func existingEvent(id: String, occurrenceDate: Date?) throws -> CalendarEvent {
    guard let event = try calendarProvider.event(eventId: id, occurrenceDate: occurrenceDate) else {
      throw AppleGatewayError(
        code: .eventNotFound,
        message: "Event not found",
        details: ["eventId": id]
      )
    }
    return event
  }

  private func existingReminder(id: String) throws -> Reminder {
    guard let reminder = try remindersProvider.reminder(reminderId: id) else {
      throw AppleGatewayError(
        code: .reminderNotFound,
        message: "Reminder not found",
        details: ["reminderId": id]
      )
    }
    return reminder
  }

  private func defaultCalendar(entityType: CalendarEntityType) throws -> GatewayCalendar {
    let calendars = try calendars(entityType: entityType)
    if let defaultCalendar = calendars.first(where: \.isDefault) {
      return defaultCalendar
    }
    guard let first = calendars.first else {
      throw AppleGatewayError(
        code: .calendarNotFound,
        message: "Default calendar not found",
        details: ["entityType": entityType.rawValue]
      )
    }
    return first
  }

  private func calendar(id: String, entityType: CalendarEntityType?) throws -> GatewayCalendar {
    guard let calendar = try calendars(entityType: entityType).first(where: { $0.id == id }) else {
      throw AppleGatewayError(
        code: .calendarNotFound,
        message: "Calendar not found",
        details: ["calendarId": id]
      )
    }
    return calendar
  }

  private func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    switch entityType {
    case .event:
      return try calendarProvider.calendars(entityType: .event)
    case .reminder:
      return try remindersProvider.reminderLists()
    case nil:
      return try calendarProvider.calendars(entityType: nil) + remindersProvider.reminderLists()
    }
  }

  private func ensureWritable(_ calendar: GatewayCalendar) throws {
    guard calendar.allowsModifications else {
      throw AppleGatewayError(
        code: .calendarReadOnly,
        message: "Calendar is read-only",
        details: ["calendarId": calendar.id]
      )
    }
  }
}
