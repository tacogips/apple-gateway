import Foundation

public enum CalendarEntityType: String, Codable, Sendable {
  case event = "EVENT"
  case reminder = "REMINDER"
}

public struct GatewayCalendar: Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var entityType: CalendarEntityType
  public var sourceTitle: String
  public var sourceType: String
  public var colorHex: String?
  public var allowsModifications: Bool
  public var isSubscribed: Bool
  public var isDefault: Bool

  public init(
    id: String,
    title: String,
    entityType: CalendarEntityType,
    sourceTitle: String,
    sourceType: String,
    colorHex: String? = nil,
    allowsModifications: Bool,
    isSubscribed: Bool,
    isDefault: Bool
  ) {
    self.id = id
    self.title = title
    self.entityType = entityType
    self.sourceTitle = sourceTitle
    self.sourceType = sourceType
    self.colorHex = colorHex
    self.allowsModifications = allowsModifications
    self.isSubscribed = isSubscribed
    self.isDefault = isDefault
  }
}

public enum EventStatus: String, Codable, Sendable {
  case none = "NONE"
  case confirmed = "CONFIRMED"
  case tentative = "TENTATIVE"
  case canceled = "CANCELED"
}

public enum EventAvailability: String, Codable, Sendable {
  case notSupported = "NOT_SUPPORTED"
  case busy = "BUSY"
  case free = "FREE"
  case tentative = "TENTATIVE"
  case unavailable = "UNAVAILABLE"
}

public enum AttendeeStatus: String, Codable, Sendable {
  case unknown = "UNKNOWN"
  case pending = "PENDING"
  case accepted = "ACCEPTED"
  case declined = "DECLINED"
  case tentative = "TENTATIVE"
  case delegated = "DELEGATED"
  case completed = "COMPLETED"
  case inProcess = "IN_PROCESS"
}

public enum RecurrenceFrequency: String, Codable, Sendable {
  case daily = "DAILY"
  case weekly = "WEEKLY"
  case monthly = "MONTHLY"
  case yearly = "YEARLY"
}

public struct EventParticipant: Codable, Equatable, Sendable {
  public var name: String?
  public var email: String?
  public var isCurrentUser: Bool
  public var status: AttendeeStatus

  public init(
    name: String? = nil,
    email: String? = nil,
    isCurrentUser: Bool,
    status: AttendeeStatus
  ) {
    self.name = name
    self.email = email
    self.isCurrentUser = isCurrentUser
    self.status = status
  }
}

public struct Alarm: Codable, Equatable, Sendable {
  public var relativeOffsetSeconds: Int?
  public var absoluteDate: Date?

  public init(relativeOffsetSeconds: Int? = nil, absoluteDate: Date? = nil) {
    self.relativeOffsetSeconds = relativeOffsetSeconds
    self.absoluteDate = absoluteDate
  }
}

public struct RecurrenceRule: Codable, Equatable, Sendable {
  public var frequency: RecurrenceFrequency
  public var interval: Int
  public var daysOfWeek: [Int]
  public var daysOfMonth: [Int]
  public var monthsOfYear: [Int]
  public var weeksOfYear: [Int]
  public var daysOfYear: [Int]
  public var setPositions: [Int]
  public var endDate: Date?
  public var occurrenceCount: Int?

  public init(
    frequency: RecurrenceFrequency,
    interval: Int = 1,
    daysOfWeek: [Int] = [],
    daysOfMonth: [Int] = [],
    monthsOfYear: [Int] = [],
    weeksOfYear: [Int] = [],
    daysOfYear: [Int] = [],
    setPositions: [Int] = [],
    endDate: Date? = nil,
    occurrenceCount: Int? = nil
  ) {
    self.frequency = frequency
    self.interval = interval
    self.daysOfWeek = daysOfWeek
    self.daysOfMonth = daysOfMonth
    self.monthsOfYear = monthsOfYear
    self.weeksOfYear = weeksOfYear
    self.daysOfYear = daysOfYear
    self.setPositions = setPositions
    self.endDate = endDate
    self.occurrenceCount = occurrenceCount
  }
}

public struct CalendarEvent: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var calendarId: String
  public var title: String
  public var notes: String?
  public var location: String?
  public var url: String?
  public var isAllDay: Bool
  public var startDate: Date
  public var endDate: Date
  public var timeZone: String?
  public var status: EventStatus
  public var availability: EventAvailability
  public var organizer: EventParticipant?
  public var attendees: [EventParticipant]
  public var alarms: [Alarm]
  public var recurrenceRules: [RecurrenceRule]
  public var isRecurring: Bool
  public var occurrenceDate: Date?
  public var isDetached: Bool
  public var creationDate: Date?
  public var lastModifiedDate: Date?

  public init(
    id: String,
    calendarId: String,
    title: String,
    notes: String? = nil,
    location: String? = nil,
    url: String? = nil,
    isAllDay: Bool = false,
    startDate: Date,
    endDate: Date,
    timeZone: String? = nil,
    status: EventStatus = .none,
    availability: EventAvailability = .notSupported,
    organizer: EventParticipant? = nil,
    attendees: [EventParticipant] = [],
    alarms: [Alarm] = [],
    recurrenceRules: [RecurrenceRule] = [],
    isRecurring: Bool = false,
    occurrenceDate: Date? = nil,
    isDetached: Bool = false,
    creationDate: Date? = nil,
    lastModifiedDate: Date? = nil
  ) {
    self.id = id
    self.calendarId = calendarId
    self.title = title
    self.notes = notes
    self.location = location
    self.url = url
    self.isAllDay = isAllDay
    self.startDate = startDate
    self.endDate = endDate
    self.timeZone = timeZone
    self.status = status
    self.availability = availability
    self.organizer = organizer
    self.attendees = attendees
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
    self.isRecurring = isRecurring
    self.occurrenceDate = occurrenceDate
    self.isDetached = isDetached
    self.creationDate = creationDate
    self.lastModifiedDate = lastModifiedDate
  }
}

public enum ReminderStatusFilter: String, Codable, Sendable {
  case all = "ALL"
  case incomplete = "INCOMPLETE"
  case completed = "COMPLETED"
}

public struct Reminder: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var listId: String
  public var title: String
  public var notes: String?
  public var url: String?
  public var priority: Int
  public var isCompleted: Bool
  public var completionDate: Date?
  public var startDate: Date?
  public var dueDate: Date?
  public var dueDateHasTime: Bool
  public var alarms: [Alarm]
  public var recurrenceRules: [RecurrenceRule]
  public var creationDate: Date?
  public var lastModifiedDate: Date?

  public init(
    id: String,
    listId: String,
    title: String,
    notes: String? = nil,
    url: String? = nil,
    priority: Int = 0,
    isCompleted: Bool = false,
    completionDate: Date? = nil,
    startDate: Date? = nil,
    dueDate: Date? = nil,
    dueDateHasTime: Bool = true,
    alarms: [Alarm] = [],
    recurrenceRules: [RecurrenceRule] = [],
    creationDate: Date? = nil,
    lastModifiedDate: Date? = nil
  ) {
    self.id = id
    self.listId = listId
    self.title = title
    self.notes = notes
    self.url = url
    self.priority = priority
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.startDate = startDate
    self.dueDate = dueDate
    self.dueDateHasTime = dueDateHasTime
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
    self.creationDate = creationDate
    self.lastModifiedDate = lastModifiedDate
  }
}
