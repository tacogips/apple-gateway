# Phase 4: Notifications

**Status**: TASK-001 through TASK-005 implementation complete; live
notification verification remains manual
**Design Reference**: `design-docs/specs/design-notifications.md`
**Issue References**: Phase 4 TASK-001 used "Notification helper app target,
shared JSON protocol, and bundle assembly." TASK-005 uses "Implement Notes
attachments (list/export/isShared), GATEWAY_HELPER notification date filters,
and clock-alarms CLI help in apple-gateway." No GitHub repository, issue
number, or URL was provided for either reference.

## Purpose

Notification posting with actions and reply via the bundled helper app,
gateway-notification dismissal/listing, system-wide delivered-notification
listing from the usernoted store, and the osascript fallback.

## Deliverables

- [x] `AppleGatewayNotifier` executable target + packaging script
      assembling `AppleGatewayNotifier.app` (Info.plist, LSUIElement,
      signing hooks)
- [x] One-shot JSON protocol (post/list/dismiss/dismissAll/settings) with
      `protocolVersion`, shared Codable definitions between CLI and helper
- [x] `Domains/NotificationsAdapter/` (helper resolution and driving,
      usernoted snapshot reader, osascript fallback)
- [x] Schema module: notifications query; postNotification,
      dismissNotifications, dismissAllGatewayNotifications
- [x] `GATEWAY_HELPER` `deliveredAfter` / `deliveredBefore` parity with the
      `SYSTEM_DB` half-open date interval, applied before cursor pagination

## Tasks

### TASK-001: Helper app target and bundle assembly

**Parallelizable**: No

SwiftPM executable using UNUserNotificationCenter (request authorization,
post with categories/actions/reply, list delivered, remove by id/all,
settings report); `scripts/build-notifier-app.sh` assembling the .app
layout; version/protocol handshake.

#### TASK-001 Scope

Implement only:

- `Package.swift` target/product wiring for `AppleGatewayNotifier`.
- `Sources/AppleGatewayNotifier` helper entrypoint using
  `UNUserNotificationCenter` where available from inside an assembled `.app`.
- Shared Codable one-shot notification protocol models imported by CLI-side
  code and the helper target.
- Request/response validation for malformed data, unknown operations,
  operation payload constraints, and mismatched `protocolVersion`.
- `scripts/build-notifier-app.sh` with Info.plist creation, `LSUIElement`,
  executable placement, dry-run mode, and signing hooks.
- Deterministic protocol round-trip and validation tests.

Do not implement TASK-002 helper driving/path resolution/fallback, TASK-003
`usernoted` listing, TASK-004 schema registration, Homebrew/Cask packaging,
commits, or pushes. Preserve the existing uncommitted Phase 3 Mail changes.

#### TASK-001 Data Flow

The future CLI adapter and the helper share the same Codable request and
response types. TASK-001 validates those types directly in unit tests. The
helper executable accepts one JSON request, validates `protocolVersion`,
dispatches the requested operation to its helper-local notification service,
prints one JSON response, and exits. Tests must be able to exercise protocol
validation without prompting for notification permission or depending on live
Notification Center contents.

#### TASK-001 Verification

Run the narrow commands first:

```bash
swift build --target AppleGatewayNotifier
swift test --filter NotificationProtocol
bash scripts/build-notifier-app.sh --dry-run
```

Then run shared verification because TASK-001 adds a SwiftPM target and
shared protocol models:

```bash
swift build
swift test
swiftlint
```

If `swiftlint` is unavailable in the environment, record that explicitly in
the implementation result.

**Completion Criteria**:

- [ ] Assembled bundle posts a notification with two actions and a reply
      field on a dev machine (manual; not executed in this non-interactive
      implementation run)
- [x] Protocol round-trip unit tests shared by both targets
- [x] Mismatched `protocolVersion` rejected with a clear error
- [x] Dry-run bundle assembly creates/prints the expected
      `AppleGatewayNotifier.app` layout without requiring signing secrets

### TASK-002: Adapter: helper driving and fallback

**Parallelizable**: No (after TASK-001)

