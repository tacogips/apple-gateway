import Foundation

public enum AppleGatewayErrorCode: String, CaseIterable, Codable, Sendable {
  case invalidArgument = "INVALID_ARGUMENT"
  case graphQLParseError = "GRAPHQL_PARSE_ERROR"
  case graphQLValidationError = "GRAPHQL_VALIDATION_ERROR"
  case writeDisabledInReader = "WRITE_DISABLED_IN_READER"
  case permissionDenied = "PERMISSION_DENIED"
  case permissionNotDetermined = "PERMISSION_NOT_DETERMINED"
  case writeOnlyAccess = "WRITE_ONLY_ACCESS"
  case fullDiskAccessRequired = "FULL_DISK_ACCESS_REQUIRED"
  case automationDenied = "AUTOMATION_DENIED"
  case domainDisabled = "DOMAIN_DISABLED"
  case calendarNotFound = "CALENDAR_NOT_FOUND"
  case eventNotFound = "EVENT_NOT_FOUND"
  case reminderNotFound = "REMINDER_NOT_FOUND"
  case calendarReadOnly = "CALENDAR_READ_ONLY"
  case noteNotFound = "NOTE_NOT_FOUND"
  case noteLocked = "NOTE_LOCKED"
  case noteFolderNotFound = "NOTE_FOLDER_NOT_FOUND"
  case mailboxNotFound = "MAILBOX_NOT_FOUND"
  case messageNotFound = "MESSAGE_NOT_FOUND"
  case mailStoreNotFound = "MAIL_STORE_NOT_FOUND"
  case shortcutNotInstalled = "SHORTCUT_NOT_INSTALLED"
  case shortcutActionUnsupported = "SHORTCUT_ACTION_UNSUPPORTED"
  case notifierHelperMissing = "NOTIFIER_HELPER_MISSING"
  case notificationDBUnavailable = "NOTIFICATION_DB_UNAVAILABLE"
  case appleEventTimeout = "APPLE_EVENT_TIMEOUT"
  case invalidDownloadKey = "INVALID_DOWNLOAD_KEY"
  case fileOperationFailed = "FILE_OPERATION_FAILED"
  case configInvalid = "CONFIG_INVALID"
  case unsupportedOSVersion = "UNSUPPORTED_OS_VERSION"
  case unexpectedError = "UNEXPECTED_ERROR"

  public var exitCode: Int {
    switch self {
    case .unexpectedError:
      return 1
    case .configInvalid:
      return 3
    case .permissionDenied,
         .permissionNotDetermined,
         .writeOnlyAccess,
         .fullDiskAccessRequired,
         .automationDenied:
      return 4
    case .invalidArgument,
         .graphQLParseError,
         .graphQLValidationError,
         .writeDisabledInReader,
         .domainDisabled,
         .calendarNotFound,
         .eventNotFound,
         .reminderNotFound,
         .calendarReadOnly,
         .noteNotFound,
         .noteLocked,
         .noteFolderNotFound,
         .mailboxNotFound,
         .messageNotFound,
         .mailStoreNotFound,
         .invalidDownloadKey:
      return 5
    case .shortcutNotInstalled,
         .shortcutActionUnsupported,
         .notifierHelperMissing,
         .notificationDBUnavailable,
         .appleEventTimeout,
         .fileOperationFailed,
         .unsupportedOSVersion:
      return 6
    }
  }
}

public struct AppleGatewayErrorLocation: Codable, Equatable, Sendable {
  public var line: Int
  public var column: Int

  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

public struct AppleGatewayError: Error, Equatable, Sendable {
  public var code: AppleGatewayErrorCode
  public var message: String
  public var details: [String: String]?
  public var locations: [AppleGatewayErrorLocation]?
  public var path: [String]?

  public init(
    code: AppleGatewayErrorCode,
    message: String,
    details: [String: String]? = nil,
    locations: [AppleGatewayErrorLocation]? = nil,
    path: [String]? = nil
  ) {
    self.code = code
    self.message = message
    self.details = details
    self.locations = locations
    self.path = path
  }

  public var exitCode: Int {
    code.exitCode
  }

  public func scoped(to path: [String]) -> AppleGatewayError {
    var scopedError = self
    scopedError.path = path
    return scopedError
  }
}

public struct AppleGatewayJSONResponse: Sendable {
  public var data: Data
  public var exitCode: Int32

  public init(data: Data, exitCode: Int32) {
    self.data = data
    self.exitCode = exitCode
  }
}

public enum AppleGatewayJSONEnvelope {
  public static func successData<Payload: Encodable>(
    _ data: Payload,
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> Data {
    try responseData(data: Optional(data), errors: [], requestId: requestId, pretty: pretty)
  }

  public static func errorData(
    _ error: AppleGatewayError,
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> Data {
    try responseData(data: Optional<EmptyEnvelopeData>.none, errors: [error], requestId: requestId, pretty: pretty)
  }

  public static func response<Payload: Encodable>(
    data: Payload?,
    errors: [AppleGatewayError],
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> AppleGatewayJSONResponse {
    let encoded = try responseData(data: data, errors: errors, requestId: requestId, pretty: pretty)
    return AppleGatewayJSONResponse(data: encoded, exitCode: exitCode(for: errors))
  }

  public static func responseData<Payload: Encodable>(
    data: Payload?,
    errors: [AppleGatewayError],
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> Data {
    let envelope = Envelope(
      data: data,
      errors: errors.isEmpty ? nil : errors.map(EnvelopeError.init),
      extensions: EnvelopeExtensions(requestId: requestId)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return try encoder.encode(envelope)
  }

  public static func exitCode(for errors: [AppleGatewayError]) -> Int32 {
    Int32(errors.first?.exitCode ?? 0)
  }
}

private struct EmptyEnvelopeData: Encodable {}

private struct Envelope<Payload: Encodable>: Encodable {
  var data: Payload?
  var errors: [EnvelopeError]?
  var extensions: EnvelopeExtensions

  enum CodingKeys: String, CodingKey {
    case data
    case errors
    case extensions
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if let data {
      try container.encode(data, forKey: .data)
    } else {
      try container.encodeNil(forKey: .data)
    }
    try container.encodeIfPresent(errors, forKey: .errors)
    try container.encode(extensions, forKey: .extensions)
  }
}

private struct EnvelopeError: Encodable {
  var message: String
  var locations: [AppleGatewayErrorLocation]?
  var path: [String]?
  var extensions: ErrorExtensions

  init(_ error: AppleGatewayError) {
    message = error.message
    locations = error.locations
    path = error.path
    extensions = ErrorExtensions(
      code: error.code,
      exitCode: error.exitCode,
      details: error.details
    )
  }
}

private struct ErrorExtensions: Encodable {
  var code: AppleGatewayErrorCode
  var exitCode: Int
  var details: [String: String]?
}

private struct EnvelopeExtensions: Encodable {
  var requestId: String
}
