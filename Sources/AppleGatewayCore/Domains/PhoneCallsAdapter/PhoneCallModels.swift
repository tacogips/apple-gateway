import Foundation

public enum PhoneCallState: String, Codable, CaseIterable, Sendable {
  case idle = "IDLE"
  case incoming = "INCOMING"
  case active = "ACTIVE"
  case unknown = "UNKNOWN"
}

public enum PhoneCallControlAction: String, Codable, Sendable {
  case dial
  case answer
  case decline
  case end
}

public struct PhoneCallStatus: Codable, Equatable, Sendable {
  public var state: PhoneCallState
  public var callerName: String?
  public var callerNumber: String?
  public var application: String?
  public var warning: String?

  public init(
    state: PhoneCallState,
    callerName: String? = nil,
    callerNumber: String? = nil,
    application: String? = nil,
    warning: String? = nil
  ) {
    self.state = state
    self.callerName = callerName
    self.callerNumber = callerNumber
    self.application = application
    self.warning = warning
  }
}

public struct PlacePhoneCallInput: Codable, Equatable, Sendable {
  public var phoneNumber: String?
  public var contactName: String?
  public var phoneLabel: String?
  public var autoConfirm: Bool

  public init(
    phoneNumber: String? = nil,
    contactName: String? = nil,
    phoneLabel: String? = nil,
    autoConfirm: Bool = false
  ) {
    self.phoneNumber = phoneNumber
    self.contactName = contactName
    self.phoneLabel = phoneLabel
    self.autoConfirm = autoConfirm
  }
}

public struct PhoneCallActionResult: Codable, Equatable, Sendable {
  public var success: Bool
  public var state: PhoneCallState
  public var targetName: String?
  public var application: String?
  public var warning: String?

  public init(
    success: Bool,
    state: PhoneCallState,
    targetName: String? = nil,
    application: String? = nil,
    warning: String? = nil
  ) {
    self.success = success
    self.state = state
    self.targetName = targetName
    self.application = application
    self.warning = warning
  }
}

public struct PlayPhoneCallAudioInput: Codable, Equatable, Sendable {
  public var filePath: String

  public init(filePath: String) {
    self.filePath = filePath
  }
}

public struct PhoneCallAudioConfiguration: Codable, Equatable, Sendable {
  public let playbackDeviceUID: String?
  public let captureDeviceUID: String?
  public let cacheDirectory: URL

  public init(
    playbackDeviceUID: String?,
    captureDeviceUID: String?,
    cacheDirectory: URL
  ) {
    self.playbackDeviceUID = playbackDeviceUID
    self.captureDeviceUID = captureDeviceUID
    self.cacheDirectory = cacheDirectory
  }

  init(config: AppleGatewayConfig) {
    playbackDeviceUID = config.phoneCalls.virtualAudioDeviceUID.nonEmptyPhoneCallValue
    captureDeviceUID = config.phoneCalls.captureAudioDeviceUID.nonEmptyPhoneCallValue
    cacheDirectory = URL(fileURLWithPath: config.storage.cacheDir, isDirectory: true)
  }
}

public struct PhoneCallAudioResult: Codable, Equatable, Sendable {
  public var success: Bool
  public var isPlaying: Bool
  public var filePath: String?
  public var deviceName: String?
  public var warning: String?

  public init(
    success: Bool,
    isPlaying: Bool,
    filePath: String? = nil,
    deviceName: String? = nil,
    warning: String? = nil
  ) {
    self.success = success
    self.isPlaying = isPlaying
    self.filePath = filePath
    self.deviceName = deviceName
    self.warning = warning
  }
}

private extension String {
  var nonEmptyPhoneCallValue: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

public struct StartPhoneCallListeningInput: Codable, Equatable, Sendable {
  public var chunkDurationSeconds: Int

  public init(chunkDurationSeconds: Int = 5) {
    self.chunkDurationSeconds = chunkDurationSeconds
  }
}

public struct PhoneCallListeningStatus: Codable, Equatable, Sendable {
  public var success: Bool
  public var isListening: Bool
  public var deviceName: String?
  public var chunkDurationSeconds: Int?
  public var warning: String?

  public init(
    success: Bool,
    isListening: Bool,
    deviceName: String? = nil,
    chunkDurationSeconds: Int? = nil,
    warning: String? = nil
  ) {
    self.success = success
    self.isListening = isListening
    self.deviceName = deviceName
    self.chunkDurationSeconds = chunkDurationSeconds
    self.warning = warning
  }
}

public struct PhoneCallAudioInputEvent: Codable, Equatable, Sendable {
  public var sequence: Int
  public var filePath: String
  public var createdAt: String
  public var durationSeconds: Int
  public var interruptedPlayback: Bool

  public init(
    sequence: Int,
    filePath: String,
    createdAt: String,
    durationSeconds: Int,
    interruptedPlayback: Bool
  ) {
    self.sequence = sequence
    self.filePath = filePath
    self.createdAt = createdAt
    self.durationSeconds = durationSeconds
    self.interruptedPlayback = interruptedPlayback
  }
}

struct ResolvedPhoneTarget: Equatable, Sendable {
  var phoneNumber: String
  var displayName: String?
}
