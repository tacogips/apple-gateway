import Foundation

public enum FileStoreDomain: String, Codable, CaseIterable, Sendable {
  case mail
  case notes
  case notifications
}

public enum FileStoreFileKind: String, Codable, CaseIterable, Sendable {
  case bodyText = "BODY_TEXT"
  case bodyHTML = "BODY_HTML"
  case rawSource = "RAW_SOURCE"
  case attachment = "ATTACHMENT"
  case plaintext = "PLAINTEXT"
  case html = "HTML"
}

public struct FileStoreDownloadKeyPayload: Codable, Equatable, Sendable {
  public var domain: FileStoreDomain
  public var sourceId: String
  public var sourceIds: [String: String]
  public var kind: FileStoreFileKind
  public var filename: String?

  public init(
    domain: FileStoreDomain,
    sourceId: String,
    sourceIds: [String: String] = [:],
    kind: FileStoreFileKind,
    filename: String? = nil
  ) {
    self.domain = domain
    self.sourceId = sourceId
    self.sourceIds = sourceIds
    self.kind = kind
    self.filename = filename
  }
}

public struct FileStoreDownloadManifest: Codable, Equatable, Sendable {
  public var files: [FileStoreDownloadedFile]

  public init(files: [FileStoreDownloadedFile]) {
    self.files = files
  }
}

public struct FileStoreDownloadedFile: Codable, Equatable, Sendable {
  public var downloadKey: String
  public var domain: String
  public var kind: String
  public var path: String

  public init(downloadKey: String, domain: String, kind: String, path: String) {
    self.downloadKey = downloadKey
    self.domain = domain
    self.kind = kind
    self.path = path
  }
}

public struct FileStorePruneReport: Codable, Equatable, Sendable {
  public var removedFiles: Int
  public var removedDirectories: Int

  public init(removedFiles: Int, removedDirectories: Int) {
    self.removedFiles = removedFiles
    self.removedDirectories = removedDirectories
  }
}

public struct FileStoreSnapshotResult: Equatable, Sendable {
  public var databasePath: String
  public var copiedPaths: [String]

  public init(databasePath: String, copiedPaths: [String]) {
    self.databasePath = databasePath
    self.copiedPaths = copiedPaths
  }
}

public protocol FileStoreMaterializing: Sendable {
  func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL
}

public struct UnavailableFileStoreMaterializer: FileStoreMaterializing {
  public init() {}

  public func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    throw AppleGatewayError(
      code: .fileOperationFailed,
      message: "No file materializer is registered for \(payload.domain.rawValue)",
      details: ["domain": payload.domain.rawValue, "sourceId": payload.sourceId]
    )
  }
}
