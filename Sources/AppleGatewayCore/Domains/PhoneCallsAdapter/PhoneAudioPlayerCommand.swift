import Foundation

#if canImport(AVFoundation) && canImport(AudioToolbox)
import AVFoundation
import AudioToolbox
#endif

public enum PhoneAudioPlayerCommand {
  public static func run(arguments: [String]) -> Int32 {
    #if canImport(AVFoundation) && canImport(AudioToolbox)
    do {
      let options = try Options(arguments: arguments)
      try play(options)
      return 0
    } catch {
      return 1
    }
    #else
    return 1
    #endif
  }

  #if canImport(AVFoundation) && canImport(AudioToolbox)
  private static func play(_ options: Options) throws {
    defer {
      try? CoreAudioDeviceManager.setDefaultInputDevice(options.previousInputDeviceID)
      try? FileManager.default.removeItem(atPath: options.stateFile)
    }
    let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: options.filePath))
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: audioFile.processingFormat)
    guard let audioUnit = engine.outputNode.audioUnit else {
      throw PlayerError.outputAudioUnitUnavailable
    }
    var deviceID = AudioDeviceID(options.deviceID)
    let status = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &deviceID,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
      throw PlayerError.couldNotSelectDevice(status)
    }

    let finished = DispatchSemaphore(value: 0)
    player.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
      finished.signal()
    }
    try engine.start()
    player.play()
    finished.wait()
    player.stop()
    engine.stop()
  }

  private struct Options {
    var filePath: String
    var deviceID: UInt32
    var previousInputDeviceID: UInt32
    var stateFile: String

    init(arguments: [String]) throws {
      let values = try Self.parse(arguments)
      guard let filePath = values["--file"],
            let deviceText = values["--device-id"],
            let deviceID = UInt32(deviceText),
            let previousText = values["--previous-input-device-id"],
            let previousInputDeviceID = UInt32(previousText),
            let stateFile = values["--state-file"]
      else {
        throw PlayerError.invalidArguments
      }
      self.filePath = filePath
      self.deviceID = deviceID
      self.previousInputDeviceID = previousInputDeviceID
      self.stateFile = stateFile
    }

    private static func parse(_ arguments: [String]) throws -> [String: String] {
      var output: [String: String] = [:]
      var index = 0
      while index < arguments.count {
        guard arguments[index].hasPrefix("--"), index + 1 < arguments.count else {
          throw PlayerError.invalidArguments
        }
        output[arguments[index]] = arguments[index + 1]
        index += 2
      }
      return output
    }
  }

  private enum PlayerError: Error {
    case invalidArguments
    case outputAudioUnitUnavailable
    case couldNotSelectDevice(OSStatus)
  }
  #endif
}
