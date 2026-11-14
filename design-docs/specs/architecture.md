# Architecture

## Status

Draft (target architecture; Phase 0 TASK-001 migrates the template
scaffold from `AppCore`/`AppCLI` to the target names below)

## Overview

`apple-gateway` is a Swift Package Manager project providing a GraphQL
gateway to Apple's built-in macOS apps (Calendar, Reminders, Clock alarms,
Notes, Mail, Notifications) as both a library and command line tools.
The architecture mirrors the sibling project `mail-gateway`: a single core
library, thin role-split executables, zero external package dependencies,
and a one-shot `graphql` command as the only business API surface.

## Targets

| Target | Kind | Purpose |
| --- | --- | --- |
| `AppleGatewayCore` | library (public product) | GraphQL runtime, config, permissions, file store, Apple Events bridge, all domain adapters |
| `AppleGatewayCLI` | executable `apple-gateway` | Full read/write gateway |
| `AppleGatewayReaderCLI` | executable `apple-gateway-reader` | Read-only gateway (schema without Mutation) |
| `AppleGatewayNotifier` | executable (packaged into a helper `.app`) | UNUserNotificationCenter host for posting/listing/dismissing notifications |
| `AppleGatewayCoreTests` | test target | swift-testing unit tests |
| `AppleGatewaySmokeTests` | executable | End-to-end CLI flows against fake adapters |

The current scaffold targets `AppCore`/`AppCLI` are renamed/replaced in
Phase 0 (`impl-plans/active/phase-0-foundation-and-graphql-runtime.md`).

## Phase 0 Package Boundary

TASK-001 is limited to package shape and executable identity. It renames
`Sources/AppCore` to `Sources/AppleGatewayCore` and `Sources/AppCLI` to
`Sources/AppleGatewayCLI`, adds `Sources/AppleGatewayReaderCLI`, and updates
tests/imports from `AppCoreTests`/`AppCore` to
`AppleGatewayCoreTests`/`AppleGatewayCore`.

The SwiftPM products are:

- library product `AppleGatewayCore` targeting `AppleGatewayCore`
- executable product `apple-gateway` targeting `AppleGatewayCLI`
- executable product `apple-gateway-reader` targeting
  `AppleGatewayReaderCLI`

Both executable targets depend only on `AppleGatewayCore` and keep
`main.swift` as a thin adapter: process arguments and environment enter,
an integer exit code returns. Command parsing, version handling, JSON
formatting, and role selection remain in the core library so the full and
reader binaries cannot drift.

No domain adapters, GraphQL runtime behavior, config parser, or permission
probe behavior is introduced by TASK-001. Those are later Phase 0 tasks.

## Core Library Layout

```
Sources/AppleGatewayCore/
  GraphQLRuntime/       lexer, parser, schema registry, executor, SDL printer
  CLI/                  command routing, flag parsing, JSON output
  Config/               TOML subset parser, env overrides
  Permissions/          TCC probes, prompts, doctor report
  FileStore/            download keys, materialized-file cache, path safety
  AppleEventBridge/     osascript JXA runner (batching, timeout, retry)
  Domains/
    CalendarKitAdapter/   EventKit events, calendars, EKAlarm
    RemindersAdapter/     EventKit reminders, EKAlarm
    ClockAlarmsAdapter/   JXA accessibility automation for Clock.app
    NotesAdapter/         Apple Events (JXA) to Notes.app
    MailAdapter/          Envelope Index SQLite + .emlx parsing
    NotificationsAdapter/ notifier helper driver + usernoted DB reader
```

Every domain sits behind a `*Providing` protocol so tests inject fakes and
mechanisms can be swapped without schema changes. Platform framework
objects (EventKit classes, SQLite handles) never cross the protocol
boundary; adapters return `Sendable` `Codable` value models.

## Execution Model

One-shot process execution, no server. A `graphql` invocation parses and
validates the document against the role-specific schema registry, resolves
root fields through domain adapters, projects results by the selection
set, and prints a GraphQL JSON envelope. Async platform callbacks are
bridged synchronously (`DispatchSemaphore` + lock-guarded result boxes)
under Swift 6 strict concurrency.

## Dependencies

None (SwiftPM dependency list stays empty). System frameworks only:
Foundation, CryptoKit for FileStore download-key MACs, EventKit,
`libsqlite3` (C shim), and UserNotifications (helper app target only).

## Design Documents

- `design-apple-gateway.md` — primary spec (schema, config, errors, phases)
- `design-graphql-runtime.md` — parser/executor
- `design-permissions.md` — TCC, FDA, signing
- `design-calendar-reminders.md`, `design-alarms.md`,
  `design-apple-notes.md`, `design-apple-mail.md`,
  `design-notifications.md` — domains

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/`
- Signed and notarized Cask DMGs under `dist/homebrew-cask/`
- Both install the two CLIs and `libexec/AppleGatewayNotifier.app`; the
  cask variant ships Developer ID signed binaries (stable TCC identity)
