import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notificationsSchemaPrintsReaderQueriesAndFullMutations() {
  let readerSchema = GraphQLRuntime.schema(role: .reader)
  let fullSchema = GraphQLRuntime.schema(role: .full)

  #expect(readerSchema.contains("  notifications(input: NotificationSearchInput): DeliveredNotificationConnection!"))
  #expect(readerSchema.contains("type DeliveredNotification {"))
  #expect(readerSchema.contains("enum NotificationSource {"))
  #expect(!readerSchema.contains("postNotification"))

  #expect(fullSchema.contains("  postNotification(input: PostNotificationInput!): PostedNotification!"))
  #expect(fullSchema.contains("  dismissNotifications(ids: [ID!]!): DismissResult!"))
  #expect(fullSchema.contains("  dismissAllGatewayNotifications: DismissResult!"))
}

@Test func notificationsQueryUsesInjectedService() throws {
  let fake = GraphQLNotificationsFake()
  let envelope = try notificationsExecuteGraphQL(
    """
    {
      notifications(input: { source: SYSTEM_DB, appBundleId: "com.example.chat", first: 1 }) {
        totalCount
        pageInfo { hasNextPage endCursor }
        edges {
          cursor
          node { id source appBundleId title subtitle body deliveredAt }
        }
      }
    }
    """,
    notificationsService: fake
  )

  #expect(envelope.errors.isEmpty)
  let notifications = try #require(envelope.data?["notifications"] as? [String: Any])
  let edges = try #require(notifications["edges"] as? [[String: Any]])
  let pageInfo = try #require(notifications["pageInfo"] as? [String: Any])
  let node = try #require(edges.first?["node"] as? [String: Any])

  #expect(fake.searchInputs.first?.source == .systemDb)
  #expect(fake.searchInputs.first?.appBundleId == "com.example.chat")
  #expect(fake.searchInputs.first?.first == 1)
  #expect(notifications["totalCount"] as? Int == 1)
  #expect(pageInfo["hasNextPage"] as? Bool == false)
  #expect(edges.first?["cursor"] as? String == "cursor-1")
  #expect(node["id"] as? String == "system-db-1")
  #expect(node["source"] as? String == "SYSTEM_DB")
  #expect(node["title"] as? String == "Chat")
}

@Test func notificationsMutationsUseInjectedServiceAndReaderRejectsWrites() throws {
  let fake = GraphQLNotificationsFake()
  let postEnvelope = try notificationsExecuteGraphQL(
    """
    mutation {
      postNotification(input: {
        title: "Build"
        body: "Done"
        actions: ["Open"]
        allowReply: true
        waitSeconds: 3
        allowFallback: false
      }) {
        id
        delivered
        usedFallback
        activation { kind actionLabel replyText }
      }
    }
    """,
    notificationsService: fake
  )
  let posted = try #require(postEnvelope.data?["postNotification"] as? [String: Any])
  let activation = try #require(posted["activation"] as? [String: Any])

  #expect(postEnvelope.errors.isEmpty)
  #expect(fake.postInputs.first?.title == "Build")
  #expect(fake.postInputs.first?.actions == ["Open"])
  #expect(posted["id"] as? String == "posted-1")
  #expect(posted["usedFallback"] as? Bool == false)
  #expect(activation["kind"] as? String == "ACTION")
  #expect(activation["actionLabel"] as? String == "Open")

  let dismissEnvelope = try notificationsExecuteGraphQL(
    #"mutation { dismissNotifications(ids: ["helper-1", "helper-2"]) { dismissedCount } }"#,
    notificationsService: fake
  )
  let dismissed = try #require(dismissEnvelope.data?["dismissNotifications"] as? [String: Any])
  #expect(dismissed["dismissedCount"] as? Int == 2)
  #expect(fake.dismissedIds == ["helper-1", "helper-2"])

  let dismissAllEnvelope = try notificationsExecuteGraphQL(
    "mutation { dismissAllGatewayNotifications { dismissedCount } }",
    notificationsService: fake
  )
  let dismissedAll = try #require(dismissAllEnvelope.data?["dismissAllGatewayNotifications"] as? [String: Any])
  #expect(dismissedAll["dismissedCount"] as? Int == 9)
  #expect(fake.dismissAllCalls == 1)

  let readerEnvelope = try notificationsExecuteGraphQL(
    #"mutation { postNotification(input: { title: "Blocked" }) { id } }"#,
    role: .reader,
    notificationsService: fake
  )
  #expect(readerEnvelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(fake.postInputs.count == 1)
}

