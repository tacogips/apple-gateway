import Foundation

public struct PermissionFailureMessage: Equatable, Sendable {
  public var text: String
  public var details: [String: String]

  public init(text: String, details: [String: String]) {
    self.text = text
    self.details = details
  }
}

public struct PermissionFailureFormatter: Sendable {
  public init() {}

  public func message(
    domainName: String,
    stateDescription: String,
    responsibleProcessHint: String?,
    settingsPane: String,
    requestCommand: String?,
    resetCommand: String?
  ) -> PermissionFailureMessage {
    let responsibleProcess = responsibleProcessHint?.isEmpty == false
      ? responsibleProcessHint ?? "unknown"
      : "unknown"
    var lines = [
      "\(domainName) access is \(stateDescription) for this process tree.",
      "Responsible app (best effort): \(responsibleProcess)"
    ]
    if let requestCommand {
      lines.append("Fix: \(settingsPane): enable \"\(responsibleProcess)\",")
      lines.append("or run: \(requestCommand)")
    } else {
      lines.append("Fix: \(settingsPane)")
    }
    if let resetCommand {
      lines.append("Reset: \(resetCommand)")
    }

    var details = [
      "domain": domainName,
      "state": stateDescription,
      "responsibleProcessHint": responsibleProcess,
      "settingsPane": settingsPane
    ]
    if let requestCommand {
      details["requestCommand"] = requestCommand
    }
    if let resetCommand {
      details["resetCommand"] = resetCommand
    }

    return PermissionFailureMessage(text: lines.joined(separator: "\n"), details: details)
  }
}
