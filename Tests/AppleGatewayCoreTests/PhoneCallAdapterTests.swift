import Foundation
import Testing
@testable import AppleGatewayCore

@Test func phoneCallAdapterPlacesNormalizedDirectNumber() throws {
  let resolver = StubPhoneContactResolver()
  let controller = RecordingPhoneCallController()
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: resolver,
    controller: controller
  )

  let result = try adapter.placePhoneCall(
    PlacePhoneCallInput(phoneNumber: "+81 (90) 1234-5678")
  )

  #expect(result.success)
  #expect(controller.openedPhoneNumber == "+819012345678")
  #expect(resolver.requests.isEmpty)
}

@Test func phoneCallAdapterResolvesContactAndPhoneLabel() throws {
  let resolver = StubPhoneContactResolver(
    result: ResolvedPhoneTarget(phoneNumber: "03-1234-5678", displayName: "Example Person")
  )
  let controller = RecordingPhoneCallController()
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: resolver,
    controller: controller
  )

  let result = try adapter.placePhoneCall(
    PlacePhoneCallInput(contactName: "Example Person", phoneLabel: "mobile", autoConfirm: true)
  )

  #expect(resolver.requests == [.init(name: "Example Person", label: "mobile")])
  #expect(controller.openedPhoneNumber == "0312345678")
  #expect(controller.openedAutoConfirm == true)
  #expect(result.targetName == "Example Person")
}

@Test func phoneCallAdapterRequiresExactlyOneTarget() throws {
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: RecordingPhoneCallController()
  )

  #expect(throws: AppleGatewayError.self) {
    _ = try adapter.placePhoneCall(PlacePhoneCallInput())
  }
  #expect(throws: AppleGatewayError.self) {
    _ = try adapter.placePhoneCall(
      PlacePhoneCallInput(phoneNumber: "0312345678", contactName: "Example Person")
    )
  }
}

@Test func phoneCallAdapterRejectsNonDialableNumber() throws {
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: RecordingPhoneCallController()
  )

  do {
    _ = try adapter.placePhoneCall(PlacePhoneCallInput(phoneNumber: "not-a-number"))
    Issue.record("Expected invalid phone number error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
  }
}

@Test func phoneCallAdapterNormalizesUnicodeDigitsAndDialModifiers() throws {
  let controller = RecordingPhoneCallController()
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: controller
  )

  _ = try adapter.placePhoneCall(PlacePhoneCallInput(phoneNumber: "０３‑１２３４#５６"))

  #expect(controller.openedPhoneNumber == "031234#56")
}

@Test func phoneCallAdapterDelegatesCallControls() throws {
  let controller = RecordingPhoneCallController()
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: controller
  )

  _ = try adapter.answerPhoneCall()
  _ = try adapter.declinePhoneCall()
  _ = try adapter.endPhoneCall()

  #expect(controller.actions == [.answer, .decline, .end])
}

@Test func phoneCallAdapterDelegatesAudioPlaybackAndStop() throws {
  let audio = RecordingPhoneAudioController()
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: RecordingPhoneCallController(),
    audioController: audio
  )

  let playing = try adapter.playAudioToPhoneCall(
    PlayPhoneCallAudioInput(filePath: "/tmp/prompt.wav")
  )
  let stopped = try adapter.stopPhoneCallAudio()

  #expect(audio.playedPaths == ["/tmp/prompt.wav"])
  #expect(audio.stopCalls == 1)
  #expect(playing.isPlaying)
  #expect(!stopped.isPlaying)
}

@Test func phoneCallAdapterDelegatesListeningAndAudioInputEvents() throws {
  let listening = RecordingPhoneCallListeningController()
  listening.events = [
    PhoneCallAudioInputEvent(
      sequence: 2,
      filePath: "/tmp/caller.wav",
      createdAt: "2026-07-28T00:00:00Z",
      durationSeconds: 5,
      interruptedPlayback: true
    )
  ]
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: RecordingPhoneCallController(),
    listeningController: listening
  )

  let started = try adapter.startPhoneCallListening(
    StartPhoneCallListeningInput(chunkDurationSeconds: 5)
  )
  let events = try adapter.phoneCallAudioInputEvents(afterSequence: 1)
  let stopped = try adapter.stopPhoneCallListening()

  #expect(started.isListening)
  #expect(listening.startedChunkDurations == [5])
  #expect(listening.requestedAfterSequences == [1])
  #expect(events == listening.events)
  #expect(!stopped.isListening)
}

