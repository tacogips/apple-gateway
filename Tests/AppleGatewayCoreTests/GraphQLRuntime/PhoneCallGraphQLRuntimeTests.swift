import Foundation
import Testing
@testable import AppleGatewayCore

@Test func phoneCallSchemaExposesStatusAndFullRoleMutations() {
  let fullSDL = GraphQLRuntime.schema(role: .full)
  let readerSDL = GraphQLRuntime.schema(role: .reader)

  #expect(fullSDL.contains("phoneCallStatus: PhoneCallStatus!"))
  #expect(fullSDL.contains("phoneCallAudioConfiguration: PhoneCallAudioConfiguration!"))
  #expect(fullSDL.contains("placePhoneCall(input: PlacePhoneCallInput!): PhoneCallActionResult!"))
  #expect(fullSDL.contains("answerPhoneCall: PhoneCallActionResult!"))
  #expect(fullSDL.contains("declinePhoneCall: PhoneCallActionResult!"))
  #expect(fullSDL.contains("endPhoneCall: PhoneCallActionResult!"))
  #expect(fullSDL.contains("playAudioToPhoneCall(input: PlayPhoneCallAudioInput!): PhoneCallAudioResult!"))
  #expect(fullSDL.contains("stopPhoneCallAudio: PhoneCallAudioResult!"))
  #expect(fullSDL.contains("phoneCallListeningStatus: PhoneCallListeningStatus!"))
  #expect(fullSDL.contains("phoneCallAudioInputEvents(afterSequence: Int): [PhoneCallAudioInputEvent!]!"))
  #expect(fullSDL.contains("startPhoneCallListening(input: StartPhoneCallListeningInput!): PhoneCallListeningStatus!"))
  #expect(fullSDL.contains("stopPhoneCallListening: PhoneCallListeningStatus!"))
  #expect(readerSDL.contains("phoneCallStatus: PhoneCallStatus!"))
  #expect(readerSDL.contains("phoneCallAudioConfiguration: PhoneCallAudioConfiguration!"))
  #expect(!readerSDL.contains("placePhoneCall"))
  #expect(!readerSDL.contains("answerPhoneCall"))
  #expect(!readerSDL.contains("playAudioToPhoneCall"))
  #expect(readerSDL.contains("phoneCallAudioInputEvents"))
  #expect(!readerSDL.contains("startPhoneCallListening"))
}

@Test func phoneCallGraphQLReturnsReadOnlyAudioConfiguration() throws {
  let fake = FakePhoneCallsService()
  fake.audioConfiguration = PhoneCallAudioConfiguration(
    playbackDeviceUID: "playback-device",
    captureDeviceUID: "capture-device",
    cacheDirectory: URL(fileURLWithPath: "/tmp/apple-gateway", isDirectory: true)
  )

  let json = try executePhoneGraphQL(
    "{ phoneCallAudioConfiguration { playbackDeviceUID captureDeviceUID cacheDirectory } }",
    service: fake
  )
  let data = try #require(json["data"] as? [String: Any])
  let configuration = try #require(data["phoneCallAudioConfiguration"] as? [String: Any])

  #expect(configuration["playbackDeviceUID"] as? String == "playback-device")
  #expect(configuration["captureDeviceUID"] as? String == "capture-device")
  #expect(configuration["cacheDirectory"] as? String == "/tmp/apple-gateway")
}

@Test func phoneCallGraphQLDelegatesListeningAndAudioInputEvents() throws {
  let fake = FakePhoneCallsService()
  fake.audioInputEvents = [
    PhoneCallAudioInputEvent(
      sequence: 3,
      filePath: "/tmp/chunk.wav",
      createdAt: "2026-07-28T00:00:00Z",
      durationSeconds: 5,
      interruptedPlayback: true
    )
  ]

  _ = try executePhoneGraphQL(
    """
    mutation {
      startPhoneCallListening(input: { chunkDurationSeconds: 5 }) {
        success isListening chunkDurationSeconds
      }
    }
    """,
    service: fake
  )
  let json = try executePhoneGraphQL(
    """
    {
      phoneCallAudioInputEvents(afterSequence: 2) {
        sequence filePath durationSeconds interruptedPlayback
      }
    }
    """,
    service: fake
  )
  let data = try #require(json["data"] as? [String: Any])
  let events = try #require(data["phoneCallAudioInputEvents"] as? [[String: Any]])

  #expect(fake.listeningInputs == [StartPhoneCallListeningInput(chunkDurationSeconds: 5)])
  #expect(fake.requestedAfterSequences == [2])
  #expect(events.first?["sequence"] as? Int == 3)
  #expect(events.first?["interruptedPlayback"] as? Bool == true)
}

@Test func phoneCallGraphQLResolvesStatus() throws {
  let fake = FakePhoneCallsService()
  fake.statusValue = PhoneCallStatus(
    state: .incoming,
    callerName: "Example Person",
    application: "Phone",
    warning: "best effort"
  )

  let json = try executePhoneGraphQL(
    "{ phoneCallStatus { state callerName application warning } }",
    service: fake
  )
  let data = try #require(json["data"] as? [String: Any])
  let status = try #require(data["phoneCallStatus"] as? [String: Any])

  #expect(status["state"] as? String == "INCOMING")
  #expect(status["callerName"] as? String == "Example Person")
  #expect(status["application"] as? String == "Phone")
  #expect(status["warning"] as? String == "best effort")
}

