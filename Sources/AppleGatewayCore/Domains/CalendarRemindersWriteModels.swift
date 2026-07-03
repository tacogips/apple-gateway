import Foundation

public enum RecurrenceSpan: String, Codable, Sendable {
  case thisEvent = "THIS_EVENT"
  case futureEvents = "FUTURE_EVENTS"
}

public struct DeleteResult: Codable, Equatable, Sendable {
  public var success: Bool

  public init(success: Bool) {
    self.success = success
  }
}

public struct CreateCalendarInput: Equatable, Sendable {
  public var title: String
  public var sourceTitle: String?
  public var colorHex: String?

  public init(title: String, sourceTitle: String? = nil, colorHex: String? = nil) {
    self.title = title
    self.sourceTitle = sourceTitle
    self.colorHex = colorHex
  }
}

public struct CreateReminderListInput: Equatable, Sendable {
  public var title: String
  public var sourceTitle: String?
  public var colorHex: String?

  public init(title: String, sourceTitle: String? = nil, colorHex: String? = nil) {
    self.title = title
    self.sourceTitle = sourceTitle
    self.colorHex = colorHex
  }
}

public struct CreateEventInput: Sendable {
  public var calendarId: String?
  public var title: String
  public var startDate: Date
  public var endDate: Date
  public var isAllDay: Bool
  public var notes: String?
  public var location: String?
  public var url: String?
  public var timeZone: String?
  public var availability: EventAvailability?
  public var alarms: [Alarm]?
  public var recurrenceRules: [RecurrenceRule]?

  public init(
    calendarId: String? = nil,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool = false,
    notes: String? = nil,
    location: String? = nil,
    url: String? = nil,
    timeZone: String? = nil,
    availability: EventAvailability? = nil,
    alarms: [Alarm]? = nil,
    recurrenceRules: [RecurrenceRule]? = nil
  ) {
    self.calendarId = calendarId
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.notes = notes
    self.location = location
    self.url = url
    self.timeZone = timeZone
    self.availability = availability
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}

public struct UpdateEventInput: Sendable {
  public var eventId: String
  public var occurrenceDate: Date?
  public var span: RecurrenceSpan
  public var title: String?
  public var startDate: Date?
  public var endDate: Date?
  public var isAllDay: Bool?
  public var notes: String?
  public var location: String?
  public var url: String?
  public var timeZone: String?
  public var availability: EventAvailability?
  public var calendarId: String?
  public var alarms: [Alarm]?
  public var recurrenceRules: [RecurrenceRule]?

  public init(
    eventId: String,
    occurrenceDate: Date? = nil,
    span: RecurrenceSpan = .thisEvent,
    title: String? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    isAllDay: Bool? = nil,
    notes: String? = nil,
    location: String? = nil,
    url: String? = nil,
    timeZone: String? = nil,
    availability: EventAvailability? = nil,
    calendarId: String? = nil,
    alarms: [Alarm]? = nil,
    recurrenceRules: [RecurrenceRule]? = nil
  ) {
    self.eventId = eventId
    self.occurrenceDate = occurrenceDate
    self.span = span
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.notes = notes
    self.location = location
    self.url = url
    self.timeZone = timeZone
    self.availability = availability
    self.calendarId = calendarId
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}

public struct CalendarEventSaveRequest: Equatable, Sendable {
  public var event: CalendarEvent
  public var span: RecurrenceSpan
  public var occurrenceDate: Date?

  public init(event: CalendarEvent, span: RecurrenceSpan, occurrenceDate: Date?) {
    self.event = event
    self.span = span
    self.occurrenceDate = occurrenceDate
  }
}

public struct CalendarEventDeleteRequest: Equatable, Sendable {
  public var eventId: String
  public var span: RecurrenceSpan
  public var occurrenceDate: Date?

  public init(eventId: String, span: RecurrenceSpan, occurrenceDate: Date?) {
    self.eventId = eventId
    self.span = span
    self.occurrenceDate = occurrenceDate
  }
}

public struct CreateReminderInput: Sendable {
  public var listId: String?
  public var title: String
  public var notes: String?
  public var url: String?
  public var priority: Int
  public var startDate: Date?
  public var dueDate: Date?
  public var dueDateHasTime: Bool
  public var alarms: [Alarm]?
  public var recurrenceRules: [RecurrenceRule]?

  public init(
    listId: String? = nil,
    title: String,
    notes: String? = nil,
    url: String? = nil,
    priority: Int = 0,
    startDate: Date? = nil,
    dueDate: Date? = nil,
    dueDateHasTime: Bool = true,
    alarms: [Alarm]? = nil,
    recurrenceRules: [RecurrenceRule]? = nil
  ) {
    self.listId = listId
    self.title = title
    self.notes = notes
    self.url = url
    self.priority = priority
    self.startDate = startDate
    self.dueDate = dueDate
    self.dueDateHasTime = dueDateHasTime
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}

public struct UpdateReminderInput: Sendable {
  public var reminderId: String
  public var title: String?
  public var notes: String?
  public var url: String?
  public var priority: Int?
  public var startDate: Date?
  public var dueDate: Date?
  public var dueDateHasTime: Bool?
  public var listId: String?
  public var alarms: [Alarm]?
  public var recurrenceRules: [RecurrenceRule]?

  public init(
    reminderId: String,
    title: String? = nil,
    notes: String? = nil,
    url: String? = nil,
    priority: Int? = nil,
    startDate: Date? = nil,
    dueDate: Date? = nil,
    dueDateHasTime: Bool? = nil,
    listId: String? = nil,
    alarms: [Alarm]? = nil,
    recurrenceRules: [RecurrenceRule]? = nil
  ) {
    self.reminderId = reminderId
    self.title = title
    self.notes = notes
    self.url = url
    self.priority = priority
    self.startDate = startDate
    self.dueDate = dueDate
    self.dueDateHasTime = dueDateHasTime
    self.listId = listId
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}
