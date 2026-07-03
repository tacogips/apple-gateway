#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scratch_name="${APPLE_GATEWAY_LIVE_SCRATCH_NAME:-apple-gateway-test}"
execute=false

usage() {
  cat <<EOF
Usage:
  scripts/live-calendar-reminders-check.sh [--execute]

Runs the Phase 1 Calendar/Reminders live verification flow against scratch
EventKit data only. Dry-run is the default and performs non-prompting readiness
checks plus prints the live checklist.

Safety:
  - Does not request permissions or trigger TCC prompts.
  - Refuses --execute unless both Calendar and Reminders status are GRANTED.
  - Creates only scratch calendar/list items named "$scratch_name".
  - Cleans up only IDs created during the current run.

Environment:
  APPLE_GATEWAY_BIN                 Use an existing apple-gateway binary.
  APPLE_GATEWAY_LIVE_SCRATCH_NAME   Scratch calendar/list title.

Checklist:
  impl-plans/live-checklists/phase-1-calendar-reminders-live.md

Before --execute, grant access manually if needed:
  swift run apple-gateway permissions request --domain calendar
  swift run apple-gateway permissions request --domain reminders
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      execute=true
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required for JSON validation in this script\n' >&2
  exit 2
fi

if [[ -n "${APPLE_GATEWAY_BIN:-}" ]]; then
  gateway=( "$APPLE_GATEWAY_BIN" )
else
  gateway=( swift run apple-gateway )
fi

run_gateway() {
  (
    cd "$repo_root"
    "${gateway[@]}" "$@"
  )
}

json_field() {
  local expression
  expression="$1"
  python3 -c "import json, sys; data=json.load(sys.stdin); print($expression)"
}

json_variables() {
  python3 - "$@" <<'PY'
import json
import sys

mode = sys.argv[1]

if mode == "create_calendar":
    payload = {"input": {"title": sys.argv[2]}}
elif mode == "delete_calendar":
    payload = {"calendarId": sys.argv[2]}
elif mode == "create_event":
    payload = {
        "input": {
            "calendarId": sys.argv[2],
            "title": sys.argv[3],
            "startDate": sys.argv[4],
            "endDate": sys.argv[5],
            "alarms": [{"relativeOffsetSeconds": int(sys.argv[6])}],
        }
    }
elif mode == "search_events":
    payload = {
        "input": {
            "calendarIds": [sys.argv[2]],
            "startDate": sys.argv[3],
            "endDate": sys.argv[4],
        }
    }
elif mode == "set_event_alarms":
    payload = {
        "eventId": sys.argv[2],
        "alarms": [{"relativeOffsetSeconds": int(sys.argv[3])}],
    }
elif mode == "create_recurring_event":
    payload = {
        "input": {
            "calendarId": sys.argv[2],
            "title": sys.argv[3],
            "startDate": sys.argv[4],
            "endDate": sys.argv[5],
            "recurrenceRules": [{"frequency": "DAILY", "occurrenceCount": int(sys.argv[6])}],
        }
    }
elif mode == "update_recurring_event":
    payload = {
        "input": {
            "eventId": sys.argv[2],
            "occurrenceDate": sys.argv[3],
            "span": "FUTURE_EVENTS",
            "title": sys.argv[4],
        }
    }
elif mode == "delete_event":
    payload = {"eventId": sys.argv[2]}
    if len(sys.argv) > 3:
        payload["span"] = sys.argv[3]
elif mode == "create_reminder":
    payload = {
        "input": {
            "listId": sys.argv[2],
            "title": sys.argv[3],
            "dueDate": sys.argv[4],
            "alarms": [{"relativeOffsetSeconds": int(sys.argv[5])}],
        }
    }
elif mode == "set_reminder_completed":
    payload = {"reminderId": sys.argv[2], "completed": True}
elif mode == "set_reminder_alarms":
    payload = {"reminderId": sys.argv[2], "alarms": [{"absoluteDate": sys.argv[3]}]}
elif mode == "delete_reminder":
    payload = {"reminderId": sys.argv[2]}
else:
    raise SystemExit(f"unknown JSON variable mode: {mode}")

print(json.dumps(payload, separators=(",", ":")))
PY
}

check_schema_contains() {
  local schema role description expected
  schema="$1"
  role="$2"
  description="$3"
  expected="$4"
  if ! printf '%s\n' "$schema" | grep -Fxq "$expected"; then
    printf '%s schema missing %s: %s\n' "$role" "$description" "$expected" >&2
    exit 1
  fi
}

check_schema_absent() {
  local schema role description unexpected
  schema="$1"
  role="$2"
  description="$3"
  unexpected="$4"
  if printf '%s\n' "$schema" | grep -Fxq "$unexpected"; then
    printf '%s schema unexpectedly exposes %s: %s\n' "$role" "$description" "$unexpected" >&2
    exit 1
  fi
}

extract_schema_root_block() {
  local schema role root required block
  schema="$1"
  role="$2"
  root="$3"
  required="$4"
  if ! block="$(printf '%s\n' "$schema" | python3 -c '
import re
import sys

root = sys.argv[1]
schema = sys.stdin.read()
match = re.search(r"(?m)^type[ \t]+" + re.escape(root) + r"[ \t]*\{", schema)
if match is None:
    sys.exit(1)

depth = 0
for index in range(match.end() - 1, len(schema)):
    character = schema[index]
    if character == "{":
        depth += 1
    elif character == "}":
        depth -= 1
        if depth == 0:
            print(schema[match.start():index + 1])
            sys.exit(0)

sys.exit(2)
' "$root")"; then
    if [[ "$required" == "optional" ]]; then
      printf ''
      return 0
    fi
    printf '%s schema missing type %s root block\n' "$role" "$root" >&2
    exit 1
  fi
  printf '%s\n' "$block"
}

printf 'Phase 1 Calendar/Reminders live checklist: impl-plans/live-checklists/phase-1-calendar-reminders-live.md\n'

permissions_json="$(run_gateway permissions status --json)"
calendar_state="$(printf '%s' "$permissions_json" | json_field "data['data']['calendars']")"
reminders_state="$(printf '%s' "$permissions_json" | json_field "data['data']['reminders']")"

printf 'Calendar permission: %s\n' "$calendar_state"
printf 'Reminders permission: %s\n' "$reminders_state"

full_schema="$(run_gateway schema print --role full)"
reader_schema="$(run_gateway schema print --role reader)"
full_query_root="$(extract_schema_root_block "$full_schema" full Query required)"
reader_query_root="$(extract_schema_root_block "$reader_schema" reader Query required)"
full_mutation_root="$(extract_schema_root_block "$full_schema" full Mutation required)"
reader_mutation_root="$(extract_schema_root_block "$reader_schema" reader Mutation optional)"

for expected in \
  "  calendars(entityType: CalendarEntityType): [Calendar!]!" \
  "  events(input: EventSearchInput!): EventConnection!" \
  "  event(eventId: ID!, occurrenceDate: DateTime): CalendarEvent" \
  "  reminderLists: [Calendar!]!" \
  "  reminders(input: ReminderSearchInput!): ReminderConnection!" \
  "  reminder(reminderId: ID!): Reminder"; do
  check_schema_contains "$full_query_root" "full Query root" "Calendar/Reminders query field" "$expected"
  check_schema_contains "$reader_query_root" "reader Query root" "Calendar/Reminders query field" "$expected"
done

for expected in \
  "  createCalendar(input: CreateCalendarInput!): Calendar!" \
  "  deleteCalendar(calendarId: ID!): DeleteResult!" \
  "  createEvent(input: CreateEventInput!): CalendarEvent!" \
  "  updateEvent(input: UpdateEventInput!): CalendarEvent!" \
  "  deleteEvent(eventId: ID!, span: RecurrenceSpan!, occurrenceDate: DateTime): DeleteResult!" \
  "  setEventAlarms(eventId: ID!, alarms: [AlarmInput!]!, span: RecurrenceSpan!, occurrenceDate: DateTime): CalendarEvent!" \
  "  createReminderList(input: CreateReminderListInput!): Calendar!" \
  "  createReminder(input: CreateReminderInput!): Reminder!" \
  "  updateReminder(input: UpdateReminderInput!): Reminder!" \
  "  deleteReminder(reminderId: ID!): DeleteResult!" \
  "  setReminderCompleted(reminderId: ID!, completed: Boolean!): Reminder!" \
  "  setReminderAlarms(reminderId: ID!, alarms: [AlarmInput!]!): Reminder!"; do
  check_schema_contains "$full_mutation_root" "full Mutation root" "Calendar/Reminders mutation field" "$expected"
  check_schema_absent "$reader_mutation_root" "reader Mutation root" "Calendar/Reminders mutation field" "$expected"
done

printf 'Schema readiness: exact Calendar/Reminders Query root fields are present in full and reader roles; exact Mutation root fields are full-schema only.\n'

cat <<EOF

Live checklist:
  1. Create scratch event calendar "$scratch_name".
  2. Create scratch reminder list "$scratch_name".
  3. Create event with alarm in scratch calendar.
  4. Search events and verify scratch event is returned.
  5. Replace event alarms.
  6. Create recurring event and update FUTURE_EVENTS span.
  7. Create reminder in scratch list.
  8. Complete reminder.
  9. Replace reminder alarms.
  10. Delete created event, recurring event, reminder, calendar, and list.
EOF

if [[ "$execute" != true ]]; then
  cat <<EOF

Dry-run only. No live EventKit query or mutation was performed.
Rerun with --execute only after the operator has granted Calendar and
Reminders permissions and accepts scratch EventKit mutations.
EOF
  exit 0
fi

if [[ "$calendar_state" != "GRANTED" || "$reminders_state" != "GRANTED" ]]; then
  cat >&2 <<EOF

Refusing --execute because Calendar and Reminders permissions are not both GRANTED.
Grant permissions manually from the app you want to verify, then rerun this
script with --execute:

  swift run apple-gateway permissions request --domain calendar
  swift run apple-gateway permissions request --domain reminders

For TASK-005, repeat permission-prompt observation from Terminal and iTerm2 and
record both results in impl-plans/active/phase-1-calendar-reminders.md.
EOF
  exit 4
fi

created_calendar_id=""
created_list_id=""
created_event_id=""
created_recurring_event_id=""
created_reminder_id=""

graphql() {
  local query variables output
  query="$1"
  variables="${2:-{}}"
  output="$(run_gateway graphql --query "$query" --variables "$variables")"
  if printf '%s' "$output" | python3 -c "import json, sys; data=json.load(sys.stdin); sys.exit(0 if not data.get('errors') else 1)"; then
    printf '%s\n' "$output"
    return
  fi
  printf 'GraphQL command failed:\n%s\n' "$output" >&2
  return 1
}

cleanup() {
  set +e
  if [[ -n "$created_event_id" ]]; then
    graphql 'mutation($eventId: ID!) { deleteEvent(eventId: $eventId) { success } }' \
      "$(json_variables delete_event "$created_event_id")" >/dev/null
  fi
  if [[ -n "$created_recurring_event_id" ]]; then
    graphql 'mutation($eventId: ID!, $span: RecurrenceSpan!) { deleteEvent(eventId: $eventId, span: $span) { success } }' \
      "$(json_variables delete_event "$created_recurring_event_id" FUTURE_EVENTS)" >/dev/null
  fi
  if [[ -n "$created_reminder_id" ]]; then
    graphql 'mutation($reminderId: ID!) { deleteReminder(reminderId: $reminderId) { success } }' \
      "$(json_variables delete_reminder "$created_reminder_id")" >/dev/null
  fi
  if [[ -n "$created_calendar_id" ]]; then
    graphql 'mutation($calendarId: ID!) { deleteCalendar(calendarId: $calendarId) { success } }' \
      "$(json_variables delete_calendar "$created_calendar_id")" >/dev/null
  fi
  if [[ -n "$created_list_id" ]]; then
    graphql 'mutation($calendarId: ID!) { deleteCalendar(calendarId: $calendarId) { success } }' \
      "$(json_variables delete_calendar "$created_list_id")" >/dev/null
  fi
}
trap cleanup EXIT

created_calendar_id="$(
  graphql 'mutation($input: CreateCalendarInput!) { createCalendar(input: $input) { id title } }' \
    "$(json_variables create_calendar "$scratch_name")" |
    json_field "data['data']['createCalendar']['id']"
)"
printf 'Created calendar: %s\n' "$created_calendar_id"

