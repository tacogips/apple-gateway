#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
manifest_path="$repo_root/packaging/shortcuts/manifest.json"
checklist_path="$repo_root/impl-plans/live-checklists/phase-5-clock-alarms-live.md"
prefix="${APPLE_GATEWAY_CLOCK_ALARMS_SHORTCUT_PREFIX:-}"
prefix_arg_provided=false
scratch_label="${APPLE_GATEWAY_CLOCK_ALARMS_SCRATCH_LABEL:-apple-gateway-live-check-$(date +%Y%m%d%H%M%S)}"
execute=false
read_only=false
allow_manual_cleanup=false

usage() {
  cat <<EOF
Usage:
  scripts/live-clock-alarms-check.sh [--read-only] [--execute] [--allow-manual-cleanup] [--prefix PREFIX] [--label LABEL]

Runs the Phase 5 Clock alarms live verification flow. Dry-run is the default
and checks GraphQL schema readiness plus exact expected shortcut names. It does
not run any shortcut or mutate Clock alarms.

Modes:
  default       Non-mutating schema and shortcuts-list readiness check.
  --read-only   Also runs PREFIX-get-alarms and validates JSON output.
  --execute     Runs read-only checks, then creates/toggles a scratch alarm.
                On macOS 26+, it also updates and deletes that scratch alarm.

Safety:
  - Does not request permissions or trigger TCC prompts.
  - Does not run shortcuts unless --read-only or --execute is passed.
  - Refuses --execute on macOS 13-15 unless --allow-manual-cleanup is passed,
    because update/delete shortcuts are unavailable and cleanup is manual.
  - Uses only the scratch label "$scratch_label".

Environment:
  APPLE_GATEWAY_BIN                         Use an existing apple-gateway binary.
  APPLE_GATEWAY_READER_BIN                  Use an existing apple-gateway-reader binary.
  APPLE_GATEWAY_CLOCK_ALARMS_SHORTCUT_PREFIX Shortcut prefix. Defaults to apple-gateway.
  APPLE_GATEWAY_CLOCK_ALARMS_SCRATCH_LABEL   Scratch alarm label.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      read_only=true
      shift
      ;;
    --execute)
      execute=true
      read_only=true
      shift
      ;;
    --allow-manual-cleanup)
      allow_manual_cleanup=true
      shift
      ;;
    --prefix)
      prefix="${2:-}"
      prefix_arg_provided=true
      shift 2
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

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required to parse %s\n' "$manifest_path" >&2
  exit 2
fi

if [[ ! -f "$manifest_path" ]]; then
  printf 'shortcut manifest not found: %s\n' "$manifest_path" >&2
  exit 2
fi

