import Foundation

public enum EventKitDateTime {
  public static func parse(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
      return date
    }

    throw AppleGatewayError(
      code: .invalidArgument,
      message: "DateTime must be ISO 8601 with timezone",
      details: ["value": value]
    )
  }

  public static func format(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter.string(from: date)
  }

  public static func dateOnlyComponents(from date: Date, timeZone: TimeZone) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.calendar = calendar
    components.timeZone = timeZone
    return components
  }

  public static func date(fromDateOnly components: DateComponents, timeZone: TimeZone) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var normalized = DateComponents()
    normalized.calendar = calendar
    normalized.timeZone = timeZone
    normalized.year = components.year
    normalized.month = components.month
    normalized.day = components.day
    normalized.hour = 0
    normalized.minute = 0
    normalized.second = 0
    guard let date = calendar.date(from: normalized) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Date-only value must include year, month, and day"
      )
    }
    return date
  }

  public static func allDayRange(
    startDate: Date,
    endDate: Date,
    timeZone: TimeZone
  ) -> EventKitDateOnlyRange {
    EventKitDateOnlyRange(
      start: dateOnlyComponents(from: startDate, timeZone: timeZone),
      end: dateOnlyComponents(from: endDate, timeZone: timeZone)
    )
  }
}

public struct EventKitDateOnlyRange: Equatable, Sendable {
  public var start: DateComponents
  public var end: DateComponents

  public init(start: DateComponents, end: DateComponents) {
    self.start = start
    self.end = end
  }
}
