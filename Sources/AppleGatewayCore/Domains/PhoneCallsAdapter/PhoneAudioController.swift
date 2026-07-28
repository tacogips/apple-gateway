import Foundation

#if canImport(Darwin)
import Darwin
#endif

protocol PhoneAudioControlling: Sendable {
  func play(filePath: String) throws -> PhoneCallAudioResult
  func stop() throws -> PhoneCallAudioResult
}

struct LivePhoneAudioController: PhoneAudioControlling {
  private let config: AppleGatewayConfig
  private let executablePath: String

  init(
    config: AppleGatewayConfig,
    executablePath: String? = Bundle.main.executableURL?.path
  ) {
    self.config = config
    self.executablePath = executablePath ?? ""
  }

  func play(filePath: String) throws -> PhoneCallAudioResult {
    #if os(macOS)
    guard !executablePath.isEmpty else {
      throw AppleGatewayError(code: .unexpectedError, message: "Could not resolve the audio-player executable")
    }
    let url = URL(fileURLWithPath: filePath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Audio file does not exist or is not a regular file",
        details: ["filePath": url.path]
      )
    }
    if let current = try loadState(), processIsRunning(current.pid) {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Phone-call audio is already playing",
        details: ["filePath": current.filePath]
      )
    }
    try removeState()

    let device = try CoreAudioDeviceManager.resolveVirtualDevice(
      configuredUID: config.phoneCalls.virtualAudioDeviceUID
    )
    let previousInput = try CoreAudioDeviceManager.defaultInputDevice()
    try CoreAudioDeviceManager.setDefaultInputDevice(device.id)
    let state = PhoneAudioSessionState(
      pid: 0,
      filePath: url.path,
      deviceID: device.id,
      deviceName: device.name,
      previousInputDeviceID: previousInput
    )
    try saveState(state)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = [
      "__phone-audio-player",
      "--file", url.path,
      "--device-id", "\(device.id)",
      "--previous-input-device-id", "\(previousInput)",
      "--state-file", stateFileURL.path
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      var runningState = state
      runningState.pid = process.processIdentifier
      try saveState(runningState)
    } catch {
      try? CoreAudioDeviceManager.setDefaultInputDevice(previousInput)
      try? removeState()
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Could not launch the phone audio player",
        details: ["underlyingError": String(describing: error)]
      )
    }
    return PhoneCallAudioResult(
      success: true,
      isPlaying: true,
      filePath: url.path,
      deviceName: device.name,
      warning: audioRoutingWarning
    )
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Phone-call audio requires macOS")
    #endif
  }

  func stop() throws -> PhoneCallAudioResult {
    #if os(macOS)
    guard let state = try loadState() else {
      return PhoneCallAudioResult(success: true, isPlaying: false)
    }
    if processIsRunning(state.pid) {
      _ = Darwin.kill(state.pid, SIGTERM)
    }
    try? CoreAudioDeviceManager.setDefaultInputDevice(state.previousInputDeviceID)
    try removeState()
    return PhoneCallAudioResult(
      success: true,
      isPlaying: false,
      filePath: state.filePath,
      deviceName: state.deviceName
    )
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Phone-call audio requires macOS")
    #endif
  }

  private var audioRoutingWarning: String {
    "Phone or FaceTime must use the system microphone. The previous default input is restored when playback ends or stopPhoneCallAudio is called."
  }

  private var stateFileURL: URL {
    URL(fileURLWithPath: config.storage.cacheDir, isDirectory: true)
      .appendingPathComponent("phone-audio", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  private func loadState() throws -> PhoneAudioSessionState? {
    guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
      return nil
    }
    return try JSONDecoder().decode(PhoneAudioSessionState.self, from: Data(contentsOf: stateFileURL))
  }

  private func saveState(_ state: PhoneAudioSessionState) throws {
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
}

struct PhoneAudioSessionState: Codable, Equatable, Sendable {
  var pid: Int32
  var filePath: String
  var deviceID: UInt32
  var deviceName: String
  var previousInputDeviceID: UInt32
}
