import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notificationHelperResolverUsesConfiguredPathBeforeHomebrewLayout() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let configured = try root.makeHelperApp(name: "Configured.app", mode: "post")
  let prefix = root.root.appendingPathComponent("prefix")
  let homebrew = try root.makeHelperApp(
    path: prefix.appendingPathComponent("libexec/AppleGatewayNotifier.app"),
    mode: "post"
  )
  let cli = prefix.appendingPathComponent("bin/apple-gateway")
  try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data().write(to: cli)

  var config = AppleGatewayConfig.defaultValue
  config.notifications.helperAppPath = configured.app.path
  let resolver = NotificationHelperResolver(
    cliExecutablePath: cli.path,
    homeDirectory: root.home.path,
    applicationsDirectory: root.applications.path
  )

  let bundle = try resolver.resolve(config: config)

  #expect(bundle.appURL.path == configured.app.path)
  #expect(bundle.appURL.path != homebrew.app.path)
}

@Test func notificationAdapterPostsThroughStubHelperAndPreservesActivation() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let helper = try root.makeHelperApp(name: "AppleGatewayNotifier.app", mode: "post")
  let adapter = LiveNotificationsAdapter(
    config: root.config(helperAppPath: helper.app.path),
    resolver: root.resolver(),
    helperExecutor: SubprocessNotificationHelperExecutor(timeoutSeconds: 2, environment: helper.environment),
    fallbackPoster: CountingNotificationFallback()
  )

  let result = try adapter.postNotification(PostNotificationInput(
    title: "Build",
    body: "Done",
    actions: ["Open"],
    allowReply: true,
    waitSeconds: 5
  ))
  let captured = try helper.capturedRequest()

  #expect(captured.operation == .post)
  #expect(captured.title == "Build")
  #expect(captured.body == "Done")
  #expect(captured.actions == ["Open"])
  #expect(captured.allowReply == true)
  #expect(captured.waitSeconds == 5)
  #expect(result.id == "stub-post")
  #expect(result.delivered == true)
  #expect(result.usedFallback == false)
  #expect(result.activation?.kind == .action)
  #expect(result.activation?.actionLabel == "Open")
}

@Test func notificationAdapterListsAndDismissesThroughStubHelper() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let helper = try root.makeHelperApp(name: "AppleGatewayNotifier.app", mode: "dispatch")
  let adapter = LiveNotificationsAdapter(
    config: root.config(helperAppPath: helper.app.path),
    resolver: root.resolver(),
    helperExecutor: SubprocessNotificationHelperExecutor(timeoutSeconds: 2, environment: helper.environment),
    fallbackPoster: CountingNotificationFallback()
  )

  let notifications = try adapter.listGatewayNotifications()
  let dismissed = try adapter.dismissNotifications(ids: ["one", "two"])
  let dismissedAll = try adapter.dismissAllGatewayNotifications()

  #expect(notifications == [
    DeliveredNotification(
      id: "one",
      source: .gatewayHelper,
      appBundleId: "me.tacogips.apple-gateway.notifier",
      title: "Stub",
      deliveredAt: "2026-07-03T00:00:00Z"
    )
  ])
  #expect(dismissed.dismissedCount == 2)
  #expect(dismissedAll.dismissedCount == 7)
}

@Test func notificationAdapterMapsMissingHelperAndPermittedFallback() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let fallback = CountingNotificationFallback()
  let adapter = LiveNotificationsAdapter(
    config: .defaultValue,
    resolver: root.resolver(),
    helperExecutor: FailingNotificationHelperExecutor(),
    fallbackPoster: fallback
  )

  do {
    _ = try adapter.postNotification(PostNotificationInput(title: "No helper"))
    Issue.record("Expected missing helper")
  } catch let error as AppleGatewayError {
    #expect(error.code == .notifierHelperMissing)
  }

  let result = try adapter.postNotification(PostNotificationInput(title: "Fallback", allowFallback: true))

  #expect(result.delivered == true)
  #expect(result.usedFallback == true)
  #expect(result.activation == nil)
  #expect(fallback.posts.map(\.title) == ["Fallback"])
}

