import Foundation
import Testing
@testable import AppleGatewayCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Test func appleEventBudgetUsesMonotonicElapsedTime() {
  let start = Date(timeIntervalSince1970: 100)
  let budget = AppleEventProcessBudget(timeout: 30, deadline: start.addingTimeInterval(2), now: start, uptime: 500)
  #expect(!budget.expired(uptime: 501))
  #expect(budget.expired(uptime: 502))
  let unlimited = AppleEventProcessBudget(timeout: 0, deadline: start.addingTimeInterval(2), now: start, uptime: 500)
  #expect(unlimited.expired(uptime: 502))
}

@Test(arguments: [false, true]) func appleEventExpiredDeadlineDoesNotLaunch(write: Bool) throws {
  let fixture = try CancellationProcessFixture()
  defer { fixture.clean() }
  do {
    try AppleWriteExecutionContext.withDeadline(Date().addingTimeInterval(-1)) {
      if write { _ = try fixture.bridge.runWriteJXA(script: "fixture", argumentsJSON: "{}") } else {
        _ = try fixture.bridge.runJXA(script: "fixture", argumentsJSON: "{}")
      }
    }
    Issue.record("Expected expired deadline")
  } catch let error as AppleGatewayError {
    #expect(write)
    #expect(error.details?["writeOutcome"] == "notDispatched")
    #expect(error.details?["writeAttempts"] == "0")
  } catch AppleEventBridgeError.timeout {
    #expect(!write)
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.pidFile.path))
}

@Test(arguments: [false, true]) func appleEventPrecancelledTaskDoesNotLaunch(write: Bool) async throws {
  let fixture = try CancellationProcessFixture()
  defer { fixture.clean() }
  let task = Task.detached {
    // Waiting is cancelled even if cancel() wins before this task starts.
    try? await Task.sleep(for: .seconds(30))
    if write { _ = try fixture.bridge.runWriteJXA(script: "fixture", argumentsJSON: "{}") } else {
      _ = try fixture.bridge.runJXA(script: "fixture", argumentsJSON: "{}")
    }
  }
  task.cancel()
  do {
    try await task.value
    Issue.record("Expected cancellation")
  } catch let error as AppleGatewayError {
    #expect(write)
    #expect(error.details?["writeOutcome"] == "notDispatched")
    #expect(error.details?["writeAttempts"] == "0")
  } catch is CancellationError {
    #expect(!write)
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.pidFile.path))
}

@Test(arguments: [false, true]) func appleEventDeadlineStopsOwnedChildWithoutReplay(write: Bool) throws {
  let fixture = try CancellationProcessFixture()
  defer { fixture.clean() }
  let start = ProcessInfo.processInfo.systemUptime
  do {
    try AppleWriteExecutionContext.withDeadline(Date().addingTimeInterval(3)) {
      if write { _ = try fixture.bridge.runWriteJXA(script: "fixture", argumentsJSON: "{}") } else { _ = try fixture.bridge.runJXA(script: "fixture", argumentsJSON: "{}") }
    }
    Issue.record("Expected execution deadline")
  } catch let error as AppleGatewayError {
    #expect(write)
    #expect(error.details?["writeOutcome"] == "unknown")
    #expect(error.details?["writeAttempts"] == "1")
    #expect(error.details?["retrySafe"] == "false")
  } catch AppleEventBridgeError.timeout {
    #expect(!write)
  }
  #expect(ProcessInfo.processInfo.systemUptime - start < 5)
  try fixture.assertStoppedOnce()
}

@Test(arguments: [false, true]) func appleEventCancellationStopsOwnedChildWithoutReplay(write: Bool) async throws {
  let fixture = try CancellationProcessFixture()
  defer { fixture.clean() }
  let task = Task.detached {
    if write { _ = try fixture.bridge.runWriteJXA(script: "fixture", argumentsJSON: "{}") } else { _ = try fixture.bridge.runJXA(script: "fixture", argumentsJSON: "{}") }
  }
  let waitEnd = ProcessInfo.processInfo.systemUptime + 5
  while !FileManager.default.fileExists(atPath: fixture.pidFile.path), ProcessInfo.processInfo.systemUptime < waitEnd {
    try await Task.sleep(for: .milliseconds(10))
  }
  task.cancel()
  let start = ProcessInfo.processInfo.systemUptime
  do {
    try await task.value
    Issue.record("Expected cancellation")
  } catch let error as AppleGatewayError {
    #expect(write)
    #expect(error.details?["writeOutcome"] == "unknown")
    #expect(error.details?["writeAttempts"] == "1")
  } catch is CancellationError {
    #expect(!write)
  }
  #expect(ProcessInfo.processInfo.systemUptime - start < 5)
  try fixture.assertStoppedOnce()
}

private struct CancellationProcessFixture: Sendable {
  let root: URL
  let pidFile: URL
  let bridge: AppleEventBridge

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("apple-gateway-cancellation-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    pidFile = root.appendingPathComponent("pid")
    let executable = root.appendingPathComponent("stub")
    try """
    #!/bin/sh
    trap '' TERM
    echo $$ >> "$PID_FILE"
    while :; do :; done
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    bridge = AppleEventBridge(osascriptPath: executable.path, timeoutSeconds: 30,
      environment: ["PID_FILE": pidFile.path], maxTimeoutRetries: 3,
      terminationGraceSeconds: 0.05, temporaryDirectory: root)
  }

  func assertStoppedOnce() throws {
    let pids = try String(contentsOf: pidFile, encoding: .utf8).split(separator: "\n").compactMap { Int32($0) }
    #expect(pids.count == 1)
    for pid in pids { #expect(kill(pid, 0) == -1 && errno == ESRCH) }
    let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(!contents.contains { $0.hasPrefix("apple-gateway-osascript-") })
  }

  func clean() {
    // Only synthetic child PIDs recorded by this fixture, never application processes.
    if let text = try? String(contentsOf: pidFile, encoding: .utf8) {
      for pid in text.split(separator: "\n").compactMap({ Int32($0) }) { _ = kill(pid, SIGKILL) }
    }
    try? FileManager.default.removeItem(at: root)
  }
}
