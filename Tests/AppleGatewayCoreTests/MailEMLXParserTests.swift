import Foundation
import Testing
@testable import AppleGatewayCore

@Test func emlxParserExtractsBodiesAndAttachmentsFromNestedMultipart() throws {
  let root = try makeMailParserTemporaryRoot()
  let emlx = root.appendingPathComponent("message.emlx")
  let raw = """
  Subject: =?UTF-8?B?44Os44K344O844OI?=
  Content-Type: multipart/mixed; boundary="mixed"

  --mixed
  Content-Type: multipart/alternative; boundary="alt"

  --alt
  Content-Type: text/plain; charset="utf-8"
  Content-Transfer-Encoding: quoted-printable

  Hello =E4=B8=96=E7=95=8C
  --alt
  Content-Type: text/html; charset="utf-8"

  <p>Hello <b>世界</b></p>
  --alt--
  --mixed
  Content-Type: application/pdf; name="=?UTF-8?B?44Os44K344O844OILnBkZg==?="
  Content-Disposition: attachment; filename="=?UTF-8?B?44Os44K344O844OILnBkZg==?="
  Content-Transfer-Encoding: base64

  UERGREFUQQ==
  --mixed--
  """
  try writeEMLX(raw: raw, to: emlx, trailer: "<plist/>")

  let message = try MailEMLXParser().parse(fileURL: emlx)
  let attachment = try #require(message.attachments.first)

  #expect(message.bodyText == "Hello 世界")
  #expect(message.bodyHTML == "<p>Hello <b>世界</b></p>")
  #expect(attachment.filename == "レシート.pdf")
  #expect(attachment.mimeType == "application/pdf")
  #expect(attachment.data == Data("PDFDATA".utf8))
}

@Test func emlxParserAcceptsMissingTrailer() throws {
  let root = try makeMailParserTemporaryRoot()
  let emlx = root.appendingPathComponent("message.emlx")
  let raw = """
  Content-Type: text/plain; charset="utf-8"

  Body without plist trailer
  """
  try writeEMLX(raw: raw, to: emlx, trailer: nil)

  let message = try MailEMLXParser().parse(fileURL: emlx)

  #expect(message.bodyText == "Body without plist trailer")
  #expect(message.rawSource == Data(raw.utf8))
}

@Test func partialEmlxReassemblesAttachmentFromSiblingAttachmentsDirectory() throws {
  let root = try makeMailParserTemporaryRoot()
  let emlx = root.appendingPathComponent("message.partial.emlx")
  let attachments = root.appendingPathComponent("Attachments", isDirectory: true)
  try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
  try Data("external attachment".utf8).write(to: attachments.appendingPathComponent("report.txt"))
  let raw = """
  Content-Type: multipart/mixed; boundary="mixed"

  --mixed
  Content-Type: text/plain; charset="utf-8"

  Body
  --mixed
  Content-Type: text/plain; name="report.txt"
  Content-Disposition: attachment; filename="report.txt"

  --mixed--
  """
  try writeEMLX(raw: raw, to: emlx, trailer: "<plist/>")

  let message = try MailEMLXParser().parse(fileURL: emlx)
  let attachment = try #require(message.attachments.first)

  #expect(message.bodyText == "Body")
  #expect(attachment.filename == "report.txt")
  #expect(attachment.data == Data("external attachment".utf8))
}

@Test func mailMessageFileFactoryProducesDownloadKeysAndMaterializerWritesFiles() throws {
  let root = try makeMailParserTemporaryRoot()
  let emlx = root.appendingPathComponent("message.emlx")
  let cache = root.appendingPathComponent("cache")
  let output = root.appendingPathComponent("out")
  let testKey = Data("mail-materializer-test-key-material".utf8)
  let raw = """
  Content-Type: multipart/mixed; boundary="mixed"

  --mixed
  Content-Type: text/plain; charset="utf-8"

  Plain body
  --mixed
  Content-Type: text/html; charset="utf-8"

  <p>HTML body</p>
  --mixed
  Content-Type: text/plain; name="note.txt"
  Content-Disposition: attachment; filename="note.txt"

  attachment body
  --mixed--
  """
  try writeEMLX(raw: raw, to: emlx, trailer: "<plist/>")
  let store = FileStore(cacheRoot: cache.path, secret: testKey)
  let files = try MailMessageFileFactory(fileStore: store).files(emlxPath: emlx.path)
  let keys = [
    try #require(files.bodyText?.downloadKey),
    try #require(files.bodyHtml?.downloadKey),
    try #require(files.rawSource?.downloadKey),
    try #require(files.attachments.first?.downloadKey)
  ]

  let manifest = try store.download(
    keys: keys,
    outputDirectory: output.path,
    materializer: MailFileMaterializer(scratchDirectory: root.appendingPathComponent("scratch"))
  )
  let materialized = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.kind, $0.path) })

  #expect(files.bodyText?.byteSize == Data("Plain body".utf8).count)
  #expect(files.bodyHtml?.byteSize == Data("<p>HTML body</p>".utf8).count)
  #expect(files.rawSource?.byteSize == Data(raw.utf8).count)
  #expect(files.attachments.first?.filename == "note.txt")
  #expect(files.attachments.first?.mimeType == "text/plain")
  #expect(files.attachments.first?.byteSize == Data("attachment body".utf8).count)
  #expect(try String(contentsOfFile: #require(materialized["BODY_TEXT"]), encoding: .utf8) == "Plain body")
  #expect(try String(contentsOfFile: #require(materialized["BODY_HTML"]), encoding: .utf8) == "<p>HTML body</p>")
  #expect(try String(contentsOfFile: #require(materialized["RAW_SOURCE"]), encoding: .utf8) == raw)
  #expect(try String(contentsOfFile: #require(materialized["ATTACHMENT"]), encoding: .utf8) == "attachment body")
}

@Test func mailMaterializerReportsEvictedBodyAsMessageNotFound() throws {
  let root = try makeMailParserTemporaryRoot()
  let missing = root.appendingPathComponent("missing.emlx")
  let payload = FileStoreDownloadKeyPayload(
    domain: .mail,
    sourceId: MailFileStoreIdentifier.encode(missing.path),
    kind: .bodyText,
    filename: "body.txt"
  )

  do {
    _ = try MailFileMaterializer().sourceFile(for: payload)
    Issue.record("Expected missing local body error")
  } catch let error as AppleGatewayError {
    #expect(error.code == .messageNotFound)
    #expect(error.details?["reason"]?.contains("not stored locally") == true)
  }
}

private func writeEMLX(raw: String, to url: URL, trailer: String?) throws {
  let data = Data(raw.utf8)
  var emlx = Data("\(data.count)\n".utf8)
  emlx.append(data)
  if let trailer {
    emlx.append(Data(trailer.utf8))
  }
  try emlx.write(to: url)
}

private func makeMailParserTemporaryRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("apple-gateway-mail-parser-tests")
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
