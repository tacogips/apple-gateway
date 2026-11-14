import AppKit
import EventKit
import Foundation

enum EventKitCalendarReminderMapper {
  static func gatewayCalendar(
    _ calendar: EKCalendar,
    entityType: CalendarEntityType,
    defaultCalendarId: String?
  ) -> GatewayCalendar {
    GatewayCalendar(
      id: calendar.calendarIdentifier,
      title: calendar.title,
      entityType: entityType,
      sourceTitle: calendar.source?.title ?? "",
      sourceType: sourceType(calendar.source?.sourceType),
      colorHex: colorHex(calendar.color),
      allowsModifications: calendar.allowsContentModifications,
      isSubscribed: calendar.isSubscribed,
      isDefault: calendar.calendarIdentifier == defaultCalendarId
    )
  }

  static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
    CalendarEvent(
      id: event.eventIdentifier,
      calendarId: event.calendar.calendarIdentifier,
      title: event.title,
      notes: event.notes,
      location: event.location,
      url: event.url?.absoluteString,
      isAllDay: event.isAllDay,
      startDate: event.startDate,
      endDate: event.endDate,
      timeZone: event.timeZone?.identifier,
      status: eventStatus(event.status),
      availability: eventAvailability(event.availability),
      organizer: event.organizer.map(eventParticipant),
      attendees: (event.attendees ?? []).map(eventParticipant),
      alarms: (event.alarms ?? []).map(alarm),
      recurrenceRules: (event.recurrenceRules ?? []).map(recurrenceRule),
      isRecurring: event.hasRecurrenceRules,
      occurrenceDate: event.occurrenceDate,
      isDetached: event.isDetached,
      creationDate: event.creationDate,
      lastModifiedDate: event.lastModifiedDate
    )
  }

  static func reminder(_ reminder: EKReminder) -> Reminder {
    let dueDate = date(from: reminder.dueDateComponents)
    return Reminder(
      id: reminder.calendarItemIdentifier,
      listId: reminder.calendar.calendarIdentifier,
      title: reminder.title,
      notes: reminder.notes,
      url: reminder.url?.absoluteString,
      priority: Int(reminder.priority),
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      startDate: date(from: reminder.startDateComponents),
      dueDate: dueDate,
      dueDateHasTime: hasTime(reminder.dueDateComponents),
      alarms: (reminder.alarms ?? []).map(alarm),
      recurrenceRules: (reminder.recurrenceRules ?? []).map(recurrenceRule),
      creationDate: reminder.creationDate,
      lastModifiedDate: reminder.lastModifiedDate
    )
  }

  static func apply(
    _ event: CalendarEvent,
    to ekEvent: EKEvent,
    calendar: EKCalendar,
    includeRecurrenceRules: Bool = true
  ) throws {
    ekEvent.calendar = calendar
    ekEvent.title = event.title
    ekEvent.notes = event.notes
    ekEvent.location = event.location
    ekEvent.url = try url(event.url)
    ekEvent.startDate = event.startDate
    ekEvent.endDate = event.endDate
    ekEvent.timeZone = event.timeZone.flatMap(TimeZone.init(identifier:))
    if event.availability != .notSupported {
      ekEvent.availability = ekEventAvailability(event.availability)
    }
    ekEvent.alarms = try event.alarms.map(makeAlarm)
    if includeRecurrenceRules {
      ekEvent.recurrenceRules = try event.recurrenceRules.map(makeRecurrenceRule)
    }
    ekEvent.isAllDay = event.isAllDay
  }

  static func apply(_ reminder: Reminder, to ekReminder: EKReminder, calendar: EKCalendar) throws {
    ekReminder.calendar = calendar
    ekReminder.title = reminder.title
    ekReminder.notes = reminder.notes
    ekReminder.url = try url(reminder.url)
    ekReminder.priority = reminder.priority
    ekReminder.isCompleted = reminder.isCompleted
    ekReminder.completionDate = reminder.completionDate
    ekReminder.startDateComponents = dateComponents(from: reminder.startDate, hasTime: true)
    ekReminder.dueDateComponents = dateComponents(from: reminder.dueDate, hasTime: reminder.dueDateHasTime)
    ekReminder.alarms = try reminder.alarms.map(makeAlarm)
    ekReminder.recurrenceRules = try reminder.recurrenceRules.map(makeRecurrenceRule)
  }

  static func makeAlarm(_ alarm: Alarm) throws -> EKAlarm {
    switch (alarm.relativeOffsetSeconds, alarm.absoluteDate) {
    case (.some(let seconds), nil):
      return EKAlarm(relativeOffset: TimeInterval(seconds))
    case (nil, .some(let date)):
      return EKAlarm(absoluteDate: date)
    default:
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Alarm must set exactly one of relativeOffsetSeconds or absoluteDate"
      )
    }
  }

  static func alarm(_ alarm: EKAlarm) -> Alarm {
    if let absoluteDate = alarm.absoluteDate {
      return Alarm(absoluteDate: absoluteDate)
    }
    return Alarm(relativeOffsetSeconds: Int(alarm.relativeOffset.rounded()))
  }

  static func makeRecurrenceRule(_ rule: RecurrenceRule) throws -> EKRecurrenceRule {
    guard rule.interval > 0 else {
      throw AppleGatewayError(code: .invalidArgument, message: "Recurrence interval must be positive")
    }
    guard rule.endDate == nil || rule.occurrenceCount == nil else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Recurrence rule must set at most one of endDate or occurrenceCount"
      )
    }
    let end = try recurrenceEnd(endDate: rule.endDate, occurrenceCount: rule.occurrenceCount)
    return EKRecurrenceRule(
      recurrenceWith: ekRecurrenceFrequency(rule.frequency),
      interval: rule.interval,
      daysOfTheWeek: try nilIfEmpty(rule.daysOfWeek.map(makeDayOfWeek)),
      daysOfTheMonth: nilIfEmpty(rule.daysOfMonth.map(NSNumber.init(value:))),
      monthsOfTheYear: nilIfEmpty(rule.monthsOfYear.map(NSNumber.init(value:))),
      weeksOfTheYear: nilIfEmpty(rule.weeksOfYear.map(NSNumber.init(value:))),
      daysOfTheYear: nilIfEmpty(rule.daysOfYear.map(NSNumber.init(value:))),
      setPositions: nilIfEmpty(rule.setPositions.map(NSNumber.init(value:))),
      end: end
    )
  }

  static func recurrenceRule(_ rule: EKRecurrenceRule) -> RecurrenceRule {
    RecurrenceRule(
      frequency: recurrenceFrequency(rule.frequency),
      interval: rule.interval,
      daysOfWeek: (rule.daysOfTheWeek ?? []).map { Int($0.dayOfTheWeek.rawValue) },
      daysOfMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
      monthsOfYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
      weeksOfYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
      daysOfYear: (rule.daysOfTheYear ?? []).map(\.intValue),
      setPositions: (rule.setPositions ?? []).map(\.intValue),
      endDate: rule.recurrenceEnd?.endDate,
      occurrenceCount: recurrenceOccurrenceCount(rule.recurrenceEnd)
    )
  }

  static func ekSpan(_ span: RecurrenceSpan) -> EKSpan {
    switch span {
    case .thisEvent:
      return .thisEvent
    case .futureEvents:
      return .futureEvents
    }
  }

  static func dateComponents(from date: Date?, hasTime: Bool) -> DateComponents? {
    guard let date else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    var components = calendar.dateComponents(
      hasTime ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day],
      from: date
    )
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    return components
  }

  static func date(from components: DateComponents?) -> Date? {
    guard var components else {
      return nil
    }
    if components.calendar == nil {
      components.calendar = Calendar(identifier: .gregorian)
    }
    return components.date
  }

  private static func eventParticipant(_ participant: EKParticipant) -> EventParticipant {
    EventParticipant(
      name: participant.name,
      email: participant.url.emailAddress,
      isCurrentUser: participant.isCurrentUser,
      status: attendeeStatus(participant.participantStatus)
    )
  }

  private static func url(_ value: String?) throws -> URL? {
    guard let value, !value.isEmpty else {
      return nil
    }
    guard let url = URL(string: value) else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid URL", details: ["url": value])
    }
    return url
  }

  private static func sourceType(_ sourceType: EKSourceType?) -> String {
    switch sourceType {
    case .local:
      return "local"
    case .exchange:
      return "exchange"
    case .calDAV:
      return "caldav"
    case .mobileMe:
      return "mobileme"
    case .subscribed:
      return "subscribed"
    case .birthdays:
      return "birthdays"
    case nil:
      return ""
    @unknown default:
      return "unknown"
    }
  }

  private static func colorHex(_ color: NSColor?) -> String? {
    guard
      let color = color?.usingColorSpace(.sRGB)
    else {
      return nil
    }
    return String(
      format: "#%02X%02X%02X",
      Int((color.redComponent * 255).rounded()),
      Int((color.greenComponent * 255).rounded()),
      Int((color.blueComponent * 255).rounded())
    )
  }

  private static func makeDayOfWeek(_ value: Int) throws -> EKRecurrenceDayOfWeek {
    guard (1...7).contains(value), let weekday = EKWeekday(rawValue: value) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Recurrence weekday must be between 1 and 7",
        details: ["dayOfWeek": String(value)]
      )
    }
    return EKRecurrenceDayOfWeek(weekday)
  }

  private static func nilIfEmpty<Element>(_ values: [Element]) -> [Element]? {
    values.isEmpty ? nil : values
  }

  private static func recurrenceEnd(endDate: Date?, occurrenceCount: Int?) throws -> EKRecurrenceEnd? {
    if let endDate {
      return EKRecurrenceEnd(end: endDate)
    }
    if let occurrenceCount {
      guard occurrenceCount > 0 else {
        throw AppleGatewayError(code: .invalidArgument, message: "Recurrence occurrenceCount must be positive")
      }
      return EKRecurrenceEnd(occurrenceCount: occurrenceCount)
    }
    return nil
  }

  private static func recurrenceOccurrenceCount(_ end: EKRecurrenceEnd?) -> Int? {
    guard let count = end?.occurrenceCount, count > 0 else {
      return nil
    }
    return Int(count)
  }

  private static func hasTime(_ components: DateComponents?) -> Bool {
    guard let components else {
      return true
    }
    return components.hour != nil || components.minute != nil || components.second != nil
  }

  private static func eventStatus(_ status: EKEventStatus) -> EventStatus {
    switch status {
    case .none:
      return .none
    case .confirmed:
      return .confirmed
    case .tentative:
      return .tentative
    case .canceled:
      return .canceled
    @unknown default:
      return .none
    }
  }

  private static func eventAvailability(_ availability: EKEventAvailability) -> EventAvailability {
    switch availability {
    case .notSupported:
      return .notSupported
    case .busy:
      return .busy
    case .free:
      return .free
    case .tentative:
      return .tentative
    case .unavailable:
      return .unavailable
    @unknown default:
      return .notSupported
    }
  }

  private static func ekEventAvailability(_ availability: EventAvailability) -> EKEventAvailability {
    switch availability {
    case .notSupported:
      return .notSupported
    case .busy:
      return .busy
    case .free:
      return .free
    case .tentative:
      return .tentative
    case .unavailable:
      return .unavailable
    }
  }

  private static func attendeeStatus(_ status: EKParticipantStatus) -> AttendeeStatus {
    switch status {
    case .unknown:
      return .unknown
    case .pending:
      return .pending
    case .accepted:
      return .accepted
    case .declined:
      return .declined
    case .tentative:
      return .tentative
    case .delegated:
      return .delegated
    case .completed:
      return .completed
    case .inProcess:
      return .inProcess
    @unknown default:
      return .unknown
    }
  }

  private static func ekRecurrenceFrequency(_ frequency: RecurrenceFrequency) -> EKRecurrenceFrequency {
    switch frequency {
    case .daily:
      return .daily
    case .weekly:
      return .weekly
    case .monthly:
      return .monthly
    case .yearly:
      return .yearly
    }
  }

  private static func recurrenceFrequency(_ frequency: EKRecurrenceFrequency) -> RecurrenceFrequency {
    switch frequency {
    case .daily:
      return .daily
    case .weekly:
      return .weekly
    case .monthly:
      return .monthly
    case .yearly:
      return .yearly
    @unknown default:
      return .daily
    }
  }
}

private extension URL {
  var emailAddress: String? {
    if scheme == "mailto" {
      return String(absoluteString.dropFirst("mailto:".count)).removingPercentEncoding
    }
    return nil
  }
}
