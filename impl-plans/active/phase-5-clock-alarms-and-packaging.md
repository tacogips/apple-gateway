# Phase 5: Clock Alarms Bridge and Packaging

**Status**: Implementation complete except real exported `.shortcut` files and
manual live Shortcuts checks
**Design Reference**: `design-docs/specs/design-alarms.md`,
`design-docs/specs/design-permissions.md#signing-and-distribution`

## Purpose

Ship the Shortcuts-bridged Clock alarm surface and finish distribution:
bridge shortcuts, helper-app packaging in formula and cask, signing, and
user-facing setup docs.

## Deliverables

- [x] `Domains/ClockAlarmsAdapter/` (`shortcuts` subprocess layer,
      availability probing, verification-by-relisting)
- [x] Schema module: clockAlarms; createClockAlarm, toggleClockAlarm,
      updateClockAlarm, deleteClockAlarm
- [ ] `packaging/shortcuts/` with the five `.shortcut` files and README
      (JSON contract + install guide)
- [x] Homebrew formula/cask updates installing both CLIs and
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
- [x] Contract documented with field-by-field semantics and versioned

**Notes**: JSON contract and tests are implemented in
`packaging/shortcuts/README.md`,
`packaging/shortcuts/SOURCE.md`, `packaging/shortcuts/manifest.json`,
`ClockAlarmShortcutContractTests`, and `ClockAlarmShortcutAdapterTests`.
The five exported `.shortcut` files were not generated in this non-interactive
run because Shortcuts.app authoring/export is manual and the local
`shortcuts` CLI exposes no create/import/export subcommand.

### TASK-002: ClockAlarmsAdapter

**Parallelizable**: Yes (after Phase 0)

`shortcuts list` availability check, subprocess invocation with
input/output files, label addressing with ambiguity errors, macOS-version
gating (`SHORTCUT_ACTION_UNSUPPORTED`/`UNSUPPORTED_OS_VERSION`),
post-mutation verification by re-listing with `warning` population.

**Completion Criteria**:

- [x] Stub-`shortcuts` tests: missing shortcut, canned alarm JSON, garbage
      output, nonzero exit, ambiguous label
- [x] Every mutation re-lists and diffs; inconclusive results set `warning`

### TASK-003: Schema registration and smoke flows

**Parallelizable**: No (after TASK-002)

Register the clock-alarms module, SDL snapshot, smoke flows, manual
checklist on macOS 13-15 (create/toggle only) and 26+ (full set).

**Completion Criteria**:

- [x] Update/delete on pre-26 fails with the documented code, not silence
- [ ] Manual checklist executed and logged below

**Notes**: GraphQL fake-backed query/mutations and reader-role rejection are
covered by `ClockAlarmGraphQLRuntimeTests` and `AppleGatewaySmokeTests`.
Live checklist scaffolding exists in
`impl-plans/live-checklists/phase-5-clock-alarms-live.md` and
`scripts/live-clock-alarms-check.sh`. Live macOS 13-15 and 26+ Shortcuts
checks remain skipped until the bridge shortcuts are installed.

### TASK-004: Packaging and release updates

**Parallelizable**: Yes (after Phase 4 TASK-001)

Extend `scripts/build-homebrew-release.sh` and the cask scripts to build
and embed the notifier app under `libexec/`, install both binaries and the
`.shortcut` files, sign and notarize the helper in the cask flow
(`macos-cask-release` skill), and document the full permission setup
(TCC, FDA deep link, shortcut install) in README.

**Completion Criteria**:

- [x] Release packaging refuses missing exported `.shortcut` assets unless
      `APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1` documents an
      incomplete local/manual run
- [ ] `task build:homebrew -- darwin-arm64` archive contains both CLIs,
      the helper app, and real exported shortcuts
- [x] Cask dry-run shows helper signing steps
- [x] README setup section reviewed against `design-permissions.md`

## Progress Log

- 2026-07-02: Plan created from approved design docs.
- 2026-07-03: TASK-001/TASK-002 routed through Riela session
  `codex-design-and-implement-review-loop-session-388`; workflow stalled at
  intake, so implementation continued locally under the recorded scope.
  Added Clock alarm models/protocol, versioned Shortcuts JSON contract,
  subprocess `shortcuts` executor, availability probing, label ambiguity
  checks, macOS 26 gating, and post-mutation re-list verification.
