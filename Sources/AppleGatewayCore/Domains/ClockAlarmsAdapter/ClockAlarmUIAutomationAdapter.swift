import Foundation

public protocol ClockAlarmUIAutomationExecuting: Sendable {
  func listAlarms() throws -> [ClockAlarm]
  func createAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarm
  func toggleAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarm
  func updateAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarm
  func deleteAlarm(_ input: DeleteClockAlarmInput) throws
}

public struct JXAClockAlarmUIAutomationExecutor: ClockAlarmUIAutomationExecuting {
  private let bridge: AppleEventBridge
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(bridge: AppleEventBridge = AppleEventBridge()) {
    self.bridge = bridge
    encoder = JSONEncoder()
    decoder = JSONDecoder()
  }

  public func listAlarms() throws -> [ClockAlarm] {
    let response: ClockAlarmAutomationResponse = try run(
      ClockAlarmAutomationRequest(operation: .list)
    )
    return response.alarms ?? []
  }

  public func createAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarm {
    try requireAlarm(
      from: run(
        ClockAlarmAutomationRequest(
          operation: .create,
          time: input.time,
          label: input.label,
          repeatDays: input.repeatDays
        )
      )
    )
  }

  public func toggleAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarm {
    try requireAlarm(
      from: run(
        ClockAlarmAutomationRequest(
          operation: .toggle,
          label: input.label,
          enabled: input.enabled
        )
      )
    )
  }

  public func updateAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarm {
    try requireAlarm(
      from: run(
        ClockAlarmAutomationRequest(
          operation: .update,
          time: input.time,
          label: input.label,
          newLabel: input.newLabel,
          repeatDays: input.repeatDays
        )
      )
    )
  }

  public func deleteAlarm(_ input: DeleteClockAlarmInput) throws {
    let response: ClockAlarmAutomationResponse = try run(
      ClockAlarmAutomationRequest(operation: .delete, label: input.label)
    )
    guard response.success == true else {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Clock UI automation did not confirm alarm deletion"
      )
    }
  }

  private func run<Response: Decodable>(_ request: ClockAlarmAutomationRequest) throws -> Response {
    let requestData = try encoder.encode(request)
    guard let requestJSON = String(data: requestData, encoding: .utf8) else {
      throw AppleGatewayError(code: .unexpectedError, message: "Failed to encode Clock automation request")
    }

    do {
      let data = try bridge.runJXA(script: ClockAlarmJXATemplate.source, argumentsJSON: requestJSON)
      return try decoder.decode(Response.self, from: data)
    } catch let error as AppleGatewayError {
      throw error
    } catch let error as AppleEventBridgeError {
      throw map(error)
    } catch {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Clock UI automation returned an invalid response",
        details: ["underlyingError": String(describing: error)]
      )
    }
  }

  private func requireAlarm(from response: ClockAlarmAutomationResponse) throws -> ClockAlarm {
    guard let alarm = response.alarm else {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Clock UI automation did not return the affected alarm"
      )
    }
    return alarm
  }

  private func map(_ error: AppleEventBridgeError) -> AppleGatewayError {
    switch error {
    case .automationDenied(let message):
      AppleGatewayError(
        code: .automationDenied,
        message: "Clock UI automation permission was denied",
        details: ["underlyingError": message, "target": "System Events"]
      )
    case .timeout(let message):
      AppleGatewayError(
        code: .appleEventTimeout,
        message: "Clock UI automation timed out",
        details: ["underlyingError": message]
      )
    case .appUnavailable(let message):
      AppleGatewayError(
        code: .unexpectedError,
        message: "Clock app is unavailable",
        details: ["underlyingError": message]
      )
    case .scriptFailure(let message), .invalidArgumentsJSON(let message):
      AppleGatewayError(
        code: .unexpectedError,
        message: "Clock UI automation failed",
        details: ["underlyingError": message]
      )
    }
  }
}

public struct LiveClockAlarmsAdapter: ClockAlarmsProviding {
  private let executor: any ClockAlarmUIAutomationExecuting

  public init(
    config _: AppleGatewayConfig,
    executor: any ClockAlarmUIAutomationExecuting = JXAClockAlarmUIAutomationExecutor()
  ) {
    self.executor = executor
  }

  public func clockAlarms() throws -> [ClockAlarm] {
    try executor.listAlarms()
  }

  public func createClockAlarm(_ input: CreateClockAlarmInput) throws -> ClockAlarmResult {
    try validateTime(input.time)
    if let label = input.label {
      try validateLabel(label, field: "label")
    }
    let alarm = try executor.createAlarm(input)
    return ClockAlarmResult(success: true, alarm: alarm)
  }

  public func toggleClockAlarm(_ input: ToggleClockAlarmInput) throws -> ClockAlarmResult {
    try validateLabel(input.label, field: "label")
    try requireUnambiguous(label: input.label)
    let alarm = try executor.toggleAlarm(input)
    return ClockAlarmResult(success: true, alarm: alarm)
  }

  public func updateClockAlarm(_ input: UpdateClockAlarmInput) throws -> ClockAlarmResult {
    try validateLabel(input.label, field: "label")
    if let time = input.time {
      try validateTime(time)
    }
    if let newLabel = input.newLabel {
      try validateLabel(newLabel, field: "newLabel")
    }
    try requireUnambiguous(label: input.label)
    let alarm = try executor.updateAlarm(input)
    return ClockAlarmResult(success: true, alarm: alarm)
  }

  public func deleteClockAlarm(_ input: DeleteClockAlarmInput) throws -> ClockAlarmResult {
    try validateLabel(input.label, field: "label")
    try requireUnambiguous(label: input.label)
    try executor.deleteAlarm(input)
    return ClockAlarmResult(success: true)
  }

  private func requireUnambiguous(label: String) throws {
    let matches = try executor.listAlarms().filter { $0.label == label }
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

private enum ClockAlarmAutomationOperation: String, Encodable {
  case list
  case create
  case toggle
  case update
  case delete
}

private struct ClockAlarmAutomationRequest: Encodable {
  var operation: ClockAlarmAutomationOperation
  var time: String?
  var label: String?
  var newLabel: String?
  var enabled: Bool?
  var repeatDays: [ClockAlarmWeekday]?
}

private struct ClockAlarmAutomationResponse: Decodable {
  var success: Bool?
  var alarm: ClockAlarm?
  var alarms: [ClockAlarm]?
}
