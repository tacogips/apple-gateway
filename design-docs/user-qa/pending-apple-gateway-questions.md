# Pending Product Questions for apple-gateway

**Status**: Pending
**Created**: 2026-07-02
**Category**: apple-gateway Product Design

Open questions that do not block Phase 0-1 implementation. Defaults are
proposed so work can proceed; answers may override them.

## Question 1: Timers and stopwatch

Should the Clock accessibility adapter also expose `startTimer` as a mutation
in the Clock domain?

Proposed default: defer past v1; alarms only.

## Question 2: Notes direct-SQLite fast-read mode

A Full-Disk-Access-gated read path over `NoteStore.sqlite` would make bulk
note search dramatically faster and expose tags/checklists that Apple
Events hide, at the cost of tracking an undocumented schema. Add it as an
opt-in `--fast` read mode in a later phase?

Proposed default: not in v1; revisit after Phase 2 ships and real
performance numbers exist.

## Question 3: System-wide notification clearing

The only mechanism is Accessibility UI scripting of Notification Center,
which breaks on most major macOS releases. v1 does not offer it. Should a
best-effort, config-gated implementation be added later?

Proposed default: keep it out; document `dismissAllGatewayNotifications`
as the supported scope.

## Question 4: Mail live actions (mark read, move)

Requirements say retrieval only. If light mutations are ever wanted, the
only mechanism is AppleScript to Mail.app (slow, Tahoe-fragile). Confirm
retrieval-only is the long-term scope?

Proposed default: retrieval-only permanently; mutations would be a new
design document.

## Question 5: GraphQL server mode

mail-gateway deferred a `serve` mode; the same question applies here,
with the extra wrinkle that a long-lived process would hold TCC grants and
EventKit stores open. Should a local HTTP/stdio server mode be designed
for v2?

Proposed default: defer; revisit when a concrete consumer (e.g. an MCP
wrapper) exists.

## Question 6: Reader-specific embedded bundle identifier

Phase 0 TASK-001 intentionally uses one checked-in
`Resources/AppleGatewayInfo.plist` for both command line executables. Should
the reader binary later embed a distinct `CFBundleIdentifier`
(`me.tacogips.apple-gateway.reader`) through target-specific plist
materialization?

Proposed default: defer until signing/cask packaging work needs separate
reader TCC identity. For TASK-001, both binaries embed the shared
`me.tacogips.apple-gateway` plist to satisfy EventKit and Apple Events usage
string requirements.
