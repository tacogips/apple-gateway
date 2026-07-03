import AppleGatewayCore
import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

@main
struct AppleGatewayNotifierMain {
  static func main() async {
    let data = readRequestData()
    let response: NotificationHelperResponse

    switch NotificationHelperProtocol.decodeRequestResult(from: data) {
    case .success(let request):
      response = await NotificationRuntime().handle(request)
    case .failure(let failure):
      response = failure
    }

    do {
      let output = try NotificationHelperProtocol.encodeResponse(response)
      FileHandle.standardOutput.write(output)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      let fallback = #"{"error":{"code":"UNEXPECTED_ERROR","message":"Failed to encode notification helper response"},"ok":false,"protocolVersion":1}"#
      FileHandle.standardOutput.write(Data(fallback.utf8))
      FileHandle.standardOutput.write(Data("\n".utf8))
      exit(1)
    }

    exit(response.ok ? 0 : 1)
  }

  private static func readRequestData() -> Data {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if let request = arguments.first, !request.isEmpty {
      return Data(request.utf8)
    }
    return FileHandle.standardInput.readDataToEndOfFile()
  }
}

private struct NotificationRuntime {
  func handle(_ request: NotificationHelperRequest) async -> NotificationHelperResponse {
    #if canImport(UserNotifications)
    return await UserNotificationRuntime().handle(request)
    #else
    return .failure(NotificationHelperProtocolError(
      code: .notificationUnavailable,
      message: "UserNotifications is unavailable on this platform"
    ))
    #endif
  }
}