- 2026-07-03: TASK-003 routed through Riela session
  `codex-design-and-implement-review-loop-session-389`; intake completed and
  the long-running process was stopped before local implementation. Registered
  `clockAlarms` GraphQL schema/query/mutations, CLI/runtime injection, SDL and
  runtime tests, and fake-backed smoke flows.
- 2026-07-03: TASK-004 routed through Riela session
  `codex-design-and-implement-review-loop-session-390`; workflow stalled at
  intake, so packaging work continued locally. Updated formula/cask builders
  and renderers to stage/install `apple-gateway`, `apple-gateway-reader`,
  `libexec/AppleGatewayNotifier.app`, and `share/apple-gateway/shortcuts`.
  Cask dry-run now prints helper signing/notarization intent. README now
  documents TCC prompts, Full Disk Access, notification helper authorization,
  and Clock alarm Shortcuts setup.
- 2026-07-03: Pre-shortcut-assets-gate verification: `swift test --filter
  ClockAlarm`, `swift run AppleGatewaySmokeTests`, `bash -n` for packaging
  scripts, Homebrew and Cask dry-runs, rendered formula/cask `ruby -c` syntax
  checks with temporary checksum fixtures, `task build:homebrew --
  darwin-arm64`, archive content inspection for the then-staged
  shortcuts docs/manifest package, full `swift test` (177 tests),
  `task build`, `task lint` (0 violations), and `git diff --check` all
  passed. This historical check predates the release shortcut-assets gate
  below and does not mean current production archives are ready without the
  real exported `.shortcut` files.
- 2026-07-03: Remaining Shortcuts packaging/manual gap routed through Riela
  session `codex-design-and-implement-review-loop-session-392`; intake
  accepted the scope and flagged Shortcut/Clock safety for adversarial review,
  then the workflow stalled in design-doc update and the local process was
  stopped. Local closeout work continued under the accepted scope. Local
  `shortcuts help` showed only `run`, `list`, `view`, and `sign`; no
  create/import/export command exists. Prefix-filtered `shortcuts list`
  found no installed `apple-gateway-*` bridge shortcuts on this machine.
  Added `packaging/shortcuts/SOURCE.md`, machine-readable
  `packaging/shortcuts/manifest.json`,
  `impl-plans/live-checklists/phase-5-clock-alarms-live.md`, and
  `scripts/live-clock-alarms-check.sh`. The checker defaults to list-only
  readiness, supports `--read-only` get-alarms JSON validation, and requires
  `--execute` before creating/toggling scratch alarms. Verification:
  `bash -n scripts/live-clock-alarms-check.sh`, `python3 -m json.tool
  packaging/shortcuts/manifest.json`, `scripts/live-clock-alarms-check.sh`
  safe refusal with missing shortcuts and exit 6, an incomplete/manual
  `task build:homebrew -- darwin-arm64` package check that inspected only
  `README.md`, `SOURCE.md`, and `manifest.json`, and `git diff --check`
  passed. Production release readiness is governed by the later
  shortcut-assets gate, which fails while the real exported `.shortcut` files
  are absent unless the incomplete local/manual bypass is set.
- 2026-07-03: Shortcuts readiness false-positive fix routed through Riela
  session `codex-design-and-implement-review-loop-session-393`; intake
  accepted the scope and identified the same risk that any prefix-matching
  shortcut could incorrectly mark `shortcutsClockBridge` ready. The workflow
  then looped in design-doc update and the local process was stopped. Local
  implementation continued under the accepted scope. Updated the permissions
  probe to require exact expected bridge names from
  `ClockAlarmShortcutNames`, using get/create/toggle on macOS 13-15 and also
  update/delete on macOS 26+. Added deterministic tests for exact matching,
  prefix-only false positives, macOS 26 update/delete requirements, and custom
  prefixes. Live `permissions status --json` now reports
  `shortcutsClockBridge: UNKNOWN` with all five expected shortcuts missing on
  this macOS 26 machine. Verification: `swift test --filter Permissions`,
  full `swift test` (181 tests), `task lint`, live `swift run apple-gateway
  permissions status --json` inspection, and `git diff --check` passed.
- 2026-07-03: Release shortcut-assets gate routed through Riela session
  `codex-simple-work-package-session-396`. Added manifest-based validation
  for Homebrew formula and Cask release builders so real production packaging
  fails while the five exported `.shortcut` files are absent. Preserved the
  manual export truth by keeping `packaging/shortcuts/` as source docs plus
  manifest only, and added explicit
  `APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1` bypass wording for
  incomplete local/manual checks. Verification recorded by the work package:
  `bash -n scripts/validate-shortcut-assets.sh
  scripts/build-homebrew-release.sh scripts/build-homebrew-cask-release.sh`,
  failing `scripts/build-homebrew-release.sh --validate-shortcuts-only`,
  allowed `APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1
  scripts/build-homebrew-release.sh --validate-shortcuts-only`, and
  `git diff --check`.
