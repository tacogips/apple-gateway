import Foundation

public enum CalendarReminderServiceFactory {
  public static func liveServices() -> CalendarReminderServices {
    let adapter = LiveEventKitCalendarReminderAdapter()
    return CalendarReminderServices(
      readService: CalendarReadService(calendarProvider: adapter, remindersProvider: adapter),
      writeService: CalendarWriteService(
        calendarProvider: adapter,
        calendarWriter: adapter,
        remindersProvider: adapter,
        remindersWriter: adapter
      )
    )
  }

  public static func liveReadService() -> CalendarReadService {
    liveServices().readService
  }

  public static func liveWriteService() -> CalendarWriteService {
    liveServices().writeService
  }

  public static func unavailableReadService() -> CalendarReadService {
    let provider = UnavailableCalendarReminderProvider()
    return CalendarReadService(calendarProvider: provider, remindersProvider: provider)
  }

  public static func unavailableWriteService() -> CalendarWriteService {
    let provider = UnavailableCalendarReminderProvider()
    return CalendarWriteService(
      calendarProvider: provider,
      calendarWriter: provider,
      remindersProvider: provider,
      remindersWriter: provider
    )
  }
}

public struct CalendarReminderServices: Sendable {
  public var readService: CalendarReadService
  public var writeService: CalendarWriteService

  public init(readService: CalendarReadService, writeService: CalendarWriteService) {
    self.readService = readService
    self.writeService = writeService
  }
}

public struct UnavailableCalendarReminderProvider: CalendarProviding, CalendarWriting, RemindersProviding, RemindersWriting {
  public init() {}

  public func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar] {
    throw unavailable("Calendar provider is unavailable")
  }

  public func events(in window: EventFetchWindow) throws -> [CalendarEvent] {
    throw unavailable("Calendar provider is unavailable")
  }

  public func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent? {
    throw unavailable("Calendar provider is unavailable")
  }

  public func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar {
    throw unavailable("Calendar writer is unavailable")
  }

  public func deleteCalendar(calendarId: String) throws -> DeleteResult {
    throw unavailable("Calendar writer is unavailable")
  }

  public func createEvent(_ event: CalendarEvent) throws -> CalendarEvent {
    throw unavailable("Calendar writer is unavailable")
  }

  public func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent {
    throw unavailable("Calendar writer is unavailable")
  }

  public func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult {
    throw unavailable("Calendar writer is unavailable")
  }

  public func reminderLists() throws -> [GatewayCalendar] {
    throw unavailable("Reminders provider is unavailable")
  }

  public func reminders() throws -> [Reminder] {
    throw unavailable("Reminders provider is unavailable")
  }

  public func reminder(reminderId: String) throws -> Reminder? {
    throw unavailable("Reminders provider is unavailable")
  }

  public func createReminderList(_ input: CreateReminderListInput) throws -> GatewayCalendar {
    throw unavailable("Reminders writer is unavailable")
  }

  public func createReminder(_ reminder: Reminder) throws -> Reminder {
    throw unavailable("Reminders writer is unavailable")
  }

  public func updateReminder(_ reminder: Reminder) throws -> Reminder {
    throw unavailable("Reminders writer is unavailable")
  }

  public func deleteReminder(reminderId: String) throws -> DeleteResult {
    throw unavailable("Reminders writer is unavailable")
  }

  private func unavailable(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: message)
  }
}
