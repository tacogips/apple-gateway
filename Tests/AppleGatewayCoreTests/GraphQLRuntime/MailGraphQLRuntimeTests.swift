import Foundation
import Testing
@testable import AppleGatewayCore

@Test func mailSchemaPrintsQueryOnlyFields() {
  let readerSchema = GraphQLRuntime.schema(role: .reader)
  let fullSchema = GraphQLRuntime.schema(role: .full)

  #expect(GraphQLSchemaModule.mail.mutationFields.isEmpty)
  #expect(readerSchema.contains("  mailAccounts: [MailAccount!]!"))
  #expect(readerSchema.contains("  mailboxes(accountId: ID): [Mailbox!]!"))
  #expect(readerSchema.contains("  mailMessages(input: MailSearchInput!): MailMessageConnection!"))
  #expect(readerSchema.contains("  mailMessage(messageId: ID!): MailMessage"))
  #expect(readerSchema.contains("enum MailFileKind"))
  #expect(!readerSchema.contains("type Mutation"))

  #expect(fullSchema.contains("type Mutation {"))
  #expect(fullSchema.contains("  mailAccounts: [MailAccount!]!"))
  #expect(!fullSchema.contains("createMail"))
  #expect(!fullSchema.contains("updateMail"))
  #expect(!fullSchema.contains("deleteMail"))
}

@Test func mailReadSchemaUsesInjectedFakeService() throws {
  let fake = GraphQLMailFake()
  let envelope = try mailExecuteGraphQL(
    """
    {
      mailAccounts { id name kind }
      mailboxes(accountId: "mail-account-1") { id accountId path totalCount unreadCount }
      mailMessages(input: { query: "invoice", unreadOnly: true, first: 5 }) {
        totalCount
        edges {
          cursor
          node {
            id
            subject
            from { email }
            to { email }
            files {
              bodyText { kind filename byteSize downloadKey }
              attachments { kind filename mimeType byteSize }
            }
          }
        }
      }
      mailMessage(messageId: "message-1") {
        id
        messageId
        cc { email }
        files { rawSource { kind filename } }
      }
    }
    """,
    mailReadService: MailReadService(provider: fake)
  )

  #expect(envelope.errors.isEmpty)
  let accounts = try #require(envelope.data?["mailAccounts"] as? [[String: Any]])
  let mailboxes = try #require(envelope.data?["mailboxes"] as? [[String: Any]])
  let messages = try #require(envelope.data?["mailMessages"] as? [String: Any])
  let edges = try #require(messages["edges"] as? [[String: Any]])
  let node = try #require(edges.first?["node"] as? [String: Any])
  let files = try #require(node["files"] as? [String: Any])
  let bodyText = try #require(files["bodyText"] as? [String: Any])
  let single = try #require(envelope.data?["mailMessage"] as? [String: Any])

  #expect(accounts.first?["kind"] as? String == "imap")
  #expect(mailboxes.first?["path"] as? String == "INBOX")
  #expect(messages["totalCount"] as? Int == 1)
  #expect(node["id"] as? String == "message-1")
  #expect(bodyText["kind"] as? String == "BODY_TEXT")
  #expect(bodyText["downloadKey"] as? String == "mail-body-key")
  #expect(single["messageId"] as? String == "rfc-message-1")
  #expect(fake.lastSearch?.query == "invoice")
  #expect(fake.lastSearch?.unreadOnly == true)
}

@Test func mailGraphQLResolversPreserveFixtureDatabaseBehavior() throws {
  let fixture = try MailEnvelopeFixture()
  let firstPageEnvelope = try mailExecuteGraphQL(
    """
    {
      mailAccounts { id name kind }
      mailboxes(accountId: "\(fixture.imapAccountId)") { id path totalCount }
      mailMessages(input: { accountId: "\(fixture.imapAccountId)", first: 1 }) {
        totalCount
        pageInfo { hasNextPage endCursor }
        edges { node { id subject snippet dateReceived } }
      }
      mailMessage(messageId: "message-103") { id subject isFlagged to { email } }
    }
    """,
    mailReadService: MailReadService(provider: fixture.service)
  )

  #expect(firstPageEnvelope.errors.isEmpty)
  let accounts = try #require(firstPageEnvelope.data?["mailAccounts"] as? [[String: Any]])
  let mailboxes = try #require(firstPageEnvelope.data?["mailboxes"] as? [[String: Any]])
  let messages = try #require(firstPageEnvelope.data?["mailMessages"] as? [String: Any])
  let pageInfo = try #require(messages["pageInfo"] as? [String: Any])
  let edges = try #require(messages["edges"] as? [[String: Any]])
  let single = try #require(firstPageEnvelope.data?["mailMessage"] as? [String: Any])

  #expect(accounts.contains { $0["name"] as? String == "Example Mail" })
  #expect(mailboxes.map { $0["id"] as? String }.contains(fixture.inboxMailboxId))
  #expect(messages["totalCount"] as? Int == 4)
  #expect(pageInfo["hasNextPage"] as? Bool == true)
  #expect(edges.first?["node"].flatMap { ($0 as? [String: Any])?["id"] as? String } == "message-103")
  #expect(single["subject"] as? String == "Flag update")
  #expect(single["isFlagged"] as? Bool == true)

  let cursor = try #require(pageInfo["endCursor"] as? String)
  let secondPageEnvelope = try mailExecuteGraphQL(
    """
    {
      mailMessages(input: { accountId: "\(fixture.imapAccountId)", first: 2, after: "\(cursor)" }) {
        edges { node { id } }
      }
    }
    """,
    mailReadService: MailReadService(provider: fixture.service)
  )
  let secondMessages = try #require(secondPageEnvelope.data?["mailMessages"] as? [String: Any])
  let secondEdges = try #require(secondMessages["edges"] as? [[String: Any]])

  #expect(secondPageEnvelope.errors.isEmpty)
  #expect(secondEdges.compactMap { ($0["node"] as? [String: Any])?["id"] as? String } == ["message-101", "message-106"])
}