@Test func phoneCallGraphQLPlacesContactCall() throws {
  let fake = FakePhoneCallsService()

  let json = try executePhoneGraphQL(
    """
    mutation {
      placePhoneCall(input: { contactName: "Example Person", phoneLabel: "mobile", autoConfirm: true }) {
        success state targetName warning
      }
    }
    """,
    service: fake
  )
  let data = try #require(json["data"] as? [String: Any])
  let result = try #require(data["placePhoneCall"] as? [String: Any])

  #expect(fake.placeInputs == [
    PlacePhoneCallInput(contactName: "Example Person", phoneLabel: "mobile", autoConfirm: true)
  ])
  #expect(result["success"] as? Bool == true)
  #expect(result["targetName"] as? String == "Example Person")
}

@Test func phoneCallGraphQLDelegatesAnswerDeclineAndEnd() throws {
  let fake = FakePhoneCallsService()

  _ = try executePhoneGraphQL(
    "mutation { answerPhoneCall { success } declinePhoneCall { success } endPhoneCall { success } }",
    service: fake
  )

  #expect(fake.actions == [.answer, .decline, .end])
}

@Test func phoneCallGraphQLDelegatesAudioPlaybackAndStop() throws {
  let fake = FakePhoneCallsService()

  let json = try executePhoneGraphQL(
    """
    mutation {
      playAudioToPhoneCall(input: { filePath: "/tmp/prompt.wav" }) {
        success isPlaying filePath deviceName
      }
      stopPhoneCallAudio { success isPlaying }
    }
    """,
    service: fake
  )
  let data = try #require(json["data"] as? [String: Any])
  let playing = try #require(data["playAudioToPhoneCall"] as? [String: Any])
  let stopped = try #require(data["stopPhoneCallAudio"] as? [String: Any])

  #expect(playing["isPlaying"] as? Bool == true)
  #expect(playing["filePath"] as? String == "/tmp/prompt.wav")
  #expect(stopped["isPlaying"] as? Bool == false)
  #expect(fake.audioPaths == ["/tmp/prompt.wav"])
  #expect(fake.stopAudioCalls == 1)
}

private func executePhoneGraphQL(
  _ query: String,
  service: any PhoneCallsProviding
) throws -> [String: Any] {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: [:],
    role: .full,
    phoneCallsService: service
  )
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private final class FakePhoneCallsService: PhoneCallsProviding, @unchecked Sendable {
  var statusValue = PhoneCallStatus(state: .idle)
  var audioConfiguration = PhoneCallAudioConfiguration(
    playbackDeviceUID: nil,
    captureDeviceUID: nil,
    cacheDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
  )
  private(set) var placeInputs: [PlacePhoneCallInput] = []
  private(set) var actions: [PhoneCallControlAction] = []
  private(set) var audioPaths: [String] = []
  private(set) var stopAudioCalls = 0
  var audioInputEvents: [PhoneCallAudioInputEvent] = []
  private(set) var listeningInputs: [StartPhoneCallListeningInput] = []
  private(set) var requestedAfterSequences: [Int] = []

  func phoneCallStatus() throws -> PhoneCallStatus {
    statusValue
  }

  func phoneCallAudioConfiguration() throws -> PhoneCallAudioConfiguration {
    audioConfiguration
  }

  func placePhoneCall(_ input: PlacePhoneCallInput) throws -> PhoneCallActionResult {
    placeInputs.append(input)
    return PhoneCallActionResult(
      success: true,
      state: .unknown,
      targetName: input.contactName,
      warning: "confirmation may be required"
    )
  }

  func answerPhoneCall() throws -> PhoneCallActionResult {
    action(.answer)
  }

  func declinePhoneCall() throws -> PhoneCallActionResult {
    action(.decline)
  }

  func endPhoneCall() throws -> PhoneCallActionResult {
    action(.end)
  }

  func playAudioToPhoneCall(_ input: PlayPhoneCallAudioInput) throws -> PhoneCallAudioResult {
    audioPaths.append(input.filePath)
    return PhoneCallAudioResult(success: true, isPlaying: true, filePath: input.filePath, deviceName: "BlackHole 2ch")
  }

  func stopPhoneCallAudio() throws -> PhoneCallAudioResult {
    stopAudioCalls += 1
    return PhoneCallAudioResult(success: true, isPlaying: false)
  }

  func phoneCallListeningStatus() throws -> PhoneCallListeningStatus {
    PhoneCallListeningStatus(success: true, isListening: !listeningInputs.isEmpty)
  }

  func phoneCallAudioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent] {
    requestedAfterSequences.append(afterSequence)
    return audioInputEvents
  }

  func startPhoneCallListening(
    _ input: StartPhoneCallListeningInput
  ) throws -> PhoneCallListeningStatus {
    listeningInputs.append(input)
    return PhoneCallListeningStatus(
      success: true,
      isListening: true,
      chunkDurationSeconds: input.chunkDurationSeconds
    )
  }

  func stopPhoneCallListening() throws -> PhoneCallListeningStatus {
    PhoneCallListeningStatus(success: true, isListening: false)
  }

  private func action(_ action: PhoneCallControlAction) -> PhoneCallActionResult {
    actions.append(action)
    return PhoneCallActionResult(success: true, state: action == .answer ? .active : .idle)
  }
}
