import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum AppleEventBridgeError: Error, Equatable, Sendable {
  case automationDenied(message: String)
  case timeout(message: String)
  case appUnavailable(message: String)
  case scriptFailure(message: String)
  case invalidArgumentsJSON(message: String)
}

public struct AppleEventBridge: Sendable {
  private let writeRetryPolicy: AppleWriteRetryPolicy?
  private let osascriptPath: String
  private let timeoutSeconds: TimeInterval
  private let environment: [String: String]
  private let maxTimeoutRetries: Int
  private let terminationGraceSeconds: TimeInterval
  private let temporaryDirectory: URL

  public init(
    osascriptPath: String = "/usr/bin/osascript",
    timeoutSeconds: TimeInterval = TimeInterval(AppleGatewayConfig.Limits.defaultValue.appleEventTimeoutSeconds),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    maxTimeoutRetries: Int = 1,
    terminationGraceSeconds: TimeInterval = 1,
    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    writeRetryPolicy: AppleWriteRetryPolicy? = nil
  ) {
    self.writeRetryPolicy = writeRetryPolicy
    self.osascriptPath = osascriptPath
    self.timeoutSeconds = timeoutSeconds
    self.environment = environment
    self.maxTimeoutRetries = maxTimeoutRetries
    self.terminationGraceSeconds = max(terminationGraceSeconds, 0.01)
    self.temporaryDirectory = temporaryDirectory
  }

  public func runJXA(script: String, argumentsJSON: String) throws -> Data {
    try runJXA(script: script, argumentsJSON: argumentsJSON, retryTimeouts: true)
  }

  func runWriteJXA(script: String, argumentsJSON: String, tracksDispatch: Bool = false, retry: AppleWriteRetry? = nil) throws -> Data {
    try validateArgumentsJSON(argumentsJSON)
    return try (retry ?? AppleWriteRetry(policy: writeRetryPolicy ?? AppleWriteRetryContext.policy)).run {
      let data = try runOnce(script: AppleWriteJXA.source(script, tracksDispatch: tracksDispatch), argumentsJSON: argumentsJSON, writeAttempt: true)
      try AppleWriteJXA.validate(data)
      return data
    }
  }

  func runJXA(script: String, argumentsJSON: String, retryTimeouts: Bool) throws -> Data {
    guard !script.isEmpty else {
      throw AppleEventBridgeError.scriptFailure(message: "JXA script must not be empty")
    }
    try validateArgumentsJSON(argumentsJSON)

    var attempt = 0
    while true {
      try checkExecutionBudget()
      do {
        return try runOnce(script: script, argumentsJSON: argumentsJSON)
      } catch AppleEventBridgeError.timeout where retryTimeouts && attempt < maxTimeoutRetries && !AppleWriteExecutionContext.stopped {
        attempt += 1
        continue
      }
    }
  }

  private func validateArgumentsJSON(_ argumentsJSON: String) throws {
    guard let data = argumentsJSON.data(using: .utf8) else {
      throw AppleEventBridgeError.invalidArgumentsJSON(message: "Arguments JSON must be UTF-8")
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AppleEventBridgeError.invalidArgumentsJSON(message: "Arguments JSON must be valid JSON")
    }
  }

