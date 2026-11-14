import Foundation

public enum NotificationHelperOperation: String, Codable, CaseIterable, Sendable {
  case post
  case list
  case dismiss
  case dismissAll
  case settings
}

public enum NotificationHelperErrorCode: String, Codable, Sendable {
  case invalidArgument = "INVALID_ARGUMENT"
  case malformedRequest = "MALFORMED_REQUEST"
  case permissionDenied = "PERMISSION_DENIED"
  case protocolVersionMismatch = "PROTOCOL_VERSION_MISMATCH"
  case notificationUnavailable = "NOTIFICATION_UNAVAILABLE"
  case unexpectedError = "UNEXPECTED_ERROR"
}

public struct NotificationHelperProtocolError: Error, Equatable, Sendable {
  public var code: NotificationHelperErrorCode
  public var message: String
  public var details: [String: String]?

  public init(
    code: NotificationHelperErrorCode,
    message: String,
    details: [String: String]? = nil
  ) {
    self.code = code
    self.message = message
    self.details = details
  }
}

public struct NotificationHelperRequest: Codable, Equatable, Sendable {
  public var protocolVersion: Int
  public var operation: NotificationHelperOperation
  public var id: String?
  public var title: String?
  public var subtitle: String?
  public var body: String?
  public var sound: String?
  public var actions: [String]?
  public var allowReply: Bool?
  public var waitSeconds: Int?
  public var ids: [String]?

  public init(
    protocolVersion: Int = NotificationHelperProtocol.supportedProtocolVersion,
    operation: NotificationHelperOperation,
    id: String? = nil,
    title: String? = nil,
    subtitle: String? = nil,
    body: String? = nil,
    sound: String? = nil,
    actions: [String]? = nil,
    allowReply: Bool? = nil,
    waitSeconds: Int? = nil,
    ids: [String]? = nil
  ) {
    self.protocolVersion = protocolVersion
    self.operation = operation
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.sound = sound
    self.actions = actions
    self.allowReply = allowReply
    self.waitSeconds = waitSeconds
    self.ids = ids
  }
}

public enum NotificationHelperActivationKind: String, Codable, Sendable {
  case clicked
  case action
  case replied
  case timeout
  case dismissed
}

public struct NotificationHelperActivation: Codable, Equatable, Sendable {
  public var kind: NotificationHelperActivationKind
  public var actionLabel: String?
  public var replyText: String?

  public init(
    kind: NotificationHelperActivationKind,
    actionLabel: String? = nil,
    replyText: String? = nil
  ) {
    self.kind = kind
    self.actionLabel = actionLabel
    self.replyText = replyText
  }
}

public struct NotificationHelperPosted: Codable, Equatable, Sendable {
  public var id: String
  public var delivered: Bool
  public var activation: NotificationHelperActivation?

  public init(id: String, delivered: Bool, activation: NotificationHelperActivation? = nil) {
    self.id = id
    self.delivered = delivered
    self.activation = activation
  }
}

public struct NotificationHelperDeliveredNotification: Codable, Equatable, Sendable {
  public var id: String
  public var appBundleId: String?
  public var title: String?
  public var subtitle: String?
  public var body: String?
  public var deliveredAt: String?

  public init(
    id: String,
    appBundleId: String? = nil,
    title: String? = nil,
    subtitle: String? = nil,
    body: String? = nil,
    deliveredAt: String? = nil
  ) {
    self.id = id
    self.appBundleId = appBundleId
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.deliveredAt = deliveredAt
  }
}

public struct NotificationHelperSettings: Codable, Equatable, Sendable {
  public var authorizationStatus: String
  public var alertSetting: String?
  public var soundSetting: String?

  public init(
    authorizationStatus: String,
    alertSetting: String? = nil,
    soundSetting: String? = nil
  ) {
    self.authorizationStatus = authorizationStatus
    self.alertSetting = alertSetting
    self.soundSetting = soundSetting
  }
}

public struct NotificationHelperResult: Codable, Equatable, Sendable {
  public var posted: NotificationHelperPosted?
  public var notifications: [NotificationHelperDeliveredNotification]?
  public var dismissedCount: Int?
  public var settings: NotificationHelperSettings?

