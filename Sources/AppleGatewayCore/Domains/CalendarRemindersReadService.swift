import Foundation

public struct EventSearchInput: Sendable {
  public var calendarIds: [String]
  public var startDate: Date?
  public var endDate: Date?
  public var query: String?
  public var first: Int?
  public var after: String?

  public init(
    calendarIds: [String] = [],
    startDate: Date? = nil,
    endDate: Date? = nil,
    query: String? = nil,
    first: Int? = nil,
    after: String? = nil
  ) {
    self.calendarIds = calendarIds
    self.startDate = startDate
    self.endDate = endDate
    self.query = query
    self.first = first
    self.after = after
  }
}

public struct ReminderSearchInput: Sendable {
  public var listIds: [String]
  public var status: ReminderStatusFilter
  public var dueAfter: Date?
  public var dueBefore: Date?
  public var query: String?
  public var first: Int?
  public var after: String?

  public init(
    listIds: [String] = [],
    status: ReminderStatusFilter = .all,
    dueAfter: Date? = nil,
    dueBefore: Date? = nil,
    query: String? = nil,
    first: Int? = nil,
    after: String? = nil
  ) {
    self.listIds = listIds
    self.status = status
    self.dueAfter = dueAfter
    self.dueBefore = dueBefore
    self.query = query
    self.first = first
    self.after = after
  }
}

public struct EventFetchWindow: Equatable, Sendable {
  public var startDate: Date
  public var endDate: Date
  public var calendarIds: [String]

  public init(startDate: Date, endDate: Date, calendarIds: [String] = []) {
    self.startDate = startDate
    self.endDate = endDate
    self.calendarIds = calendarIds
  }
}

public struct PageInfo: Codable, Equatable, Sendable {
  public var hasNextPage: Bool
  public var endCursor: String?

  public init(hasNextPage: Bool, endCursor: String?) {
    self.hasNextPage = hasNextPage
    self.endCursor = endCursor
  }
}

public struct EventConnection: Codable, Equatable, Sendable {
  public var edges: [EventEdge]
  public var pageInfo: PageInfo
  public var totalCount: Int

  public init(edges: [EventEdge], pageInfo: PageInfo, totalCount: Int) {
    self.edges = edges
    self.pageInfo = pageInfo
    self.totalCount = totalCount
  }
}

public struct EventEdge: Codable, Equatable, Sendable {
  public var cursor: String
  public var node: CalendarEvent

  public init(cursor: String, node: CalendarEvent) {
    self.cursor = cursor
    self.node = node
  }
}

public struct ReminderConnection: Codable, Equatable, Sendable {
  public var edges: [ReminderEdge]
  public var pageInfo: PageInfo
  public var totalCount: Int

  public init(edges: [ReminderEdge], pageInfo: PageInfo, totalCount: Int) {
    self.edges = edges
    self.pageInfo = pageInfo
    self.totalCount = totalCount
  }
}

public struct ReminderEdge: Codable, Equatable, Sendable {
  public var cursor: String
  public var node: Reminder

  public init(cursor: String, node: Reminder) {
    self.cursor = cursor
    self.node = node
  }
}

public struct CalendarReadService: Sendable {
  private let calendarProvider: any CalendarProviding
  private let remindersProvider: any RemindersProviding
  private let limits: AppleGatewayConfig.Limits

  public init(
    calendarProvider: any CalendarProviding,
    remindersProvider: any RemindersProviding,
    limits: AppleGatewayConfig.Limits = .defaultValue
  ) {
    self.calendarProvider = calendarProvider
    self.remindersProvider = remindersProvider
    self.limits = limits
  }

  public func calendars(entityType: CalendarEntityType? = nil) throws -> [GatewayCalendar] {
    try calendarProvider.calendars(entityType: entityType)
  }

  public func reminderLists() throws -> [GatewayCalendar] {
    try remindersProvider.reminderLists()
  }

  public func event(eventId: String, occurrenceDate: Date? = nil) throws -> CalendarEvent? {
    try calendarProvider.event(eventId: eventId, occurrenceDate: occurrenceDate)
  }

  public func reminder(reminderId: String) throws -> Reminder? {
    try remindersProvider.reminder(reminderId: reminderId)
  }

  public func events(input: EventSearchInput) throws -> EventConnection {
    guard let startDate = input.startDate, let endDate = input.endDate else {
      throw invalidArgument("events input requires startDate and endDate")
    }
    guard startDate < endDate else {
      throw invalidArgument("events input startDate must be before endDate")
    }
    let first = try pageSize(input.first)
    let offset = try CursorCodec.offset(after: input.after)
    let windows = Self.eventFetchWindows(startDate: startDate, endDate: endDate, calendarIds: input.calendarIds)
    let events = try windows
      .flatMap { try calendarProvider.events(in: $0) }
      .filter { event in
        Self.matchesCalendarFilter(input.calendarIds, calendarId: event.calendarId)
          && event.endDate > startDate
          && event.startDate < endDate
          && Self.matchesEventQuery(input.query, event: event)
      }
      .sorted { lhs, rhs in
        if lhs.startDate == rhs.startDate {
          return lhs.id < rhs.id
        }
        return lhs.startDate < rhs.startDate
      }
    return EventConnection.paginating(events, first: first, offset: offset)
  }