- 2026-07-03: Review for Riela session
  `codex-simple-work-package-session-396` found that release validation still
  inherited `APPLE_GATEWAY_SHORTCUTS_DIR` while staging copied the fixed repo
  `packaging/shortcuts` directory. Updated both formula and Cask builders to
  force `APPLE_GATEWAY_SHORTCUTS_DIR="$repo_root/packaging/shortcuts"` for
  release validation, keeping the validated directory identical to the staged
  directory and preserving the standalone validator override for non-release
  checks. Verification: `bash -n scripts/validate-shortcut-assets.sh
  scripts/build-homebrew-release.sh scripts/build-homebrew-cask-release.sh`,
  failing formula and Cask `--validate-shortcuts-only` checks, failing formula
  and Cask override checks with `APPLE_GATEWAY_SHORTCUTS_DIR=/tmp` still
  reporting the repo `packaging/shortcuts/manifest.json`, allowed formula and
  Cask bypass checks with
  `APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1`, and `git diff --check`.
- 2026-07-03: Rendered tap asset assertions routed through Riela session
  `codex-simple-work-package-session-398`. Updated the Formula renderer test
  to assert `README.md`, `SOURCE.md`, `manifest.json`, and all five expected
  exported `.shortcut` paths under `pkgshare/shortcuts`. Updated the Cask
  renderer to surface the same expected Clock alarm bridge package contents in
  caveats and to zap the installed shortcuts directory, while preserving the
  release-builder shortcut validation as the production gate. Verification:
  rendered Formula and Cask files with temporary checksum fixtures, inspected
  the rendered output for `README.md`, `SOURCE.md`, `manifest.json`, all five
  `.shortcut` paths, and `zap trash`, ran `ruby -c` on both rendered files,
  `bash -n scripts/render-homebrew-formula.sh scripts/render-homebrew-cask.sh`,
  and `git diff --check`.
- 2026-07-03: Formula class-name fix routed through Riela session
  `codex-simple-work-package-session-399`; the workflow applied the scoped
  edits but stalled during final diff checking and was stopped. Local
  verification continued under the same scope. Updated the Formula renderer so
  `Formula/apple-gateway.rb` renders `class AppleGateway < Formula` instead
  of the old scaffolded `class App < Formula`, without changing shortcut
  export truth or creating placeholder `.shortcut` files. Verification:
  rendered the Formula with temporary checksum fixtures, ran `ruby -c` on the
  rendered file, confirmed `class AppleGateway < Formula` is present and
  `class App < Formula` is absent, ran `bash -n
  scripts/render-homebrew-formula.sh`, and ran `git diff --check`.
- 2026-07-03: Release metadata identity cleanup routed through Riela session
  `codex-simple-work-package-session-401`. Updated the Formula and Cask
  renderers to default release URLs, verified URL, homepage, and generated
  descriptions to `tacogips/apple-gateway`; updated the local Cask release
  wrapper to upload to `tacogips/apple-gateway` by default while preserving an
  `APPLE_GATEWAY_GITHUB_REPOSITORY` override; refreshed README and Homebrew
  packaging wording away from the scaffold summary. Verification: rendered
  Formula and Cask files with temporary checksum fixtures, ran `ruby -c` on
  both rendered files, checked rendered and repo release metadata with `rg`,
  ran `bash -n scripts/render-homebrew-formula.sh
  scripts/render-homebrew-cask.sh scripts/release-homebrew-cask-local.sh`, and
  ran `git diff --check`.
- 2026-07-03: Review revision for Riela session
  `codex-simple-work-package-session-401` addressed the Cask wrapper override
  path: `scripts/release-homebrew-cask-local.sh` now defaults
  `CASK_RELEASE_BASE_URL` from `APPLE_GATEWAY_GITHUB_REPOSITORY` before
  invoking the renderer, while preserving an explicit `CASK_RELEASE_BASE_URL`.
  The Cask renderer now derives `verified:` from GitHub release base URLs so
  repository overrides keep URL metadata aligned. Verification: focused
  wrapper render stubs confirmed a custom `APPLE_GATEWAY_GITHUB_REPOSITORY`
  renders the matching GitHub release URL and verified prefix, an explicit
  `CASK_RELEASE_BASE_URL` still wins, plus `bash -n` and `git diff --check`.