@Test func readerModeStillRejectsMailMutationAtRuntimeBoundary() throws {
  let envelope = try mailExecuteGraphQL(
    #"mutation { mailMessage(messageId: "message-1") { id } }"#,
    role: .reader,
    mailReadService: MailReadService(provider: GraphQLMailFake())
  )

  #expect(envelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
}

private func mailExecuteGraphQL(
  _ query: String,
  role: AppleGatewayRole = .full,
  mailReadService: MailReadService
) throws -> MailDecodedEnvelope {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: [:],
    role: role,
    permissionsProvider: MailGraphQLPermissionsProvider(),
    mailReadService: mailReadService
  )
  let object = try JSONSerialization.jsonObject(with: data)
  let dictionary = try #require(object as? [String: Any])
  let dataObject = dictionary["data"] as? [String: Any]
  let errorObjects = dictionary["errors"] as? [[String: Any]] ?? []
  return MailDecodedEnvelope(
    data: dataObject,
    errors: errorObjects.map {
      let extensions = $0["extensions"] as? [String: Any]
      return MailDecodedError(
        code: extensions?["code"] as? String ?? "",
        exitCode: extensions?["exitCode"] as? Int ?? 0
      )
    }
  )
}

private struct MailDecodedEnvelope {
  var data: [String: Any]?
  var errors: [MailDecodedError]
}

private struct MailDecodedError {
  var code: String
  var exitCode: Int
}

private struct MailGraphQLPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .unknown),
      reminders: PermissionFieldStatus(state: .unknown),
      notesAutomation: PermissionFieldStatus(state: .unknown),
      mailFullDiskAccess: PermissionFieldStatus(state: .granted),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .unknown)
    )
  }
}

private final class GraphQLMailFake: MailProviding, @unchecked Sendable {
  var lastSearch: MailSearchInput?

  func accounts() throws -> [MailAccount] {
    [MailAccount(id: "mail-account-1", name: "Work Mail", kind: .imap)]
  }

  func mailboxes(accountId: String?) throws -> [Mailbox] {
    guard accountId == nil || accountId == "mail-account-1" else {
      throw AppleGatewayError(code: .invalidArgument, message: "Unknown Mail account id")
    }
    return [
      Mailbox(
        id: "mailbox-1",
        accountId: "mail-account-1",
        name: "INBOX",
        path: "INBOX",
        totalCount: 1,
        unreadCount: 1
      )
    ]
  }

  func messages(input: MailSearchInput) throws -> MailMessageConnection {
    lastSearch = input
    return MailMessageConnection(
      edges: [MailMessageEdge(cursor: "cursor-1", node: message)],
      pageInfo: PageInfo(hasNextPage: false, endCursor: "cursor-1"),
      totalCount: 1
    )
  }

  func message(messageId: String) throws -> MailMessage? {
    messageId == "message-1" ? message : nil
  }

  private var message: MailMessage {
    MailMessage(
      id: "message-1",
      mailboxId: "mailbox-1",
      accountId: "mail-account-1",
      messageId: "rfc-message-1",
      subject: "Invoice",
      snippet: "Invoice snippet",
      from: MailAddress(raw: "Alice <alice@example.com>", name: "Alice", email: "alice@example.com"),
      to: [MailAddress(raw: "Bob <bob@example.com>", name: "Bob", email: "bob@example.com")],
      cc: [MailAddress(raw: "Carol <carol@example.com>", name: "Carol", email: "carol@example.com")],
      dateSent: Date(timeIntervalSince1970: 1_783_000_000),
      dateReceived: Date(timeIntervalSince1970: 1_783_000_060),
      isRead: false,
      isFlagged: true,
      hasAttachments: true,
      files: MailMessageFileSet(
        bodyText: MailMessageFile(
          downloadKey: "mail-body-key",
          kind: .bodyText,
          filename: "body.txt",
          byteSize: 12
        ),
        rawSource: MailMessageFile(
          downloadKey: "mail-raw-key",
          kind: .rawSource,
          filename: "raw.eml",
          byteSize: 128
        ),
        attachments: [
          MailMessageFile(
            downloadKey: "mail-attachment-key",
            kind: .attachment,
            filename: "invoice.pdf",
            mimeType: "application/pdf",
            byteSize: 256
          )
        ]
      )
    )
  }
}
