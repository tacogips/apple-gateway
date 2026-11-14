import EventKit
import Foundation

struct EventOccurrenceTargetIdentity: Equatable, Sendable {
  let eventIdentifiers: Set<String>
  let calendarItemIdentifiers: Set<String>
  let externalIdentifiers: Set<String>
}

struct EventOccurrenceTargetCandidate: Equatable, Sendable {
  let identity: EventOccurrenceTargetIdentity
  let calendarId: String
  let occurrenceDate: Date?
}

enum EventOccurrenceIdentityMatch: Equatable, Sendable {
  case local
  case external
}

enum EventOccurrenceTargetSelection: Equatable, Sendable {
  case selected(index: Int, match: EventOccurrenceIdentityMatch)
  case notFound
  case ambiguous
}

enum EventOccurrenceTargetSelector {
  // EventKit derives detached-occurrence identifiers by appending "/RID=<n>"
  // to the master's identifier, so series membership must compare the
  // RID-stripped form on both sides.
  static func normalizedSeriesIdentifier(_ identifier: String) -> String {
    guard let ridRange = identifier.range(of: "/RID=") else {
      return identifier
    }
    return String(identifier[..<ridRange.lowerBound])
  }

  private static func sharesSeriesIdentity(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
    guard !lhs.isEmpty, !rhs.isEmpty else {
      return false
    }
    return !Set(lhs.map(normalizedSeriesIdentifier))
      .isDisjoint(with: Set(rhs.map(normalizedSeriesIdentifier)))
  }

  static func select(
    acceptedIdentity: EventOccurrenceTargetIdentity,
    calendarId: String,
    occurrenceDate: Date,
    candidates: [EventOccurrenceTargetCandidate]
  ) -> EventOccurrenceTargetSelection {
    let eligibleCandidates = candidates.enumerated().filter { _, candidate in
      candidate.calendarId == calendarId
        && candidate.occurrenceDate == occurrenceDate
    }
    let localMatches = eligibleCandidates.filter { _, candidate in
      sharesSeriesIdentity(
        candidate.identity.eventIdentifiers,
        acceptedIdentity.eventIdentifiers
      )
        || sharesSeriesIdentity(
          candidate.identity.calendarItemIdentifiers,
          acceptedIdentity.calendarItemIdentifiers
        )
    }
    if localMatches.count > 1 {
      return .ambiguous
    }
    if let localMatch = localMatches.first {
      return .selected(index: localMatch.offset, match: .local)
    }

    let externalMatches = eligibleCandidates.filter { _, candidate in
      sharesSeriesIdentity(
        candidate.identity.externalIdentifiers,
        acceptedIdentity.externalIdentifiers
      )
    }
    if externalMatches.count > 1 {
      return .ambiguous
    }
    if let externalMatch = externalMatches.first {
      return .selected(index: externalMatch.offset, match: .external)
    }
    return .notFound
  }
}

struct EventOccurrenceSearchWindow: Equatable, Sendable {
  let startDate: Date
  let endDate: Date
}

enum EventOccurrenceExternalIdentityStatus: Equatable, Sendable {
  case unique
  case ambiguous
  case unavailable
}

enum EventOccurrenceSeriesClassifier {
  // EventKit can return a master and its detached /RID= occurrences for one
  // external identifier. Merge connected, normalized local identities before
  // deciding whether that external identifier refers to more than one series.
  static func status(
    identities: [EventOccurrenceTargetIdentity]
  ) -> EventOccurrenceExternalIdentityStatus {
    guard !identities.isEmpty else {
      return .unavailable
    }

    var series: [EventOccurrenceTargetIdentity] = []
    for identity in identities.map(normalizedLocalIdentity) {
      guard !identity.eventIdentifiers.isEmpty || !identity.calendarItemIdentifiers.isEmpty else {
        return .ambiguous
      }

      var mergedIdentity = identity
      while let matchingIndex = series.firstIndex(where: {
        sharesLocalIdentity($0, mergedIdentity)
      }) {
        mergedIdentity = merge(series.remove(at: matchingIndex), mergedIdentity)
      }
      series.append(mergedIdentity)
    }
    return series.count == 1 ? .unique : .ambiguous
  }

  private static func normalizedLocalIdentity(
    _ identity: EventOccurrenceTargetIdentity
  ) -> EventOccurrenceTargetIdentity {
    EventOccurrenceTargetIdentity(
      eventIdentifiers: Set(
        identity.eventIdentifiers.map(EventOccurrenceTargetSelector.normalizedSeriesIdentifier)
      ),
      calendarItemIdentifiers: Set(
        identity.calendarItemIdentifiers.map(
          EventOccurrenceTargetSelector.normalizedSeriesIdentifier
        )
      ),
      externalIdentifiers: []
    )
  }