@Test func notificationsDismissRejectsSystemDatabaseIdsBeforeServiceCall() throws {
  let fake = GraphQLNotificationsFake()
  let envelope = try notificationsExecuteGraphQL(
    #"mutation { dismissNotifications(ids: ["system-db-1"]) { dismissedCount } }"#,
    notificationsService: fake
  )

  #expect(envelope.errors.first?.code == "INVALID_ARGUMENT")
  #expect(envelope.errors.first?.message.contains("SYSTEM_DB ids cannot be dismissed") == true)
  #expect(fake.dismissedIds.isEmpty)
}

private func notificationsExecuteGraphQL(
  _ query: String,
  role: AppleGatewayRole = .full,
  notificationsService: any NotificationsProviding
) throws -> NotificationsDecodedEnvelope {
  let data = GraphQLRuntime.execute(
    query: query,
    variables: [:],
    role: role,
    permissionsProvider: NotificationsGraphQLPermissionsProvider(),
    notificationsService: notificationsService
  )
  let object = try JSONSerialization.jsonObject(with: data)
  let dictionary = try #require(object as? [String: Any])
  let dataObject = dictionary["data"] as? [String: Any]
  let errorObjects = dictionary["errors"] as? [[String: Any]] ?? []
  return NotificationsDecodedEnvelope(
    data: dataObject,
    errors: errorObjects.map {
      let extensions = $0["extensions"] as? [String: Any]
      return NotificationsDecodedError(
        message: $0["message"] as? String ?? "",
        code: extensions?["code"] as? String ?? "",
        exitCode: extensions?["exitCode"] as? Int ?? 0
      )
    }
  )
}

private struct NotificationsDecodedEnvelope {
  var data: [String: Any]?
  var errors: [NotificationsDecodedError]
}

private struct NotificationsDecodedError {
  var message: String
  var code: String
  var exitCode: Int
}

private struct NotificationsGraphQLPermissionsProvider: PermissionsStatusProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .unknown),
      reminders: PermissionFieldStatus(state: .unknown),
      notesAutomation: PermissionFieldStatus(state: .unknown),
      mailFullDiskAccess: PermissionFieldStatus(state: .unknown),
      notificationsHelper: PermissionFieldStatus(state: .unknown),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .unknown),
      clockAutomation: PermissionFieldStatus(state: .unknown)
    )
  }
}

private final class GraphQLNotificationsFake: NotificationsProviding, @unchecked Sendable {
  var searchInputs: [NotificationSearchInput] = []
  var postInputs: [PostNotificationInput] = []
  var dismissedIds: [String] = []
  var dismissAllCalls = 0

  func notifications(input: NotificationSearchInput) throws -> DeliveredNotificationConnection {
    searchInputs.append(input)
    return DeliveredNotificationConnection(
      edges: [
        DeliveredNotificationEdge(
          cursor: "cursor-1",
          node: DeliveredNotification(
            id: "system-db-1",
            source: .systemDb,
            appBundleId: "com.example.chat",
            title: "Chat",
            subtitle: "Team",
            body: "Planning",
            deliveredAt: "2026-07-03T12:00:00Z"
          )
        )
      ],
      pageInfo: PageInfo(hasNextPage: false, endCursor: "cursor-1"),
      totalCount: 1
    )
  }

  func postNotification(_ input: PostNotificationInput) throws -> PostedNotification {
    postInputs.append(input)
    return PostedNotification(
      id: "posted-1",
      delivered: true,
      usedFallback: false,
      activation: NotificationActivation(kind: .action, actionLabel: "Open")
    )
  }

  func listGatewayNotifications() throws -> [DeliveredNotification] {
    []
  }

  func dismissNotifications(ids: [String]) throws -> DismissResult {
    dismissedIds = ids
    return DismissResult(dismissedCount: ids.count)
  }

  func dismissAllGatewayNotifications() throws -> DismissResult {
    dismissAllCalls += 1
    return DismissResult(dismissedCount: 9)
  }
}
