import Foundation

public enum ClockAlarmShortcutContract {
  public static let version = 1

  public static func encodeInput<T: Encodable>(_ input: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(VersionedShortcutInput(payload: input))
  }

  public static func decodeAlarms(from data: Data) throws -> [ClockAlarm] {
    do {
      let response = try decoder.decode(ClockAlarmShortcutAlarmsResponse.self, from: data)
      try validate(version: response.contractVersion)
      return response.alarms
    } catch let error as AppleGatewayError {
      throw error
    } catch {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Clock alarms shortcut returned invalid JSON",
        details: ["underlyingError": String(describing: error)]
      )
    }
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    return decoder
  }()

  private static func validate(version: Int) throws {
    guard version == Self.version else {
      throw AppleGatewayError(
        code: .unexpectedError,
        message: "Clock alarms shortcut contract version mismatch",
        details: ["expected": String(Self.version), "actual": String(version)]
      )
    }
  }
}

private struct VersionedShortcutInput<Payload: Encodable>: Encodable {
  var contractVersion = ClockAlarmShortcutContract.version
  var payload: Payload
}

private struct ClockAlarmShortcutAlarmsResponse: Decodable {
  var contractVersion: Int
  var alarms: [ClockAlarm]
}
