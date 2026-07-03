import Foundation

public protocol NotificationsProviding: Sendable {
  func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection
  func postNotification(_ input: PostNotificationInput) throws -> PostedNotification
  func listGatewayNotifications() throws -> [DeliveredNotification]
  func dismissNotifications(ids: [String]) throws -> DismissResult
  func dismissAllGatewayNotifications() throws -> DismissResult
}

enum NotificationsServiceFactory {
  static func unavailableService() -> any NotificationsProviding {
    UnavailableNotificationsService()
  }

  static func liveService(config: AppleGatewayConfig) -> any NotificationsProviding {
    LiveNotificationsAdapter(config: config)
  }
}

private struct UnavailableNotificationsService: NotificationsProviding {
  func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    throw unavailable()
  }

  func postNotification(_ input: PostNotificationInput) throws -> PostedNotification {
    throw unavailable()
  }

  func listGatewayNotifications() throws -> [DeliveredNotification] {
    throw unavailable()
  }

  func dismissNotifications(ids: [String]) throws -> DismissResult {
    throw unavailable()
  }

  func dismissAllGatewayNotifications() throws -> DismissResult {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Notifications provider is unavailable")
  }
}