- 2026-07-03: Homebrew tap placeholder cleanup routed through Riela session
  `codex-simple-work-package-session-403`. Updated remaining project
  README, Homebrew packaging, and local Cask release helper examples from the
  stale scaffold tap placeholder to the active sibling tap command
  `tacogips/tap`. Verification: stale tap placeholder scan across README,
  packaging, scripts, and this active plan; `bash -n
  scripts/release-homebrew-cask-local.sh`; and `git diff --check`.
- 2026-07-03: README Shortcuts permissions wording routed through Riela
  session `codex-simple-work-package-session-404`. Updated the setup docs to
  say `permissions status --json` checks exact expected bridge shortcut names
  for the configured `clock_alarms.shortcut_prefix` and reports
  missing-shortcut detail, so a prefix-only shortcut is not documented as
  sufficient. Verification: targeted `rg` checks for stale prefix wording and
  exact-name wording in README and this active plan, plus `git diff --check`.
- 2026-07-03: Live Clock alarm checker manifest derivation routed through
  Riela session `codex-simple-work-package-session-406`. Updated
  `scripts/live-clock-alarms-check.sh` to derive exact required bridge shortcut
  names from `packaging/shortcuts/manifest.json`, adapt manifest names from
  the manifest `shortcutPrefix` to the requested `--prefix`, and preserve
  macOS availability gating so macOS 13-15 checks get/create/toggle while
  macOS 26+ also checks update/delete. No placeholder `.shortcut` files were
  created. Local review after the interrupted workflow replaced a Bash-4-only
  `mapfile` read with a Bash 3.2-compatible loop. Verification: `bash -n
  scripts/live-clock-alarms-check.sh`,
  `python3 -m json.tool packaging/shortcuts/manifest.json`,
  `scripts/live-clock-alarms-check.sh` expected missing-shortcuts exit 6 on
  this machine, and `git diff --check`.
- 2026-07-03: Live Clock alarm default readiness hardening routed through
  Riela session `codex-simple-work-package-session-425`. Updated
  `scripts/live-clock-alarms-check.sh` so the default path prints this live
  checklist path, verifies GraphQL schema readiness for both full and reader
  `clockAlarms`, verifies the full schema exposes exact create/toggle/update/
  delete Clock alarm mutations, then performs exact shortcut-name checks from
  manifest-derived names. The default path remains non-mutating and does not
  run shortcuts; `--read-only` and `--execute` remain the only shortcut
  execution paths. Real exported `.shortcut` files and live Shortcuts checks
  remain incomplete/manual.
- 2026-07-03: Manifest-driven renderer hardening routed through Riela session
  `codex-simple-work-package-session-433`. Updated the Formula renderer to
  derive `.shortcut` test assertions from
  `packaging/shortcuts/manifest.json`, while keeping explicit `README.md`,
  `SOURCE.md`, and `manifest.json` assertions. Updated the Cask renderer to
  derive the installed `.shortcut` caveat lines from the same manifest data.
  Release-builder shortcut validation remains the production gate, so release
  shortcut validation still fails until the real exported `.shortcut` files
  exist unless the incomplete local/manual bypass is set.
- 2026-07-03: Deterministic non-live closeout audit routed through Riela
  session `codex-simple-work-package-session-435`. Evidence recorded for that
  pass: `swift test`, `swift run AppleGatewaySmokeTests`, `task build`,
  `task lint`, `bash -n` for shortcut/live/release/render scripts,
  `python3 -m json.tool packaging/shortcuts/manifest.json`, Formula and Cask
  render checks with temporary checksum fixtures plus `ruby -c` on rendered
  files, production shortcut validation checks, `find packaging/shortcuts
  -name '*.shortcut' -print`, `git diff --name-only` before/after the
  deterministic pass, and `git diff --check`. The pass did not add or modify
  files. No `.shortcut` files exist under `packaging/shortcuts`. Production
  release shortcut validation still intentionally fails without the real
  exported `.shortcut` files unless
  `APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1` is set for incomplete
  local/manual checks. The goal remains incomplete: real exported Clock
  `.shortcut` files, live Shortcuts/Clock permission and app checks,
  Developer ID signing/notarization, and Homebrew audit/install remain
  external/manual blockers.
