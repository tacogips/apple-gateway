import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Convert a caller's wall-clock deadline once, then measure elapsed time using
/// uptime so a wall-clock adjustment cannot extend an in-flight subprocess.
struct AppleEventProcessBudget {
  let endUptime: TimeInterval

  init(timeout: TimeInterval, deadline: Date?, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    let processLimit = timeout > 0 ? timeout : .infinity
    let callerLimit = deadline.map { max(0, $0.timeIntervalSince(now)) } ?? .infinity
    endUptime = uptime + min(processLimit, callerLimit)
  }

  func expired(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
    uptime >= endUptime
  }
}

enum AppleEventProcessWaitResult {
  case exited, timedOut, cancelled
}

extension Process {
  func waitForGatewayExit(budget: AppleEventProcessBudget, observeCancellation: Bool = true) -> AppleEventProcessWaitResult {
    while isRunning {
      if observeCancellation && Task.isCancelled { return .cancelled }
      if budget.expired() { return .timedOut }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return .exited
  }

  func stopGatewayChild(graceSeconds: TimeInterval) {
    guard isRunning else { return }
    terminate()
    let graceful = waitForGatewayExit(budget: .init(timeout: graceSeconds, deadline: nil), observeCancellation: false)
    guard graceful != .exited, isRunning else { return }
#if canImport(Darwin)
    _ = Darwin.kill(processIdentifier, SIGKILL)
#elseif canImport(Glibc)
    _ = Glibc.kill(processIdentifier, SIGKILL)
#endif
    _ = waitForGatewayExit(budget: .init(timeout: graceSeconds, deadline: nil), observeCancellation: false)
  }
}