if [[ -z "$scratch_label" || "$scratch_label" == *\"* || "$scratch_label" == *\\* ]]; then
  printf 'scratch label must not be empty and must not contain quotes or backslashes\n' >&2
  exit 2
fi

manifest_shortcut_prefix="$(
  python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
prefix = manifest.get("shortcutPrefix")
if not isinstance(prefix, str) or not prefix:
    raise SystemExit("shortcutPrefix must be a non-empty string")
print(prefix)
PY
)"

if [[ -z "$prefix" && "$prefix_arg_provided" != true ]]; then
  prefix="$manifest_shortcut_prefix"
fi

if [[ -z "$prefix" ]]; then
  printf 'shortcut prefix must not be empty\n' >&2
  exit 2
fi

if [[ -n "${APPLE_GATEWAY_BIN:-}" ]]; then
  gateway=( "$APPLE_GATEWAY_BIN" )
else
  gateway=( swift run apple-gateway )
fi

if [[ -n "${APPLE_GATEWAY_READER_BIN:-}" ]]; then
  reader_gateway=( "$APPLE_GATEWAY_READER_BIN" )
else
  reader_gateway=( swift run apple-gateway-reader )
fi

run_gateway() {
  (
    cd "$repo_root"
    "${gateway[@]}" "$@"
  )
}

run_reader_gateway() {
  (
    cd "$repo_root"
    "${reader_gateway[@]}" "$@"
  )
}

json_field() {
  local expression
  expression="$1"
  python3 -c "import json, sys; data=json.load(sys.stdin); print($expression)"
}

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

validate_schema_readiness() {
  local schema_text schema_label required_query_fields required_mutation_fields disallowed_mutation_fields
  schema_text="$1"
  schema_label="$2"
  required_query_fields="$3"
  required_mutation_fields="$4"
  disallowed_mutation_fields="${5:-}"
  SCHEMA_TEXT="$schema_text" python3 - \
    "$schema_label" \
    "$required_query_fields" \
    "$required_mutation_fields" \
    "$disallowed_mutation_fields" <<'PY'
import os
import re
import sys

schema_label, required_query_fields, required_mutation_fields, disallowed_mutation_fields = sys.argv[1:5]
required_query = [field for field in required_query_fields.split(",") if field]
required_mutation = [field for field in required_mutation_fields.split(",") if field]
disallowed_mutation = [field for field in disallowed_mutation_fields.split(",") if field]
schema_text = os.environ["SCHEMA_TEXT"]

def root_fields(type_name):
    match = re.search(r"^type " + re.escape(type_name) + r" \{\n(?P<body>.*?)\n\}", schema_text, re.M | re.S)
    if match is None:
        return set()
    fields = set()
    for line in match.group("body").splitlines():
        line = line.strip()
        field = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(?:\(|:)", line)
        if field is not None:
            fields.add(field.group(1))
    return fields

query_names = root_fields("Query")
missing_query = [field for field in required_query if field not in query_names]
if missing_query:
    raise SystemExit(f"{schema_label} missing query field(s): {', '.join(missing_query)}")

mutation_names = root_fields("Mutation")
missing_mutation = [field for field in required_mutation if field not in mutation_names]
if missing_mutation:
    raise SystemExit(f"{schema_label} missing mutation field(s): {', '.join(missing_mutation)}")
unexpected_mutation = [field for field in disallowed_mutation if field in mutation_names]
if unexpected_mutation:
    raise SystemExit(f"{schema_label} unexpectedly exposes mutation field(s): {', '.join(unexpected_mutation)}")
PY
}

printf 'Live checklist: %s\n' "$checklist_path"

full_schema_output="$(run_gateway schema print --role full)"
clock_mutations="createClockAlarm,toggleClockAlarm,updateClockAlarm,deleteClockAlarm"
validate_schema_readiness "$full_schema_output" "full schema" "clockAlarms" "$clock_mutations"
reader_schema_output="$(run_reader_gateway schema print --role reader)"
validate_schema_readiness "$reader_schema_output" "reader schema" "clockAlarms" "" "$clock_mutations"
printf 'GraphQL schema readiness: full and reader expose clockAlarms; Clock alarm mutations are full-schema only.\n'

macos_major="$(sw_vers -productVersion | awk -F. '{print $1}')"
required_shortcuts_output="$(
  python3 - "$manifest_path" "$prefix" "$macos_major" <<'PY'
import json
import re
import sys

manifest_path, requested_prefix, macos_major_text = sys.argv[1:4]
try:
    macos_major = int(macos_major_text)
except ValueError:
    raise SystemExit(f"invalid macOS major version: {macos_major_text}")

with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

default_prefix = manifest.get("shortcutPrefix")
if not isinstance(default_prefix, str) or not default_prefix:
    raise SystemExit("shortcutPrefix must be a non-empty string")

shortcuts = manifest.get("shortcuts")
if not isinstance(shortcuts, list) or not shortcuts:
    raise SystemExit("shortcuts must be a non-empty list")

for index, shortcut in enumerate(shortcuts):
    if not isinstance(shortcut, dict):
        raise SystemExit(f"shortcut {index} must be an object")
    name = shortcut.get("name")
    availability = shortcut.get("availability")
    if not isinstance(name, str) or not name:
        raise SystemExit(f"shortcut {index} name must be a non-empty string")
    if not name.startswith(default_prefix):
        raise SystemExit(f"shortcut {name} does not start with shortcutPrefix {default_prefix}")
    if not isinstance(availability, str):
        raise SystemExit(f"shortcut {name} availability must be a string")
    match = re.fullmatch(r"macOS (\d+)\+", availability)
    if match is None:
        raise SystemExit(f"shortcut {name} availability must match 'macOS N+'")
    if macos_major >= int(match.group(1)):
        print(requested_prefix + name[len(default_prefix):])
PY
)"
required_shortcuts=()
while IFS= read -r shortcut; do
  if [[ -n "$shortcut" ]]; then
    required_shortcuts+=( "$shortcut" )
  fi
done <<< "$required_shortcuts_output"

if [[ "${#required_shortcuts[@]}" -eq 0 || -z "${required_shortcuts[0]}" ]]; then
  printf 'shortcut manifest produced no required shortcuts for macOS %s\n' "$macos_major" >&2
  exit 2
fi

installed="$(shortcuts list)"
missing=()
for shortcut in "${required_shortcuts[@]}"; do
  if ! printf '%s\n' "$installed" | grep -Fx -- "$shortcut" >/dev/null; then
    missing+=( "$shortcut" )
  fi
done

printf 'macOS major version: %s\n' "$macos_major"
printf 'Shortcut prefix: %s\n' "$prefix"
printf 'Required shortcuts checked: %s\n' "${required_shortcuts[*]}"

if [[ "${#missing[@]}" -gt 0 ]]; then
  printf 'Missing shortcuts: %s\n' "${missing[*]}" >&2
  cat >&2 <<EOF

Install or export the bridge shortcuts from Shortcuts.app using
packaging/shortcuts/SOURCE.md, then rerun this script.
EOF
  exit 6
fi

printf 'All required bridge shortcuts are installed.\n'

if [[ "$read_only" != true ]]; then
  printf 'Dry-run only. Rerun with --read-only to validate get-alarms JSON, or --execute for scratch mutations.\n'
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
get_output="$tmp_dir/get-alarms.json"
shortcuts run "$prefix-get-alarms" --output-path "$get_output" --output-type public.json >/dev/null

alarm_count="$(
  python3 - "$get_output" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
if data.get("contractVersion") != 1:
    raise SystemExit("contractVersion must be 1")
alarms = data.get("alarms")
if not isinstance(alarms, list):
    raise SystemExit("alarms must be a list")
for index, alarm in enumerate(alarms):
    if not isinstance(alarm, dict):
        raise SystemExit(f"alarm {index} must be an object")
    if not isinstance(alarm.get("label"), str):
        raise SystemExit(f"alarm {index} label must be a string")
    if not isinstance(alarm.get("time"), str):
        raise SystemExit(f"alarm {index} time must be a string")
    if not isinstance(alarm.get("isEnabled"), bool):
        raise SystemExit(f"alarm {index} isEnabled must be a boolean")
    repeat_days = alarm.get("repeatDays")
    if not isinstance(repeat_days, list) or not all(isinstance(day, str) for day in repeat_days):
        raise SystemExit(f"alarm {index} repeatDays must be a string list")
print(len(alarms))
PY
)"
printf 'Read-only get-alarms JSON is valid. Alarm count: %s\n' "$alarm_count"

