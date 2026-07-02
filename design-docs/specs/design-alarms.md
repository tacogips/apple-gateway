# Alarms Design

## Status

Draft

## Scope and Honest Capability Statement

"Alarm" means two different things on macOS, and the gateway exposes both
with different guarantees:

1. EventKit alarms (`EKAlarm` on calendar events and reminders): fully
   API-supported CRUD. This is the reliable, complete surface and the
   recommended path for programmatic alarms. Its schema lives in
   `design-calendar-reminders.md` (`Alarm`, `AlarmInput`,
   `setEventAlarms`, `setReminderAlarms`, and alarm fields on create/update
   inputs). On macOS 26.2+, a reminder with high priority and an alert can
   be flagged Urgent by the user to fire a must-dismiss alarm.

2. Clock app alarms: macOS provides no public API and Clock.app is not
   scriptable (research reference, section 2). The only supported
   automation path is Shortcuts actions, which the gateway drives through
   the `shortcuts` CLI. This surface is best-effort by construction, and
   the design says so explicitly instead of pretending full control.

## Clock Alarms via the Shortcuts Bridge

### Mechanism

The gateway invokes `shortcuts run <name> [--input-path <file>] --output-path <file>`
as a subprocess. The user installs a set of bridge shortcuts once (the repo
ships `.shortcut` files plus an install guide; shortcuts cannot be created
programmatically). Bridge shortcuts, prefixed by config
`clock_alarms.shortcut_prefix` (default `apple-gateway`):

| Shortcut | Clock action | Availability |
| --- | --- | --- |
| `apple-gateway-get-alarms` | Get All Alarms, serialize to JSON | macOS 13+ |
| `apple-gateway-create-alarm` | Create Alarm from JSON input | macOS 13+ |
| `apple-gateway-toggle-alarm` | Toggle Alarm by name | macOS 13+ |
| `apple-gateway-update-alarm` | Update Alarm from JSON input | macOS 26+ |
| `apple-gateway-delete-alarm` | Delete Alarms by name | macOS 26+ |

`ClockAlarmsAdapter` checks `shortcuts list` output before each operation;
a missing shortcut yields `SHORTCUT_NOT_INSTALLED` with the install-guide
path. Operations whose backing action does not exist on the running macOS
version yield `SHORTCUT_ACTION_UNSUPPORTED` / `UNSUPPORTED_OS_VERSION`.

### GraphQL Types

```graphql
type ClockAlarm {
  id: ID                 # stable identifier when the OS provides one; else null
  label: String!
  time: String!          # "HH:mm" local time
  isEnabled: Boolean!
  repeatDays: [Weekday!]!
}

enum Weekday { MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY }

input CreateClockAlarmInput {
  time: String!          # "HH:mm"
  label: String
  repeatDays: [Weekday!]
}

input ToggleClockAlarmInput { label: String!, enabled: Boolean }
input UpdateClockAlarmInput { label: String!, time: String, newLabel: String, repeatDays: [Weekday!] }
input DeleteClockAlarmInput { label: String! }

type ClockAlarmResult {
  success: Boolean!
  alarm: ClockAlarm
  warning: String        # e.g. "verified by re-listing; Shortcuts returned no output"
}
```

Alarms are addressed by label because pre-Tahoe Shortcuts actions expose no
stable identifier. Ambiguous labels (multiple matches) fail with
`INVALID_ARGUMENT` listing the collisions.

### Verification Strategy

`shortcuts run` reports little on failure. Every mutation therefore
re-reads via `apple-gateway-get-alarms` and diffs to confirm the change,
populating `warning` when confirmation is inconclusive.

### Read Fallback

`clockAlarms` primarily uses the get-alarms shortcut. As a diagnostics-only
extra, `permissions status --json` reports whether the local alarm store
(`com.apple.mobiletimerd` plist on macOS 13-15, group-container SQLite on
26+) is readable; the gateway never writes those stores and never uses them
as the primary read path, since the Shortcuts path reflects daemon state.

## Explicit Non-Capabilities

Recorded so users and agent callers get errors instead of surprises:

- Creating Clock alarms without the bridge shortcuts installed.
- Editing/deleting Clock alarms on macOS 13-15 (actions absent).
- Timers and stopwatch control (Start Timer exists in Shortcuts; deferred,
  tracked as an open question in `design-docs/user-qa/`).
- AlarmKit: Catalyst/iOS-only, not linkable from a CLI.

## Testing

- `ClockAlarmsProviding` fake for resolver tests.
- Subprocess layer tested with a stub `shortcuts` executable on `PATH`
  (fixture scripts emitting canned JSON, nonzero exits, and garbage
  output).
- JSON contract between bridge shortcuts and adapter documented in
  `packaging/shortcuts/README.md` and pinned by decoding unit tests.