@Test func notificationAdapterRejectsFallbackForActionsRepliesAndWaits() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let fallback = CountingNotificationFallback()
  let adapter = LiveNotificationsAdapter(
    config: .defaultValue,
    resolver: root.resolver(),
    helperExecutor: FailingNotificationHelperExecutor(),
    fallbackPoster: fallback
  )

  let inputs = [
    PostNotificationInput(title: "", allowFallback: true),
    PostNotificationInput(title: "Action", actions: ["Open"], allowFallback: true),
    PostNotificationInput(title: "Reply", allowReply: true, allowFallback: true),
    PostNotificationInput(title: "Wait", waitSeconds: 1, allowFallback: true)
  ]

  for input in inputs {
    do {
      _ = try adapter.postNotification(input)
      Issue.record("Expected fallback validation failure")
    } catch let error as AppleGatewayError {
      #expect(error.code == .invalidArgument)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
  #expect(fallback.posts.isEmpty)
}

@Test func subprocessNotificationHelperTimesOut() throws {
  let root = try NotificationAdapterTemporaryDirectory()
  let helper = try root.makeHelperApp(name: "AppleGatewayNotifier.app", mode: "timeout")
  let executor = SubprocessNotificationHelperExecutor(timeoutSeconds: 0.05, environment: helper.environment)

  do {
    _ = try executor.execute(
      NotificationHelperRequest(operation: .settings),
      bundle: NotificationHelperBundle(
        appURL: helper.app,
        executableURL: helper.executable
      )
    )
    Issue.record("Expected helper timeout")
  } catch let error as AppleGatewayError {
    #expect(error.code == .appleEventTimeout)
  }
}

private struct NotificationAdapterTemporaryDirectory {
  let root: URL
  let home: URL
  let applications: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-notification-adapter-tests")
      .appendingPathComponent(UUID().uuidString)
    home = root.appendingPathComponent("home")
    applications = root.appendingPathComponent("Applications")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
  }

  func config(helperAppPath: String) -> AppleGatewayConfig {
    var config = AppleGatewayConfig.defaultValue
    config.notifications.helperAppPath = helperAppPath
    return config
  }

  func resolver() -> NotificationHelperResolver {
    NotificationHelperResolver(
      cliExecutablePath: nil,
      homeDirectory: home.path,
      applicationsDirectory: applications.path
    )
  }

  func makeHelperApp(name: String, mode: String) throws -> StubNotificationHelper {
    try makeHelperApp(path: root.appendingPathComponent(name), mode: mode)
  }

  func makeHelperApp(path app: URL, mode: String) throws -> StubNotificationHelper {
    let executable = app
      .appendingPathComponent("Contents")
      .appendingPathComponent("MacOS")
      .appendingPathComponent("AppleGatewayNotifier")
    let capture = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.stubSource.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return StubNotificationHelper(
      app: app,
      executable: executable,
      environment: [
        "APPLE_GATEWAY_STUB_MODE": mode,
        "APPLE_GATEWAY_STUB_CAPTURE": capture.path,
        "PATH": "/usr/bin:/bin"
      ],
      capture: capture
    )
  }

  private static let stubSource = """
  #!/usr/bin/env bash
  set -euo pipefail
  mode="${APPLE_GATEWAY_STUB_MODE:?}"
  capture="${APPLE_GATEWAY_STUB_CAPTURE:?}"
  request="${1:-}"
  printf '%s' "$request" > "$capture"
  if [[ "$mode" == "timeout" ]]; then
    sleep 2
  fi
  if [[ "$mode" == "post" ]]; then
    printf '%s\\n' '{"ok":true,"protocolVersion":1,"result":{"posted":{"activation":{"actionLabel":"Open","kind":"action"},"delivered":true,"id":"stub-post"}}}'
    exit 0
  fi
  case "$request" in
    *'"operation":"list"'*)
      printf '%s\\n' '{"ok":true,"protocolVersion":1,"result":{"notifications":[{"appBundleId":"me.tacogips.apple-gateway.notifier","deliveredAt":"2026-07-03T00:00:00Z","id":"one","title":"Stub"}]}}'
      ;;
    *'"operation":"dismissAll"'*)
      printf '%s\\n' '{"ok":true,"protocolVersion":1,"result":{"dismissedCount":7}}'
      ;;
    *'"operation":"dismiss"'*)
      printf '%s\\n' '{"ok":true,"protocolVersion":1,"result":{"dismissedCount":2}}'
      ;;
    *)
      printf '%s\\n' '{"error":{"code":"INVALID_ARGUMENT","message":"unsupported stub operation"},"ok":false,"protocolVersion":1}'
      exit 1
      ;;
  esac
  """
}

private struct StubNotificationHelper {
  var app: URL
  var executable: URL
  var environment: [String: String]
  var capture: URL

  func capturedRequest() throws -> NotificationHelperRequest {
    let data = try Data(contentsOf: capture)
    return try NotificationHelperProtocol.decodeRequest(from: data)
  }
}

private final class CountingNotificationFallback: NotificationFallbackPosting, @unchecked Sendable {
  private(set) var posts: [PostNotificationInput] = []

  func post(_ input: PostNotificationInput) throws {
    posts.append(input)
  }
}

private struct FailingNotificationHelperExecutor: NotificationHelperExecuting {
  func execute(_ request: NotificationHelperRequest, bundle: NotificationHelperBundle) throws -> NotificationHelperResponse {
    throw AppleGatewayError(code: .notifierHelperMissing, message: "missing test helper")
  }
}
