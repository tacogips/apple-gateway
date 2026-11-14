import Foundation

public struct NotificationHelperBundle: Equatable, Sendable {
  public var appURL: URL
  public var executableURL: URL

  public init(appURL: URL, executableURL: URL) {
    self.appURL = appURL
    self.executableURL = executableURL
  }
}

public struct NotificationHelperResolver: @unchecked Sendable {
  private let fileManager: FileManager
  private let cliExecutablePath: String?
  private let homeDirectory: String
  private let applicationsDirectory: String

  public init(
    fileManager: FileManager = .default,
    cliExecutablePath: String? = CommandLine.arguments.first,
    homeDirectory: String = NSHomeDirectory(),
    applicationsDirectory: String = "/Applications"
  ) {
    self.fileManager = fileManager
    self.cliExecutablePath = cliExecutablePath
    self.homeDirectory = homeDirectory
    self.applicationsDirectory = applicationsDirectory
  }

  public func resolve(config: AppleGatewayConfig) throws -> NotificationHelperBundle {
    let candidates = candidateAppPaths(config: config)
    for path in candidates {
      let appURL = URL(fileURLWithPath: path)
      let executableURL = appURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("MacOS")
        .appendingPathComponent("AppleGatewayNotifier")
      if fileManager.isExecutableFile(atPath: executableURL.path) {
        return NotificationHelperBundle(appURL: appURL, executableURL: executableURL)
      }
    }

    throw AppleGatewayError(
      code: .notifierHelperMissing,
      message: "AppleGatewayNotifier.app was not found",
      details: ["candidates": candidates.joined(separator: ":")]
    )
  }

  public func candidateAppPaths(config: AppleGatewayConfig) -> [String] {
    var candidates: [String] = []
    if !config.notifications.helperAppPath.isEmpty {
      candidates.append(config.notifications.helperAppPath)
    }
    if let cliExecutablePath {
      let cliURL = URL(fileURLWithPath: cliExecutablePath)
      let homebrewCandidate = cliURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("libexec")
        .appendingPathComponent("AppleGatewayNotifier.app")
        .standardizedFileURL
        .path
      candidates.append(homebrewCandidate)
    }
    candidates.append(URL(fileURLWithPath: applicationsDirectory).appendingPathComponent("AppleGatewayNotifier.app").path)
    candidates.append(URL(fileURLWithPath: homeDirectory).appendingPathComponent("Applications/AppleGatewayNotifier.app").path)
    return Array(Set(candidates)).sortedByOriginalOrder(from: candidates)
  }
}

public protocol NotificationHelperExecuting: Sendable {
  func execute(_ request: NotificationHelperRequest, bundle: NotificationHelperBundle) throws -> NotificationHelperResponse
}

public struct SubprocessNotificationHelperExecutor: NotificationHelperExecuting {
  private let timeoutSeconds: TimeInterval
  private let environment: [String: String]

  public init(
    timeoutSeconds: TimeInterval = TimeInterval(AppleGatewayConfig.Limits.defaultValue.appleEventTimeoutSeconds),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.timeoutSeconds = timeoutSeconds
    self.environment = environment
  }

  public func execute(_ request: NotificationHelperRequest, bundle: NotificationHelperBundle) throws -> NotificationHelperResponse {
    let requestData = try NotificationHelperProtocol.encodeRequest(request)
    guard let requestJSON = String(data: requestData, encoding: .utf8) else {
      throw AppleGatewayError(code: .unexpectedError, message: "Failed to encode notification helper request")
    }

    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = bundle.executableURL
    process.arguments = [requestJSON]
    process.environment = environment
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw AppleGatewayError(
        code: .notifierHelperMissing,
        message: "Could not launch AppleGatewayNotifier",
        details: ["path": bundle.executableURL.path, "underlyingError": String(describing: error)]
      )
    }

    let timedOut = !process.waitUntilExit(timeout: timeoutSeconds)
    if timedOut {
      process.terminate()
      process.waitUntilExit()
      throw AppleGatewayError(
        code: .appleEventTimeout,
        message: "AppleGatewayNotifier timed out",
        details: ["timeoutSeconds": String(timeoutSeconds)]
      )
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    do {
      let response = try NotificationHelperProtocol.decodeResponse(from: outputData)
      if process.terminationStatus == 0 || !response.ok {
        return response
      }
    } catch {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "AppleGatewayNotifier returned invalid JSON",
        details: ["stderr": errorText, "underlyingError": String(describing: error)]
      )
    }

    throw AppleGatewayError(
      code: .unexpectedError,
      message: "AppleGatewayNotifier failed",
      details: ["status": String(process.terminationStatus), "stderr": errorText]
    )
  }
}

public protocol NotificationFallbackPosting: Sendable {
  func post(_ input: PostNotificationInput) throws
}

public struct OsascriptNotificationFallback: NotificationFallbackPosting {
  private let osascriptPath: String
  private let timeoutSeconds: TimeInterval

