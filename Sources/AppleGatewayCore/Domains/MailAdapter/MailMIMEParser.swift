import Foundation

struct MailMIMEParser: Sendable {
  func parse(rawSource: Data) -> MailParsedMessage {
    let part = MailMIMEPart.parse(rawSource)
    var collector = MailMIMECollector()
    collector.walk(part)
    return MailParsedMessage(
      rawSource: rawSource,
      bodyText: collector.bodyText,
      bodyHTML: collector.bodyHTML,
      attachments: collector.attachments
    )
  }
}

private struct MailMIMECollector {
  var bodyText: String?
  var bodyHTML: String?
  var attachments: [MailParsedAttachment] = []

  mutating func walk(_ part: MailMIMEPart) {
    if !part.children.isEmpty {
      part.children.forEach { walk($0) }
      return
    }
    let disposition = part.headerValue("content-disposition")?.lowercased() ?? ""
    let isAttachment = disposition.hasPrefix("attachment") || part.filename != nil
    if isAttachment {
      attachments.append(
        MailParsedAttachment(
          filename: MailFileStoreIdentifier.sanitizedFilename(part.filename, fallback: "attachment.bin"),
          mimeType: part.contentType.mediaType,
          data: part.decodedBody
        )
      )
      return
    }
    if part.contentType.mediaType == "text/plain", bodyText == nil {
      bodyText = part.decodedString
    } else if part.contentType.mediaType == "text/html", bodyHTML == nil {
      bodyHTML = part.decodedString
    }
  }
}

private struct MailMIMEPart {
  var headers: [String: [String]]
  var body: Data
  var children: [MailMIMEPart]

  var contentType: MailContentType {
    MailContentType(rawValue: headerValue("content-type") ?? "text/plain")
  }

  var filename: String? {
    let disposition = MailHeaderParameters(rawValue: headerValue("content-disposition") ?? "")
    let contentTypeParameters = MailHeaderParameters(rawValue: headerValue("content-type") ?? "")
    return disposition.parameters["filename"] ?? contentTypeParameters.parameters["name"]
  }

  var decodedBody: Data {
    let decoded = switch headerValue("content-transfer-encoding")?.lowercased() {
    case "base64":
      Data(base64Encoded: body.mailASCIIString.filter { !$0.isWhitespace }) ?? body
    case "quoted-printable":
      body.quotedPrintableDecoded()
    default:
      body
    }
    return decoded.removingSingleTrailingLineBreak()
  }

  var decodedString: String? {
    let data = decodedBody
    if contentType.charset == "iso-8859-1" || contentType.charset == "latin1" {
      return String(data: data, encoding: .isoLatin1)
    }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
  }

  static func parse(_ data: Data) -> MailMIMEPart {
    let (headers, body) = splitHeadersAndBody(data)
    var part = MailMIMEPart(headers: headers, body: body, children: [])
    if part.contentType.mediaType.hasPrefix("multipart/"), let boundary = part.contentType.parameters["boundary"] {
      part.children = multipartChildren(from: body, boundary: boundary)
    }
    return part
  }

  func headerValue(_ name: String) -> String? {
    headers[name.lowercased()]?.first
  }

  private static func splitHeadersAndBody(_ data: Data) -> ([String: [String]], Data) {
    let text = data.mailASCIIString
    let separatorRange = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n")
    guard let separatorRange else {
      return ([:], data)
    }
    let headerText = String(text[..<separatorRange.lowerBound])
    let bodyStart = separatorRange.upperBound.samePosition(in: text) ?? separatorRange.upperBound
    let bodyOffset = text.distance(from: text.startIndex, to: bodyStart)
    let bodyData = data.dropFirst(bodyOffset)
    return (parseHeaders(headerText), Data(bodyData))
  }

  private static func parseHeaders(_ text: String) -> [String: [String]] {
    var unfolded: [String] = []
    for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
      if line.first == " " || line.first == "\t", let last = unfolded.indices.last {
        unfolded[last] += " " + line.trimmingCharacters(in: .whitespaces)
      } else {
        unfolded.append(String(line))
      }
    }
    var headers: [String: [String]] = [:]
    for line in unfolded {
      guard let colon = line.firstIndex(of: ":") else {
        continue
      }
      let name = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
      headers[name, default: []].append(MailEncodedWords.decode(value))
    }
    return headers
  }

  private static func multipartChildren(from body: Data, boundary: String) -> [MailMIMEPart] {
    let text = body.mailASCIIString
    let marker = "--\(boundary)"
    var parts: [MailMIMEPart] = []
    var current: String?
    for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if line == "\(marker)--" {
        if let current {
          parts.append(parse(Data(current.utf8)))
        }
        return parts
      }
      if line == marker {
        if let current {
          parts.append(parse(Data(current.utf8)))
        }
        current = ""
      } else if current != nil {
        current?.append(line)
        current?.append("\n")
      }
    }
    if let current, !current.isEmpty {
      parts.append(parse(Data(current.utf8)))
    }
    return parts
  }
}