@Test func phoneCallAdapterValidatesListeningArguments() throws {
  let adapter = LivePhoneCallsAdapter(
    config: .defaultValue,
    contactResolver: StubPhoneContactResolver(),
    controller: RecordingPhoneCallController(),
    listeningController: RecordingPhoneCallListeningController()
  )

  #expect(throws: AppleGatewayError.self) {
    _ = try adapter.startPhoneCallListening(StartPhoneCallListeningInput(chunkDurationSeconds: 0))
  }
  #expect(throws: AppleGatewayError.self) {
    _ = try adapter.phoneCallAudioInputEvents(afterSequence: -1)
  }
}

@Test func phoneAudioPlayerCommandRejectsMissingInternalArguments() {
  #expect(PhoneAudioPlayerCommand.run(arguments: []) == 1)
}

@Test func phoneAudioListenerCommandRejectsMissingInternalArguments() {
  #expect(PhoneAudioListenerCommand.run(arguments: []) == 1)
}

private final class StubPhoneContactResolver: PhoneContactResolving, @unchecked Sendable {
  struct Request: Equatable {
    var name: String
    var label: String?
  }

  var result: ResolvedPhoneTarget
  private(set) var requests: [Request] = []

  init(result: ResolvedPhoneTarget = ResolvedPhoneTarget(phoneNumber: "0312345678", displayName: "Contact")) {
    self.result = result
  }

  func resolve(name: String, phoneLabel: String?) throws -> ResolvedPhoneTarget {
    requests.append(Request(name: name, label: phoneLabel))
    return result
  }
}

private final class RecordingPhoneCallController: PhoneCallUIControlling, @unchecked Sendable {
  private(set) var openedPhoneNumber: String?
  private(set) var openedAutoConfirm: Bool?
  private(set) var actions: [PhoneCallControlAction] = []

  func status() throws -> PhoneCallStatus {
    PhoneCallStatus(state: .idle)
  }

  func openCall(phoneNumber: String, displayName: String?, autoConfirm: Bool) throws -> PhoneCallActionResult {
    openedPhoneNumber = phoneNumber
    openedAutoConfirm = autoConfirm
    return PhoneCallActionResult(success: true, state: .unknown, targetName: displayName)
  }

  func perform(_ action: PhoneCallControlAction) throws -> PhoneCallActionResult {
    actions.append(action)
    return PhoneCallActionResult(success: true, state: action == .answer ? .active : .idle)
  }
}

private final class RecordingPhoneAudioController: PhoneAudioControlling, @unchecked Sendable {
  private(set) var playedPaths: [String] = []
  private(set) var stopCalls = 0

  func play(filePath: String) throws -> PhoneCallAudioResult {
    playedPaths.append(filePath)
    return PhoneCallAudioResult(success: true, isPlaying: true, filePath: filePath)
  }

  func stop() throws -> PhoneCallAudioResult {
    stopCalls += 1
    return PhoneCallAudioResult(success: true, isPlaying: false)
  }
}

private final class RecordingPhoneCallListeningController: PhoneCallListeningControlling, @unchecked Sendable {
  var events: [PhoneCallAudioInputEvent] = []
  private(set) var startedChunkDurations: [Int] = []
  private(set) var requestedAfterSequences: [Int] = []

  func status() throws -> PhoneCallListeningStatus {
    PhoneCallListeningStatus(success: true, isListening: !startedChunkDurations.isEmpty)
  }

  func audioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent] {
    requestedAfterSequences.append(afterSequence)
    return events
  }

  func start(chunkDurationSeconds: Int) throws -> PhoneCallListeningStatus {
    startedChunkDurations.append(chunkDurationSeconds)
    return PhoneCallListeningStatus(
      success: true,
      isListening: true,
      chunkDurationSeconds: chunkDurationSeconds
    )
  }

  func stop() throws -> PhoneCallListeningStatus {
    PhoneCallListeningStatus(success: true, isListening: false)
  }
}
