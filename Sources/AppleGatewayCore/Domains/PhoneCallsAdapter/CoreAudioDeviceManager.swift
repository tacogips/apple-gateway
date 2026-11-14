import Foundation

#if canImport(CoreAudio)
import CoreAudio
#endif

struct CoreAudioDevice: Equatable, Sendable {
  var id: UInt32
  var uid: String
  var name: String
}

enum CoreAudioDeviceManager {
  #if canImport(CoreAudio)
  static func resolveDevice(uid: String) throws -> CoreAudioDevice {
    guard !uid.isEmpty else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "An audio device UID is required"
      )
    }
    guard let device = try allDevices().first(where: { $0.uid == uid }) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Configured audio device was not found",
        details: ["deviceUID": uid]
      )
    }
    return device
  }

  static func resolveVirtualDevice(configuredUID: String) throws -> CoreAudioDevice {
    let devices = try allDevices()
    if !configuredUID.isEmpty {
      return try resolveDevice(uid: configuredUID)
    }
    let candidates = devices.filter {
      let name = $0.name.lowercased()
      return name.contains("blackhole") || name.contains("loopback") || name.contains("vb-cable")
    }
    guard candidates.count == 1, let device = candidates.first else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: candidates.isEmpty
          ? "No supported virtual audio device was found"
          : "Multiple virtual audio devices were found; configure phone_calls.virtual_audio_device_uid",
        details: ["candidates": candidates.map { "\($0.name)=\($0.uid)" }.joined(separator: ", ")]
      )
    }
    return device
  }

  static func defaultInputDevice() throws -> UInt32 {
    var deviceID = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    try requireSuccess(status, operation: "read the default input device")
    return deviceID
  }

  static func setDefaultInputDevice(_ deviceID: UInt32) throws {
    var mutableID = AudioDeviceID(deviceID)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableID
    )
    try requireSuccess(status, operation: "set the default input device")
  }

  private static func allDevices() throws -> [CoreAudioDevice] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    try requireSuccess(
      AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size),
      operation: "list audio devices"
    )
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else {
      return []
    }
    let pointer = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: count)
    defer { pointer.deallocate() }
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      pointer
    )
    try requireSuccess(status, operation: "list audio devices")
    let ids = Array(UnsafeBufferPointer(start: pointer, count: count))
    return try ids.map {
      CoreAudioDevice(id: $0, uid: try stringProperty($0, selector: kAudioDevicePropertyDeviceUID), name: try stringProperty($0, selector: kAudioObjectPropertyName))
    }
  }

  private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
    }
    try requireSuccess(status, operation: "read an audio device property")
    return value as String
  }

  private static func requireSuccess(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Core Audio could not \(operation)",
        details: ["osStatus": "\(status)"]
      )
    }
  }
  #else
  static func resolveDevice(uid: String) throws -> CoreAudioDevice {
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Core Audio is unavailable")
  }

  static func resolveVirtualDevice(configuredUID: String) throws -> CoreAudioDevice {
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Core Audio is unavailable")
  }

  static func defaultInputDevice() throws -> UInt32 {
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Core Audio is unavailable")
  }

  static func setDefaultInputDevice(_ deviceID: UInt32) throws {
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Core Audio is unavailable")
  }
  #endif
}