private struct MailContentType {
  var mediaType: String
  var parameters: [String: String]

  var charset: String {
    parameters["charset"]?.lowercased() ?? "utf-8"
  }

  init(rawValue: String) {
    let parsed = MailHeaderParameters(rawValue: rawValue)
    mediaType = parsed.value.lowercased()
    parameters = parsed.parameters
  }
}

private struct MailHeaderParameters {
  var value: String
  var parameters: [String: String]

  init(rawValue: String) {
    let pieces = rawValue.split(separator: ";", omittingEmptySubsequences: false)
    value = pieces.first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    var parsed: [String: String] = [:]
    for piece in pieces.dropFirst() {
      let assignment = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard assignment.count == 2 else {
        continue
      }
      let key = assignment[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      var value = assignment[1].trimmingCharacters(in: .whitespacesAndNewlines)
      if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
        value = String(value.dropFirst().dropLast())
      }
      parsed[key] = MailEncodedWords.decode(value)
    }
    parameters = parsed
  }
}

private enum MailEncodedWords {
  static func decode(_ value: String) -> String {
    if let decoded = decodeSingle(value) {
      return decoded
    }
    var result = value
    let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return value
    }
    let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed()
    for match in matches {
      guard
        let range = Range(match.range, in: value),
        let charsetRange = Range(match.range(at: 1), in: value),
        let encodingRange = Range(match.range(at: 2), in: value),
        let payloadRange = Range(match.range(at: 3), in: value)
      else {
        continue
      }
      let charset = String(value[charsetRange]).lowercased()
      let encoding = String(value[encodingRange]).lowercased()
      let payload = String(value[payloadRange])
      let data: Data?
      if encoding == "b" {
        data = Data(base64Encoded: payload)
      } else {
        data = Data(payload.replacingOccurrences(of: "_", with: " ").utf8).quotedPrintableDecoded()
      }
      guard let data, let decoded = string(data: data, charset: charset) else {
        continue
      }
      result.replaceSubrange(range, with: decoded)
    }
    return result
  }

  private static func string(data: Data, charset: String) -> String? {
    if charset == "iso-8859-1" || charset == "latin1" {
      return String(data: data, encoding: .isoLatin1)
    }
    return String(data: data, encoding: .utf8)
  }

  private static func decodeSingle(_ value: String) -> String? {
    guard value.hasPrefix("=?"), value.hasSuffix("?=") else {
      return nil
    }
    let body = value.dropFirst(2).dropLast(2)
    let pieces = body.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
    guard pieces.count == 3 else {
      return nil
    }
    let charset = String(pieces[0]).lowercased()
    let encoding = String(pieces[1]).lowercased()
    let payload = String(pieces[2])
    let data: Data?
    if encoding == "b" {
      data = Data(base64Encoded: payload)
    } else if encoding == "q" {
      data = Data(payload.replacingOccurrences(of: "_", with: " ").utf8).quotedPrintableDecoded()
    } else {
      data = nil
    }
    guard let data else {
      return nil
    }
    return string(data: data, charset: charset)
  }
}

private extension Data {
  var mailASCIIString: String {
    String(data: self, encoding: .utf8) ?? ""
  }

  func quotedPrintableDecoded() -> Data {
    let bytes = Array(self)
    var output = Data()
    var index = 0
    while index < bytes.count {
      if bytes[index] == 61, index + 2 < bytes.count {
        if bytes[index + 1] == 13, bytes[index + 2] == 10 {
          index += 3
          continue
        }
        if bytes[index + 1] == 10 {
          index += 2
          continue
        }
        if let decoded = UInt8(String(bytes: bytes[(index + 1)...(index + 2)], encoding: .ascii) ?? "", radix: 16) {
          output.append(decoded)
          index += 3
          continue
        }
      }
      output.append(bytes[index])
      index += 1
    }
    return output
  }

  func removingSingleTrailingLineBreak() -> Data {
    if count >= 2, self[index(endIndex, offsetBy: -2)] == 13, self[index(before: endIndex)] == 10 {
      return dropLast(2)
    }
    if last == 10 {
      return dropLast()
    }
    return self
  }
}
