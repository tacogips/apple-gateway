import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(ApplicationServices)
import ApplicationServices
#endif

protocol PhoneCallUIControlling: Sendable {
  func status() throws -> PhoneCallStatus
  func openCall(phoneNumber: String, displayName: String?, autoConfirm: Bool) throws -> PhoneCallActionResult
  func perform(_ action: PhoneCallControlAction) throws -> PhoneCallActionResult
}

struct LivePhoneCallUIController: PhoneCallUIControlling {
  private static let unsupportedWarning =
    "Incoming and in-call controls use best-effort macOS Accessibility automation because Apple exposes no public third-party call-control API."

  func status() throws -> PhoneCallStatus {
    #if canImport(AppKit) && canImport(ApplicationServices)
    guard AXIsProcessTrusted() else {
      return PhoneCallStatus(
        state: .unknown,
        warning: "Accessibility permission is required to inspect Phone or FaceTime call controls."
      )
    }
    for application in runningCallApplications() {
      let controls = actionableControls(application: application)
      if controls.contains(where: { matches($0, action: .answer) }) {
        return PhoneCallStatus(
          state: .incoming,
          application: application.localizedName,
          warning: Self.unsupportedWarning
        )
      }
      if controls.contains(where: { matches($0, action: .end) }) {
        return PhoneCallStatus(
          state: .active,
          application: application.localizedName,
          warning: Self.unsupportedWarning
        )
      }
    }
    return PhoneCallStatus(state: .idle, warning: Self.unsupportedWarning)
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Phone call controls require macOS")
    #endif
  }

  func openCall(phoneNumber: String, displayName: String?, autoConfirm: Bool) throws -> PhoneCallActionResult {
    #if canImport(AppKit)
    if autoConfirm {
      #if canImport(ApplicationServices)
      guard AXIsProcessTrusted() else {
        throw AppleGatewayError(
          code: .automationDenied,
          message: "Accessibility permission is required to confirm an outgoing phone call",
          details: ["hint": "Run apple-gateway permissions request --domain phone-calls"]
        )
      }
      #else
      throw AppleGatewayError(code: .unsupportedOSVersion, message: "Call confirmation requires macOS Accessibility")
      #endif
    }
    var components = URLComponents()
    components.scheme = "tel"
    components.path = phoneNumber
    guard let url = components.url else {
      throw AppleGatewayError(code: .invalidArgument, message: "Could not create a telephone URL")
    }
    guard NSWorkspace.shared.open(url) else {
      throw AppleGatewayError(code: .unexpectedError, message: "macOS could not open the telephone URL")
    }
    #if canImport(ApplicationServices)
    if autoConfirm, let confirmation = waitForControl(action: .dial) {
      let pressResult = AXUIElementPerformAction(confirmation.control, kAXPressAction as CFString)
      guard pressResult == .success else {
        throw AppleGatewayError(
          code: .unexpectedError,
          message: "The outgoing call confirmation could not be pressed",
          details: ["axError": "\(pressResult.rawValue)"]
        )
      }
      return PhoneCallActionResult(
        success: true,
        state: .unknown,
        targetName: displayName,
        application: confirmation.application.localizedName,
        warning: Self.unsupportedWarning
      )
    }
    #endif
    return PhoneCallActionResult(
      success: true,
      state: .unknown,
      targetName: displayName,
      warning: autoConfirm
        ? "The call was handed to Phone or FaceTime, but no outgoing confirmation control was found; it may already be dialing or still require manual confirmation."
        : "The call was handed to Phone or FaceTime. macOS may require visible user confirmation before dialing."
    )
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Placing phone calls requires macOS")
    #endif
  }

  func perform(_ action: PhoneCallControlAction) throws -> PhoneCallActionResult {
    #if canImport(AppKit) && canImport(ApplicationServices)
    guard AXIsProcessTrusted() else {
      throw AppleGatewayError(
        code: .automationDenied,
        message: "Accessibility permission is required for phone call controls",
        details: ["hint": "Run apple-gateway permissions request --domain phone-calls"]
      )
    }
    for application in runningCallApplications() {
      if let control = actionableControls(application: application).first(where: { matches($0, action: action) }) {
        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        guard result == .success else {
          throw AppleGatewayError(
            code: .unexpectedError,
            message: "The phone call control could not be pressed",
            details: ["axError": "\(result.rawValue)", "action": action.rawValue]
          )
        }
        return PhoneCallActionResult(
          success: true,
          state: action == .answer ? .active : .idle,
          application: application.localizedName,
          warning: Self.unsupportedWarning
        )
      }
    }
    throw AppleGatewayError(
      code: .invalidArgument,
      message: "No matching phone call control is currently available",
      details: ["action": action.rawValue]
    )
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Phone call controls require macOS")
    #endif
  }

