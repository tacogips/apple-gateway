# Phase 5 Clock Alarms Live Checklist

Use this checklist after the five bridge shortcuts have been created and
exported from Shortcuts.app. Run only against scratch Clock alarms.

## Environment

- [ ] macOS version recorded:
- [ ] `apple-gateway --version` recorded:
- [ ] Terminal or host process recorded:
- [ ] `clock_alarms.shortcut_prefix` recorded:
- [ ] Exported `.shortcut` file paths recorded:

## Shortcut Installation

- [ ] `apple-gateway-get-alarms` installed.
- [ ] `apple-gateway-create-alarm` installed.
- [ ] `apple-gateway-toggle-alarm` installed.
- [ ] `apple-gateway-update-alarm` installed on macOS 26+.
- [ ] `apple-gateway-delete-alarm` installed on macOS 26+.

Non-mutating readiness check:

```bash
scripts/live-clock-alarms-check.sh
```

- [ ] Script printed this checklist path before readiness checks.
- [ ] Dry-run completed GraphQL schema readiness checks before shortcut checks.
- [ ] Full GraphQL schema exposed `clockAlarms`.
- [ ] Reader GraphQL schema exposed `clockAlarms`.
- [ ] Full GraphQL schema exposed `createClockAlarm`, `toggleClockAlarm`,
      `updateClockAlarm`, and `deleteClockAlarm`.
- [ ] exact shortcut-name checks used manifest-derived names for the configured
      prefix.
- [ ] Dry-run did not run shortcuts or mutate Clock alarms.
- [ ] Missing shortcuts, if any, produced exit 6 with the exact missing names.

## Read-Only JSON Contract

- [ ] Run the get shortcut and validate parseable JSON:

```bash
scripts/live-clock-alarms-check.sh --read-only
```

- [ ] Record alarm count returned by the script:
- [ ] Record any JSON contract failure:

## Scratch Mutation Flow

Run this only after confirming a scratch alarm may be created:

```bash
scripts/live-clock-alarms-check.sh --execute
```

- [ ] Scratch alarm created.
- [ ] Scratch alarm toggled.
- [ ] On macOS 26+, scratch alarm updated.
- [ ] On macOS 26+, scratch alarm deleted by the script.
- [ ] On macOS 13-15, manual cleanup completed if `--allow-manual-cleanup`
      was used.

## Reader Behavior

- [ ] Reader serves `clockAlarms` read query:

```bash
swift run apple-gateway-reader graphql --query '{ clockAlarms { label time isEnabled repeatDays } }'
```

- [ ] Reader rejects clock alarm mutation with `WRITE_DISABLED_IN_READER`:

```bash
swift run apple-gateway-reader graphql --query 'mutation {
  createClockAlarm(input: { time: "09:00", label: "Blocked" }) { success }
}'
```

## Findings

- [ ] macOS 13-15 create/toggle behavior recorded:
- [ ] macOS 26+ update/delete behavior recorded:
- [ ] Any Shortcuts UI/action naming differences recorded:
- [ ] Any follow-up spec or user-qa item filed:
