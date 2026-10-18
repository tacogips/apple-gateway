import Foundation

/// Controlled scripts set the marker before their first mutating AppleEvent.
/// A process timeout cannot provide this frame and must never be replayed.
enum AppleWriteJXA {
  static func source(_ script: String, tracksDispatch: Bool) -> String {
    let body = script.replacingOccurrences(of: "function run(argv)", with: "function appleGatewayPerformWrite(argv)")
    return """
    var appleGatewayWriteStarted = \(tracksDispatch ? "false" : "true");
    function appleGatewayWillWrite() { appleGatewayWriteStarted = true; }
    \(body)
    function run(argv) {
      try { return appleGatewayPerformWrite(argv); }
      catch (error) {
        return JSON.stringify({_appleGatewayWriteFailure: {
          started: appleGatewayWriteStarted,
          number: typeof error.errorNumber === 'number' ? error.errorNumber : (typeof error.number === 'number' ? error.number : 0),
          message: String(error.message || error)
        }});
      }
    }
    """
  }

  static func validate(_ data: Data) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let frame = object["_appleGatewayWriteFailure"] as? [String: Any] else { return }
    guard let started = frame["started"] as? Bool,
          let number = frame["number"] as? Int,
          let message = frame["message"] as? String else {
      throw AppleGatewayError(code: .unexpectedError, message: "Invalid write outcome frame")
    }
    let code: AppleGatewayErrorCode
    if number == -1743 {
      code = .automationDenied
    } else if number == -1712 {
      code = .appleEventTimeout
    } else if message.contains("APPLE_GATEWAY_MESSAGE_NOT_FOUND:") {
      code = .messageNotFound
    } else if message.contains("APPLE_GATEWAY_MAILBOX_NOT_FOUND:") {
      code = .mailboxNotFound
    } else {
      code = .unexpectedError
    }
    throw AppleWriteAttemptFailure(
      error: AppleGatewayError(code: code, message: message),
      definitelyNotDispatched: !started,
      transient: [-1712, -600, -609].contains(number)
    )
  }
}