  private static func sharesLocalIdentity(
    _ lhs: EventOccurrenceTargetIdentity,
    _ rhs: EventOccurrenceTargetIdentity
  ) -> Bool {
    !lhs.eventIdentifiers.isDisjoint(with: rhs.eventIdentifiers)
      || !lhs.calendarItemIdentifiers.isDisjoint(with: rhs.calendarItemIdentifiers)
  }

  private static func merge(
    _ lhs: EventOccurrenceTargetIdentity,
    _ rhs: EventOccurrenceTargetIdentity
  ) -> EventOccurrenceTargetIdentity {
    EventOccurrenceTargetIdentity(
      eventIdentifiers: lhs.eventIdentifiers.union(rhs.eventIdentifiers),
      calendarItemIdentifiers: lhs.calendarItemIdentifiers.union(
        rhs.calendarItemIdentifiers
      ),
      externalIdentifiers: []
    )
  }
}

struct EventOccurrenceSearchPolicy: Equatable, Sendable {
  let maximumWindowCount: Int
  let maximumCandidateCount: Int

  static let defaultValue = EventOccurrenceSearchPolicy(
    maximumWindowCount: 49,
    maximumCandidateCount: 10_000
  )
}

struct EventOccurrenceSearchCandidate<Value> {
  let target: EventOccurrenceTargetCandidate
  let value: Value
}

enum EventOccurrenceResolution<Value> {
  case selected(Value)
  case notFound
  case ambiguous
  case resourceLimitExceeded
  case cancelled
}

extension EventOccurrenceResolution: Sendable where Value: Sendable {}

enum EventOccurrenceResolver {
  static func resolve<Value>(
    acceptedIdentity: EventOccurrenceTargetIdentity,
    calendarId: String,
    occurrenceDate: Date,
    externalIdentityStatus: EventOccurrenceExternalIdentityStatus,
    windows: [EventOccurrenceSearchWindow],
    policy: EventOccurrenceSearchPolicy = .defaultValue,
    candidatesInWindow: (EventOccurrenceSearchWindow) -> [EventOccurrenceSearchCandidate<Value>]
  ) -> EventOccurrenceResolution<Value> {
    var candidateCount = 0
    for (windowIndex, window) in windows.enumerated() {
      if Task.isCancelled {
        return .cancelled
      }
      guard windowIndex < policy.maximumWindowCount else {
        return .resourceLimitExceeded
      }
      let candidates = candidatesInWindow(window)
      candidateCount += candidates.count
      guard candidateCount <= policy.maximumCandidateCount else {
        return .resourceLimitExceeded
      }

      switch EventOccurrenceTargetSelector.select(
        acceptedIdentity: acceptedIdentity,
        calendarId: calendarId,
        occurrenceDate: occurrenceDate,
        candidates: candidates.map(\.target)
      ) {
      case let .selected(index, .local):
        return .selected(candidates[index].value)
      case let .selected(index, .external):
        switch externalIdentityStatus {
        case .unique:
          return .selected(candidates[index].value)
        case .ambiguous:
          return .ambiguous
        case .unavailable:
          return .notFound
        }
      case .ambiguous:
        return .ambiguous
      case .notFound:
        continue
      }
    }
    return .notFound
  }
}

enum EventOccurrenceSearchWindowPlanner {
  static func narrowWindow(around occurrenceDate: Date) -> EventOccurrenceSearchWindow {
    EventOccurrenceSearchWindow(
      startDate: occurrenceDate.addingTimeInterval(-86_400),
      endDate: occurrenceDate.addingTimeInterval(86_400)
    )
  }

  static func fallbackWindows(around occurrenceDate: Date) -> [EventOccurrenceSearchWindow] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let lowerBound = calendar.date(byAdding: .year, value: -2, to: occurrenceDate)
      ?? occurrenceDate.addingTimeInterval(-63_072_000)
    let upperBound = calendar.date(byAdding: .year, value: 2, to: occurrenceDate)
      ?? occurrenceDate.addingTimeInterval(63_072_000)
    let narrowWindow = narrowWindow(around: occurrenceDate)
    var lowerCursor = narrowWindow.startDate
    var upperCursor = narrowWindow.endDate
    var windows: [EventOccurrenceSearchWindow] = []

