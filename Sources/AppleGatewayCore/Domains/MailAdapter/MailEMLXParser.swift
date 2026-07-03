import Foundation

struct MailParsedMessage: Equatable, Sendable {
  var rawSource: Data
  var bodyText: String?
  var bodyHTML: String?
  var attachments: [MailParsedAttachment]
}

struct MailParsedAttachment: Equatable, Sendable {
  var filename: String
  var mimeType: String
  var data: Data
}

struct MailEMLXParser: Sendable {
  func parse(fileURL: URL) throws -> MailParsedMessage {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw AppleGatewayError(
        code: .messageNotFound,
        message: "Mail message body is not stored locally",
        details: [
          "path": fileURL.path,
          "reason": "The body is not stored locally by Mail"
        ]
      )
    }
    let rawSource = try rawSource(from: data, path: fileURL.path)
    var message = MailMIMEParser().parse(rawSource: rawSource)
    if fileURL.lastPathComponent.hasSuffix(".partial.emlx") {
      message = try reassembledPartial(message, fileURL: fileURL)
    }
    return message
  }

  private func rawSource(from data: Data, path: String) throws -> Data {
    guard let newline = data.firstIndex(of: 0x0A) else {
      throw parseError(path: path, reason: "Missing emlx byte-count line")
    }
    let countLineData = data[..<newline].dropLast(data[newline - 1] == 0x0D ? 1 : 0)
    guard
      let countLine = String(data: countLineData, encoding: .ascii),
      let byteCount = Int(countLine.trimmingCharacters(in: .whitespacesAndNewlines)),
      byteCount >= 0
    else {
      throw parseError(path: path, reason: "Invalid emlx byte-count line")
    }
    let payloadStart = data.index(after: newline)
    let payloadEnd = data.index(payloadStart, offsetBy: byteCount, limitedBy: data.endIndex) ?? data.endIndex
    guard data.distance(from: payloadStart, to: payloadEnd) == byteCount else {
      throw parseError(path: path, reason: "emlx payload is shorter than byte-count line")
    }
    return data[payloadStart..<payloadEnd]
  }

  private func reassembledPartial(_ message: MailParsedMessage, fileURL: URL) throws -> MailParsedMessage {
    let attachmentsDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    var reassembled = message
    reassembled.attachments = message.attachments.map { attachment in
      guard attachment.data.isEmpty else {
        return attachment
      }
      let filename = MailFileStoreIdentifier.sanitizedFilename(attachment.filename, fallback: "attachment.bin")
      let source = attachmentsDirectory.appendingPathComponent(filename)
      guard let data = try? Data(contentsOf: source) else {
        return attachment
      }
      return MailParsedAttachment(filename: filename, mimeType: attachment.mimeType, data: data)
    }
    return reassembled
  }

  private func parseError(path: String, reason: String) -> AppleGatewayError {
    AppleGatewayError(
      code: .fileOperationFailed,
      message: "Could not parse Mail emlx file",
      details: ["path": path, "reason": reason]
    )
  }
}
