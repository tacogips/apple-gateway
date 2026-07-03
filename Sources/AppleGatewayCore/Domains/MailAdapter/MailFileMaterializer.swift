import Foundation

public struct MailFileMaterializer: FileStoreMaterializing {
  private let parser: MailEMLXParser
  private let scratchDirectory: URL

  public init(
    scratchDirectory: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-mail-materializer", isDirectory: true)
  ) {
    parser = MailEMLXParser()
    self.scratchDirectory = scratchDirectory
  }

  public func sourceFile(for payload: FileStoreDownloadKeyPayload) throws -> URL {
    guard payload.domain == .mail else {
      throw AppleGatewayError(
        code: .fileOperationFailed,
        message: "Mail materializer cannot handle \(payload.domain.rawValue) files",
        details: ["domain": payload.domain.rawValue]
      )
    }
    let emlxPath = try MailFileStoreIdentifier.decode(payload.sourceId)
    let message = try parser.parse(fileURL: URL(fileURLWithPath: emlxPath))
    let materialized = try data(for: payload, message: message, emlxPath: emlxPath)
    return try write(materialized.data, filename: materialized.filename)
  }

  private func data(
    for payload: FileStoreDownloadKeyPayload,
    message: MailParsedMessage,
    emlxPath: String
  ) throws -> (data: Data, filename: String) {
    switch payload.kind {
    case .bodyText:
      guard let body = message.bodyText else {
        throw bodyMissing(path: emlxPath, kind: payload.kind)
      }
      return (Data(body.utf8), payload.filename ?? "body.txt")
    case .bodyHTML:
      guard let body = message.bodyHTML else {
        throw bodyMissing(path: emlxPath, kind: payload.kind)
      }
      return (Data(body.utf8), payload.filename ?? "body.html")
    case .rawSource:
      return (message.rawSource, payload.filename ?? "raw.eml")
    case .attachment:
      let index = Int(payload.sourceIds["attachmentIndex"] ?? "")
      guard let index, message.attachments.indices.contains(index) else {
        throw AppleGatewayError(
          code: .messageNotFound,
          message: "Mail attachment is not stored locally",
          details: ["path": emlxPath, "reason": "The attachment is not stored locally by Mail"]
        )
      }
      let attachment = message.attachments[index]
      return (attachment.data, payload.filename ?? attachment.filename)
    case .plaintext, .html:
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Download key does not reference a Mail file",
        details: ["kind": payload.kind.rawValue]
      )
    }
  }

  private func write(_ data: Data, filename: String) throws -> URL {
    let filename = MailFileStoreIdentifier.sanitizedFilename(filename, fallback: "mail.bin")
    let destination = scratchDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent(filename)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destination, options: [.atomic])
    return destination
  }

  private func bodyMissing(path: String, kind: FileStoreFileKind) -> AppleGatewayError {
    AppleGatewayError(
      code: .messageNotFound,
      message: "Mail message body is not stored locally",
      details: [
        "path": path,
        "kind": kind.rawValue,
        "reason": "The body is not stored locally by Mail"
      ]
    )
  }
}

public struct MailMessageFileFactory: Sendable {
  private let fileStore: FileStore
  private let parser: MailEMLXParser

  public init(fileStore: FileStore) {
    self.fileStore = fileStore
    parser = MailEMLXParser()
  }

  public func files(emlxPath: String) throws -> MailMessageFileSet {
    let message = try parser.parse(fileURL: URL(fileURLWithPath: emlxPath))
    let sourceId = MailFileStoreIdentifier.encode(emlxPath)
    return MailMessageFileSet(
      bodyText: try bodyFile(
        sourceId: sourceId,
        kind: .bodyText,
        filename: "body.txt",
        byteSize: message.bodyText.map { Data($0.utf8).count }
      ),
      bodyHtml: try bodyFile(
        sourceId: sourceId,
        kind: .bodyHTML,
        filename: "body.html",
        byteSize: message.bodyHTML.map { Data($0.utf8).count }
      ),
      rawSource: try bodyFile(
        sourceId: sourceId,
        kind: .rawSource,
        filename: "raw.eml",
        byteSize: message.rawSource.count
      ),
      attachments: try message.attachments.enumerated().map { index, attachment in
        try attachmentFile(sourceId: sourceId, index: index, attachment: attachment)
      }
    )
  }

  private func bodyFile(
    sourceId: String,
    kind: FileStoreFileKind,
    filename: String,
    byteSize: Int?
  ) throws -> MailMessageFile? {
    guard let byteSize else {
      return nil
    }
    return MailMessageFile(
      downloadKey: try fileStore.issueDownloadKey(
        FileStoreDownloadKeyPayload(domain: .mail, sourceId: sourceId, kind: kind, filename: filename)
      ),
      kind: try MailFileKind(fileStoreKind: kind),
      filename: filename,
      byteSize: byteSize
    )
  }

  private func attachmentFile(
    sourceId: String,
    index: Int,
    attachment: MailParsedAttachment
  ) throws -> MailMessageFile {
    let filename = MailFileStoreIdentifier.sanitizedFilename(attachment.filename, fallback: "attachment.bin")
    return MailMessageFile(
      downloadKey: try fileStore.issueDownloadKey(
        FileStoreDownloadKeyPayload(
          domain: .mail,
          sourceId: sourceId,
          sourceIds: ["attachmentIndex": "\(index)"],
          kind: .attachment,
          filename: filename
        )
      ),
      kind: .attachment,
      filename: filename,
      mimeType: attachment.mimeType,
      byteSize: attachment.data.count
    )
  }
}

private extension MailFileKind {
  init(fileStoreKind: FileStoreFileKind) throws {
    switch fileStoreKind {
    case .bodyText:
      self = .bodyText
    case .bodyHTML:
      self = .bodyHTML
    case .rawSource:
      self = .rawSource
    case .attachment:
      self = .attachment
    case .plaintext, .html:
      throw AppleGatewayError(
        code: .invalidDownloadKey,
        message: "Download key does not reference a Mail file",
        details: ["kind": fileStoreKind.rawValue]
      )
    }
  }
}