  public init(
    osascriptPath: String = "/usr/bin/osascript",
    timeoutSeconds: TimeInterval = TimeInterval(AppleGatewayConfig.Limits.defaultValue.appleEventTimeoutSeconds)
  ) {
    self.osascriptPath = osascriptPath
    self.timeoutSeconds = timeoutSeconds
  }

  public func post(_ input: PostNotificationInput) throws {
    let process = Process()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: osascriptPath)
    process.arguments = [
      "-e", "on run argv",
      "-e", "display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv)",
      "-e", "end run",
      input.title,
      input.body ?? "",
      input.subtitle ?? ""
    ]
    process.standardOutput = Pipe()
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Could not launch osascript notification fallback",
        details: ["underlyingError": String(describing: error)]
      )
    }

    let timedOut = !process.waitUntilExit(timeout: timeoutSeconds)
    if timedOut {
      process.terminate()
      process.waitUntilExit()
      throw AppleGatewayError(code: .appleEventTimeout, message: "osascript notification fallback timed out")
    }

    guard process.terminationStatus == 0 else {
      let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "osascript notification fallback failed",
        details: ["status": String(process.terminationStatus), "stderr": stderrText]
      )
    }
  }
}

public struct LiveNotificationsAdapter: NotificationsProviding {
  private let config: AppleGatewayConfig
  private let resolver: NotificationHelperResolver
  private let helperExecutor: NotificationHelperExecuting
  private let fallbackPoster: NotificationFallbackPosting

  public init(
    config: AppleGatewayConfig,
    resolver: NotificationHelperResolver = NotificationHelperResolver(),
    helperExecutor: NotificationHelperExecuting = SubprocessNotificationHelperExecutor(),
    fallbackPoster: NotificationFallbackPosting = OsascriptNotificationFallback()
  ) {
    self.config = config
    self.resolver = resolver
    self.helperExecutor = helperExecutor
    self.fallbackPoster = fallbackPoster
  }

