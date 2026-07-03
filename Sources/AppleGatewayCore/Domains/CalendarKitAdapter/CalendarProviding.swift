import Foundation

public protocol CalendarProviding: Sendable {
  func calendars(entityType: CalendarEntityType?) throws -> [GatewayCalendar]
  func events(in window: EventFetchWindow) throws -> [CalendarEvent]
  func event(eventId: String, occurrenceDate: Date?) throws -> CalendarEvent?
}

public protocol CalendarWriting: Sendable {
  func createCalendar(_ input: CreateCalendarInput) throws -> GatewayCalendar
  func deleteCalendar(calendarId: String) throws -> DeleteResult
  func createEvent(_ event: CalendarEvent) throws -> CalendarEvent
  func updateEvent(_ request: CalendarEventSaveRequest) throws -> CalendarEvent
  func deleteEvent(_ request: CalendarEventDeleteRequest) throws -> DeleteResult
}
