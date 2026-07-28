import Foundation

public protocol PhoneCallsProviding: Sendable {
  func phoneCallStatus() throws -> PhoneCallStatus
  func phoneCallAudioConfiguration() throws -> PhoneCallAudioConfiguration
  func placePhoneCall(_ input: PlacePhoneCallInput) throws -> PhoneCallActionResult
  func answerPhoneCall() throws -> PhoneCallActionResult
  func declinePhoneCall() throws -> PhoneCallActionResult
  func endPhoneCall() throws -> PhoneCallActionResult
  func playAudioToPhoneCall(_ input: PlayPhoneCallAudioInput) throws -> PhoneCallAudioResult
  func stopPhoneCallAudio() throws -> PhoneCallAudioResult
  func phoneCallListeningStatus() throws -> PhoneCallListeningStatus
  func phoneCallAudioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent]
  func startPhoneCallListening(_ input: StartPhoneCallListeningInput) throws -> PhoneCallListeningStatus
  func stopPhoneCallListening() throws -> PhoneCallListeningStatus
}

public enum PhoneCallsServiceFactory {
  public static func unavailableService() -> any PhoneCallsProviding {
    UnavailablePhoneCallsService()
  }

  public static func liveService(config: AppleGatewayConfig) -> any PhoneCallsProviding {
    LivePhoneCallsAdapter(config: config)
  }
}

private struct UnavailablePhoneCallsService: PhoneCallsProviding {
  func phoneCallStatus() throws -> PhoneCallStatus {
    throw unavailable()
  }

  func phoneCallAudioConfiguration() throws -> PhoneCallAudioConfiguration {
    throw unavailable()
  }

  func placePhoneCall(_ input: PlacePhoneCallInput) throws -> PhoneCallActionResult {
    throw unavailable()
  }

  func answerPhoneCall() throws -> PhoneCallActionResult {
    throw unavailable()
  }

  func declinePhoneCall() throws -> PhoneCallActionResult {
    throw unavailable()
  }

  func endPhoneCall() throws -> PhoneCallActionResult {
    throw unavailable()
  }

  func playAudioToPhoneCall(_ input: PlayPhoneCallAudioInput) throws -> PhoneCallAudioResult {
    throw unavailable()
  }

  func stopPhoneCallAudio() throws -> PhoneCallAudioResult {
    throw unavailable()
  }

  func phoneCallListeningStatus() throws -> PhoneCallListeningStatus {
    throw unavailable()
  }

  func phoneCallAudioInputEvents(afterSequence: Int) throws -> [PhoneCallAudioInputEvent] {
    throw unavailable()
  }

  func startPhoneCallListening(_ input: StartPhoneCallListeningInput) throws -> PhoneCallListeningStatus {
    throw unavailable()
  }

  func stopPhoneCallListening() throws -> PhoneCallListeningStatus {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Phone calls provider is unavailable")
  }
}
