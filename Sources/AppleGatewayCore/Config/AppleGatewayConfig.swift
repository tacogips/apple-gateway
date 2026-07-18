import Foundation

// swiftlint:disable nesting

public struct AppleGatewayConfig: Codable, Equatable, Sendable {
  public var storage: Storage
  public var limits: Limits
  public var domains: Domains
  public var mail: Mail
  public var notifications: Notifications

  public init(
    storage: Storage = .defaultValue,
    limits: Limits = .defaultValue,
    domains: Domains = .defaultValue,
    mail: Mail = .defaultValue,
    notifications: Notifications = .defaultValue
  ) {
    self.storage = storage
    self.limits = limits
    self.domains = domains
    self.mail = mail
    self.notifications = notifications
  }

  public static let defaultValue = AppleGatewayConfig()

  enum CodingKeys: String, CodingKey {
    case storage
    case limits
    case domains
    case mail
    case notifications
  }
}

public extension AppleGatewayConfig {
  struct Storage: Codable, Equatable, Sendable {
    public var cacheDir: String

    public init(cacheDir: String) {
      self.cacheDir = cacheDir
    }

    public static let defaultValue = Storage(cacheDir: "~/.cache/apple-gateway")

    enum CodingKeys: String, CodingKey {
      case cacheDir = "cache_dir"
    }
  }

  struct Limits: Codable, Equatable, Sendable {
    public var defaultPageSize: Int
    public var maxPageSize: Int
    public var maxInlineBodyBytes: Int
    public var appleEventTimeoutSeconds: Int
    public var appleEventBatchSize: Int

    public init(
      defaultPageSize: Int,
      maxPageSize: Int,
      maxInlineBodyBytes: Int,
      appleEventTimeoutSeconds: Int,
      appleEventBatchSize: Int
    ) {
      self.defaultPageSize = defaultPageSize
      self.maxPageSize = maxPageSize
      self.maxInlineBodyBytes = maxInlineBodyBytes
      self.appleEventTimeoutSeconds = appleEventTimeoutSeconds
      self.appleEventBatchSize = appleEventBatchSize
    }

    public static let defaultValue = Limits(
      defaultPageSize: 20,
      maxPageSize: 200,
      maxInlineBodyBytes: 65_536,
      appleEventTimeoutSeconds: 30,
      appleEventBatchSize: 200
    )

    enum CodingKeys: String, CodingKey {
      case defaultPageSize = "default_page_size"
      case maxPageSize = "max_page_size"
      case maxInlineBodyBytes = "max_inline_body_bytes"
      case appleEventTimeoutSeconds = "apple_event_timeout_seconds"
      case appleEventBatchSize = "apple_event_batch_size"
    }
  }

  struct Domains: Codable, Equatable, Sendable {
    public var calendar: Bool
    public var reminders: Bool
    public var clockAlarms: Bool
    public var notes: Bool
    public var mail: Bool
    public var notifications: Bool

    public init(
      calendar: Bool,
      reminders: Bool,
      clockAlarms: Bool,
      notes: Bool,
      mail: Bool,
      notifications: Bool
    ) {
      self.calendar = calendar
      self.reminders = reminders
      self.clockAlarms = clockAlarms
      self.notes = notes
      self.mail = mail
      self.notifications = notifications
    }

    public static let defaultValue = Domains(
      calendar: true,
      reminders: true,
      clockAlarms: true,
      notes: true,
      mail: true,
      notifications: true
    )

    enum CodingKeys: String, CodingKey {
      case calendar
      case reminders
      case clockAlarms = "clock_alarms"
      case notes
      case mail
      case notifications
    }
  }

  struct Mail: Codable, Equatable, Sendable {
    public var mailRoot: String

    public init(mailRoot: String) {
      self.mailRoot = mailRoot
    }

    public static let defaultValue = Mail(mailRoot: "")

    enum CodingKeys: String, CodingKey {
      case mailRoot = "mail_root"
    }
  }

  struct Notifications: Codable, Equatable, Sendable {
    public var helperAppPath: String

    public init(helperAppPath: String) {
      self.helperAppPath = helperAppPath
    }

    public static let defaultValue = Notifications(helperAppPath: "")

    enum CodingKeys: String, CodingKey {
      case helperAppPath = "helper_app_path"
    }
  }
}

public struct ResolvedAppleGatewayConfig: Codable, Equatable, Sendable {
  public var source: AppleGatewayConfigSource
  public var config: AppleGatewayConfig

  public init(source: AppleGatewayConfigSource, config: AppleGatewayConfig) {
    self.source = source
    self.config = config
  }
}

public struct AppleGatewayConfigSource: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case file
    case missingDefault
  }

  public var kind: Kind
  public var path: String
  public var explicit: Bool

  public init(kind: Kind, path: String, explicit: Bool) {
    self.kind = kind
    self.path = path
    self.explicit = explicit
  }
}

// swiftlint:enable nesting
