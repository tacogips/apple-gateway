# Phase 5: Clock Alarms Bridge and Packaging

**Status**: In Progress (blocked on Phase 0; packaging tasks depend on Phases 1-4)
**Design Reference**: `design-docs/specs/design-alarms.md`,
`design-docs/specs/design-permissions.md#signing-and-distribution`

## Purpose

Ship the Shortcuts-bridged Clock alarm surface and finish distribution:
bridge shortcuts, helper-app packaging in formula and cask, signing, and
user-facing setup docs.

## Deliverables

- [ ] `Domains/ClockAlarmsAdapter/` (`shortcuts` subprocess layer,
      availability probing, verification-by-relisting)
- [ ] Schema module: clockAlarms; createClockAlarm, toggleClockAlarm,
      updateClockAlarm, deleteClockAlarm
- [ ] `packaging/shortcuts/` with the five `.shortcut` files and README
      (JSON contract + install guide)
- [ ] Homebrew formula/cask updates installing both CLIs and
      `libexec/AppleGatewayNotifier.app`; cask signing/notarization of the
      helper; README permission-setup section

## Tasks

### TASK-001: Bridge shortcuts and JSON contract

**Parallelizable**: Yes

Author the five shortcuts (get/create/toggle on macOS 13+; update/delete
on macOS 26+) emitting/accepting the JSON contract; document the contract
in `packaging/shortcuts/README.md`; pin it with decoding unit tests.

**Completion Criteria**:

- [ ] `shortcuts run apple-gateway-get-alarms` returns parseable JSON on a
      dev machine (manual)
- [ ] Contract documented with field-by-field semantics and versioned

### TASK-002: ClockAlarmsAdapter

**Parallelizable**: Yes (after Phase 0)

`shortcuts list` availability check, subprocess invocation with
input/output files, label addressing with ambiguity errors, macOS-version
gating (`SHORTCUT_ACTION_UNSUPPORTED`/`UNSUPPORTED_OS_VERSION`),
post-mutation verification by re-listing with `warning` population.

**Completion Criteria**:

- [ ] Stub-`shortcuts` tests: missing shortcut, canned alarm JSON, garbage
      output, nonzero exit, ambiguous label
- [ ] Every mutation re-lists and diffs; inconclusive results set `warning`

### TASK-003: Schema registration and smoke flows

**Parallelizable**: No (after TASK-002)

Register the clock-alarms module, SDL snapshot, smoke flows, manual
checklist on macOS 13-15 (create/toggle only) and 26+ (full set).

**Completion Criteria**:

- [ ] Update/delete on pre-26 fails with the documented code, not silence
- [ ] Manual checklist executed and logged below

### TASK-004: Packaging and release updates

**Parallelizable**: Yes (after Phase 4 TASK-001)

Extend `scripts/build-homebrew-release.sh` and the cask scripts to build
and embed the notifier app under `libexec/`, install both binaries and the
`.shortcut` files, sign and notarize the helper in the cask flow
(`macos-cask-release` skill), and document the full permission setup
(TCC, FDA deep link, shortcut install) in README.

**Completion Criteria**:

- [ ] `task build:homebrew -- darwin-arm64` archive contains both CLIs,
      the helper app, and shortcuts
- [ ] Cask dry-run shows helper signing steps
- [ ] README setup section reviewed against `design-permissions.md`

## Progress Log

- 2026-07-02: Plan created from approved design docs.
