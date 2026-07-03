# Notifications Design

## Status

Draft

## Capability Map

| Operation | Mechanism | Guarantee |
| --- | --- | --- |
| Post notification (title/body/sound/actions/reply) | `AppleGatewayNotifier.app` helper (UNUserNotificationCenter) | Full, supported API |
| Post notification (fallback, no helper) | `osascript display notification` | Best-effort, banner only |
| Wait for user action/reply | Helper app category actions | Supported |
| Dismiss gateway-posted notifications | Helper `removeDeliveredNotifications` | Supported (own only) |
| List gateway-posted delivered notifications | Helper `getDeliveredNotifications` | Supported (own only) |
| List all apps' delivered notifications | usernoted db2 SQLite (read-only copy) | Unsupported store; FDA-gated; may break on OS updates |
| Dismiss other apps' notifications / clear all | none in v1 | Not offered (Accessibility UI scripting rejected as too fragile; open question) |

`UNUserNotificationCenter` cannot run in a bare CLI (crashes on
`bundleProxyForCurrentProcess`); a real `.app` bundle is mandatory
(research reference, section 5). Hence the helper.

## AppleGatewayNotifier Helper App

A minimal SwiftPM-built app bundle (assembled by packaging scripts into
`AppleGatewayNotifier.app`; no Xcode project):

- Bundle id `me.tacogips.apple-gateway.notifier`; LSUIElement (no Dock
  icon); Developer ID signed and notarized in release artifacts.
- Speaks a one-shot JSON protocol: the CLI launches the inner executable
  (`Contents/MacOS/AppleGatewayNotifier`) directly with a JSON request on
  argv, and the helper prints a JSON response on stdout and exits. No
  persistent daemon, no sockets.
- Requests: `post` (content, sound, action labels, reply flag, optional
  `waitSeconds` to block for activation), `list`, `dismiss` (ids),
  `dismissAll`, `settings` (authorization status for the doctor).
- First `post` triggers the helper's own Notification permission prompt.
- Resolution order for the bundle path: config
  `notifications.helper_app_path`, then `../libexec/AppleGatewayNotifier.app`
  relative to the CLI binary (Homebrew layout), then
  `/Applications` and `~/Applications`. Missing helper on a
  notification mutation yields `NOTIFIER_HELPER_MISSING`; `postNotification`
  falls back to osascript only when `input.allowFallback == true`, so
  callers relying on actions/reply are never silently downgraded.

### Phase 4 TASK-001 Boundary

TASK-001 creates the helper executable target, the shared JSON protocol
types, deterministic protocol validation tests, and the local bundle
assembly script. It does not connect GraphQL or CLI notification commands to
the helper, implement helper path resolution, add osascript fallback, inspect
the `usernoted` database, or register notification schema fields. Those
surfaces remain TASK-002 through TASK-004 work.

The SwiftPM package gains an `AppleGatewayNotifier` executable target. The
target may depend on shared protocol models from `AppleGatewayCore`, and its
runtime entrypoint is responsible only for decoding one JSON request,
validating the protocol version and operation-specific fields, dispatching to
the available helper operation, encoding one JSON response, and exiting.

Where `UserNotifications` is available, `post`, `list`, `dismiss`,
`dismissAll`, and `settings` use `UNUserNotificationCenter` from inside the
assembled `.app` bundle. The implementation must keep the compile-time and
runtime boundary explicit so deterministic unit tests can validate protocol
behavior without requiring a notification permission prompt or live
Notification Center state.

### One-Shot JSON Protocol

Every request includes:

- `protocolVersion`: integer; TASK-001 defines the initial supported version.
- `operation`: one of `post`, `list`, `dismiss`, `dismissAll`, `settings`.
- Operation payload fields, encoded in a single shared Codable model or a
  shared enum shape that both the CLI-side adapter and helper target import.

Every response includes:

- `protocolVersion`: the same supported integer when decoding succeeded.
- `ok`: boolean success flag.
- Success payload for the requested operation, or an error object with a
  stable code and message.

Validation rules:

- Malformed JSON, missing `protocolVersion`, non-integer protocol versions,
  and unsupported versions fail before operation dispatch.
- Mismatched protocol versions return a clear protocol-version error rather
  than falling through to `INVALID_ARGUMENT`.
- Unknown operations fail with `INVALID_ARGUMENT`.
- `post` requires a non-empty title and validates bounded optional strings
  for subtitle, body, action labels, reply settings, sound, and wait timeout.
- `dismiss` requires at least one non-empty helper notification id.
- `list`, `dismissAll`, and `settings` reject operation-specific payload
  fields that are not meaningful for the operation when the shared decoder can
  detect them.
- Validation and round-trip tests must run without launching the helper app.

### Bundle Assembly Script