  public init(
    posted: NotificationHelperPosted? = nil,
    notifications: [NotificationHelperDeliveredNotification]? = nil,
    dismissedCount: Int? = nil,
    settings: NotificationHelperSettings? = nil
  ) {
    self.posted = posted
    self.notifications = notifications
    self.dismissedCount = dismissedCount
    self.settings = settings
  }
}

public struct NotificationHelperError: Codable, Equatable, Sendable {
  public var code: NotificationHelperErrorCode
  public var message: String
  public var details: [String: String]?

  public init(code: NotificationHelperErrorCode, message: String, details: [String: String]? = nil) {
    self.code = code
    self.message = message
    self.details = details
  }

  public init(_ error: NotificationHelperProtocolError) {
    self.init(code: error.code, message: error.message, details: error.details)
  }
}

public struct NotificationHelperResponse: Codable, Equatable, Sendable {
  public var protocolVersion: Int
  public var ok: Bool
  public var result: NotificationHelperResult?
  public var error: NotificationHelperError?

  public init(
    protocolVersion: Int = NotificationHelperProtocol.supportedProtocolVersion,
    ok: Bool,
    result: NotificationHelperResult? = nil,
    error: NotificationHelperError? = nil
  ) {
    self.protocolVersion = protocolVersion
    self.ok = ok
    self.result = result
    self.error = error
  }

  public static func success(_ result: NotificationHelperResult) -> NotificationHelperResponse {
    NotificationHelperResponse(ok: true, result: result)
  }

  public static func failure(_ error: NotificationHelperProtocolError) -> NotificationHelperResponse {
    NotificationHelperResponse(ok: false, error: NotificationHelperError(error))
  }
}

public enum NotificationHelperRequestDecodeResult: Equatable, Sendable {
  case success(NotificationHelperRequest)
  case failure(NotificationHelperResponse)
}

public enum NotificationHelperProtocol {
  public static let supportedProtocolVersion = 1

  public static func encodeRequest(_ request: NotificationHelperRequest) throws -> Data {
    try encoder.encode(request)
  }

  public static func encodeResponse(_ response: NotificationHelperResponse) throws -> Data {
    try encoder.encode(response)
  }

  public static func decodeRequest(from data: Data) throws -> NotificationHelperRequest {
    let object = try parseObject(from: data)
    let version = try parseProtocolVersion(from: object)
    guard version == supportedProtocolVersion else {
      throw NotificationHelperProtocolError(
        code: .protocolVersionMismatch,
        message: "Unsupported notification helper protocolVersion",
        details: [
          "supportedProtocolVersion": String(supportedProtocolVersion),
          "receivedProtocolVersion": String(version)
        ]
      )
    }

    let operation = try parseOperation(from: object)
    try validateKeys(Set(object.keys), for: operation)

    let request: NotificationHelperRequest
    do {
      request = try decoder.decode(NotificationHelperRequest.self, from: data)
    } catch {
      throw NotificationHelperProtocolError(
        code: .malformedRequest,
        message: "Notification helper request has invalid field types",
        details: ["underlyingError": String(describing: error)]
      )
    }
    try validate(request)
    return request
  }

  public static func decodeRequestResult(from data: Data) -> NotificationHelperRequestDecodeResult {
    do {
      return .success(try decodeRequest(from: data))
    } catch let error as NotificationHelperProtocolError {
      return .failure(NotificationHelperResponse.failure(error))
    } catch {
      return .failure(NotificationHelperResponse.failure(NotificationHelperProtocolError(
        code: .unexpectedError,
        message: "Unexpected notification helper request failure",
        details: ["underlyingError": String(describing: error)]
      )))
    }
  }

  public static func decodeResponse(from data: Data) throws -> NotificationHelperResponse {
    try decoder.decode(NotificationHelperResponse.self, from: data)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()
}

private extension NotificationHelperProtocol {
  static let titleLimit = 256
  static let optionalTextLimit = 2_048
  static let idLimit = 512
  static let soundLimit = 128
  static let maxActions = 4
  static let actionLimit = 128
  static let maxWaitSeconds = 86_400

  static let globalKeys: Set<String> = ["protocolVersion", "operation"]
  static let postKeys = globalKeys.union(["id", "title", "subtitle", "body", "sound", "actions", "allowReply", "waitSeconds"])
  static let dismissKeys = globalKeys.union(["ids"])

