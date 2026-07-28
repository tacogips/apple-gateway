import Foundation

#if canImport(AVFoundation) && canImport(AudioToolbox) && canImport(Darwin)
import AudioToolbox
import AVFoundation
import Darwin
#endif

public enum PhoneAudioListenerCommand {
  public static func run(
    arguments: [String]
  ) -> Int32 {
    #if canImport(AVFoundation) && canImport(AudioToolbox) && canImport(Darwin)
    do {
      let options = try Options(arguments: arguments)
      let listener = try PhoneAudioChunkListener(options: options)
      try listener.run()
      return 0
    } catch {
      return 1
    }
    #else
    return 1
    #endif
  }

  #if canImport(AVFoundation) && canImport(AudioToolbox) && canImport(Darwin)
  fileprivate struct Options: Sendable {
    var deviceID: UInt32
    var chunkDurationSeconds: Int
    var stateFileURL: URL
    var eventFileURL: URL
    var chunksDirectoryURL: URL
    var playerStateFileURL: URL

    init(arguments: [String]) throws {
      let values = try Self.parse(arguments)
      guard let deviceText = values["--device-id"],
            let deviceID = UInt32(deviceText),
            let chunkText = values["--chunk-seconds"],
            let chunkDurationSeconds = Int(chunkText),
            (1...30).contains(chunkDurationSeconds),
            let stateFile = values["--state-file"],
            let eventFile = values["--event-file"],
            let chunksDirectory = values["--chunks-dir"],
            let playerStateFile = values["--player-state-file"]
      else {
        throw ListenerError.invalidArguments
      }
      self.deviceID = deviceID
      self.chunkDurationSeconds = chunkDurationSeconds
      stateFileURL = URL(fileURLWithPath: stateFile)
      eventFileURL = URL(fileURLWithPath: eventFile)
      chunksDirectoryURL = URL(fileURLWithPath: chunksDirectory, isDirectory: true)
      playerStateFileURL = URL(fileURLWithPath: playerStateFile)
    }

    private static func parse(_ arguments: [String]) throws -> [String: String] {
      var output: [String: String] = [:]
      var index = 0
      while index < arguments.count {
        guard arguments[index].hasPrefix("--"), index + 1 < arguments.count else {
          throw ListenerError.invalidArguments
        }
        output[arguments[index]] = arguments[index + 1]
        index += 2
      }
      return output
    }
  }

  fileprivate enum ListenerError: Error {
    case invalidArguments
    case inputAudioUnitUnavailable
    case couldNotSelectDevice(OSStatus)
    case invalidInputFormat
  }
  #endif
}

#if canImport(AVFoundation) && canImport(AudioToolbox) && canImport(Darwin)
private final class PhoneAudioChunkListener: @unchecked Sendable {
  private let options: PhoneAudioListenerCommand.Options
  private let engine = AVAudioEngine()
  private let eventWriter: PhoneCallAudioInputEventWriter
  private let playbackInterrupter: PhoneAudioPlaybackInterrupter
  private let stopped = DispatchSemaphore(value: 0)
  private var signalSource: DispatchSourceSignal?
  private var audioFile: AVAudioFile?
  private var chunkFrameCount: AVAudioFramePosition = 0
  private var currentSequence = 0
  private var currentChunkHasSpeech = false
  private var currentChunkInterruptedPlayback = false
  private var framesPerChunk: AVAudioFramePosition = 0

  init(options: PhoneAudioListenerCommand.Options) throws {
    self.options = options
    eventWriter = PhoneCallAudioInputEventWriter(fileURL: options.eventFileURL)
    playbackInterrupter = PhoneAudioPlaybackInterrupter(stateFileURL: options.playerStateFileURL)
  }

  func run() throws {
    defer {
      stopCapture()
      try? FileManager.default.removeItem(at: options.stateFileURL)
    }
    try startCapture()
    installSignalHandler()
    stopped.wait()
  }