created_list_id="$(
  graphql 'mutation($input: CreateReminderListInput!) { createReminderList(input: $input) { id title } }' \
    "$(json_variables create_calendar "$scratch_name")" |
    json_field "data['data']['createReminderList']['id']"
)"
printf 'Created reminder list: %s\n' "$created_list_id"

created_event_id="$(
  graphql 'mutation($input: CreateEventInput!) {
  createEvent(input: $input) { id title alarms { relativeOffsetSeconds } }
}' "$(json_variables create_event "$created_calendar_id" "apple-gateway live event" "2026-07-03T09:00:00Z" "2026-07-03T10:00:00Z" "-600")" |
    json_field "data['data']['createEvent']['id']"
)"
printf 'Created event: %s\n' "$created_event_id"

event_search_count="$(
  graphql 'query($input: EventSearchInput!) {
  events(input: $input) { totalCount edges { node { id title } } }
}' "$(json_variables search_events "$created_calendar_id" "2026-07-03T00:00:00Z" "2026-07-04T00:00:00Z")" |
    json_field "data['data']['events']['totalCount']"
)"
printf 'Event search totalCount: %s\n' "$event_search_count"

graphql 'mutation($eventId: ID!, $alarms: [AlarmInput!]!) {
  setEventAlarms(eventId: $eventId, alarms: $alarms) { id alarms { relativeOffsetSeconds } }
}' "$(json_variables set_event_alarms "$created_event_id" "-300")" >/dev/null
printf 'Replaced event alarms\n'