`scripts/build-notifier-app.sh` assembles a local
`AppleGatewayNotifier.app` without changing Homebrew formula or Cask
packaging. The script contract is:

- Build or accept a prebuilt `AppleGatewayNotifier` executable.
- Create `Contents/MacOS/AppleGatewayNotifier` with executable permissions.
- Create `Contents/Info.plist` with bundle id
  `me.tacogips.apple-gateway.notifier`, executable name
  `AppleGatewayNotifier`, bundle package type `APPL`, and `LSUIElement`.
- Support dry-run-friendly behavior that prints planned filesystem and
  signing actions without requiring Apple signing credentials.
- Provide signing hooks for ad-hoc and Developer ID signing, but do not
  notarize, upload releases, or alter Homebrew/Cask scripts in TASK-001.
- Fail clearly when the executable cannot be found or the output bundle
  cannot be assembled.

## System-Wide Delivered Notification Listing

Read-only parsing of the Notification Center store:

- Path on macOS 15+: `~/Library/Group Containers/group.com.apple.usernoted/db2/db`;
  legacy pre-Sequoia path `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`
  probed second for macOS 14 hosts.
- Copy-then-open (same snapshot pattern as the Mail adapter); never write,
  never delete rows (racing `usernoted` is unsafe).
- `record` rows: `app_id` join to `app`, `delivered_date` as
  CFAbsoluteTime, `data` BLOB as NSKeyedArchiver binary plist decoded with
  `PropertyListSerialization` + keyed-unarchive traversal to extract title,
  subtitle, body.
- FDA required on 15+; failures yield `FULL_DISK_ACCESS_REQUIRED`. Schema
  drift yields `NOTIFICATION_DB_UNAVAILABLE` with the probed path in
  details; the spec explicitly labels this surface "unsupported store,
  best effort".

## GraphQL Types

```graphql
type DeliveredNotification {
  id: ID!
  source: NotificationSource!    # GATEWAY_HELPER | SYSTEM_DB
  appBundleId: String!
  title: String
  subtitle: String
  body: String
  deliveredAt: DateTime!
}
enum NotificationSource { GATEWAY_HELPER, SYSTEM_DB }

input NotificationSearchInput {
  source: NotificationSource = SYSTEM_DB
  appBundleId: String
  deliveredAfter: DateTime
  deliveredBefore: DateTime
  first: Int
  after: String
}

type DeliveredNotificationConnection {
  edges: [DeliveredNotificationEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}
type DeliveredNotificationEdge { cursor: String!, node: DeliveredNotification! }

input PostNotificationInput {
  title: String!
  subtitle: String
  body: String
  sound: Boolean = true
  actions: [String!]             # action button labels
  allowReply: Boolean = false
  waitSeconds: Int               # block for activation up to N seconds
  allowFallback: Boolean = false # permit osascript fallback (no actions/reply)
}

type PostedNotification {
  id: ID!
  delivered: Boolean!
  usedFallback: Boolean!
  activation: NotificationActivation   # null unless waitSeconds elapsed with action
}

type NotificationActivation {
  kind: NotificationActivationKind!    # CLICKED | ACTION | REPLIED | TIMEOUT | DISMISSED
  actionLabel: String
  replyText: String
}
enum NotificationActivationKind { CLICKED, ACTION, REPLIED, TIMEOUT, DISMISSED }

type DismissResult { dismissedCount: Int! }
```

`dismissNotifications(ids:)` and `dismissAllGatewayNotifications` operate
only on helper-posted notifications; ids from `SYSTEM_DB` rows fail with
`INVALID_ARGUMENT` explaining that macOS offers no supported system-wide
dismissal.

## Packaging Notes

- Homebrew formula and cask install the helper under
  `libexec/AppleGatewayNotifier.app` (terminal-notifier precedent).
- The helper is versioned with the CLI and rejects requests from
  mismatched protocol versions (`protocolVersion` field in every request).
- Cask release signs and notarizes the helper; the formula (source build)
  produces an ad-hoc signed helper, documented as losing its notification
  grant on rebuild.

## Testing

- `NotificationsProviding` fake for resolver tests.
- Helper protocol: encode/decode round-trip tests shared between CLI and
  helper target; a stub helper executable drives CLI-side integration in
  smoke tests.
- usernoted decoding tested against fixture databases with synthetic
  keyed-archiver blobs (both pre- and post-Sequoia schema variants).
- Manual live checklist: post with actions and reply, verify prompt,
  dismiss, list.

TASK-001 verification is limited to deterministic build, protocol, and bundle
assembly checks:

- `swift build --target AppleGatewayNotifier`
- Narrow protocol tests under `AppleGatewayCoreTests` for JSON round trips,
  malformed data, unknown operations, invalid operation payloads, and
  mismatched `protocolVersion`.
- `bash scripts/build-notifier-app.sh --dry-run`
- `swiftlint` when available.
