#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scratch_label="${APPLE_GATEWAY_CLOCK_ALARMS_SCRATCH_LABEL:-apple-gateway-live-check-$(date +%Y%m%d%H%M%S)}"
execute=false

usage() {
  cat <<EOF
Usage:
  scripts/live-clock-alarms-check.sh [--execute] [--label LABEL]

Lists Clock alarms through apple-gateway without mutating them. With --execute,
it creates, disables, updates, and deletes one uniquely labelled scratch alarm.
The adapter controls Clock.app directly; no Shortcuts assets are required.

Environment:
  APPLE_GATEWAY_BIN                         Existing apple-gateway binary.
  APPLE_GATEWAY_CLOCK_ALARMS_SCRATCH_LABEL  Scratch alarm label.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      execute=true
      shift
      ;;
    --label)
      scratch_label="${2:-}"
      shift 2
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

if [[ -z "$scratch_label" || "$scratch_label" == *\"* || "$scratch_label" == *\\* ]]; then
  printf 'scratch label must not be empty and must not contain quotes or backslashes\n' >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required for safe GraphQL variable encoding\n' >&2
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

graphql() {
  local query variables output
  query="$1"
  variables="${2:-{}}"
  output="$(run_gateway graphql --query "$query" --variables "$variables")"
  if printf '%s' "$output" | python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(bool(data.get("errors")))'; then
    printf '%s\n' "$output"
    return
  fi
  printf 'GraphQL command failed:\n%s\n' "$output" >&2
  return 1
}

list_query='{ clockAlarms { label time isEnabled repeatDays } }'
graphql "$list_query" >/dev/null
printf 'Clock alarm read check passed.\n'

if [[ "$execute" != true ]]; then
  printf 'Read-only check complete. Rerun with --execute for scratch mutations.\n'
  exit 0
fi

active_label="$scratch_label"
cleanup() {
  local cleanup_variables
  cleanup_variables="$(python3 -c 'import json,sys; print(json.dumps({"input":{"label":sys.argv[1]}}))' "$active_label")"
  graphql 'mutation($input: DeleteClockAlarmInput!) { deleteClockAlarm(input: $input) { success } }' "$cleanup_variables" >/dev/null 2>&1 || true
}
trap cleanup EXIT

create_variables="$(python3 -c 'import json,sys; print(json.dumps({"input":{"time":"23:59","label":sys.argv[1],"repeatDays":["MONDAY","FRIDAY"]}}))' "$active_label")"
graphql 'mutation($input: CreateClockAlarmInput!) { createClockAlarm(input: $input) { success } }' "$create_variables" >/dev/null
printf 'Created scratch alarm: %s\n' "$active_label"

toggle_variables="$(python3 -c 'import json,sys; print(json.dumps({"input":{"label":sys.argv[1],"enabled":False}}))' "$active_label")"
graphql 'mutation($input: ToggleClockAlarmInput!) { toggleClockAlarm(input: $input) { success } }' "$toggle_variables" >/dev/null
printf 'Disabled scratch alarm.\n'

updated_label="$scratch_label-updated"
update_variables="$(python3 -c 'import json,sys; print(json.dumps({"input":{"label":sys.argv[1],"newLabel":sys.argv[2],"time":"23:58","repeatDays":["TUESDAY"]}}))' "$active_label" "$updated_label")"
graphql 'mutation($input: UpdateClockAlarmInput!) { updateClockAlarm(input: $input) { success } }' "$update_variables" >/dev/null
active_label="$updated_label"
printf 'Updated scratch alarm: %s\n' "$active_label"

delete_variables="$(python3 -c 'import json,sys; print(json.dumps({"input":{"label":sys.argv[1]}}))' "$active_label")"
graphql 'mutation($input: DeleteClockAlarmInput!) { deleteClockAlarm(input: $input) { success } }' "$delete_variables" >/dev/null
trap - EXIT
printf 'Deleted scratch alarm: %s\n' "$active_label"
printf 'Live Clock alarm verification completed.\n'
