# Phase 5: Clock Alarms and Packaging

**Status**: Complete (phase and feature-local CLI help follow-up)
**Design References**: `design-docs/specs/design-alarms.md`,
`design-docs/specs/command.md#permissions`

## Purpose

Ship a self-contained Clock alarm surface and finish Homebrew distribution.

## Deliverables

- [x] JXA accessibility adapter for Clock.app list/create/toggle/update/delete.
- [x] Label ambiguity checks and post-mutation verification.
- [x] GraphQL schema, reader restrictions, and injected unit tests.
- [x] Accessibility and System Events permission status/request support.
- [x] Formula and Cask packaging with both CLIs and notifier helper.
- [x] Read-only and scratch-mutation live verification script.
- [x] No Shortcuts.app workflows or external bridge assets required.

## 2026-07-18 implementation update

Clock.app has no AppleScript dictionary or public alarm API, so the final
adapter follows the existing Notes automation architecture by executing JXA
through the shared Apple Event bridge. It uses Clock.app accessibility
identifiers, numerically addresses duplicate repeat-day controls, preserves
enabled state during updates, and polls through transient UI refreshes.

The previous external bridge design was removed in full: its adapters,
contracts, tests, configuration key, error codes, package assets, validation
gate, archive staging, formula assertions, Cask caveats, and setup docs were
deleted. Live create/list/toggle/update/delete verification succeeded and the
scratch alarm was removed.

## Feature-local follow-up: Clock alarms permission help

**Feature ID**: `clock-alarms-permission-help`
**Status**: Complete

### Scope and dependencies

This follow-up only aligns the shared CLI guidance with the already implemented
`PermissionRequestDomain.clockAlarms` behavior. It depends on the existing
permission-domain parser and provider routing; it does not change permission
requests, Clock.app automation, packaging, or other feature work.

### Deliverables and progress

- [x] Add `clock-alarms` to the permission-domain list in
  `AppleGatewayCommand.usage` in
  `Sources/AppleGatewayCore/CLI/Command.swift`.
- [x] Add `clock-alarms` to the missing-`--domain` usage diagnostic in
  `AppleGatewayCommand.parsePermissionsRequestArguments` in the same file.
- [x] Extend `Tests/AppleGatewayCoreTests/CommandTests.swift` to assert that
  top-level `--help` contains the complete domain list.
- [x] Add a regression test that invokes `permissions request` without
  `--domain`, captures `AppleGatewayCommand.Error.invalidUsage`, and asserts
  that its usage text contains the same complete domain list.
- [x] Confirm existing `PermissionRequestDomain(commandValue: "clock-alarms")`
  parsing and domain-isolation tests remain unchanged and passing.

### Completion criteria

- Top-level help and missing-domain usage guidance both contain
  `calendar|reminders|notes|notifications|clock-alarms`.
- The implementation adds no new domain enum, provider route, or public API.
- Focused command tests, SwiftLint, the package build, and the full task test
  suite pass before any commit or push.

### Verification

Run from the repository root:

```bash
swift test --filter commandReportsUsage
swift test --filter commandPermissionsRequestUsageIncludesClockAlarms
swiftlint
task build
task test
```

If `task` is unavailable, use `swift build` and `swift test`; report SwiftLint
as unavailable rather than silently skipping it.

### 2026-07-18 completion update

Both user-visible permission-domain usage strings now include `clock-alarms`,
with focused tests for top-level help and the missing-domain diagnostic.
Verification passed: both focused command tests, `task build`, full `task test`
(181 tests plus AppleGatewaySmokeTests), `task lint` (0 violations), and
`git diff --check`. Permission routing, Clock automation, and packaging were
not changed.