Helper path resolution order from the spec, subprocess request/response
with timeout, `waitSeconds` activation flow, `NOTIFIER_HELPER_MISSING`,
osascript fallback gated on `allowFallback` with `usedFallback: true`.

**Completion Criteria**:

- [x] Stub-helper smoke tests: post, activation kinds, dismiss counts,
      missing helper, fallback permitted/forbidden
- [x] Fallback never claims action/reply support (validation rejects
      `actions`/`allowReply` + `allowFallback`-only availability)

### TASK-003: System-wide listing from usernoted DB

**Parallelizable**: Yes (after Phase 0 TASK-006)

Sequoia+ and legacy path probing, snapshot copy, `record`/`app` join,
CFAbsoluteTime conversion, keyed-archiver blob traversal for
title/subtitle/body, search filters and connection, FDA and schema-drift
error mapping.

**Completion Criteria**:

- [x] Fixture DBs (both schema variants) drive decoding tests including
      undecodable blobs (row skipped, warning detail)
- [x] FDA-denied fixture yields `FULL_DISK_ACCESS_REQUIRED`

### TASK-004: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the notifications module, SDL snapshot, smoke flows, manual
checklist (first-run permission prompt for the helper, action click,
reply text, dismiss, system-wide list on macOS 14 and 15+).

**Completion Criteria**:

- [x] `dismissNotifications` with SYSTEM_DB ids fails `INVALID_ARGUMENT`
      with the documented explanation
- [x] Manual checklist artifact exists at
      `impl-plans/live-checklists/phase-4-notifications-live.md`; live
      execution was skipped in the non-interactive run and remains manual
- [x] Safe live readiness helper exists at
      `scripts/live-notifications-check.sh`; default dry-run is
      non-prompting and non-mutating, validates exact Notifications Query and
      Mutation root-field schema exposure for full/reader roles, and opt-in
      `--read-only` listing is source-scoped with `SYSTEM_DB` guarded by
      `notificationDbFullDiskAccess: GRANTED`

### TASK-005: Gateway-helper date-filter parity

**Feature ID**: `notification-helper-date-filters`

**Feature Title**: `GATEWAY_HELPER notification date filtering`

**Workflow Mode**: `issue-resolution`

**Issue Reference**: "Implement Notes attachments
(list/export/isShared), GATEWAY_HELPER notification date filters, and
clock-alarms CLI help in apple-gateway". No repository, issue number, or URL
was provided.

**Codex-Agent References**: None provided.

**Parallelizable**: No; this bounded correction depends on the completed
TASK-002 helper adapter and its connection pagination behavior plus the
TASK-003 `SYSTEM_DB` filter contract used as the semantic reference.

Implement the accepted contract in
`Sources/AppleGatewayCore/Domains/NotificationsAdapter/NotificationHelperAdapter.swift`:

- Validate that `deliveredAfter` is not later than `deliveredBefore`, using
  the same `INVALID_ARGUMENT` behavior and message as
  `UsernotedNotificationQueryService`.
- Parse helper `deliveredAt` ISO-8601 strings, including current helper output
  and fractional-second variants, without changing the public notification
  model or one-shot helper protocol.
- Apply the inclusive lower bound (`>=`) and exclusive upper bound (`<`)
  together with the existing application-id filter before cursor lookup,
  page slicing, and connection metadata calculation.
- Exclude missing or malformed helper timestamps only when a date filter is
  active. Preserve the helper's returned ordering and current unfiltered
  behavior.

Add focused coverage in
`Tests/AppleGatewayCoreTests/NotificationAdapterTests.swift` through the
public `notifications(input:)` adapter surface. The fixture response must
contain records below, exactly on, and above each bound plus a missing or
malformed timestamp. Assertions must cover lower-bound inclusion,
upper-bound exclusion, equal and reversed bounds, `totalCount`, `hasNextPage`,
end cursor, and a second page so the tests prove filtering precedes
pagination.

#### TASK-005 Dependencies and Deliverables

- [x] Accepted source-independent date semantics in
      `design-docs/specs/design-notifications.md`
- [x] Existing helper connection and `SYSTEM_DB` reference behavior inspected
- [x] Gateway-helper validation, ISO-8601 parsing, and pre-pagination filters
- [x] Boundary and pagination regression tests
- [x] Narrow and full verification recorded in the progress log