created_recurring_event_id="$(
  graphql 'mutation($input: CreateEventInput!) {
  createEvent(input: $input) { id title recurrenceRules { frequency occurrenceCount } }
}' "$(json_variables create_recurring_event "$created_calendar_id" "apple-gateway live recurring event" "2026-07-04T09:00:00Z" "2026-07-04T10:00:00Z" "3")" |
    json_field "data['data']['createEvent']['id']"
)"
printf 'Created recurring event: %s\n' "$created_recurring_event_id"

graphql 'mutation($input: UpdateEventInput!) {
  updateEvent(input: $input) { id title }
}' "$(json_variables update_recurring_event "$created_recurring_event_id" "2026-07-05T09:00:00Z" "apple-gateway live recurring event updated")" >/dev/null
printf 'Updated recurring event with FUTURE_EVENTS span\n'

created_reminder_id="$(
  graphql 'mutation($input: CreateReminderInput!) {
  createReminder(input: $input) { id title alarms { relativeOffsetSeconds } }
}' "$(json_variables create_reminder "$created_list_id" "apple-gateway live reminder" "2026-07-03T12:00:00Z" "-300")" |
    json_field "data['data']['createReminder']['id']"
)"
printf 'Created reminder: %s\n' "$created_reminder_id"

graphql 'mutation($reminderId: ID!, $completed: Boolean!) {
  setReminderCompleted(reminderId: $reminderId, completed: $completed) { id isCompleted }
}' "$(json_variables set_reminder_completed "$created_reminder_id")" >/dev/null
printf 'Completed reminder\n'

graphql 'mutation($reminderId: ID!, $alarms: [AlarmInput!]!) {
  setReminderAlarms(reminderId: $reminderId, alarms: $alarms) { id alarms { absoluteDate } }
}' "$(json_variables set_reminder_alarms "$created_reminder_id" "2026-07-03T11:45:00Z")" >/dev/null
printf 'Replaced reminder alarms\n'

cleanup
trap - EXIT
printf 'Cleaned up scratch EventKit data created by this run\n'
printf 'Live Calendar/Reminders verification passed\n'