  #if canImport(AppKit) && canImport(ApplicationServices)
  private func runningCallApplications() -> [NSRunningApplication] {
    let bundleIdentifiers = [
      "com.apple.mobilephone",
      "com.apple.FaceTime",
      "com.apple.notificationcenterui"
    ]
    return bundleIdentifiers.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:))
  }

  private func actionableControls(application: NSRunningApplication) -> [AXUIElement] {
    let root = AXUIElementCreateApplication(application.processIdentifier)
    var output: [AXUIElement] = []
    var queue = [root]
    var visited = 0
    while !queue.isEmpty, visited < 2_000 {
      let element = queue.removeFirst()
      visited += 1
      if attribute(element, kAXRoleAttribute) == kAXButtonRole as String,
         isCallContext(element, application: application) {
        output.append(element)
      }
      queue.append(contentsOf: children(element))
    }
    return output
  }

  private func waitForControl(
    action: PhoneCallControlAction
  ) -> (control: AXUIElement, application: NSRunningApplication)? {
    for _ in 0..<60 {
      for application in runningCallApplications()
      where application.bundleIdentifier != "com.apple.notificationcenterui" {
        if let control = actionableControls(application: application).first(where: { matches($0, action: action) }) {
          return (control, application)
        }
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
  }

  private func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
      return []
    }
    return value as? [AXUIElement] ?? []
  }

  private func attribute(_ element: AXUIElement, _ name: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return ""
    }
    return value as? String ?? ""
  }

  private func matches(_ element: AXUIElement, action: PhoneCallControlAction) -> Bool {
    let identifier = normalized(attribute(element, kAXIdentifierAttribute))
    if action.identifierTerms.contains(where: identifier.contains) {
      return true
    }
    let labels = [
      attribute(element, kAXTitleAttribute),
      attribute(element, kAXDescriptionAttribute),
      attribute(element, kAXHelpAttribute)
    ]
      .map(normalized)
    return labels.contains(where: action.visibleLabels.contains)
  }

  private func isCallContext(_ element: AXUIElement, application: NSRunningApplication) -> Bool {
    guard application.bundleIdentifier == "com.apple.notificationcenterui" else {
      return true
    }
    var current: AXUIElement? = element
    for _ in 0..<8 {
      guard let candidate = current else {
        break
      }
      let context = [
        attribute(candidate, kAXIdentifierAttribute),
        attribute(candidate, kAXTitleAttribute),
        attribute(candidate, kAXDescriptionAttribute),
        attribute(candidate, kAXHelpAttribute)
      ]
        .map(normalized)
        .joined(separator: " ")
      if ["phone", "facetime", "incoming call", "電話", "着信"].contains(where: context.contains) {
        return true
      }
      var parentValue: CFTypeRef?
      guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
            let parent = parentValue
      else {
        break
      }
      guard CFGetTypeID(parent) == AXUIElementGetTypeID() else {
        break
      }
      current = unsafeDowncast(parent, to: AXUIElement.self)
    }
    return false
  }

  private func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }
  #endif
}

private extension PhoneCallControlAction {
  var identifierTerms: [String] {
    switch self {
    case .dial:
      ["dial", "callbutton", "call-button", "startcall", "start-call"]
    case .answer:
      ["answer", "accept"]
    case .decline:
      ["decline", "reject"]
    case .end:
      ["endcall", "end-call", "hangup", "hang-up", "disconnect"]
    }
  }

  var visibleLabels: [String] {
    switch self {
    case .dial:
      ["call", "発信"]
    case .answer:
      ["answer", "accept", "応答", "出る"]
    case .decline:
      ["decline", "reject", "拒否", "辞退"]
    case .end:
      ["end call", "hang up", "disconnect", "通話を終了"]
    }
  }
}
