import Foundation

public enum AppleGatewayConfigError: Error, Equatable, Sendable {
  case missingExplicitConfig(path: String)
  case fileReadFailed(path: String, message: String)
  case parse(path: String, line: Int, column: Int, message: String)
  case environment(name: String, message: String)
  case validation(message: String)

  public var message: String {
    switch self {
    case .missingExplicitConfig(let path):
      "Config file does not exist: \(path)"
    case .fileReadFailed(let path, let message):
      "Could not read config file \(path): \(message)"
    case .parse(_, _, _, let message):
      message
    case .environment(let name, let message):
      "Invalid environment override \(name): \(message)"
    case .validation(let message):
      message
    }
  }

  public var details: [String: String] {
    switch self {
    case .missingExplicitConfig(let path):
      ["path": path]
    case .fileReadFailed(let path, let message):
      ["path": path, "reason": message]
    case .parse(let path, let line, let column, let message):
      [
        "path": path,
        "line": String(line),
        "column": String(column),
        "reason": message
      ]
    case .environment(let name, let message):
      ["env": name, "reason": message]
    case .validation(let message):
      ["reason": message]
    }
  }

  public var appleGatewayError: AppleGatewayError {
    AppleGatewayError(
      code: .configInvalid,
      message: message,
      details: details
    )
  }
}
