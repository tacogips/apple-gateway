import Foundation

enum FileStorePathSafety {
  static func validateSegment(_ value: String, field: String) throws {
    guard !value.isEmpty else {
      throw invalidKey("\(field) must not be empty")
    }
    guard value != "." && value != ".." else {
      throw invalidKey("\(field) must not be a dot segment")
    }
    guard !value.contains("/") && !value.contains("\\") else {
      throw invalidKey("\(field) must be a single path segment")
    }
    guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
      throw invalidKey("\(field) must not contain NUL")
    }
    guard !value.hasPrefix("~") else {
      throw invalidKey("\(field) must not use tilde expansion")
    }
  }

  static func normalizedRoot(_ path: String, field: String) throws -> URL {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw fileError("\(field) must not be empty", path: path)
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path != "/" else {
      throw fileError("\(field) must not be the filesystem root", path: path)
    }
    return url
  }

  static func ensureContained(_ candidate: URL, in root: URL) throws {
    let rootPath = root.standardizedFileURL.path
    let candidatePath = candidate.standardizedFileURL.path
    guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
      throw fileError("Path escapes its root", path: candidatePath)
    }
  }

  static func invalidKey(_ reason: String) -> AppleGatewayError {
    AppleGatewayError(
      code: .invalidDownloadKey,
      message: reason,
      details: ["reason": reason]
    )
  }

  static func fileError(_ reason: String, path: String) -> AppleGatewayError {
    AppleGatewayError(
      code: .fileOperationFailed,
      message: reason,
      details: ["path": path, "reason": reason]
    )
  }
}
