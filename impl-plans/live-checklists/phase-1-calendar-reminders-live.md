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

Execute live scratch verification:

```bash
scripts/live-calendar-reminders-check.sh --execute
```

The script refuses to execute unless Calendar and Reminders are already
`GRANTED`. It creates only scratch items named `apple-gateway-test` by default
and cleans up only IDs created during the current run.

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

Live mutation was not executed because doing so would require prompting for
Calendar and Reminders access first.
