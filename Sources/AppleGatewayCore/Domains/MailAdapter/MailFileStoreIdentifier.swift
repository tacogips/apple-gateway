import Foundation

enum MailFileStoreIdentifier {
  private static let prefix = "m_"

  static func encode(_ value: String) -> String {
    prefix + Data(value.utf8).mailBase64URLEncodedString()
  }

  static func decode(_ value: String) throws -> String {
    guard value.hasPrefix(prefix) else {
      throw invalidIdentifier()
    }
    let encoded = String(value.dropFirst(prefix.count))
    guard
      let data = Data(mailBase64URLEncoded: encoded),
      let decoded = String(data: data, encoding: .utf8),
      !decoded.isEmpty
    else {
      throw invalidIdentifier()
    }
    return decoded
  }

  static func sanitizedFilename(_ value: String?, fallback: String) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let candidate = trimmed.isEmpty ? fallback : trimmed
    let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")
      .union(.newlines)
      .union(.controlCharacters)
    let sanitized = candidate
      .components(separatedBy: invalidCharacters)
      .filter { !$0.isEmpty }
      .joined(separator: "_")
    guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
      return fallback
    }
    return sanitized
  }

  private static func invalidIdentifier() -> AppleGatewayError {
    AppleGatewayError(
      code: .invalidDownloadKey,
      message: "Invalid Mail source identifier",
      details: ["reason": "Invalid Mail source identifier"]
    )
  }
}

extension Data {
  func mailBase64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  init?(mailBase64URLEncoded string: String) {
    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = base64.count % 4
    if padding > 0 {
      base64 += String(repeating: "=", count: 4 - padding)
    }
    self.init(base64Encoded: base64)
  }
}
