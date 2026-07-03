import EventKit
import Foundation

public final class LiveEventKitCalendarReminderAdapter: CalendarProviding, CalendarWriting,
  RemindersProviding, RemindersWriting, @unchecked Sendable {
  private let store: EKEventStore
  private let session: EventKitSession
  private let lock = NSRecursiveLock()

  public init(store: EKEventStore = EKEventStore()) {
    self.store = store
    session = EventKitSession(access: LiveEventKitStoreAccess(store: store))
  }

  public func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    try lock.withLock {
      switch entityType {
      case .event:
        return try eventCalendars()
      case .reminder:
        return try reminderCalendars()
      case nil:
        return try eventCalendars() + reminderCalendars()
      }
    }
  }

  public func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      let calendars = try eventCalendars(ids: window.calendarIds)
      let predicate = store.predicateForEvents(
        withStart: window.startDate,
        end: window.endDate,
        calendars: calendars.nilIfEmpty
      )
      return store.events(matching: predicate).map(EventKitCalendarReminderMapper.calendarEvent)
    }
  }

  public func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      if let occurrenceDate {
        return try eventOccurrence(eventId: eventId, occurrenceDate: occurrenceDate)
          .map(EventKitCalendarReminderMapper.calendarEvent)
      }
      return store.event(withIdentifier: eventId).map(EventKitCalendarReminderMapper.calendarEvent)
    }
  }

  public func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = input.title
      calendar.source = try source(entityType: .event, preferredTitle: input.sourceTitle)
      try store.saveCalendar(calendar, commit: true)
      return EventKitCalendarReminderMapper.gatewayCalendar(
        calendar,
        entityType: .event,
        defaultCalendarId: store.defaultCalendarForNewEvents?.calendarIdentifier
      )
    }
  }

  public func deleteCalendar(calendarId: String) throws -> DeleteResult {
    try lock.withLock {
      let calendar = try calendarForDeletion(calendarId: calendarId)
      try store.removeCalendar(calendar, commit: true)
      return DeleteResult(success: true)
    }
  }

  public func createEvent(_ event: CalendarEvent) throws -> CalendarEvent {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      let calendar = try eventCalendar(id: event.calendarId)
      let ekEvent = EKEvent(eventStore: store)
      try EventKitCalendarReminderMapper.apply(event, to: ekEvent, calendar: calendar)
      try store.save(ekEvent, span: .thisEvent, commit: true)
      return EventKitCalendarReminderMapper.calendarEvent(ekEvent)
    }
  }

  public func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      let ekEvent = try existingEvent(id: request.event.id, occurrenceDate: request.occurrenceDate)
      let calendar = try eventCalendar(id: request.event.calendarId)
      try EventKitCalendarReminderMapper.apply(request.event, to: ekEvent, calendar: calendar)
      try store.save(
        ekEvent,
        span: EventKitCalendarReminderMapper.ekSpan(request.span),
        commit: true
      )
      return EventKitCalendarReminderMapper.calendarEvent(ekEvent)
    }
  }

  public func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult {
    try lock.withLock {
      try session.ensureReadAccess(for: .calendar)
      let ekEvent = try existingEvent(id: request.eventId, occurrenceDate: request.occurrenceDate)
      try store.remove(
        ekEvent,
        span: EventKitCalendarReminderMapper.ekSpan(request.span),
        commit: true
      )
      return DeleteResult(success: true)
    }
  }

  public func reminderLists() throws -> [GatewayCalendar] {
    try lock.withLock {
      try reminderCalendars()
    }
  }

  public func reminders() throws -> [Reminder] {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      let predicate = store.predicateForReminders(in: nil)
      return try fetchReminders(matching: predicate).map(EventKitCalendarReminderMapper.reminder)
    }
  }

  public func reminder(reminderId: String) throws -> Reminder? {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      return (store.calendarItem(withIdentifier: reminderId) as? EKReminder)
        .map(EventKitCalendarReminderMapper.reminder)
    }
  }

  public func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      let calendar = EKCalendar(for: .reminder, eventStore: store)
      calendar.title = input.title
      calendar.source = try source(entityType: .reminder, preferredTitle: input.sourceTitle)
      try store.saveCalendar(calendar, commit: true)
      return EventKitCalendarReminderMapper.gatewayCalendar(
        calendar,
        entityType: .reminder,
        defaultCalendarId: store.defaultCalendarForNewReminders()?.calendarIdentifier
      )
    }
  }

  public func createReminder(_ reminder: Reminder) throws -> Reminder {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      let calendar = try reminderCalendar(id: reminder.listId)
      let ekReminder = EKReminder(eventStore: store)
      try EventKitCalendarReminderMapper.apply(reminder, to: ekReminder, calendar: calendar)
      try store.save(ekReminder, commit: true)
      return EventKitCalendarReminderMapper.reminder(ekReminder)
    }
  }

  public func updateReminder(_ reminder: Reminder) throws -> Reminder {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      let ekReminder = try existingReminder(id: reminder.id)
      let calendar = try reminderCalendar(id: reminder.listId)
      try EventKitCalendarReminderMapper.apply(reminder, to: ekReminder, calendar: calendar)
      try store.save(ekReminder, commit: true)
      return EventKitCalendarReminderMapper.reminder(ekReminder)
    }
  }

  public func deleteReminder(reminderId: String) throws -> DeleteResult {
    try lock.withLock {
      try session.ensureReadAccess(for: .reminders)
      let ekReminder = try existingReminder(id: reminderId)
      try store.remove(ekReminder, commit: true)
      return DeleteResult(success: true)
    }
  }

  private func eventCalendars() throws -> [GatewayCalendar] {
    try session.ensureReadAccess(for: .calendar)
    let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
    return store.calendars(for: .event)
      .map {
        EventKitCalendarReminderMapper.gatewayCalendar(
          $0,
          entityType: .event,
          defaultCalendarId: defaultId
        )
      }
  }

  private func reminderCalendars() throws -> [GatewayCalendar] {
    try session.ensureReadAccess(for: .reminders)
    let defaultId = store.defaultCalendarForNewReminders()?.calendarIdentifier
    return store.calendars(for: .reminder)
      .map {
        EventKitCalendarReminderMapper.gatewayCalendar(
          $0,
          entityType: .reminder,
          defaultCalendarId: defaultId
        )
      }
  }

  private func eventCalendars(ids: [String]) throws -> [EKCalendar] {
    guard !ids.isEmpty else {
      return []
    }
    return try ids.map { try eventCalendar(id: $0) }
  }

  private func eventCalendar(id: String) throws -> EKCalendar {
    try session.ensureReadAccess(for: .calendar)
    guard
      let calendar = store.calendar(withIdentifier: id),
      calendar.allowedEntityTypes.contains(.event)
    else {
      throw AppleGatewayError(
        code: .calendarNotFound,
        message: "Calendar not found",
        details: ["calendarId": id]
      )
    }
    return calendar
  }

  private func reminderCalendar(id: String) throws -> EKCalendar {
    try session.ensureReadAccess(for: .reminders)
    guard
      let calendar = store.calendar(withIdentifier: id),
      calendar.allowedEntityTypes.contains(.reminder)
    else {
      throw AppleGatewayError(
        code: .calendarNotFound,
        message: "Reminder list not found",
        details: ["calendarId": id]
      )
    }
    return calendar
  }

  private func calendarForDeletion(calendarId: String) throws -> EKCalendar {
    do {
      return try eventCalendar(id: calendarId)
    } catch let eventError as AppleGatewayError where eventError.code == .calendarNotFound {
      return try reminderCalendar(id: calendarId)
    }
  }

  private func existingEvent(id: String, occurrenceDate: Date?) throws -> EKEvent {
    if let occurrenceDate, let event = try eventOccurrence(eventId: id, occurrenceDate: occurrenceDate) {
      return event
    }
    if let event = store.event(withIdentifier: id) {
      return event
    }
    throw AppleGatewayError(code: .eventNotFound, message: "Event not found", details: ["eventId": id])
  }

  private func eventOccurrence(eventId: String, occurrenceDate: Date) throws -> EKEvent? {
    let startDate = occurrenceDate.addingTimeInterval(-86_400)
    let endDate = occurrenceDate.addingTimeInterval(86_400)
    let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
    return store.events(matching: predicate).first { event in
      event.eventIdentifier == eventId && event.occurrenceDate == occurrenceDate
    }
  }

  private func existingReminder(id: String) throws -> EKReminder {
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw AppleGatewayError(code: .reminderNotFound, message: "Reminder not found", details: ["reminderId": id])
    }
    return reminder
  }

  private func source(entityType: EKEntityType, preferredTitle: String?) throws -> EKSource {
    if let preferredTitle,
       let source = store.sources.first(where: { $0.title == preferredTitle && !$0.calendars(for: entityType).isEmpty }) {
      return source
    }
    if entityType == .event, let source = store.defaultCalendarForNewEvents?.source {
      return source
    }
    if entityType == .reminder, let source = store.defaultCalendarForNewReminders()?.source {
      return source
    }
    if let source = store.sources.first(where: { !$0.calendars(for: entityType).isEmpty }) {
      return source
    }
    throw AppleGatewayError(
      code: .calendarNotFound,
      message: "No EventKit source is available for new calendars",
      details: ["entityType": entityType == .event ? "EVENT" : "REMINDER"]
    )
  }

  private func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = ReminderFetchResultBox()
    _ = store.fetchReminders(matching: predicate) { reminders in
      resultBox.set(reminders ?? [])
      semaphore.signal()
    }
    semaphore.wait()
    return resultBox.result()
  }
}

private final class ReminderFetchResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var reminders: [EKReminder] = []

  func set(_ reminders: [EKReminder]) {
    lock.withLock {
      self.reminders = reminders
    }
  }

  func result() -> [EKReminder] {
    lock.withLock {
      reminders
    }
  }
}

private extension Array {
  var nilIfEmpty: [Element]? {
    isEmpty ? nil : self
  }
}
