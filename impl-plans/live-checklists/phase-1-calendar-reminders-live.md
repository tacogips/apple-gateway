# Phase 1 Calendar/Reminders Live Checklist

Use this checklist for TASK-005 after TASK-004A is complete. Live verification
must use only scratch `apple-gateway-test` calendar and reminder-list data.

## Readiness

Run the non-prompting status check:

```bash
swift run apple-gateway permissions status --json
```

Do not run live mutations unless both `calendars` and `reminders` are
`GRANTED`. If either is `NOT_DETERMINED`, observe prompt behavior manually from
the app being verified:

```bash
swift run apple-gateway permissions request --domain calendar
swift run apple-gateway permissions request --domain reminders
```

Repeat the prompt observation from Terminal and iTerm2 when both are available,
then record the exact results in
`impl-plans/active/phase-1-calendar-reminders.md`.

## Safe Script

Dry-run readiness and checklist:

```bash
scripts/live-calendar-reminders-check.sh
```

Default dry-run behavior:

- Prints this checklist path.
- Runs `permissions status --json` without requesting permissions or prompting.
- Reports `calendars` and `reminders` permission states.
- Extracts the GraphQL `Query` root block and verifies the full and reader
  schemas expose the exact Calendar/Reminders root read fields.
- Extracts the GraphQL `Mutation` root block and verifies the exact
  Calendar/Reminders root mutation fields are present only in the full schema
  and absent from the reader schema.
- Exits 0 even when Calendar or Reminders permissions are not `GRANTED`.
- Clearly states that no live EventKit query or mutation was performed.

Execute live scratch verification:

```bash
scripts/live-calendar-reminders-check.sh --execute
```

The script refuses `--execute` with exit 4 unless Calendar and Reminders are
already `GRANTED`, before any live EventKit mutation. When permissions are
granted and the operator explicitly runs `--execute`, it creates only scratch
items named `apple-gateway-test` by default and cleans up only IDs created
during the current run.

## Manual Assertions

- Create a scratch event calendar.
- Create a scratch reminder list.
- Create an event with a relative alarm.
- Search events in the scratch calendar.
- Replace event alarms.
- Create a recurring event and update with `span: FUTURE_EVENTS`.
- Create a reminder with an alarm.
- Complete the reminder.
- Replace reminder alarms with an absolute alarm.
- Delete created event, recurring event, reminder, calendar, and list.

## Current Environment Evidence

2026-07-03 non-prompting readiness check:

- macOS: 26.5.1 (Build 25F80)
- User: `taco`
- Calendar permission: `NOT_DETERMINED`
- Reminders permission: `NOT_DETERMINED`

Dry-run readiness does not require permissions and performs no live EventKit
query or mutation. Live mutation was not executed because doing so would require
the operator to grant Calendar and Reminders access first, then explicitly run
`scripts/live-calendar-reminders-check.sh --execute`.
