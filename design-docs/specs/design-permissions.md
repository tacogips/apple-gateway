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

Both executables embed an Info.plist section via SwiftPM:

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

Plist contents: `CFBundleIdentifier` (`me.tacogips.apple-gateway` /
`.reader`), `CFBundleName`, `CFBundleShortVersionString`, the four
EventKit usage keys (macOS 14 full-access plus legacy fallbacks), and
`NSAppleEventsUsageDescription`.

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
prompts. GraphQL resolvers never trigger prompts implicitly when status is
`.notDetermined`; they fail with `PERMISSION_NOT_DETERMINED` and
instructions, so agent-driven queries cannot spam the user with dialogs.
(Rationale recorded in `design-docs/user-qa/resolved-apple-gateway-defaults.md`.)

Full Disk Access guidance prints the manual path and the deep link
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.

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