  public func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    switch input.source {
    case .gatewayHelper:
      return try gatewayConnection(input: input)
    case .systemDb:
      let database = try UsernotedNotificationStore(config: config).openDatabase()
      defer {
        database.close()
      }
      return try UsernotedNotificationQueryService(database: database, limits: config.limits).notifications(input: input)
    }
  }

  public func postNotification(_ input: PostNotificationInput) throws -> PostedNotification {
    let request = try validatedRequest(NotificationHelperRequest(
      operation: .post,
      title: input.title,
      subtitle: input.subtitle,
      body: input.body,
      sound: input.sound ? "default" : nil,
      actions: input.actions,
      allowReply: input.allowReply,
      waitSeconds: input.waitSeconds
    ))
    do {
      let response = try helperExecutor.execute(request, bundle: try resolver.resolve(config: config))
      let posted = try requireResponse(response).posted
      guard let posted else {
        throw AppleGatewayError(code: .unexpectedError, message: "Notification helper response is missing posted result")
      }
      return PostedNotification(
        id: posted.id,
        delivered: posted.delivered,
        usedFallback: false,
        activation: posted.activation.map(NotificationActivation.init(helperActivation:))
      )
    } catch let error as AppleGatewayError where error.code == .notifierHelperMissing {
      return try postWithFallbackIfAllowed(input, missingHelperError: error)
    }
  }

  public func listGatewayNotifications() throws -> [DeliveredNotification] {
    let response = try helperExecutor.execute(
      NotificationHelperRequest(operation: .list),
      bundle: try resolver.resolve(config: config)
    )
    return try requireResponse(response).notifications?.map {
      DeliveredNotification(
        id: $0.id,
        source: .gatewayHelper,
        appBundleId: $0.appBundleId,
        title: $0.title,
        subtitle: $0.subtitle,
        body: $0.body,
        deliveredAt: $0.deliveredAt
      )
    } ?? []
  }

  public func dismissNotifications(ids: [String]) throws -> DismissResult {
    let response = try helperExecutor.execute(
      try validatedRequest(NotificationHelperRequest(operation: .dismiss, ids: ids)),
      bundle: try resolver.resolve(config: config)
    )
    return DismissResult(dismissedCount: try requireDismissedCount(response))
  }

  public func dismissAllGatewayNotifications() throws -> DismissResult {
    let response = try helperExecutor.execute(
      NotificationHelperRequest(operation: .dismissAll),
      bundle: try resolver.resolve(config: config)
    )
    return DismissResult(dismissedCount: try requireDismissedCount(response))
  }

  private func postWithFallbackIfAllowed(
    _ input: PostNotificationInput,
    missingHelperError: AppleGatewayError
  ) throws -> PostedNotification {
    guard input.allowFallback else {
      throw missingHelperError
    }
    guard input.actions.isEmpty, !input.allowReply, input.waitSeconds == nil else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "osascript notification fallback does not support actions, replies, or activation waiting"
      )
    }
    try fallbackPoster.post(input)
    return PostedNotification(id: UUID().uuidString, delivered: true, usedFallback: true)
  }

  private func requireDismissedCount(_ response: NotificationHelperResponse) throws -> Int {
    guard let dismissedCount = try requireResponse(response).dismissedCount else {
      throw AppleGatewayError(code: .unexpectedError, message: "Notification helper response is missing dismissedCount")
    }
    return dismissedCount
  }

  private func requireResponse(_ response: NotificationHelperResponse) throws -> NotificationHelperResult {
    if response.ok, let result = response.result {
      return result
    }
    if let error = response.error {
      throw AppleGatewayError(notificationHelperError: error)
    }
    throw AppleGatewayError(code: .unexpectedError, message: "Notification helper returned an empty failure")
  }

  private func validatedRequest(_ request: NotificationHelperRequest) throws -> NotificationHelperRequest {
    do {
      return try NotificationHelperProtocol.decodeRequest(from: NotificationHelperProtocol.encodeRequest(request))
    } catch let error as NotificationHelperProtocolError {
      throw AppleGatewayError(notificationHelperError: NotificationHelperError(error))
    }
  }

  private func gatewayConnection(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    if let deliveredAfter = input.deliveredAfter,
       let deliveredBefore = input.deliveredBefore,
       deliveredAfter > deliveredBefore {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "notifications input deliveredAfter must not be after deliveredBefore"
      )
    }
    let hasDateFilter = input.deliveredAfter != nil || input.deliveredBefore != nil
    let notifications = try listGatewayNotifications().filter { notification in
      if let appBundleId = input.appBundleId, notification.appBundleId != appBundleId {
        return false
      }
      guard hasDateFilter else {
        return true
      }
      guard let deliveredAt = Self.helperDate(notification.deliveredAt) else {
        return false
      }
      if let deliveredAfter = input.deliveredAfter, deliveredAt < deliveredAfter {
        return false
      }
      if let deliveredBefore = input.deliveredBefore, deliveredAt >= deliveredBefore {
        return false
      }
      return true
    }
    let first = min(input.first ?? config.limits.defaultPageSize, config.limits.maxPageSize)
    guard first > 0 else {
      throw AppleGatewayError(code: .invalidArgument, message: "first must be positive")
    }
    let offset = try gatewayOffset(after: input.after, notifications: notifications)
    let page = Array(notifications.dropFirst(offset).prefix(first))
    return DeliveredNotificationConnection(
      edges: page.map { notification in
        DeliveredNotificationEdge(cursor: "gateway:\(notification.id)", node: notification)
      },
      pageInfo: PageInfo(
        hasNextPage: offset + page.count < notifications.count,
        endCursor: page.last.map { "gateway:\($0.id)" }
      ),
      totalCount: notifications.count
    )
  }

  private static func helperDate(_ value: String?) -> Date? {
    guard let value else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) {
      return date
    }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value)
  }

  private func gatewayOffset(after cursor: String?, notifications: [DeliveredNotification]) throws -> Int {
    guard let cursor else {
      return 0
    }
    guard cursor.hasPrefix("gateway:") else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid pagination cursor")
    }
    let id = String(cursor.dropFirst("gateway:".count))
    guard let index = notifications.firstIndex(where: { $0.id == id }) else {
      throw AppleGatewayError(code: .invalidArgument, message: "Invalid pagination cursor")
    }
    return index + 1
  }
}

private extension AppleGatewayError {
  init(notificationHelperError error: NotificationHelperError) {
    let code: AppleGatewayErrorCode
    switch error.code {
    case .invalidArgument, .protocolVersionMismatch, .malformedRequest:
      code = .invalidArgument
    case .permissionDenied:
      code = .permissionDenied
    case .notificationUnavailable, .unexpectedError:
      code = .unexpectedError
    }
    self.init(code: code, message: error.message, details: error.details)
  }
}

private extension NotificationActivation {
  init(helperActivation: NotificationHelperActivation) {
    let kind: NotificationActivationKind
    switch helperActivation.kind {
    case .clicked:
      kind = .clicked
    case .action:
      kind = .action
    case .replied:
      kind = .replied
    case .timeout:
      kind = .timeout
    case .dismissed:
      kind = .dismissed
    }
    self.init(kind: kind, actionLabel: helperActivation.actionLabel, replyText: helperActivation.replyText)
  }
}

private extension Array where Element == String {
  func sortedByOriginalOrder(from original: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in original where !seen.contains(item) {
      seen.insert(item)
      result.append(item)
    }
    return result
  }
}

private extension Process {
  func waitUntilExit(timeout seconds: TimeInterval) -> Bool {
    guard seconds > 0 else {
      waitUntilExit()
      return true
    }

    let deadline = Date().addingTimeInterval(seconds)
    while isRunning {
      if Date() >= deadline {
        return false
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return true
  }
}
