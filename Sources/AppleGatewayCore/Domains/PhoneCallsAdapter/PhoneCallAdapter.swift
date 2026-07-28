import Foundation

public struct LivePhoneCallsAdapter: PhoneCallsProviding {
  private let contactResolver: any PhoneContactResolving
  private let controller: any PhoneCallUIControlling
  private let audioController: any PhoneAudioControlling
  private let listeningController: any PhoneCallListeningControlling

  init(
    config: AppleGatewayConfig,
    contactResolver: any PhoneContactResolving,
    controller: any PhoneCallUIControlling,
    audioController: (any PhoneAudioControlling)? = nil,
    listeningController: (any PhoneCallListeningControlling)? = nil
  ) {
    self.contactResolver = contactResolver
    self.controller = controller
    self.audioController = audioController ?? LivePhoneAudioController(config: config)
    self.listeningController = listeningController ?? LivePhoneCallListeningController(config: config)
  }

  public init(config: AppleGatewayConfig) {
    self.init(
      config: config,
      contactResolver: LivePhoneContactResolver(),
      controller: LivePhoneCallUIController(),
      audioController: LivePhoneAudioController(config: config),
      listeningController: LivePhoneCallListeningController(config: config)
    )
  }

  public func phoneCallStatus() throws -> PhoneCallStatus {
    try controller.status()
  }

  public func placePhoneCall(_ input: PlacePhoneCallInput) throws -> PhoneCallActionResult {
    let hasNumber = input.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasContact = input.contactName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    guard hasNumber != hasContact else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Provide exactly one of phoneNumber or contactName"
      )
    }
    let target: ResolvedPhoneTarget
    if let phoneNumber = input.phoneNumber, hasNumber {
      target = ResolvedPhoneTarget(phoneNumber: phoneNumber, displayName: nil)
    } else if let contactName = input.contactName {
      target = try contactResolver.resolve(name: contactName, phoneLabel: input.phoneLabel)
    } else {
      throw AppleGatewayError(code: .invalidArgument, message: "A phone target is required")
    }
    let normalized = try normalize(phoneNumber: target.phoneNumber)
    return try controller.openCall(
      phoneNumber: normalized,
      displayName: target.displayName,
      autoConfirm: input.autoConfirm
    )
  }

  public func answerPhoneCall() throws -> PhoneCallActionResult {
    try controller.perform(.answer)
  }

  public func declinePhoneCall() throws -> PhoneCallActionResult {
    try controller.perform(.decline)
  }

  public func endPhoneCall() throws -> PhoneCallActionResult {
    try controller.perform(.end)
  }

  public func playAudioToPhoneCall(_ input: PlayPhoneCallAudioInput) throws -> PhoneCallAudioResult {
    let path = input.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      throw AppleGatewayError(code: .invalidArgument, message: "filePath must not be empty")
    }
    return try audioController.play(filePath: path)
  }

  public func stopPhoneCallAudio() throws -> PhoneCallAudioResult {
    try audioController.stop()
  }

  public func phoneCallListeningStatus() throws -> PhoneCallListeningStatus {
    try listeningController.status()
  }

  public func phoneCallAudioInputEvents(
    afterSequence: Int
  ) throws -> [PhoneCallAudioInputEvent] {
    guard afterSequence >= 0 else {
      throw AppleGatewayError(code: .invalidArgument, message: "afterSequence must not be negative")
    }
    return try listeningController.audioInputEvents(afterSequence: afterSequence)
  }

  public func startPhoneCallListening(
    _ input: StartPhoneCallListeningInput
  ) throws -> PhoneCallListeningStatus {
    guard (1...30).contains(input.chunkDurationSeconds) else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "chunkDurationSeconds must be between 1 and 30"
      )
    }
    return try listeningController.start(chunkDurationSeconds: input.chunkDurationSeconds)
  }

  public func stopPhoneCallListening() throws -> PhoneCallListeningStatus {
    try listeningController.stop()
  }

  private func normalize(phoneNumber: String) throws -> String {
    var normalized = ""
    for character in phoneNumber {
      if let digit = character.wholeNumberValue, (0...9).contains(digit) {
        normalized.append(String(digit))
      } else if character == "+", normalized.isEmpty {
        normalized.append(character)
      } else if "*#,;".contains(character) {
        normalized.append(character)
      } else if character.isWhitespace || "-().‐‑‒–—−".contains(character) {
        continue
      } else {
        throw AppleGatewayError(code: .invalidArgument, message: "phoneNumber is not a valid dialable number")
      }
    }
    guard normalized.filter(\.isNumber).count >= 3 else {
      throw AppleGatewayError(code: .invalidArgument, message: "phoneNumber must contain at least three digits")
    }
    return normalized
  }
}