  private func runOnce(script: String, argumentsJSON: String, writeAttempt: Bool = false) throws -> Data {
    try checkExecutionBudget()
    let waitBudget = AppleEventProcessBudget(timeout: timeoutSeconds, deadline: AppleWriteExecutionContext.deadline)
    let process = Process()
    let fileManager = FileManager.default
    let captureId = UUID().uuidString
    let captureDirectory = temporaryDirectory
      .appendingPathComponent("apple-gateway-osascript-\(captureId)", isDirectory: true)
    do {
      try fileManager.createDirectory(
        at: captureDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      if writeAttempt { throw AppleWriteRetry.launchFailure(error, message: "Could not create osascript output capture directory") }
      throw AppleEventBridgeError.appUnavailable(message: "Could not create osascript output capture directory")
    }
    defer {
      try? fileManager.removeItem(at: captureDirectory)
    }

    let stdoutURL = captureDirectory.appendingPathComponent("stdout")
    let stderrURL = captureDirectory.appendingPathComponent("stderr")
    let privateFileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
    guard fileManager.createFile(atPath: stdoutURL.path, contents: nil, attributes: privateFileAttributes),
          fileManager.createFile(atPath: stderrURL.path, contents: nil, attributes: privateFileAttributes) else {
      if writeAttempt {
        throw AppleWriteAttemptFailure(error: .init(code: .fileOperationFailed, message: "Could not create osascript output capture files"), definitelyNotDispatched: true, transient: false)
      }
      throw AppleEventBridgeError.appUnavailable(message: "Could not create osascript output capture files")
    }
    let stdout = try FileHandle(forWritingTo: stdoutURL)
    let stderr = try FileHandle(forWritingTo: stderrURL)
    defer {
      try? stdout.close()
      try? stderr.close()
    }

    process.executableURL = URL(fileURLWithPath: osascriptPath)
    process.arguments = ["-l", "JavaScript", "-e", script, argumentsJSON]
    process.environment = environment
    process.standardOutput = stdout
    process.standardError = stderr

    try checkExecutionBudget()
    do {
      try process.run()
    } catch {
      if writeAttempt {
        throw AppleWriteRetry.launchFailure(error, message: "Could not launch osascript")
      }
      throw AppleEventBridgeError.appUnavailable(
        message: "Could not launch osascript: \(String(describing: error))"
      )
    }

    // Only this owned child is signalled. Stopping its interpreter cannot undo
    // an AppleEvent already delivered; write callers retain an unknown outcome.
    let result = process.waitForGatewayExit(budget: waitBudget)
    if result != .exited {
      process.stopGatewayChild(graceSeconds: terminationGraceSeconds)
      if result == .cancelled { throw CancellationError() }
      throw AppleEventBridgeError.timeout(message: "osascript exceeded its execution budget")
    }

    try? stdout.synchronize()
    try? stderr.synchronize()
    try? stdout.close()
    try? stderr.close()
    let outputData = try Data(contentsOf: stdoutURL)
    let errorData = try Data(contentsOf: stderrURL)
    let stderrText = String(data: errorData, encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      throw classifyFailure(status: process.terminationStatus, stderr: stderrText)
    }

    do {
      _ = try JSONSerialization.jsonObject(with: outputData)
    } catch {
      throw AppleEventBridgeError.scriptFailure(message: "osascript returned non-JSON output")
    }
    return outputData
  }

  private func checkExecutionBudget() throws {
    if Task.isCancelled { throw CancellationError() }
    if AppleWriteExecutionContext.deadline.map({ $0.timeIntervalSinceNow <= 0 }) == true {
      throw AppleEventBridgeError.timeout(message: "osascript execution deadline expired before launch")
    }
  }

  private func classifyFailure(status: Int32, stderr: String) -> AppleEventBridgeError {
    let normalized = stderr.lowercased()
    if stderr.contains("-1712") || normalized.contains("timed out") || normalized.contains("timeout") {
      return .timeout(message: trimmed(stderr, fallback: "osascript timed out"))
    }
    if stderr.contains("-1743")
      || normalized.contains("not authorized")
      || normalized.contains("not permitted")
      || normalized.contains("not allowed")
      || normalized.contains("automation")
      || normalized.contains("tcc") {
      return .automationDenied(message: trimmed(stderr, fallback: "Automation denied"))
    }
    if stderr.contains("-600")
      || stderr.contains("-609")
      || normalized.contains("application isn")
      || normalized.contains("application is not running")
      || normalized.contains("can't get application")
      || normalized.contains("not found") {
      return .appUnavailable(message: trimmed(stderr, fallback: "Application unavailable"))
    }
    return .scriptFailure(
      message: trimmed(stderr, fallback: "osascript failed with status \(status)")
    )
  }

  private func trimmed(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }
}