    while lowerCursor > lowerBound || upperCursor < upperBound {
      if lowerCursor > lowerBound {
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: lowerCursor)
          ?? lowerCursor.addingTimeInterval(-2_678_400)
        let startDate = max(lowerBound, previousMonth)
        windows.append(EventOccurrenceSearchWindow(startDate: startDate, endDate: lowerCursor))
        lowerCursor = startDate
      }
      if upperCursor < upperBound {
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: upperCursor)
          ?? upperCursor.addingTimeInterval(2_678_400)
        let endDate = min(upperBound, nextMonth)
        windows.append(EventOccurrenceSearchWindow(startDate: upperCursor, endDate: endDate))
        upperCursor = endDate
      }
    }
    return windows
  }
}

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
      return try resolveEvent(eventId: eventId, occurrenceDate: occurrenceDate)
        .map(EventKitCalendarReminderMapper.calendarEvent)
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
      let ekEvent = try existingEvent(id: request.eventId, occurrenceDate: request.occurrenceDate)
      let calendar = try eventCalendar(id: request.event.calendarId)
      try EventKitCalendarReminderMapper.apply(
        request.event,
        to: ekEvent,
        calendar: calendar,
        includeRecurrenceRules: request.updatesRecurrenceRules
      )
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
    if let event = try resolveEvent(eventId: id, occurrenceDate: occurrenceDate) {
      return event
    }
    throw AppleGatewayError(code: .eventNotFound, message: "Event not found", details: ["eventId": id])
  }

  private func resolveEvent(eventId: String, occurrenceDate: Date?) throws -> EKEvent? {
    guard let resolved = store.event(withIdentifier: eventId) else {
      return nil
    }
    guard let occurrenceDate else {
      return resolved
    }

    let acceptedIdentity = eventIdentity(resolved, including: eventId)
    let windows = [EventOccurrenceSearchWindowPlanner.narrowWindow(around: occurrenceDate)]
      + EventOccurrenceSearchWindowPlanner.fallbackWindows(around: occurrenceDate)
    let resolution = EventOccurrenceResolver.resolve(
      acceptedIdentity: acceptedIdentity,
      calendarId: resolved.calendar.calendarIdentifier,
      occurrenceDate: occurrenceDate,
      externalIdentityStatus: externalIdentityStatus(
        acceptedIdentity: acceptedIdentity,
        calendar: resolved.calendar
      ),
      windows: windows,
      candidatesInWindow: { window in
        self.occurrenceCandidates(calendar: resolved.calendar, window: window)
      }
    )
    switch resolution {
    case let .selected(event):
      return event
    case .notFound, .ambiguous:
      return nil
    case .cancelled:
      throw CancellationError()
    case .resourceLimitExceeded:
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Event occurrence lookup exceeded safe search limits",
        details: [
          "eventId": eventId,
          "maximumWindowCount": String(EventOccurrenceSearchPolicy.defaultValue.maximumWindowCount),
          "maximumCandidateCount": String(EventOccurrenceSearchPolicy.defaultValue.maximumCandidateCount)
        ]
      )
    }
  }

  private func externalIdentityStatus(
    acceptedIdentity: EventOccurrenceTargetIdentity,
    calendar: EKCalendar
  ) -> EventOccurrenceExternalIdentityStatus {
    guard !acceptedIdentity.externalIdentifiers.isEmpty else {
      return .unavailable
    }
    let matchingIdentities: [EventOccurrenceTargetIdentity] =
      acceptedIdentity.externalIdentifiers.flatMap { externalIdentifier in
        store.calendarItems(withExternalIdentifier: externalIdentifier).compactMap { item in
          guard
            let event = item as? EKEvent,
            event.calendar.calendarIdentifier == calendar.calendarIdentifier
          else {
            return nil
          }
          return eventIdentity(event)
        }
      }
    return EventOccurrenceSeriesClassifier.status(
      identities: matchingIdentities
    )
  }

  private func occurrenceCandidates(
    calendar: EKCalendar,
    window: EventOccurrenceSearchWindow
  ) -> [EventOccurrenceSearchCandidate<EKEvent>] {
    let predicate = store.predicateForEvents(
      withStart: window.startDate,
      end: window.endDate,
      calendars: [calendar]
    )
    return store.events(matching: predicate).map { event in
      EventOccurrenceSearchCandidate(
        target: EventOccurrenceTargetCandidate(
          identity: eventIdentity(event),
          calendarId: event.calendar.calendarIdentifier,
          occurrenceDate: event.occurrenceDate
        ),
        value: event
      )
    }
  }

  private func eventIdentity(
    _ event: EKEvent,
    including fallbackEventIdentifier: String? = nil
  ) -> EventOccurrenceTargetIdentity {
    EventOccurrenceTargetIdentity(
      eventIdentifiers: nonEmptyIdentitySet([
        fallbackEventIdentifier,
        event.eventIdentifier
      ]),
      calendarItemIdentifiers: nonEmptyIdentitySet([event.calendarItemIdentifier]),
      externalIdentifiers: nonEmptyIdentitySet([event.calendarItemExternalIdentifier])
    )
  }

  private func nonEmptyIdentitySet(_ identities: [String?]) -> Set<String> {
    Set(identities.compactMap { identity in
      guard let identity, !identity.isEmpty else {
        return nil
      }
      return identity
    })
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
