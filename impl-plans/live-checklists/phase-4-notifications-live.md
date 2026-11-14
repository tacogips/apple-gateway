# Phase 4 Notifications Live Checklist

Use this checklist for TASK-004 after the notifications schema registration,
fake-backed smoke tests, helper app bundle assembly, and usernoted fixture
tests pass. Run only from an interactive macOS session where notification
permission prompts and scratch delivered notifications are acceptable.

Do not run this checklist from non-interactive automation. Do not request
notification permissions or post live notifications unless the operator has
explicitly opted into the live run.

Use `scripts/live-notifications-check.sh` for non-mutating readiness checks
before any manual live execution. Its default dry-run prints permissions
status, validates the exact full and reader notification root schema fields,
and points back to this checklist without posting, listing, dismissing,
requesting notification permission, or reading the system notification
database.

## Environment

- [ ] macOS version and build recorded:
- [ ] `apple-gateway --version` recorded:
- [ ] Terminal or host process recorded:
- [ ] `notifications.helper_app_path` recorded, if configured:
- [ ] Resolved `AppleGatewayNotifier.app` path recorded:
- [ ] Helper bundle identifier recorded:
- [ ] Notification permission state before prompting recorded:
- [ ] Full Disk Access state for the host process recorded:
- [ ] Scratch notification ids created by this run recorded:

Non-mutating readiness checks:

```bash
scripts/live-notifications-check.sh
```

Equivalent underlying dry-run commands, if the helper script is unavailable:

```bash
swift run apple-gateway permissions status --json
swift run apple-gateway schema print --role full
swift run apple-gateway schema print --role reader
```

The helper validates the exact Query root field
`notifications(input: NotificationSearchInput): DeliveredNotificationConnection!`
for both full and reader schemas. It validates the exact full-schema Mutation
root fields `postNotification(input: PostNotificationInput!): PostedNotification!`,
`dismissNotifications(ids: [ID!]!): DismissResult!`, and
`dismissAllGatewayNotifications: DismissResult!`; the reader schema must not
expose those Mutation root fields.

Opt-in read-only delivered-notification listing is source-scoped:

```bash
scripts/live-notifications-check.sh --read-only --source gateway-helper
scripts/live-notifications-check.sh --read-only --source system-db
scripts/live-notifications-check.sh --read-only --source both
```

The `system-db` source must remain gated by
`notificationDbFullDiskAccess: GRANTED`; do not request permission or automate
Full Disk Access from this helper.

## Helper Permission Prompt

- [ ] Start from a clean helper notification authorization state only when
      safe for the dev machine.
- [ ] Run the first helper-backed live post from the interactive host process.
- [ ] Record whether the macOS notification permission prompt appears for
      `AppleGatewayNotifier.app`:
- [ ] If prompted, record whether Allow or Deny was selected:
- [ ] If denied, record the GraphQL error code and helper stderr/stdout
      behavior:
- [ ] If already authorized, record the existing state and continue:

## Scratch Post With Actions And Reply

Post exactly one scratch notification with two actions and text reply enabled.
Use a title/body that clearly marks the notification as scratch data.

- [ ] Scratch title recorded:
- [ ] Scratch body recorded:
- [ ] First action label recorded:
- [ ] Second action label recorded:
- [ ] `waitSeconds` value recorded:
- [ ] Response `id` recorded:
- [ ] Response `delivered` recorded:
- [ ] Response `usedFallback` is `false`:
- [ ] Notification is visible in Notification Center:

Example shape, with local ids/titles adjusted as needed:

```bash
swift run apple-gateway graphql --query 'mutation($input: PostNotificationInput!) {
  postNotification(input: $input) {
    id delivered usedFallback activation { kind actionLabel replyText }
  }
}' --variables '{
  "input": {
    "title": "Apple Gateway Scratch",
    "body": "Phase 4 live notification checklist",
    "sound": true,
    "actions": ["Open", "Archive"],
    "allowReply": true,
    "waitSeconds": 20,
    "allowFallback": false
  }
}'
```

## Activation Observations

- [ ] Click the notification body. Record activation kind and any app focus
      behavior:
- [ ] Repost if needed, then click action one. Record activation kind and
      `actionLabel`:
- [ ] Repost if needed, then click action two. Record activation kind and
      `actionLabel`:
