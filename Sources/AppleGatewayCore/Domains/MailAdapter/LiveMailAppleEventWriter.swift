import Foundation

public struct LiveMailAppleEventWriter: MailWriting {
  private let bridge: AppleEventBridge
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(bridge: AppleEventBridge = AppleEventBridge()) {
    self.bridge = bridge
    encoder = JSONEncoder()
    decoder = JSONDecoder()
  }

  public func setRead(target: MailMessageTarget, isRead: Bool) throws {
    try run(template: .setRead, arguments: MailBooleanWriteArguments(target: target, value: isRead))
  }

  public func setFlagged(target: MailMessageTarget, isFlagged: Bool) throws {
    try run(template: .setFlagged, arguments: MailBooleanWriteArguments(target: target, value: isFlagged))
  }

  public func move(target: MailMessageTarget, destination: MailboxTarget) throws {
    try run(template: .move, arguments: MailMoveArguments(target: target, destination: destination))
  }

  public func delete(target: MailMessageTarget) throws {
    try run(template: .delete, arguments: MailDeleteArguments(target: target))
  }

  private func run<Arguments: Encodable>(
    template: MailJXATemplate,
    arguments: Arguments
  ) throws {
    do {
      let argumentsData = try encoder.encode(arguments)
      guard let argumentsJSON = String(data: argumentsData, encoding: .utf8) else {
        throw AppleGatewayError(code: .unexpectedError, message: "Failed to encode Mail JXA arguments")
      }
      let data = try bridge.runJXA(script: template.source, argumentsJSON: argumentsJSON)
      let result = try decoder.decode(MailJXAWriteResult.self, from: data)
      guard result.success else {
        throw AppleGatewayError(code: .unexpectedError, message: "Mail automation did not confirm the update")
      }
    } catch let error as AppleGatewayError {
      throw error
    } catch let error as AppleEventBridgeError {
      throw map(error)
    } catch {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Mail automation failed",
        details: ["reason": String(describing: error)]
      )
    }
  }

  private func map(_ error: AppleEventBridgeError) -> AppleGatewayError {
    switch error {
    case .automationDenied(let message):
      return AppleGatewayError(code: .automationDenied, message: message)
    case .timeout(let message):
      return AppleGatewayError(code: .appleEventTimeout, message: message)
    case .appUnavailable(let message):
      return AppleGatewayError(code: .domainDisabled, message: message)
    case .scriptFailure(let message):
      if message.contains("APPLE_GATEWAY_MESSAGE_NOT_FOUND:") {
        return AppleGatewayError(code: .messageNotFound, message: "Mail message not found in Mail.app")
      }
      if message.contains("APPLE_GATEWAY_MAILBOX_NOT_FOUND:") {
        return AppleGatewayError(code: .mailboxNotFound, message: "Mailbox not found in Mail.app")
      }
      return AppleGatewayError(code: .unexpectedError, message: message)
    case .invalidArgumentsJSON(let message):
      return AppleGatewayError(code: .unexpectedError, message: message)
    }
  }
}

private struct MailBooleanWriteArguments: Encodable {
  var target: MailMessageTarget
  var value: Bool
}

private struct MailMoveArguments: Encodable {
  var target: MailMessageTarget
  var destination: MailboxTarget
}

private struct MailDeleteArguments: Encodable {
  var target: MailMessageTarget
}

private struct MailJXAWriteResult: Decodable {
  var success: Bool
}