  public func reminders(input: ReminderSearchInput) throws -> ReminderConnection {
    if let dueAfter = input.dueAfter, let dueBefore = input.dueBefore, dueAfter > dueBefore {
      throw invalidArgument("reminders input dueAfter must not be after dueBefore")
    }
    let first = try pageSize(input.first)
    let offset = try CursorCodec.offset(after: input.after)
    let reminders = try remindersProvider.reminders()
      .filter { reminder in
        Self.matchesListFilter(input.listIds, listId: reminder.listId)
          && Self.matchesReminderStatus(input.status, reminder: reminder)
          && Self.matchesReminderDueRange(reminder, dueAfter: input.dueAfter, dueBefore: input.dueBefore)
          && Self.matchesReminderQuery(input.query, reminder: reminder)
      }
      .sorted(by: Self.sortReminders)
    return ReminderConnection.paginating(reminders, first: first, offset: offset)
  }

  public static func eventFetchWindows(
    startDate: Date,
    endDate: Date,
    calendarIds: [String] = []
  ) -> [EventFetchWindow] {
    var windows: [EventFetchWindow] = []
    var cursor = startDate
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    while cursor < endDate {
      let chunkEnd = min(calendar.date(byAdding: .year, value: 4, to: cursor) ?? endDate, endDate)
      windows.append(EventFetchWindow(startDate: cursor, endDate: chunkEnd, calendarIds: calendarIds))
      cursor = chunkEnd
    }

    return windows
  }

  private func pageSize(_ requested: Int?) throws -> Int {
    let value = requested ?? limits.defaultPageSize
    guard value > 0 else {
      throw invalidArgument("first must be positive")
    }
    return min(value, limits.maxPageSize)
  }

  private func invalidArgument(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }

  private static func matchesCalendarFilter(_ calendarIds: [String], calendarId: String) -> Bool {
    calendarIds.isEmpty || calendarIds.contains(calendarId)
  }

  private static func matchesListFilter(_ listIds: [String], listId: String) -> Bool {
    listIds.isEmpty || listIds.contains(listId)
  }

  private static func matchesEventQuery(_ query: String?, event: CalendarEvent) -> Bool {
    matchesQuery(query, values: [event.title, event.notes, event.location])
  }

  private static func matchesReminderQuery(_ query: String?, reminder: Reminder) -> Bool {
    matchesQuery(query, values: [reminder.title, reminder.notes])
  }

  private static func matchesQuery(_ query: String?, values: [String?]) -> Bool {
    guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
      return true
    }
    return values.contains { value in
      value?.localizedCaseInsensitiveContains(query) == true
    }
  }

  private static func matchesReminderStatus(_ status: ReminderStatusFilter, reminder: Reminder) -> Bool {
    switch status {
    case .all:
      return true
    case .incomplete:
      return !reminder.isCompleted
    case .completed:
      return reminder.isCompleted
    }
  }

  private static func matchesReminderDueRange(
    _ reminder: Reminder,
    dueAfter: Date?,
    dueBefore: Date?
  ) -> Bool {
    guard dueAfter != nil || dueBefore != nil else {
      return true
    }
    guard let dueDate = reminder.dueDate else {
      return false
    }
    if let dueAfter, dueDate < dueAfter {
      return false
    }
    if let dueBefore, dueDate > dueBefore {
      return false
    }
    return true
  }

  private static func sortReminders(_ lhs: Reminder, _ rhs: Reminder) -> Bool {
    switch (lhs.dueDate, rhs.dueDate) {
    case (.some(let lhsDue), .some(let rhsDue)):
      if lhsDue == rhsDue {
        return lhs.id < rhs.id
      }
      return lhsDue < rhsDue
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    case (.none, .none):
      return lhs.id < rhs.id
    }
  }
}

private enum CursorCodec {
  private static let prefix = "offset:"

  static func cursor(for index: Int) -> String {
    Data("\(prefix)\(index)".utf8).base64EncodedString()
  }

  static func offset(after cursor: String?) throws -> Int {
    guard let cursor else {
      return 0
    }
    guard
      let data = Data(base64Encoded: cursor),
      let decoded = String(data: data, encoding: .utf8),
      decoded.hasPrefix(prefix),
      let index = Int(decoded.dropFirst(prefix.count)),
      index >= 0
    else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Invalid pagination cursor"
      )
    }
    return index + 1
  }
}

private extension EventConnection {
  static func paginating(
    _ events: [CalendarEvent],
    first: Int,
    offset: Int
  ) -> EventConnection {
    let page = events.dropFirst(offset).prefix(first)
    let edges = page.enumerated().map { index, event in
      EventEdge(cursor: CursorCodec.cursor(for: offset + index), node: event)
    }
    return EventConnection(
      edges: edges,
      pageInfo: PageInfo(
        hasNextPage: offset + edges.count < events.count,
        endCursor: edges.last?.cursor
      ),
      totalCount: events.count
    )
  }
}

private extension ReminderConnection {
  static func paginating(
    _ reminders: [Reminder],
    first: Int,
    offset: Int
  ) -> ReminderConnection {
    let page = reminders.dropFirst(offset).prefix(first)
    let edges = page.enumerated().map { index, reminder in
      ReminderEdge(cursor: CursorCodec.cursor(for: offset + index), node: reminder)
    }
    return ReminderConnection(
      edges: edges,
      pageInfo: PageInfo(
        hasNextPage: offset + edges.count < reminders.count,
        endCursor: edges.last?.cursor
      ),
      totalCount: reminders.count
    )
  }
}