  static func parseObject(from data: Data) throws -> [String: Any] {
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NotificationHelperProtocolError(
          code: .malformedRequest,
          message: "Notification helper request must be a JSON object"
        )
      }
      return object
    } catch let error as NotificationHelperProtocolError {
      throw error
    } catch {
      throw NotificationHelperProtocolError(
        code: .malformedRequest,
        message: "Notification helper request must be valid JSON",
        details: ["underlyingError": String(describing: error)]
      )
    }
  }

  static func parseProtocolVersion(from object: [String: Any]) throws -> Int {
    guard let rawVersion = object["protocolVersion"] else {
      throw NotificationHelperProtocolError(
        code: .malformedRequest,
        message: "Notification helper request is missing protocolVersion"
      )
    }
    guard let number = rawVersion as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.rounded(.towardZero) == number.doubleValue else {
      throw NotificationHelperProtocolError(
        code: .malformedRequest,
        message: "Notification helper protocolVersion must be an integer"
      )
    }
    return number.intValue
  }

  static func parseOperation(from object: [String: Any]) throws -> NotificationHelperOperation {
    guard let operationValue = object["operation"] as? String else {
      throw NotificationHelperProtocolError(
        code: .invalidArgument,
        message: "Notification helper request is missing operation"
      )
    }
    guard let operation = NotificationHelperOperation(rawValue: operationValue) else {
      throw NotificationHelperProtocolError(
        code: .invalidArgument,
        message: "Unknown notification helper operation",
        details: ["operation": operationValue]
      )
    }
    return operation
  }

  static func validateKeys(_ keys: Set<String>, for operation: NotificationHelperOperation) throws {
    let allowed: Set<String>
    switch operation {
    case .post:
      allowed = postKeys
    case .dismiss:
      allowed = dismissKeys
    case .list, .dismissAll, .settings:
      allowed = globalKeys
    }

    let unexpected = keys.subtracting(allowed).sorted()
    guard unexpected.isEmpty else {
      throw NotificationHelperProtocolError(
        code: .invalidArgument,
        message: "Notification helper request has unsupported fields for operation \(operation.rawValue)",
        details: ["fields": unexpected.joined(separator: ",")]
      )
    }
  }

  static func validate(_ request: NotificationHelperRequest) throws {
    switch request.operation {
    case .post:
      try validatePost(request)
    case .dismiss:
      try validateDismiss(request)
    case .list, .dismissAll, .settings:
      break
    }
  }

  static func validatePost(_ request: NotificationHelperRequest) throws {
    guard let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      throw invalidArgument("post requires a non-empty title")
    }
    try validateBoundedString(title, field: "title", limit: titleLimit, allowEmpty: false)
    try validateBoundedString(request.id, field: "id", limit: idLimit, allowEmpty: false)
    try validateBoundedString(request.subtitle, field: "subtitle", limit: optionalTextLimit, allowEmpty: true)
    try validateBoundedString(request.body, field: "body", limit: optionalTextLimit, allowEmpty: true)
    try validateBoundedString(request.sound, field: "sound", limit: soundLimit, allowEmpty: false)

    if let actions = request.actions {
      guard actions.count <= maxActions else {
        throw invalidArgument("post actions must contain at most \(maxActions) labels")
      }
      for (index, action) in actions.enumerated() {
        try validateBoundedString(action, field: "actions[\(index)]", limit: actionLimit, allowEmpty: false)
      }
    }

    if let waitSeconds = request.waitSeconds, waitSeconds <= 0 || waitSeconds > maxWaitSeconds {
      throw invalidArgument("waitSeconds must be between 1 and \(maxWaitSeconds)")
    }
  }

  static func validateDismiss(_ request: NotificationHelperRequest) throws {
    guard let ids = request.ids, !ids.isEmpty else {
      throw invalidArgument("dismiss requires at least one id")
    }
    for (index, id) in ids.enumerated() {
      try validateBoundedString(id, field: "ids[\(index)]", limit: idLimit, allowEmpty: false)
    }
  }

  static func validateBoundedString(
    _ value: String?,
    field: String,
    limit: Int,
    allowEmpty: Bool
  ) throws {
    guard let value else {
      return
    }
    if !allowEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw invalidArgument("\(field) must not be empty")
    }
    if value.count > limit {
      throw invalidArgument("\(field) must be at most \(limit) characters")
    }
  }

  static func invalidArgument(_ message: String) -> NotificationHelperProtocolError {
    NotificationHelperProtocolError(code: .invalidArgument, message: message)
  }
}
