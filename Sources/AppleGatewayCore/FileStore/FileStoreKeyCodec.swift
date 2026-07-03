import CryptoKit
import Foundation

public struct FileStoreDownloadKeyCodec: Sendable {
  private static let version = "agdk1"
  private let secret: SymmetricKey

  public init(secret: Data) {
    self.secret = SymmetricKey(data: secret)
  }

  public func encode(_ payload: FileStoreDownloadKeyPayload) throws -> String {
    try Self.validate(payload)
    let payloadData = try canonicalData(payload)
    let payloadPart = Self.base64URLEncode(payloadData)
    let mac = HMAC<SHA256>.authenticationCode(for: Data(payloadPart.utf8), using: secret)
    return "\(Self.version).\(payloadPart).\(Self.base64URLEncode(Data(mac)))"
  }

  public func decode(_ key: String) throws -> FileStoreDownloadKeyPayload {
    try Self.prevalidateSyntax(key)
    let parts = key.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == Self.version else {
      throw Self.invalidKey("Invalid download key format")
    }
    let payloadPart = String(parts[1])
    guard let expectedMAC = Self.base64URLDecode(String(parts[2])) else {
      throw Self.invalidKey("Invalid download key MAC encoding")
    }
    let actualMAC = HMAC<SHA256>.authenticationCode(for: Data(payloadPart.utf8), using: secret)
    guard Data(actualMAC) == expectedMAC else {
      throw Self.invalidKey("Download key authentication failed")
    }
    guard let payloadData = Self.base64URLDecode(payloadPart) else {
      throw Self.invalidKey("Invalid download key payload encoding")
    }
    let payload: FileStoreDownloadKeyPayload
    do {
      payload = try JSONDecoder().decode(FileStoreDownloadKeyPayload.self, from: payloadData)
    } catch {
      throw Self.invalidKey("Invalid download key payload")
    }
    try Self.validate(payload)
    return payload
  }

  public static func prevalidateSyntax(_ key: String) throws {
    let parts = key.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == version else {
      throw invalidKey("Invalid download key format")
    }
    guard base64URLDecode(String(parts[2])) != nil else {
      throw invalidKey("Invalid download key MAC encoding")
    }
    guard let payloadData = base64URLDecode(String(parts[1])) else {
      throw invalidKey("Invalid download key payload encoding")
    }
    let payload: FileStoreDownloadKeyPayload
    do {
      payload = try JSONDecoder().decode(FileStoreDownloadKeyPayload.self, from: payloadData)
    } catch {
      throw invalidKey("Invalid download key payload")
    }
    try validate(payload)
  }

  private func canonicalData(_ payload: FileStoreDownloadKeyPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(payload)
  }

  private static func validate(_ payload: FileStoreDownloadKeyPayload) throws {
    try FileStorePathSafety.validateSegment(payload.sourceId, field: "sourceId")
    for (key, value) in payload.sourceIds {
      try FileStorePathSafety.validateSegment(key, field: "sourceIds key")
      try FileStorePathSafety.validateSegment(value, field: "sourceIds value")
    }
    if let filename = payload.filename {
      try FileStorePathSafety.validateSegment(filename, field: "filename")
    }
    guard isAllowed(domain: payload.domain, kind: payload.kind) else {
      throw invalidKey("Unsupported domain/kind pair")
    }
  }

  private static func isAllowed(domain: FileStoreDomain, kind: FileStoreFileKind) -> Bool {
    switch domain {
    case .mail:
      return [.bodyText, .bodyHTML, .rawSource, .attachment].contains(kind)
    case .notes:
      return [.plaintext, .html, .attachment].contains(kind)
    case .notifications:
      return [.attachment].contains(kind)
    }
  }

  private static func invalidKey(_ reason: String) -> AppleGatewayError {
    AppleGatewayError(
      code: .invalidDownloadKey,
      message: reason,
      details: ["reason": reason]
    )
  }

  private static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func base64URLDecode(_ value: String) -> Data? {
    var normalized = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - normalized.count % 4) % 4
    normalized += String(repeating: "=", count: padding)
    return Data(base64Encoded: normalized)
  }
}