#### TASK-005 Verification

Run the narrowest regression first, then the repository-required full checks:

```bash
swift test --filter notificationAdapterGatewayConnectionAppliesDateFiltersBeforePagination
swift test --filter NotificationAdapter
task build
task test
task lint
git diff --check
```

If `task lint` reports that SwiftLint is unavailable, record that environment
limitation; `task build`, `task test`, and `git diff --check` remain required.
Live Notification Center state is not required for this deterministic adapter
test. If go-task itself is unavailable, use `swift build` and `swift test` as
the recorded build and full-suite fallbacks.

**Completion Criteria**:

- [x] `GATEWAY_HELPER` and `SYSTEM_DB` use the same inclusive lower and
      exclusive upper date boundaries.
- [x] Date filtering occurs before cursor resolution and page slicing, and
      connection metadata describes the filtered collection.
- [x] Reversed bounds fail consistently; equal bounds return an empty
      connection.
- [x] Missing or malformed helper timestamps do not pass an active date
      filter and remain visible when no date bound is supplied.
- [x] Focused adapter tests, `task build`, and the full `task test` suite pass.

## Progress Log

- 2026-07-18: TASK-005 implemented. `GATEWAY_HELPER` now validates reversed
  ranges with the SYSTEM_DB message, parses ISO-8601 timestamps with and
  without fractional seconds, applies the inclusive/exclusive date interval
  before cursor pagination, and excludes invalid timestamps only for active
  date filters. Focused NotificationAdapter tests (7 tests), `task build`,
  full `task test` (181 tests plus AppleGatewaySmokeTests), `task lint` (0
  violations), and `git diff --check` passed.

- 2026-07-02: Plan created from approved design docs.
- 2026-07-18: Feature-local planning for
  `notification-helper-date-filters` in issue-resolution mode defined
  source-independent half-open date semantics, pre-pagination filtering,
  malformed timestamp handling, focused adapter tests, completion criteria,
  and narrow/full verification. The supplied issue had no repository, number,
  or URL, and no codex-agent references or prior review TODOs were provided.
- 2026-07-03: TASK-001 issue-resolution design update for workflow
  `codex-design-and-implement-review-loop-session-382` documented the
  helper target, shared protocol, validation, bundle assembly, explicit
  out-of-scope Phase 4 tasks, and verification commands. No GitHub issue URL,
  issue number, codex-agent reference, or review feedback was provided.
- 2026-07-03: TASK-001 implementation completed after the Riela session
  accepted scope and then stalled in its documentation step. Added the
  `AppleGatewayNotifier` SwiftPM executable target, shared notification
  helper protocol models and validation, deterministic protocol tests, and
  `scripts/build-notifier-app.sh`. Verified `swift build --target
  AppleGatewayNotifier`, `swift test --filter NotificationProtocol`,
  `bash -n scripts/build-notifier-app.sh`, `bash
  scripts/build-notifier-app.sh --dry-run`, real local bundle assembly with
  valid `Info.plist` and executable placement, `swift build`, `swift test`,
  `task lint`, and `git diff --check`. Live notification prompt/action/reply
  verification remains manual.
- 2026-07-03: TASK-002 implementation completed after Riela session
  `codex-design-and-implement-review-loop-session-384` started and then
  stalled in intake. Added notification domain models, helper bundle
  resolution, subprocess helper execution with timeout handling, missing
  helper mapping to `NOTIFIER_HELPER_MISSING`, osascript fallback gated by
  `allowFallback`, and fallback validation that rejects actions, replies,
  activation waits, and invalid post payloads. Added deterministic stub-helper
  tests for post activation, list, dismiss, dismiss all, missing helper,
  fallback permitted/forbidden, and helper timeout. Verified `swift test
  --filter Notification`, `swift build`, `swift test`, and `task lint`.
