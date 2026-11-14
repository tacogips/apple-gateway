import Foundation

public struct PostNotificationInput: Codable, Equatable, Sendable {
  public var title: String
  public var subtitle: String?
  public var body: String?
  public var sound: Bool
  public var actions: [String]
  public var allowReply: Bool
  public var waitSeconds: Int?
  public var allowFallback: Bool

  public init(
    title: String,
    subtitle: String? = nil,
    body: String? = nil,
    sound: Bool = true,
    actions: [String] = [],
    allowReply: Bool = false,
    waitSeconds: Int? = nil,
    allowFallback: Bool = false
  ) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.sound = sound
    self.actions = actions
    self.allowReply = allowReply
    self.waitSeconds = waitSeconds
    self.allowFallback = allowFallback
  }
}

public enum NotificationActivationKind: String, Codable, Sendable {
  case clicked
  case action
  case replied
  case timeout
  case dismissed
}

public struct NotificationActivation: Codable, Equatable, Sendable {
  public var kind: NotificationActivationKind
  public var actionLabel: String?
  public var replyText: String?

  public init(kind: NotificationActivationKind, actionLabel: String? = nil, replyText: String? = nil) {
    self.kind = kind
    self.actionLabel = actionLabel
    self.replyText = replyText
  }
}

public struct PostedNotification: Codable, Equatable, Sendable {
  public var id: String
  public var delivered: Bool
  public var usedFallback: Bool
  public var activation: NotificationActivation?

  public init(
    id: String,
    delivered: Bool,
    usedFallback: Bool,
    activation: NotificationActivation? = nil
  ) {
    self.id = id
    self.delivered = delivered
    self.usedFallback = usedFallback
    self.activation = activation
  }
}

public enum NotificationSource: String, Codable, Sendable {
  case gatewayHelper = "GATEWAY_HELPER"
  case systemDb = "SYSTEM_DB"
}

public struct DeliveredNotification: Codable, Equatable, Sendable {
  public var id: String
  public var source: NotificationSource
  public var appBundleId: String?
  public var title: String?
  public var subtitle: String?
  public var body: String?
  public var deliveredAt: String?

  public init(
    id: String,
    source: NotificationSource,
    appBundleId: String? = nil,
    title: String? = nil,
    subtitle: String? = nil,
    body: String? = nil,
    deliveredAt: String? = nil
  ) {
    self.id = id
    self.source = source
    self.appBundleId = appBundleId
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.deliveredAt = deliveredAt
  }
}

public struct DismissResult: Codable, Equatable, Sendable {
  public var dismissedCount: Int

  public init(dismissedCount: Int) {
    self.dismissedCount = dismissedCount
  }
}

public struct NotificationSearchInput: Codable, Equatable, Sendable {
  public var source: NotificationSource
  public var appBundleId: String?
  public var deliveredAfter: Date?
  public var deliveredBefore: Date?
  public var first: Int?
  public var after: String?

  public init(
    source: NotificationSource = .systemDb,
    appBundleId: String? = nil,
    deliveredAfter: Date? = nil,
    deliveredBefore: Date? = nil,
    first: Int? = nil,
    after: String? = nil
  ) {
    self.source = source
    self.appBundleId = appBundleId
    self.deliveredAfter = deliveredAfter
    self.deliveredBefore = deliveredBefore
    self.first = first
    self.after = after
  }
}

public struct DeliveredNotificationEdge: Codable, Equatable, Sendable {
  public var cursor: String
  public var node: DeliveredNotification

  public init(cursor: String, node: DeliveredNotification) {
    self.cursor = cursor
    self.node = node
  }
}

public struct DeliveredNotificationConnection: Codable, Equatable, Sendable {
  public var edges: [DeliveredNotificationEdge]
  public var pageInfo: PageInfo
  public var totalCount: Int
  public var warnings: [NotificationListingWarning]

  public init(
    edges: [DeliveredNotificationEdge],
    pageInfo: PageInfo,
    totalCount: Int,
    warnings: [NotificationListingWarning] = []
  ) {
    self.edges = edges
    self.pageInfo = pageInfo
    self.totalCount = totalCount
    self.warnings = warnings
  }
}

public struct NotificationListingWarning: Codable, Equatable, Sendable {
  public var id: String
  public var message: String

  public init(id: String, message: String) {
    self.id = id
    self.message = message
  }
}
