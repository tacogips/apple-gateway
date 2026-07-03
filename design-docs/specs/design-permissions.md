# Permissions, TCC, and Signing Design

## Status

Draft

## Purpose

macOS privacy enforcement (TCC) is the dominant failure mode for this tool.
This spec defines how apple-gateway requests, detects, and reports every
permission it needs, and how signing keeps grants stable. Facts are sourced
from `design-docs/references/macos-platform-research-2026-07.md`.

## Permission Matrix

| Domain | Mechanism | TCC service | Prompt possible from CLI | Usage keys |
| --- | --- | --- | --- | --- |
| Calendar | EventKit | Calendars (full access) | Yes (`requestFullAccessToEvents`) | `NSCalendarsFullAccessUsageDescription` + legacy `NSCalendarsUsageDescription` |
| Reminders | EventKit | Reminders (full access) | Yes (`requestFullAccessToReminders`) | `NSRemindersFullAccessUsageDescription` + legacy `NSRemindersUsageDescription` |
| Notes | Apple Events to Notes.app | Automation (`kTCCServiceAppleEvents`) | Yes (first send prompts) | `NSAppleEventsUsageDescription` |
| Mail | Read `~/Library/Mail` | Full Disk Access | No (manual grant only) | none |
| Notifications: post/dismiss own | Helper .app | Notifications | Yes (helper's first request) | helper Info.plist |
| Notifications: system-wide list | Read usernoted db2 | Full Disk Access | No | none |
| Clock alarms | `shortcuts run` | none (Shortcuts mediates) | n/a | none |

## The Responsible-Process Problem

Interactive TCC grants attribute to the nearest user-visible ancestor
process: the terminal app, not our binary. Consequences the design must
handle:

1. Terminals that lack calendar/reminders usage keys in their own
   Info.plist are denied silently, with no prompt
   (`EKEventStore` returns denied immediately). iTerm2 ships the keys;
   several popular AI-terminal hosts do not.
2. Grants live per terminal app. Switching from iTerm2 to Terminal.app
   requires granting again.
3. When run from `launchd` (no user-visible ancestor), the binary itself is
   the responsible process; then the embedded Info.plist usage strings and
   a stable code signature matter directly.

Every permission error message therefore includes: the detected
responsible-process hint (best-effort from the process tree), the System
Settings pane to open, and the relevant `tccutil reset` command.

## Embedded Info.plist

Both executables embed `Resources/AppleGatewayInfo.plist` as an
`__TEXT,__info_plist` section via SwiftPM:

```swift
linkerSettings: [
  .unsafeFlags([
    "-Xlinker", "-sectcreate",
    "-Xlinker", "__TEXT",
    "-Xlinker", "__info_plist",
    "-Xlinker", "Resources/AppleGatewayInfo.plist"
  ])
]
```

Plist contents: `CFBundleIdentifier`, `CFBundleName`,
`CFBundleShortVersionString`, the four EventKit usage keys (macOS 14
full-access plus legacy fallbacks), and
`NSAppleEventsUsageDescription`.

Phase 0 TASK-001 uses the requested singular source file,
`Resources/AppleGatewayInfo.plist`, for both executable targets. Its
`CFBundleIdentifier` is `me.tacogips.apple-gateway`; the embedded usage
strings are the blocking requirement for EventKit and Apple Events prompt
eligibility. A reader-specific bundle id
`me.tacogips.apple-gateway.reader` requires target-specific plist
materialization and is tracked as a non-blocking follow-up question in
`design-docs/user-qa/pending-apple-gateway-questions.md`.

Verification for this design is build-artifact based: `swift build` must
produce `.build/debug/apple-gateway` and `.build/debug/apple-gateway-reader`,
and `otool -s __TEXT __info_plist .build/debug/apple-gateway` must show the
embedded plist section. The same check should be applied to
`.build/debug/apple-gateway-reader` when changing linker settings.

## Detection and the Doctor Surface

`Permissions/` implements non-prompting probes:

- Calendars/Reminders: `EKEventStore.authorizationStatus(for:)`, mapping
  `.fullAccess`, `.writeOnly`, `.denied`, `.notDetermined`.
- Notes automation: `AEDeterminePermissionToAutomateTarget` with
  `askUserIfNeeded=false` against `com.apple.Notes`.
- Full Disk Access: attempt to `open(2)` a known TCC-protected probe file
  read-only (the resolved Mail `Envelope Index` and the usernoted db path);
  `EPERM` implies FDA missing.
- Notifications helper: helper app resolvable and its
  `getNotificationSettings` reports authorized (queried over the helper
  IPC described in `design-notifications.md`).
- Shortcuts bridge: `shortcuts list` contains the expected
  `apple-gateway-*` shortcuts.

Exposed three ways with one implementation:

```bash
apple-gateway permissions status            # human-readable table + JSON with --json
apple-gateway permissions request --domain calendar|reminders|notes|notifications
apple-gateway graphql --query '{ permissions { calendars mailFullDiskAccess } }'
```

`permissions request` is the only code path that intentionally triggers
prompts. The `permissions` GraphQL field is a doctor/status surface and
returns `PermissionState` values, including `NOT_DETERMINED`, without
prompting. Later domain data resolvers never trigger prompts implicitly
when a required status is `NOT_DETERMINED`; they fail with
`PERMISSION_NOT_DETERMINED` and instructions, so agent-driven queries
cannot spam the user with dialogs. (Rationale recorded in
`design-docs/user-qa/resolved-apple-gateway-defaults.md`.)

Full Disk Access guidance prints the manual path and the deep link
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.

## TASK-005 Behavioral Boundary

TASK-005 replaces the bootstrap placeholder permissions field with the real
permissions status service only. It does not implement the file store, smoke
frame, or later domain adapters.

The permissions service has two explicit entrypoints:

- `status`: non-prompting, read-only probes for every field in
  `PermissionsStatus`.
- `request(domain:)`: the only prompt-capable path, limited to
  `calendar`, `reminders`, `notes`, and `notifications`.

The status entrypoint must be injectable for tests, so unit tests can prove
that CLI and GraphQL status paths do not call prompt APIs. Calendar and
reminders status use EventKit authorization-status APIs only. Notes
automation status calls `AEDeterminePermissionToAutomateTarget` with
`askUserIfNeeded=false`. Full Disk Access checks open known protected probe
paths read-only and never create, modify, chmod, delete, or copy the probe
locations. Shortcuts status may list shortcuts but must not run shortcuts.

`permissions request --domain calendar` calls only the EventKit calendar
request path. `--domain reminders` calls only the EventKit reminders request
path. `--domain notes` may trigger the first Notes automation prompt through
the minimal Notes Apple Event path. `--domain notifications` delegates only
to an already installed and configured notifier helper notification
authorization path. If no helper is configured or the configured helper
cannot be resolved, TASK-005 must return `UNKNOWN` with an unavailable
diagnostic for notification request/status instead of scaffolding,
installing, signing, packaging, or launching a new helper app. Helper app
creation and distribution remain Phase 4 notification-domain work. Full Disk
Access and Shortcuts bridge setup are not requestable and remain manual
instructions in status output.

`permissions status --json` and GraphQL `permissions` use the same field
names and state vocabulary as `PermissionsStatus`:

- `calendars`
- `reminders`
- `notesAutomation`
- `mailFullDiskAccess`
- `notificationsHelper`
- `notificationDbFullDiskAccess`
- `shortcutsClockBridge`

Configuration-disabled domains report `NOT_REQUIRED`; unavailable or
undetectable probes report `UNKNOWN` with details in the human doctor output
or JSON details object. Responsible-process detection is a best-effort hint
only and must never be presented as definitive.

## Signing and Distribution

- Release artifacts (both CLIs and `AppleGatewayNotifier.app`) are
  Developer ID signed and notarized through the existing
  `macos-cask-release` workflow, giving stable TCC identities across
  updates.
- The Homebrew formula (unsigned source build) still works interactively
  because grants attach to the terminal; the docs note that launchd usage
  needs the signed cask build.
- The notifier helper must always be signed: unsigned helper apps get their
  notification permission wiped on every update.

## Failure Message Contract

All permission failures share one formatter:

```
Calendar access is denied for this process tree.
Responsible app (best effort): iTerm2
Fix: System Settings > Privacy & Security > Calendars: enable "iTerm2",
or run: apple-gateway permissions request --domain calendar
Reset: tccutil reset Calendar
```

The same content ships in the GraphQL error `extensions.details` so
programmatic callers can relay it.

The shared formatter owns the exact line ordering and labels for both CLI
and GraphQL errors. Its inputs are the permission domain, denied or missing
state, responsible-process hint, System Settings pane, optional
`permissions request` command, and optional `tccutil reset` command. If the
responsible app is unknown, the formatter prints `unknown` rather than
omitting the line.
