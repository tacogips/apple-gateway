import Foundation

struct MailStorePaths: Equatable, Sendable {
  var root: URL
  var envelopeIndex: URL
}

protocol MailFileSystem: Sendable {
  func directoryExists(atPath path: String) -> Bool
  func fileExists(atPath path: String) -> Bool
  func isReadableFile(atPath path: String) -> Bool
}

struct LiveMailFileSystem: MailFileSystem {
  func directoryExists(atPath path: String) -> Bool {
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
  }

  func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  func isReadableFile(atPath path: String) -> Bool {
    FileManager.default.isReadableFile(atPath: path)
  }
}

struct MailRootResolver: Sendable {
  private static let supportedVersions = ["V11", "V10", "V9"]
  private static let fullDiskAccessSettingsURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  var fileSystem: any MailFileSystem
  var homeDirectory: URL

  init(
    fileSystem: any MailFileSystem = LiveMailFileSystem(),
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
  ) {
    self.fileSystem = fileSystem
    self.homeDirectory = homeDirectory
  }

  func resolve(config: AppleGatewayConfig) throws -> MailStorePaths {
    let roots = candidateRoots(config: config)
    for root in roots {
      guard fileSystem.directoryExists(atPath: root.path) else {
        continue
      }
      try requireReadable(path: root.path, description: "Mail root")

      let mailData = root.appendingPathComponent("MailData", isDirectory: true)
      guard fileSystem.directoryExists(atPath: mailData.path) else {
        continue
      }
      try requireReadable(path: mailData.path, description: "MailData directory")

      let envelopeIndex = mailData.appendingPathComponent("Envelope Index")
      guard fileSystem.fileExists(atPath: envelopeIndex.path) else {
        continue
      }
      try requireReadable(path: envelopeIndex.path, description: "Envelope Index")
      return MailStorePaths(root: root, envelopeIndex: envelopeIndex)
    }

    throw AppleGatewayError(
      code: .mailStoreNotFound,
      message: "Apple Mail store was not found",
      details: [
        "searchedRoots": roots.map(\.path).joined(separator: ","),
        "expectedFile": "MailData/Envelope Index"
      ]
    )
  }

  private func candidateRoots(config: AppleGatewayConfig) -> [URL] {
    let configuredRoot = config.mail.mailRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    if !configuredRoot.isEmpty {
      return [URL(fileURLWithPath: configuredRoot.expandingTildeInPath, isDirectory: true).standardizedFileURL]
    }
    let mailRoot = homeDirectory.appendingPathComponent("Library/Mail", isDirectory: true)
    return Self.supportedVersions.map { version in
      mailRoot.appendingPathComponent(version, isDirectory: true).standardizedFileURL
    }
  }

  private func requireReadable(path: String, description: String) throws {
    guard fileSystem.isReadableFile(atPath: path) else {
      throw AppleGatewayError(
        code: .fullDiskAccessRequired,
        message: "Apple Mail data requires Full Disk Access",
        details: [
          "path": path,
          "resource": description,
          "settingsURL": Self.fullDiskAccessSettingsURL,
          "guidance": "Grant Full Disk Access to the invoking terminal or helper app in System Settings."
        ]
      )
    }
  }
}

private extension String {
  var expandingTildeInPath: String {
    (self as NSString).expandingTildeInPath
  }
}