#if canImport(UserNotifications)
private final class UserNotificationRuntime: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private let center = UNUserNotificationCenter.current()
  private let activationStore = ActivationContinuationStore()
  private var actionLabelsByIdentifier: [String: String] = [:]

  func handle(_ request: NotificationHelperRequest) async -> NotificationHelperResponse {
    switch request.operation {
    case .post:
      return await post(request)
    case .list:
      return await list()
    case .dismiss:
      return dismiss(request)
    case .dismissAll:
      return await dismissAll()
    case .settings:
      return await settings()
    }
  }

  private func post(_ request: NotificationHelperRequest) async -> NotificationHelperResponse {
    let granted = await requestAuthorization()
    guard granted else {
      return .failure(NotificationHelperProtocolError(
        code: .permissionDenied,
        message: "Notification authorization was not granted"
      ))
    }

    center.delegate = self
    let id = request.id ?? UUID().uuidString
    let content = UNMutableNotificationContent()
    content.title = request.title ?? ""
    content.subtitle = request.subtitle ?? ""
    content.body = request.body ?? ""
    if let sound = request.sound {
      content.sound = sound == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(sound))
    }

    if request.actions?.isEmpty == false || request.allowReply == true {
      let categoryIdentifier = "apple-gateway-\(id)"
      content.categoryIdentifier = categoryIdentifier
      center.setNotificationCategories([category(for: categoryIdentifier, request: request)])
    }

    let notificationRequest = UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: nil
    )

    do {
      try await add(notificationRequest)
    } catch {
      return .failure(NotificationHelperProtocolError(
        code: .notificationUnavailable,
        message: "Failed to post notification",
        details: ["underlyingError": String(describing: error)]
      ))
    }

    let activation: NotificationHelperActivation?
    if let waitSeconds = request.waitSeconds {
      activation = await waitForActivation(timeoutSeconds: waitSeconds)
    } else {
      activation = nil
    }

    return .success(NotificationHelperResult(
      posted: NotificationHelperPosted(id: id, delivered: true, activation: activation)
    ))
  }

  private func list() async -> NotificationHelperResponse {
    return .success(NotificationHelperResult(notifications: await deliveredNotificationSnapshots()))
  }

  private func dismiss(_ request: NotificationHelperRequest) -> NotificationHelperResponse {
    let ids = request.ids ?? []
    center.removeDeliveredNotifications(withIdentifiers: ids)
    return .success(NotificationHelperResult(dismissedCount: ids.count))
  }

  private func dismissAll() async -> NotificationHelperResponse {
    let count = await deliveredNotificationCount()
    center.removeAllDeliveredNotifications()
    return .success(NotificationHelperResult(dismissedCount: count))
  }

  private func settings() async -> NotificationHelperResponse {
    let settings = await notificationSettings()
    return .success(NotificationHelperResult(settings: NotificationHelperSettings(
      authorizationStatus: String(describing: settings.authorizationStatus),
      alertSetting: String(describing: settings.alertSetting),
      soundSetting: String(describing: settings.soundSetting)
    )))
  }

  private func requestAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        continuation.resume(returning: granted)
      }
    }
  }

  private func add(_ request: UNNotificationRequest) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      center.add(request) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func deliveredNotificationSnapshots() async -> [NotificationHelperDeliveredNotification] {
    let bundleId = Bundle.main.bundleIdentifier
    return await withCheckedContinuation { continuation in
      center.getDeliveredNotifications { notifications in
        let formatter = ISO8601DateFormatter()
        continuation.resume(returning: notifications.map { notification in
          NotificationHelperDeliveredNotification(
            id: notification.request.identifier,
            appBundleId: bundleId,
            title: notification.request.content.title,
            subtitle: notification.request.content.subtitle,
            body: notification.request.content.body,
            deliveredAt: formatter.string(from: notification.date)
          )
        })
      }
    }
  }

  private func deliveredNotificationCount() async -> Int {
    await withCheckedContinuation { continuation in
      center.getDeliveredNotifications { notifications in
        continuation.resume(returning: notifications.count)
      }
    }
  }

  private func notificationSettings() async -> UNNotificationSettings {
    await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(returning: settings)
      }
    }
  }

  private func category(for identifier: String, request: NotificationHelperRequest) -> UNNotificationCategory {
    var actions: [UNNotificationAction] = []
    actionLabelsByIdentifier.removeAll()

    for (index, label) in (request.actions ?? []).enumerated() {
      let actionIdentifier = "action-\(index)"
      actionLabelsByIdentifier[actionIdentifier] = label
      actions.append(UNNotificationAction(identifier: actionIdentifier, title: label, options: [.foreground]))
    }

    if request.allowReply == true {
      let replyIdentifier = "reply"
      actionLabelsByIdentifier[replyIdentifier] = "Reply"
      actions.append(UNTextInputNotificationAction(
        identifier: replyIdentifier,
        title: "Reply",
        options: [.foreground],
        textInputButtonTitle: "Send",
        textInputPlaceholder: ""
      ))
    }

    return UNNotificationCategory(
      identifier: identifier,
      actions: actions,
      intentIdentifiers: [],
      options: []
    )
  }

  private func waitForActivation(timeoutSeconds: Int) async -> NotificationHelperActivation {
    await withCheckedContinuation { continuation in
      Task {
        await activationStore.set(continuation)
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
        await activationStore.resumeIfPresent(NotificationHelperActivation(kind: .timeout))
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let activation: NotificationHelperActivation
    if let textResponse = response as? UNTextInputNotificationResponse {
      activation = NotificationHelperActivation(
        kind: .replied,
        actionLabel: actionLabelsByIdentifier[textResponse.actionIdentifier],
        replyText: textResponse.userText
      )
    } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      activation = NotificationHelperActivation(kind: .clicked)
    } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
      activation = NotificationHelperActivation(kind: .dismissed)
    } else {
      activation = NotificationHelperActivation(
        kind: .action,
        actionLabel: actionLabelsByIdentifier[response.actionIdentifier]
      )
    }

    await activationStore.resumeIfPresent(activation)
  }
}

private actor ActivationContinuationStore {
  private var continuation: CheckedContinuation<NotificationHelperActivation, Never>?

  func set(_ continuation: CheckedContinuation<NotificationHelperActivation, Never>) {
    self.continuation = continuation
  }

  func resumeIfPresent(_ activation: NotificationHelperActivation) {
    let current = continuation
    continuation = nil
    current?.resume(returning: activation)
  }

}
#endif
