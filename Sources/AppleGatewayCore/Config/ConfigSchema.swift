import Foundation

enum ConfigScalar: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case boolean(Bool)
}

struct ParsedConfigFile: Equatable, Sendable {
  var values: [String: [String: ConfigScalar]]

  init(values: [String: [String: ConfigScalar]] = [:]) {
    self.values = values
  }
}

enum ConfigSchema {
  static let sections: Set<String> = [
    "storage",
    "limits",
    "domains",
    "mail",
    "notifications"
  ]

  static let keysBySection: [String: Set<String>] = [
    "storage": ["cache_dir"],
    "limits": [
      "default_page_size",
      "max_page_size",
      "max_inline_body_bytes",
      "apple_event_timeout_seconds",
      "apple_event_batch_size"
    ],
    "domains": [
      "calendar",
      "reminders",
      "clock_alarms",
      "notes",
      "mail",
      "notifications"
    ],
    "mail": ["mail_root"],
    "notifications": ["helper_app_path"]
  ]

  static let envOverrides: [String: (section: String, key: String)] = [
    "APPLE_GATEWAY_STORAGE_CACHE_DIR": ("storage", "cache_dir"),
    "APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE": ("limits", "default_page_size"),
    "APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE": ("limits", "max_page_size"),
    "APPLE_GATEWAY_LIMITS_MAX_INLINE_BODY_BYTES": ("limits", "max_inline_body_bytes"),
    "APPLE_GATEWAY_LIMITS_APPLE_EVENT_TIMEOUT_SECONDS": ("limits", "apple_event_timeout_seconds"),
    "APPLE_GATEWAY_LIMITS_APPLE_EVENT_BATCH_SIZE": ("limits", "apple_event_batch_size"),
    "APPLE_GATEWAY_DOMAINS_CALENDAR": ("domains", "calendar"),
    "APPLE_GATEWAY_DOMAINS_REMINDERS": ("domains", "reminders"),
    "APPLE_GATEWAY_DOMAINS_CLOCK_ALARMS": ("domains", "clock_alarms"),
    "APPLE_GATEWAY_DOMAINS_NOTES": ("domains", "notes"),
    "APPLE_GATEWAY_DOMAINS_MAIL": ("domains", "mail"),
    "APPLE_GATEWAY_DOMAINS_NOTIFICATIONS": ("domains", "notifications"),
    "APPLE_GATEWAY_MAIL_MAIL_ROOT": ("mail", "mail_root"),
    "APPLE_GATEWAY_NOTIFICATIONS_HELPER_APP_PATH": ("notifications", "helper_app_path")
  ]

  static let envSectionPrefixes = [
    "APPLE_GATEWAY_STORAGE_",
    "APPLE_GATEWAY_LIMITS_",
    "APPLE_GATEWAY_DOMAINS_",
    "APPLE_GATEWAY_MAIL_",
    "APPLE_GATEWAY_NOTIFICATIONS_"
  ]

  static func isKnown(section: String, key: String) -> Bool {
    keysBySection[section]?.contains(key) == true
  }

  static func expectedType(section: String, key: String) -> ConfigValueType? {
    switch (section, key) {
    case ("storage", "cache_dir"),
         ("mail", "mail_root"),
         ("notifications", "helper_app_path"):
      .string
    case ("limits", _):
      .integer
    case ("domains", _):
      .boolean
    default:
      nil
    }
  }
}

enum ConfigValueType {
  case string
  case integer
  case boolean

  var description: String {
    switch self {
    case .string:
      "string"
    case .integer:
      "integer"
    case .boolean:
      "boolean"
    }
  }
}
