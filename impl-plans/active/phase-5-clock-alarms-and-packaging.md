# Phase 5: Clock Alarms and Packaging

**Status**: Complete
**Design Reference**: `design-docs/specs/design-alarms.md`

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
