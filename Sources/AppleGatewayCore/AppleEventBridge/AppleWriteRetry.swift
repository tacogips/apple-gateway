import Foundation

/// Retries only failures proven to precede the first externally visible write.
public struct AppleWriteRetryPolicy: Codable, Equatable, Sendable {
  public var initialWaitSeconds: Int
  public var maxRetries: Int

  public init(initialWaitSeconds: Int = 2, maxRetries: Int = 3) {
    self.initialWaitSeconds = initialWaitSeconds
    self.maxRetries = maxRetries
  }

  public static let defaultValue = AppleWriteRetryPolicy()

  enum CodingKeys: String, CodingKey {
    case initialWaitSeconds = "initial_wait_seconds"
    case maxRetries = "max_retries"
  }

  func validate() throws {
    guard (1...60).contains(initialWaitSeconds), (0...5).contains(maxRetries) else {
      throw AppleGatewayConfigError.validation(
        message: "write_retry requires initial_wait_seconds in 1...60 and max_retries in 0...5"
      )
    }
  }

  func delay(retryIndex: Int) -> TimeInterval {
    TimeInterval(min(initialWaitSeconds * (1 << min(max(retryIndex, 0), 5)), 60))
  }
}

/// Execution budget for synchronous hosts such as Riela. An in-flight native
/// call may finish after the deadline, but no subsequent attempt may begin.
public enum AppleWriteExecutionContext {
  @TaskLocal static var deadline: Date?

  public static func withDeadline<Value>(_ deadline: Date?, operation: () throws -> Value) rethrows -> Value {
    let effective = [Self.deadline, deadline].compactMap { $0 }.min()
    return try $deadline.withValue(effective, operation: operation)
  }

  public static func withDeadline<Value>(_ deadline: Date?, operation: () async throws -> Value) async rethrows -> Value {
    let effective = [Self.deadline, deadline].compactMap { $0 }.min()
    return try await $deadline.withValue(effective, operation: operation)
  }

  static var stopped: Bool {
    Task.isCancelled || deadline.map { $0.timeIntervalSinceNow <= 0 } == true
  }
}

// Scoped to one SDK/GraphQL invocation; never caches credentials or outcomes.
enum AppleWriteRetryContext {
  @TaskLocal static var policy = AppleWriteRetryPolicy.defaultValue
}

struct AppleWriteAttemptFailure: Error {
  let error: AppleGatewayError
  let definitelyNotDispatched: Bool
  let transient: Bool
}

struct AppleWriteRetry {
  var policy: AppleWriteRetryPolicy = AppleWriteRetryContext.policy
  var sleep: (TimeInterval) -> Void = { seconds in
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !AppleWriteExecutionContext.stopped {
      let remaining = deadline - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { return }
      Thread.sleep(forTimeInterval: min(remaining, 0.05))
    }
  }
  var isCancelled: () -> Bool = { AppleWriteExecutionContext.stopped }

  func run<Value>(_ operation: () throws -> Value) throws -> Value {
    try policy.validate()
    var retries = 0
    var attempts = 0
    while true {
      guard !isCancelled() else {
        throw Self.annotated(CancellationError(), outcome: "notDispatched", attempts: attempts)
      }
      attempts += 1
      do {
        return try operation()
      } catch let failure as AppleWriteAttemptFailure {
        if failure.definitelyNotDispatched && failure.transient && retries < policy.maxRetries {
          sleep(policy.delay(retryIndex: retries))
          retries += 1
          continue
        }
        throw Self.annotated(
          failure.error,
          outcome: failure.definitelyNotDispatched ? "notDispatched" : "unknown",
          attempts: retries + 1
        )
      } catch {
        // No transport proof means no replay, regardless of error text or code.
        throw Self.annotated(error, outcome: "unknown", attempts: retries + 1)
      }
    }
  }

  func readback<Value>(id: String, _ operation: () throws -> Value) throws -> Value {
    try policy.validate()
    var retries = 0
    while true {
      guard !isCancelled() else {
        var result = Self.annotated(CancellationError(), outcome: "confirmed", attempts: 1)
        result.details?["resourceId"] = id
        result.details?["readbackAttempts"] = String(retries)
        throw result
      }
      do {
        return try operation()
      } catch {
        let transient: Bool
        switch error {
        case AppleEventBridgeError.timeout, AppleEventBridgeError.appUnavailable:
          transient = true
        case let gateway as AppleGatewayError:
          transient = gateway.code == .appleEventTimeout
        default:
          transient = false
        }
        if transient && retries < policy.maxRetries {
          sleep(policy.delay(retryIndex: retries))
          retries += 1
          continue
        }
        var result = Self.annotated(error, outcome: "confirmed", attempts: 1)
        result.details?["resourceId"] = id
        result.details?["readbackAttempts"] = String(retries + 1)
        throw result
      }
    }
  }

  static func launchFailure(_ error: Error, message: String, code: AppleGatewayErrorCode = .unexpectedError) -> AppleWriteAttemptFailure {
    let native = error as NSError
    let underlying = native.userInfo[NSUnderlyingErrorKey] as? NSError
    let posix = native.domain == NSPOSIXErrorDomain ? native : underlying
    let transient = posix?.domain == NSPOSIXErrorDomain
      && [Int(POSIXErrorCode.EAGAIN.rawValue), Int(POSIXErrorCode.ENOMEM.rawValue)].contains(posix?.code ?? 0)
    return AppleWriteAttemptFailure(
      error: AppleGatewayError(code: code, message: message),
      definitelyNotDispatched: true,
      transient: transient
    )
  }

  static func annotated(_ error: Error, outcome: String, attempts: Int) -> AppleGatewayError {
    var result: AppleGatewayError
    if let gateway = error as? AppleGatewayError {
      result = gateway
    } else if case AppleEventBridgeError.timeout(let message) = error {
      result = AppleGatewayError(code: .appleEventTimeout, message: message)
    } else if case AppleEventBridgeError.automationDenied(let message) = error {
      result = AppleGatewayError(code: .automationDenied, message: message)
    } else {
      result = AppleGatewayError(code: .unexpectedError, message: String(describing: error))
    }
    var details = result.details ?? [:]
    details["writeOutcome"] = outcome
    details["retrySafe"] = "false"
    details["writeAttempts"] = String(attempts)
    result.details = details
    return result
  }
}
