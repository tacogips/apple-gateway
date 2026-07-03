import Foundation

public struct ClockAlarmShortcutNames: Equatable, Sendable {
  public var getAlarms: String
  public var createAlarm: String
  public var toggleAlarm: String
  public var updateAlarm: String
  public var deleteAlarm: String

  public init(prefix: String) {
    let normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = normalized.isEmpty ? AppleGatewayConfig.ClockAlarms.defaultValue.shortcutPrefix : normalized
    getAlarms = "\(value)-get-alarms"
    createAlarm = "\(value)-create-alarm"
    toggleAlarm = "\(value)-toggle-alarm"
    updateAlarm = "\(value)-update-alarm"
    deleteAlarm = "\(value)-delete-alarm"
  }

  public var all: [String] {
    [getAlarms, createAlarm, toggleAlarm, updateAlarm, deleteAlarm]
  }
}

public protocol ClockAlarmShortcutExecuting: Sendable {
  func listShortcuts() throws -> [String]
  func runShortcut(name: String, input: Data?) throws -> Data
}

public struct SubprocessClockAlarmShortcutExecutor: ClockAlarmShortcutExecuting, @unchecked Sendable {
  private let shortcutsPath: String
  private let timeoutSeconds: TimeInterval
  private let environment: [String: String]
  private let fileManager: FileManager

  public init(
    shortcutsPath: String = "/usr/bin/shortcuts",
    timeoutSeconds: TimeInterval = TimeInterval(AppleGatewayConfig.Limits.defaultValue.appleEventTimeoutSeconds),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) {
    self.shortcutsPath = shortcutsPath
    self.timeoutSeconds = timeoutSeconds
    self.environment = environment
    self.fileManager = fileManager
  }

  public func listShortcuts() throws -> [String] {
    let result = try runProcess(arguments: ["list"])
    return result.output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  public func runShortcut(name: String, input: Data?) throws -> Data {
    let directory = fileManager.temporaryDirectory
      .appendingPathComponent("apple-gateway-shortcuts")
      .appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? fileManager.removeItem(at: directory)
    }

    let output = directory.appendingPathComponent("output.json")
    var arguments = ["run", name, "--output-path", output.path]
    if let input {
      let inputURL = directory.appendingPathComponent("input.json")
      try input.write(to: inputURL, options: [.atomic])
      arguments.append(contentsOf: ["--input-path", inputURL.path])
    }

    _ = try runProcess(arguments: arguments)
    if fileManager.fileExists(atPath: output.path) {
      return try Data(contentsOf: output)
    }
    return Data()
  }

  private func runProcess(arguments: [String]) throws -> ShortcutProcessResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: shortcutsPath)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw AppleGatewayError(
        code: .shortcutNotInstalled,
        message: "Could not launch shortcuts CLI",
        details: ["path": shortcutsPath, "underlyingError": String(describing: error)]
      )
    }

    let timedOut = !process.waitUntilExit(timeout: timeoutSeconds)
    if timedOut {
      process.terminate()
      process.waitUntilExit()
      throw AppleGatewayError(
        code: .appleEventTimeout,
        message: "shortcuts CLI timed out",
        details: ["timeoutSeconds": String(timeoutSeconds)]
      )
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw AppleGatewayError(
        code: .shortcutActionUnsupported,
        message: "shortcuts CLI failed",
        details: [
          "status": String(process.terminationStatus),
          "stderr": stderrText,
          "stdout": outputText
        ]
      )
    }
    return ShortcutProcessResult(output: outputText)
  }
}

public struct LiveClockAlarmsAdapter: ClockAlarmsProviding {
  private enum MutationKind {
    case create(label: String?)
    case toggle(label: String, enabled: Bool?)
    case update(label: String, newLabel: String?)
    case delete(label: String)
  }

  private let config: AppleGatewayConfig
  private let executor: any ClockAlarmShortcutExecuting
  private let osVersion: OperatingSystemVersion

  public init(
    config: AppleGatewayConfig,
    executor: any ClockAlarmShortcutExecuting = SubprocessClockAlarmShortcutExecutor(),
    osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) {
    self.config = config
    self.executor = executor
    self.osVersion = osVersion
  }

  public func clockAlarms() throws -> [ClockAlarm] {
    let names = ClockAlarmShortcutNames(prefix: config.clockAlarms.shortcutPrefix)
    try require(shortcut: names.getAlarms, names: names)
    return try readAlarms(names: names)
  }