  private func startCapture() throws {
    let inputNode = engine.inputNode
    guard let audioUnit = inputNode.audioUnit else {
      throw PhoneAudioListenerCommand.ListenerError.inputAudioUnitUnavailable
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
      throw PhoneAudioListenerCommand.ListenerError.couldNotSelectDevice(status)
    }
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw PhoneAudioListenerCommand.ListenerError.invalidInputFormat
    }
    framesPerChunk = AVAudioFramePosition(format.sampleRate * Double(options.chunkDurationSeconds))
    inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
      self?.consume(buffer)
    }
    try engine.start()
  }

  private func stopCapture() {
    if engine.isRunning {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    finishCurrentChunk()
  }

  private func consume(_ buffer: AVAudioPCMBuffer) {
    do {
      if audioFile == nil {
        try beginChunk(format: buffer.format)
      }
      let containsSpeech = rms(buffer) >= 0.015
      if containsSpeech {
        currentChunkHasSpeech = true
        if playbackInterrupter.interruptIfPlaying() {
          currentChunkInterruptedPlayback = true
        }
      }
      try audioFile?.write(from: buffer)
      chunkFrameCount += AVAudioFramePosition(buffer.frameLength)
      if chunkFrameCount >= framesPerChunk {
        finishCurrentChunk()
      }
    } catch {
      stopped.signal()
    }
  }

  private func beginChunk(format: AVAudioFormat) throws {
    currentSequence += 1
    chunkFrameCount = 0
    currentChunkHasSpeech = false
    currentChunkInterruptedPlayback = false
    try FileManager.default.createDirectory(
      at: options.chunksDirectoryURL,
      withIntermediateDirectories: true
    )
    audioFile = try AVAudioFile(
      forWriting: chunkURL(sequence: currentSequence),
      settings: format.settings,
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved
    )
  }

  private func finishCurrentChunk() {
    guard audioFile != nil else {
      return
    }
    audioFile = nil
    let sequence = currentSequence
    let containsSpeech = currentChunkHasSpeech
    let interrupted = currentChunkInterruptedPlayback
    let fileURL = chunkURL(sequence: sequence)
    if containsSpeech {
      try? eventWriter.append(
        PhoneCallAudioInputEvent(
          sequence: sequence,
          filePath: fileURL.path,
          createdAt: ISO8601DateFormatter().string(from: Date()),
          durationSeconds: options.chunkDurationSeconds,
          interruptedPlayback: interrupted
        )
      )
    } else {
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  private func chunkURL(sequence: Int) -> URL {
    options.chunksDirectoryURL.appendingPathComponent(
      String(format: "chunk-%08d.wav", sequence)
    )
  }

  private func rms(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
      return 0
    }
    var sum: Float = 0
    let frameCount = Int(buffer.frameLength)
    for channelIndex in 0..<Int(buffer.format.channelCount) {
      let channel = channels[channelIndex]
      for frameIndex in 0..<frameCount {
        let sample = channel[frameIndex]
        sum += sample * sample
      }
    }
    let sampleCount = Float(frameCount * Int(buffer.format.channelCount))
    return sqrt(sum / sampleCount)
  }

  private func installSignalHandler() {
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    source.setEventHandler { [weak self] in
      self?.stopped.signal()
    }
    source.resume()
    signalSource = source
  }
}

private final class PhoneCallAudioInputEventWriter: @unchecked Sendable {
  private let fileURL: URL
  private let lock = NSLock()

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func append(_ event: PhoneCallAudioInputEvent) throws {
    lock.lock()
    defer { lock.unlock() }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    var data = try JSONEncoder().encode(event)
    data.append(Data("\n".utf8))
    try handle.write(contentsOf: data)
  }
}

private struct PhoneAudioPlaybackInterrupter: Sendable {
  private let stateFileURL: URL

  init(stateFileURL: URL) {
    self.stateFileURL = stateFileURL
  }

  func interruptIfPlaying() -> Bool {
    guard let data = try? Data(contentsOf: stateFileURL),
          let state = try? JSONDecoder().decode(PhoneAudioSessionState.self, from: data),
          state.pid > 0,
          Darwin.kill(state.pid, 0) == 0 || errno == EPERM
    else {
      return false
    }
    _ = Darwin.kill(state.pid, SIGTERM)
    try? CoreAudioDeviceManager.setDefaultInputDevice(state.previousInputDeviceID)
    try? FileManager.default.removeItem(at: stateFileURL)
    return true
  }
}
#endif
