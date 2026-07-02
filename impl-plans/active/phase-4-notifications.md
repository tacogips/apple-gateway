# Phase 4: Notifications

**Status**: In Progress (blocked on Phase 0)
**Design Reference**: `design-docs/specs/design-notifications.md`

## Purpose

Notification posting with actions and reply via the bundled helper app,
gateway-notification dismissal/listing, system-wide delivered-notification
listing from the usernoted store, and the osascript fallback.

## Deliverables

- [ ] `AppleGatewayNotifier` executable target + packaging script
      assembling `AppleGatewayNotifier.app` (Info.plist, LSUIElement,
      signing hooks)
- [ ] One-shot JSON protocol (post/list/dismiss/dismissAll/settings) with
      `protocolVersion`, shared Codable definitions between CLI and helper
- [ ] `Domains/NotificationsAdapter/` (helper resolution and driving,
      usernoted snapshot reader, osascript fallback)
- [ ] Schema module: notifications query; postNotification,
      dismissNotifications, dismissAllGatewayNotifications

## Tasks

### TASK-001: Helper app target and bundle assembly

**Parallelizable**: No

SwiftPM executable using UNUserNotificationCenter (request authorization,
post with categories/actions/reply, list delivered, remove by id/all,
settings report); `scripts/build-notifier-app.sh` assembling the .app
layout; version/protocol handshake.

**Completion Criteria**:

- [ ] Assembled bundle posts a notification with two actions and a reply
      field on a dev machine (manual)
- [ ] Protocol round-trip unit tests shared by both targets
- [ ] Mismatched `protocolVersion` rejected with a clear error

### TASK-002: Adapter: helper driving and fallback

**Parallelizable**: No (after TASK-001)

Helper path resolution order from the spec, subprocess request/response
with timeout, `waitSeconds` activation flow, `NOTIFIER_HELPER_MISSING`,
osascript fallback gated on `allowFallback` with `usedFallback: true`.

**Completion Criteria**:

- [ ] Stub-helper smoke tests: post, activation kinds, dismiss counts,
      missing helper, fallback permitted/forbidden
- [ ] Fallback never claims action/reply support (validation rejects
      `actions`/`allowReply` + `allowFallback`-only availability)

### TASK-003: System-wide listing from usernoted DB

**Parallelizable**: Yes (after Phase 0 TASK-006)

Sequoia+ and legacy path probing, snapshot copy, `record`/`app` join,
CFAbsoluteTime conversion, keyed-archiver blob traversal for
title/subtitle/body, search filters and connection, FDA and schema-drift
error mapping.

**Completion Criteria**:

- [ ] Fixture DBs (both schema variants) drive decoding tests including
      undecodable blobs (row skipped, warning detail)
- [ ] FDA-denied fixture yields `FULL_DISK_ACCESS_REQUIRED`

### TASK-004: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the notifications module, SDL snapshot, smoke flows, manual
checklist (first-run permission prompt for the helper, action click,
reply text, dismiss, system-wide list on macOS 14 and 15+).

**Completion Criteria**:

- [ ] `dismissNotifications` with SYSTEM_DB ids fails `INVALID_ARGUMENT`
      with the documented explanation
- [ ] Manual checklist executed and logged below

## Progress Log

- 2026-07-02: Plan created from approved design docs.
