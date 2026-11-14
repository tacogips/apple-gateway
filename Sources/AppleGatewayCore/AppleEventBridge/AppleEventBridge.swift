import Foundation

public enum AppleEventBridgeError: Error, Equatable, Sendable {
  case automationDenied(message: String)
  case timeout(message: String)
  case appUnavailable(message: String)
  case scriptFailure(message: String)
  case invalidArgumentsJSON(message: String)
}

public struct AppleEventBridge: Sendable {
  private let osascriptPath: String
  private let timeoutSeconds: TimeInterval
  private let environment: [String: String]
  private let maxTimeoutRetries: Int

  public init(
    osascriptPath: String = "/usr/bin/osascript",
    timeoutSeconds: TimeInterval = TimeInterval(AppleGatewayConfig.Limits.defaultValue.appleEventTimeoutSeconds),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    maxTimeoutRetries: Int = 1
  ) {
    self.osascriptPath = osascriptPath
    self.timeoutSeconds = timeoutSeconds
    self.environment = environment
    self.maxTimeoutRetries = maxTimeoutRetries
  }

  public func runJXA(script: String, argumentsJSON: String) throws -> Data {
    guard !script.isEmpty else {
      throw AppleEventBridgeError.scriptFailure(message: "JXA script must not be empty")
    }
    try validateArgumentsJSON(argumentsJSON)

    var attempt = 0
    while true {
      do {
        return try runOnce(script: script, argumentsJSON: argumentsJSON)
      } catch AppleEventBridgeError.timeout where attempt < maxTimeoutRetries {
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

  private func runOnce(script: String, argumentsJSON: String) throws -> Data {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: osascriptPath)
    process.arguments = ["-l", "JavaScript", "-e", script, argumentsJSON]
    process.environment = environment
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw AppleEventBridgeError.appUnavailable(
        message: "Could not launch osascript: \(String(describing: error))"
      )
    }

    let timedOut = !process.waitUntilExit(timeout: timeoutSeconds)
    if timedOut {
      process.terminate()
      process.waitUntilExit()
      throw AppleEventBridgeError.timeout(message: "osascript timed out")
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
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

private extension Process {
  func waitUntilExit(timeout seconds: TimeInterval) -> Bool {
    guard seconds > 0 else {
      waitUntilExit()
      return true
    }

    let deadline = Date().addingTimeInterval(seconds)
    while isRunning {
      if Date() >= deadline {
        return false
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return true
  }
}