- [ ] Repost if needed, enter reply text, and submit the reply. Record
      activation kind, `actionLabel`, and `replyText`:
- [ ] Record whether activation waits time out cleanly when the notification
      is ignored:

## Helper List And Dismiss

- [ ] List gateway-posted delivered notifications and confirm the scratch ids
      are present:

```bash
swift run apple-gateway graphql --query '{
  notifications(input: { source: GATEWAY_HELPER, first: 20 }) {
    totalCount edges { node { id source appBundleId title body deliveredAt } }
  }
}'
```

- [ ] Dismiss one scratch notification by helper id:

```bash
swift run apple-gateway graphql --query 'mutation($ids: [ID!]!) {
  dismissNotifications(ids: $ids) { dismissedCount }
}' --variables '{"ids":["<helper-notification-id>"]}'
```

- [ ] Confirm the dismissed id is absent from helper list output:
- [ ] Repost scratch notifications if needed, then run helper dismiss-all for
      gateway notifications only:

```bash
swift run apple-gateway graphql --query 'mutation {
  dismissAllGatewayNotifications { dismissedCount }
}'
```

- [ ] Confirm helper list no longer returns scratch gateway notifications:
- [ ] Confirm non-gateway notifications were not removed:

## System-Wide usernoted Listing

Run only read-only list queries. Never modify, delete, or write rows in the
usernoted SQLite store.

- [ ] On macOS 14, record the legacy
      `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db` path
      existence and query result:
- [ ] On macOS 15+, record the
      `~/Library/Group Containers/group.com.apple.usernoted/db2/db` path
      existence and query result:
- [ ] Confirm results use `source: SYSTEM_DB`:
- [ ] Confirm app/title/body fields decode where available:
- [ ] Confirm undecodable rows are skipped with warnings instead of failing
      the whole query:
- [ ] Confirm `dismissNotifications` with a `SYSTEM_DB` id fails with
      `INVALID_ARGUMENT` and does not attempt dismissal:

```bash
swift run apple-gateway graphql --query '{
  notifications(input: { source: SYSTEM_DB, first: 20 }) {
    totalCount edges { node { id source appBundleId title body deliveredAt } }
  }
}'
```

## Full Disk Access Handling

- [ ] Without Full Disk Access, record whether the system-wide list returns
      `FULL_DISK_ACCESS_REQUIRED`:
- [ ] Record the remediation text or settings deep link shown to the user:
- [ ] After granting Full Disk Access manually, rerun the system-wide list and
      record success or the remaining error:
- [ ] If schema drift is encountered, record the error classification and
      macOS build:

## osascript Fallback Boundaries

Use fallback checks only when the helper app is intentionally unavailable or
misconfigured for this test. Fallback must remain best-effort banner posting
and must not claim action or reply support.

- [ ] With `allowFallback: false` and missing helper, post fails with
      `NOTIFIER_HELPER_MISSING`:
- [ ] With `allowFallback: true`, no actions, and no reply, post succeeds with
      `usedFallback: true`:
- [ ] With fallback plus actions, validation rejects the request:
- [ ] With fallback plus `allowReply`, validation rejects the request:
- [ ] With fallback plus activation wait, validation rejects the request:
- [ ] Fallback-created notifications are not claimed as helper-dismissible:

## Reader Behavior

- [ ] Reader serves notification read queries:

```bash
swift run apple-gateway-reader graphql --query '{
  notifications(input: { source: GATEWAY_HELPER, first: 5 }) {
    edges { node { id source title deliveredAt } }
  }
}'
```

- [ ] Reader omits or rejects notification mutations with
      `WRITE_DISABLED_IN_READER` before resolver dispatch:

```bash
swift run apple-gateway-reader graphql --query 'mutation {
  postNotification(input: { title: "Blocked", body: "No" }) { id }
}'
```

## Cleanup And Follow-Up

- [ ] Dismiss all scratch gateway notifications created by this run.
- [ ] Confirm helper list is clean of scratch notification ids.
- [ ] Leave unrelated delivered notifications untouched.
- [ ] Record any scratch notifications requiring manual cleanup:
- [ ] Record any unexpected prompt, FDA, reader, osascript, or usernoted
      behavior in `impl-plans/active/phase-4-notifications.md`.
- [ ] File or link follow-up design/user-qa items for unresolved platform
      behavior:
