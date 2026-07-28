import Foundation

#if canImport(Darwin)
import Darwin
#endif

protocol PhoneCallListeningControlling: Sendable {
  func status() throws -> PhoneCallListeningStatus
  func audioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent]
  func start(chunkDurationSeconds: Int) throws -> PhoneCallListeningStatus
  func stop() throws -> PhoneCallListeningStatus
}

struct LivePhoneCallListeningController: PhoneCallListeningControlling {
  private let config: AppleGatewayConfig
  private let executablePath: String

  init(
    config: AppleGatewayConfig,
    executablePath: String? = Bundle.main.executableURL?.path
  ) {
    self.config = config
    self.executablePath = executablePath ?? ""
  }

  func status() throws -> PhoneCallListeningStatus {
    #if os(macOS)
    guard let state = try loadState(), processIsRunning(state.pid) else {
      return PhoneCallListeningStatus(success: true, isListening: false)
    }
    return statusValue(state)
    #else
    throw unsupported()
    #endif
  }

  func audioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent] {
    #if os(macOS)
    guard FileManager.default.fileExists(atPath: eventFileURL.path) else {
      return []
    }
    let contents = try String(contentsOf: eventFileURL, encoding: .utf8)
    return contents
      .split(whereSeparator: \.isNewline)
      .compactMap { try? JSONDecoder().decode(PhoneCallAudioInputEvent.self, from: Data($0.utf8)) }
      .filter { $0.sequence > afterSequence }
      .sorted { $0.sequence < $1.sequence }
    #else
    throw unsupported()
    #endif
  }

  func start(chunkDurationSeconds: Int) throws -> PhoneCallListeningStatus {
    #if os(macOS)
    guard !executablePath.isEmpty else {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Could not resolve the phone-listener executable"
      )
    }
    guard !config.phoneCalls.captureAudioDeviceUID.isEmpty else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "phone_calls.capture_audio_device_uid is required for phone-call listening"
      )
    }
    if let current = try loadState(), processIsRunning(current.pid) {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Phone-call listening is already active"
      )
    }

    let device = try CoreAudioDeviceManager.resolveDevice(
      uid: config.phoneCalls.captureAudioDeviceUID
    )
    try prepareSessionDirectory()
    let state = PhoneCallListenerSessionState(
      pid: 0,
      deviceID: device.id,
      deviceName: device.name,
      chunkDurationSeconds: chunkDurationSeconds
    )
    try saveState(state)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = [
      "__phone-audio-listener",
      "--device-id", "\(device.id)",
      "--chunk-seconds", "\(chunkDurationSeconds)",
      "--state-file", stateFileURL.path,
      "--event-file", eventFileURL.path,
      "--chunks-dir", chunksDirectoryURL.path,
      "--player-state-file", playerStateFileURL.path
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      var runningState = state
      runningState.pid = process.processIdentifier
      try saveState(runningState)
      return statusValue(runningState)
    } catch {
      try? removeState()
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Could not launch the phone-call listener",
        details: ["underlyingError": String(describing: error)]
      )
    }
    #else
    throw unsupported()
    #endif
  }

  func stop() throws -> PhoneCallListeningStatus {
    #if os(macOS)
    guard let state = try loadState() else {
      return PhoneCallListeningStatus(success: true, isListening: false)
    }
    if processIsRunning(state.pid) {
      _ = Darwin.kill(state.pid, SIGTERM)
      for _ in 0..<100 where processIsRunning(state.pid) {
        Thread.sleep(forTimeInterval: 0.01)
      }
    }
    try? removeState()
    return PhoneCallListeningStatus(
      success: true,
      isListening: false,
      deviceName: state.deviceName,
      chunkDurationSeconds: state.chunkDurationSeconds
    )
    #else
    throw unsupported()
    #endif
  }

  private func statusValue(_ state: PhoneCallListenerSessionState) -> PhoneCallListeningStatus {
    PhoneCallListeningStatus(
      success: true,
      isListening: true,
      deviceName: state.deviceName,
      chunkDurationSeconds: state.chunkDurationSeconds,
      warning: "Consumers must poll phoneCallAudioInputEvents. Caller speech stops active phone-call playback immediately."
    )
  }

  private var sessionDirectoryURL: URL {
    URL(fileURLWithPath: config.storage.cacheDir, isDirectory: true)
      .appendingPathComponent("phone-listener", isDirectory: true)
  }

  private var stateFileURL: URL {
    sessionDirectoryURL.appendingPathComponent("session.json")
  }

  private var eventFileURL: URL {
    sessionDirectoryURL.appendingPathComponent("audio-input-events.jsonl")
  }

  private var chunksDirectoryURL: URL {
    sessionDirectoryURL.appendingPathComponent("chunks", isDirectory: true)
  }

  private var playerStateFileURL: URL {
    URL(fileURLWithPath: config.storage.cacheDir, isDirectory: true)
      .appendingPathComponent("phone-audio", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  private func prepareSessionDirectory() throws {
    if FileManager.default.fileExists(atPath: chunksDirectoryURL.path) {
      try FileManager.default.removeItem(at: chunksDirectoryURL)
    }
    try FileManager.default.createDirectory(at: chunksDirectoryURL, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: eventFileURL.path) {
      try FileManager.default.removeItem(at: eventFileURL)
    }
  }

  private func loadState() throws -> PhoneCallListenerSessionState? {
    guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
      return nil
    }
    return try JSONDecoder().decode(
      PhoneCallListenerSessionState.self,
      from: Data(contentsOf: stateFileURL)
    )
  }

  private func saveState(_ state: PhoneCallListenerSessionState) throws {
    try FileManager.default.createDirectory(
      at: stateFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(state).write(to: stateFileURL, options: .atomic)
  }

  private func removeState() throws {
    guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
      return
    }
    try FileManager.default.removeItem(at: stateFileURL)
  }

  private func processIsRunning(_ pid: Int32) -> Bool {
    #if canImport(Darwin)
    pid > 0 && (Darwin.kill(pid, 0) == 0 || errno == EPERM)
    #else
    false
    #endif
  }

  private func unsupported() -> AppleGatewayError {
    AppleGatewayError(
      code: .unsupportedOSVersion,
      message: "Phone-call listening requires macOS"
    )
  }
}

struct PhoneCallListenerSessionState: Codable, Equatable, Sendable {
  var pid: Int32
  var deviceID: UInt32
  var deviceName: String
  var chunkDurationSeconds: Int
}