if [[ "$execute" != true ]]; then
  printf 'Read-only check complete. Rerun with --execute to mutate a scratch Clock alarm.\n'
  exit 0
fi

if [[ "$macos_major" -lt 26 && "$allow_manual_cleanup" != true ]]; then
  cat >&2 <<EOF
Refusing --execute on macOS $macos_major without --allow-manual-cleanup.
Create/toggle shortcuts exist before macOS 26, but update/delete shortcuts do
not, so the scratch alarm may require manual cleanup in Clock.app.
EOF
  exit 4
fi

create_query='mutation($input: CreateClockAlarmInput!) { createClockAlarm(input: $input) { success alarm { label time isEnabled repeatDays } warning } }'
toggle_query='mutation($input: ToggleClockAlarmInput!) { toggleClockAlarm(input: $input) { success alarm { label isEnabled } warning } }'
update_query='mutation($input: UpdateClockAlarmInput!) { updateClockAlarm(input: $input) { success alarm { label time } warning } }'
delete_query='mutation($input: DeleteClockAlarmInput!) { deleteClockAlarm(input: $input) { success warning } }'

create_variables="$(python3 -c 'import json, sys; print(json.dumps({"input":{"time":"23:59","label":sys.argv[1],"repeatDays":[]}}))' "$scratch_label")"
graphql "$create_query" "$create_variables" >/dev/null
printf 'Created scratch alarm: %s\n' "$scratch_label"

toggle_variables="$(python3 -c 'import json, sys; print(json.dumps({"input":{"label":sys.argv[1],"enabled":False}}))' "$scratch_label")"
graphql "$toggle_query" "$toggle_variables" >/dev/null
printf 'Toggled scratch alarm off\n'

if [[ "$macos_major" -ge 26 ]]; then
  updated_label="$scratch_label-updated"
  update_variables="$(python3 -c 'import json, sys; print(json.dumps({"input":{"label":sys.argv[1],"newLabel":sys.argv[2],"time":"23:58"}}))' "$scratch_label" "$updated_label")"
  graphql "$update_query" "$update_variables" >/dev/null
  printf 'Updated scratch alarm: %s\n' "$updated_label"

  delete_variables="$(python3 -c 'import json, sys; print(json.dumps({"input":{"label":sys.argv[1]}}))' "$updated_label")"
  graphql "$delete_query" "$delete_variables" >/dev/null
  printf 'Deleted scratch alarm: %s\n' "$updated_label"
else
  cat <<EOF
Scratch alarm remains because delete is unavailable before macOS 26.
Remove this alarm manually in Clock.app: $scratch_label
EOF
fi

printf 'Live Clock alarms verification flow completed\n'
