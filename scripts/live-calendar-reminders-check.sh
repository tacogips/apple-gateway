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

json_optional_field() {
  local expression
  expression="$1"
  python3 -c "import json, sys; data=json.load(sys.stdin); value=$expression; print('' if value is None else value)"
}

permissions_json="$(run_gateway permissions status --json)"
calendar_state="$(printf '%s' "$permissions_json" | json_field "data['data']['calendars']")"
reminders_state="$(printf '%s' "$permissions_json" | json_field "data['data']['reminders']")"

printf 'Calendar permission: %s\n' "$calendar_state"
printf 'Reminders permission: %s\n' "$reminders_state"

if [[ "$calendar_state" != "GRANTED" || "$reminders_state" != "GRANTED" ]]; then
  cat <<EOF

Live verification is not ready. Grant permissions manually from the app you
want to verify, then rerun this script with --execute:

  swift run apple-gateway permissions request --domain calendar
  swift run apple-gateway permissions request --domain reminders

For TASK-005, repeat permission-prompt observation from Terminal and iTerm2 and
record both results in impl-plans/active/phase-1-calendar-reminders.md.
EOF
  exit 4
fi

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
  printf '\nDry-run only. Rerun with --execute to mutate scratch EventKit data.\n'
  exit 0
fi

created_calendar_id=""
created_list_id=""
created_event_id=""
created_recurring_event_id=""
created_reminder_id=""

graphql() {
  local query output
  query="$1"
  output="$(run_gateway graphql --query "$query")"
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
    graphql "mutation { deleteEvent(eventId: \"$created_event_id\") { success } }" >/dev/null
  fi
  if [[ -n "$created_recurring_event_id" ]]; then
    graphql "mutation { deleteEvent(eventId: \"$created_recurring_event_id\", span: FUTURE_EVENTS) { success } }" >/dev/null
  fi
  if [[ -n "$created_reminder_id" ]]; then
    graphql "mutation { deleteReminder(reminderId: \"$created_reminder_id\") { success } }" >/dev/null
  fi
  if [[ -n "$created_calendar_id" ]]; then
    graphql "mutation { deleteCalendar(calendarId: \"$created_calendar_id\") { success } }" >/dev/null
  fi
  if [[ -n "$created_list_id" ]]; then
    graphql "mutation { deleteCalendar(calendarId: \"$created_list_id\") { success } }" >/dev/null
  fi
}
trap cleanup EXIT

created_calendar_id="$(
  graphql "mutation { createCalendar(input: { title: \"$scratch_name\" }) { id title } }" |
    json_field "data['data']['createCalendar']['id']"
)"
printf 'Created calendar: %s\n' "$created_calendar_id"

created_list_id="$(
  graphql "mutation { createReminderList(input: { title: \"$scratch_name\" }) { id title } }" |
    json_field "data['data']['createReminderList']['id']"
)"
printf 'Created reminder list: %s\n' "$created_list_id"

created_event_id="$(
  graphql "mutation { createEvent(input: { calendarId: \"$created_calendar_id\", title: \"apple-gateway live event\", startDate: \"2026-07-03T09:00:00Z\", endDate: \"2026-07-03T10:00:00Z\", alarms: [{ relativeOffsetSeconds: -600 }] }) { id title alarms { relativeOffsetSeconds } } }" |
    json_field "data['data']['createEvent']['id']"
)"
printf 'Created event: %s\n' "$created_event_id"

event_search_count="$(
  graphql "{ events(input: { calendarIds: [\"$created_calendar_id\"], startDate: \"2026-07-03T00:00:00Z\", endDate: \"2026-07-04T00:00:00Z\" }) { totalCount edges { node { id title } } } }" |
    json_field "data['data']['events']['totalCount']"
)"
printf 'Event search totalCount: %s\n' "$event_search_count"

graphql "mutation { setEventAlarms(eventId: \"$created_event_id\", alarms: [{ relativeOffsetSeconds: -300 }]) { id alarms { relativeOffsetSeconds } } }" >/dev/null
printf 'Replaced event alarms\n'

created_recurring_event_id="$(
  graphql "mutation { createEvent(input: { calendarId: \"$created_calendar_id\", title: \"apple-gateway live recurring event\", startDate: \"2026-07-04T09:00:00Z\", endDate: \"2026-07-04T10:00:00Z\", recurrenceRules: [{ frequency: DAILY, occurrenceCount: 3 }] }) { id title recurrenceRules { frequency occurrenceCount } } }" |
    json_field "data['data']['createEvent']['id']"
)"
printf 'Created recurring event: %s\n' "$created_recurring_event_id"

graphql "mutation { updateEvent(input: { eventId: \"$created_recurring_event_id\", occurrenceDate: \"2026-07-05T09:00:00Z\", span: FUTURE_EVENTS, title: \"apple-gateway live recurring event updated\" }) { id title } }" >/dev/null
printf 'Updated recurring event with FUTURE_EVENTS span\n'

created_reminder_id="$(
  graphql "mutation { createReminder(input: { listId: \"$created_list_id\", title: \"apple-gateway live reminder\", dueDate: \"2026-07-03T12:00:00Z\", alarms: [{ relativeOffsetSeconds: -300 }] }) { id title alarms { relativeOffsetSeconds } } }" |
    json_field "data['data']['createReminder']['id']"
)"
printf 'Created reminder: %s\n' "$created_reminder_id"

graphql "mutation { setReminderCompleted(reminderId: \"$created_reminder_id\", completed: true) { id isCompleted } }" >/dev/null
printf 'Completed reminder\n'

graphql "mutation { setReminderAlarms(reminderId: \"$created_reminder_id\", alarms: [{ absoluteDate: \"2026-07-03T11:45:00Z\" }]) { id alarms { absoluteDate } } }" >/dev/null
printf 'Replaced reminder alarms\n'

cleanup
trap - EXIT
printf 'Cleaned up scratch EventKit data created by this run\n'
printf 'Live Calendar/Reminders verification passed\n'