- 2026-07-03: TASK-003 implementation completed after Riela session
  `codex-design-and-implement-review-loop-session-385` started and then
  stalled in intake. Added usernoted database path probing for Sequoia+
  group-container and legacy DARWIN_USER_DIR locations, read-only access
  checks, copy-then-open snapshot support, schema-variant introspection,
  `record`/`app` joins, CFAbsoluteTime conversion, best-effort binary plist
  content traversal, filtering, cursor pagination, skipped-row warnings for
  undecodable payloads, and `FULL_DISK_ACCESS_REQUIRED` /
  `NOTIFICATION_DB_UNAVAILABLE` mapping. Added deterministic fixture tests
  for post-Sequoia and legacy schemas, FDA denial, missing DB, schema drift,
  filters, pagination, and undecodable blobs. Verified `swift test --filter
  Usernoted`, `swift build`, full `swift test`, `task lint`, and
  `git diff --check`.
- 2026-07-03: TASK-004 implementation completed after Riela session
  `codex-design-and-implement-review-loop-session-387` started and then
  stalled in intake. Registered the notifications schema module, wired
  notification service injection through `GraphQLRuntime` and CLI command
  execution, added query/mutation resolvers, rejected `SYSTEM_DB` ids in
  `dismissNotifications` with `INVALID_ARGUMENT`, added GraphQL runtime tests
  for reader/full schema behavior and injected services, and extended smoke
  flows with fake-backed notification query/post/dismiss validation. Live
  manual checks for first-run helper prompt, action click, reply text,
  dismiss, and system-wide list were skipped because this was a
  non-interactive run. Verified `swift test --filter notifications`, `swift
  run AppleGatewaySmokeTests`, full `swift test`, `task lint`, schema print
  for full/reader roles, `task build` with Xcode toolchain environment, and
  `git diff --check`.
- 2026-07-03: Riela work package
  `codex-simple-work-package-session-408` added the missing Phase 4
  notifications live manual checklist artifact at
  `impl-plans/live-checklists/phase-4-notifications-live.md` and clarified
  TASK-004 status so the plan records that live execution was skipped in this
  non-interactive run rather than implying live execution happened. The
  checklist covers environment capture, helper permission prompt observation,
  two-action and reply posting, click/action/reply activation observations,
  helper list/dismiss/dismiss-all, osascript fallback boundaries,
  system-wide usernoted listing on macOS 14 and macOS 15+, Full Disk Access
  handling, reader behavior, cleanup, and follow-up recording. Verification:
  `test -f impl-plans/live-checklists/phase-4-notifications-live.md`, targeted
  `rg` checks for checklist terms and stale executed wording, and
  `git diff --check`.
- 2026-07-03: Riela work package
  `codex-simple-work-package-session-416` added
  `scripts/live-notifications-check.sh` as the safe Phase 4 Notifications live
  readiness helper. The default dry-run runs only permissions status plus
  full/reader schema checks and prints the Phase 4 checklist path; explicit
  `--read-only --source gateway-helper|system-db|both` gates delivered
  notification listing by source, with `SYSTEM_DB` refused unless
  `notificationDbFullDiskAccess` is `GRANTED`. Updated the live checklist to
  route readiness through the helper and to document the non-mutating dry-run
  and guarded read-only modes. Verification recorded for this session:
  `bash -n scripts/live-notifications-check.sh`, dry-run helper execution when
  feasible, targeted `rg` checks for script references and safety wording, and
  `git diff --check`.
- 2026-07-03: Riela work package
  `codex-simple-work-package-session-428` hardened
  `scripts/live-notifications-check.sh` schema readiness checks so default
  dry-run validates exact Notifications Query and Mutation root-field
  exposure for full and reader schemas instead of broad SDL substring
  matches. The full and reader schemas must expose the exact
  `notifications(input: NotificationSearchInput): DeliveredNotificationConnection!`
  Query root field; the full schema must expose the exact
  `postNotification(input: PostNotificationInput!): PostedNotification!`,
  `dismissNotifications(ids: [ID!]!): DismissResult!`, and
  `dismissAllGatewayNotifications: DismissResult!` Mutation root fields; the
  reader schema must not expose those Mutation root fields. Default dry-run
  remains non-prompting and non-mutating, and no delivered notifications or
  usernoted database rows are listed or read unless `--read-only` is
  explicitly requested.