  public func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    try validateTime(input.time)
    if let label = input.label {
      try validateLabel(label, field: "label")
    }
    let names = ClockAlarmShortcutNames(prefix: config.clockAlarms.shortcutPrefix)
    try require(shortcut: names.createAlarm, names: names)
    let before = try readAlarms(names: names)
    let inputData = try ClockAlarmShortcutContract.encodeInput(input)
    _ = try executor.runShortcut(name: names.createAlarm, input: inputData)
    return try verify(kind: .create(label: input.label), before: before, names: names)
  }

  public func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    try validateLabel(input.label, field: "label")
    let names = ClockAlarmShortcutNames(prefix: config.clockAlarms.shortcutPrefix)
    try require(shortcut: names.toggleAlarm, names: names)
    let before = try readAlarms(names: names)
    try requireUnambiguous(label: input.label, in: before)
    let inputData = try ClockAlarmShortcutContract.encodeInput(input)
    _ = try executor.runShortcut(name: names.toggleAlarm, input: inputData)
    return try verify(kind: .toggle(label: input.label, enabled: input.enabled), before: before, names: names)
  }

  public func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    try requireMacOS26(action: "update Clock alarms")
    try validateLabel(input.label, field: "label")
    if let time = input.time {
      try validateTime(time)
    }
    if let newLabel = input.newLabel {
      try validateLabel(newLabel, field: "newLabel")
    }
    let names = ClockAlarmShortcutNames(prefix: config.clockAlarms.shortcutPrefix)
    try require(shortcut: names.updateAlarm, names: names)
    let before = try readAlarms(names: names)
    try requireUnambiguous(label: input.label, in: before)
    let inputData = try ClockAlarmShortcutContract.encodeInput(input)
    _ = try executor.runShortcut(name: names.updateAlarm, input: inputData)
    return try verify(kind: .update(label: input.label, newLabel: input.newLabel), before: before, names: names)
  }

  public func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    try requireMacOS26(action: "delete Clock alarms")
    try validateLabel(input.label, field: "label")
    let names = ClockAlarmShortcutNames(prefix: config.clockAlarms.shortcutPrefix)
    try require(shortcut: names.deleteAlarm, names: names)
    let before = try readAlarms(names: names)
    try requireUnambiguous(label: input.label, in: before)
    let inputData = try ClockAlarmShortcutContract.encodeInput(input)
    _ = try executor.runShortcut(name: names.deleteAlarm, input: inputData)
    return try verify(kind: .delete(label: input.label), before: before, names: names)
  }

  private func require(shortcut: String, names: ClockAlarmShortcutNames) throws {
    let installed = try executor.listShortcuts()
    guard installed.contains(shortcut) else {
      throw AppleGatewayError(
        code: .shortcutNotInstalled,
        message: "Clock alarms bridge shortcut is not installed",
        details: [
          "shortcut": shortcut,
          "installGuide": "packaging/shortcuts/README.md",
          "expectedShortcuts": names.all.joined(separator: ",")
        ]
      )
    }
  }

  private func readAlarms(names: ClockAlarmShortcutNames) throws -> [ClockAlarm] {
    let output = try executor.runShortcut(name: names.getAlarms, input: nil)
    return try ClockAlarmShortcutContract.decodeAlarms(from: output)
  }

  private func verify(kind: MutationKind, before: [ClockAlarm], names: ClockAlarmShortcutNames) throws -> ClockAlarmResult {
    let after: [ClockAlarm]
    do {
      after = try readAlarms(names: names)
    } catch let error as AppleGatewayError {
      return ClockAlarmResult(success: true, warning: "Mutation ran, but verification by re-listing failed: \(error.message)")
    }

    switch kind {
    case .create(let label):
      if let label, let alarm = createdOrMatching(label: label, before: before, after: after) {
        return ClockAlarmResult(success: true, alarm: alarm)
      }
      if let alarm = after.first(where: { candidate in !before.contains(candidate) }) {
        return ClockAlarmResult(success: true, alarm: alarm)
      }
      return ClockAlarmResult(success: true, warning: "Mutation ran, but created alarm could not be confirmed by re-listing")
    case .toggle(let label, let enabled):
      let matches = after.filter { $0.label == label }
      if let alarm = matches.first, matches.count == 1 {
        if enabled == nil || alarm.isEnabled == enabled {
          return ClockAlarmResult(success: true, alarm: alarm)
        }
      }
      return ClockAlarmResult(success: true, warning: "Mutation ran, but toggled alarm could not be confirmed by re-listing")
    case .update(let label, let newLabel):
      let targetLabel = newLabel ?? label
      let matches = after.filter { $0.label == targetLabel }
      if let alarm = matches.first, matches.count == 1 {
        return ClockAlarmResult(success: true, alarm: alarm)
      }
      return ClockAlarmResult(success: true, warning: "Mutation ran, but updated alarm could not be confirmed by re-listing")
    case .delete(let label):
      if !after.contains(where: { $0.label == label }) {
        return ClockAlarmResult(success: true)
      }
      return ClockAlarmResult(success: true, warning: "Mutation ran, but deleted alarm is still present after re-listing")
    }
  }

  private func createdOrMatching(label: String, before: [ClockAlarm], after: [ClockAlarm]) -> ClockAlarm? {
    let matches = after.filter { $0.label == label }
    if matches.count == 1 {
      return matches[0]
    }
    return matches.first { candidate in !before.contains(candidate) }
  }

  private func requireUnambiguous(label: String, in alarms: [ClockAlarm]) throws {
    let matches = alarms.filter { $0.label == label }
    if matches.count > 1 {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Clock alarm label is ambiguous",
        details: ["label": label, "matches": matches.map { "\($0.time) enabled=\($0.isEnabled)" }.joined(separator: ",")]
      )
    }
    if matches.isEmpty {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Clock alarm label was not found",
        details: ["label": label]
      )
    }
  }

  private func requireMacOS26(action: String) throws {
    guard osVersion.majorVersion >= 26 else {
      throw AppleGatewayError(
        code: .unsupportedOSVersion,
        message: "Shortcuts does not support \(action) before macOS 26",
        details: ["requiredMacOS": "26", "currentMacOS": "\(osVersion.majorVersion).\(osVersion.minorVersion)"]
      )
    }
  }

  private func validateLabel(_ value: String, field: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw AppleGatewayError(code: .invalidArgument, message: "\(field) must not be empty")
    }
  }

  private func validateTime(_ value: String) throws {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          hour >= 0,
          hour <= 23,
          minute >= 0,
          minute <= 59,
          parts[0].count == 2,
          parts[1].count == 2 else {
      throw AppleGatewayError(code: .invalidArgument, message: "time must use HH:mm local 24-hour format")
    }
  }
}

private struct ShortcutProcessResult {
  var output: String
}

private extension Process {
  func waitUntilExit(timeout seconds: TimeInterval) -> Bool {
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
