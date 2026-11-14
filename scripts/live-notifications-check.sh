#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
read_only=false
source_scope=""

usage() {
  cat <<EOF
Usage:
  scripts/live-notifications-check.sh [--read-only --source gateway-helper|system-db|both]

Runs the Phase 4 Notifications live readiness flow. Dry-run is the default and
performs non-prompting checks only. It does not post notifications, request
notification permission, dismiss notifications, list delivered notifications,
or read the system notification database.

Modes:
  default      Permissions status plus full/reader schema readiness only.
  --read-only  Also runs source-scoped delivered-notification list queries.
               Requires --source gateway-helper, --source system-db, or
               --source both.

Safety:
  - Does not request or change notification permissions.
  - Does not post, dismiss, or otherwise mutate notifications.
  - Does not list delivered notifications unless --read-only is explicit.
  - Refuses SYSTEM_DB listing unless notificationDbFullDiskAccess is GRANTED.
  - Prints counts and notification ids from live reads.

Environment:
  APPLE_GATEWAY_BIN  Use an existing apple-gateway binary.

Checklist:
  impl-plans/live-checklists/phase-4-notifications-live.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      read_only=true
      shift
      ;;
    --source)
      source_scope="${2:-}"
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

case "$source_scope" in
  "" | gateway-helper | system-db | both)
    ;;
  *)
    printf 'invalid --source value: %s\n' "$source_scope" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$read_only" == true && -z "$source_scope" ]]; then
  printf '%s\n' '--read-only requires --source gateway-helper, --source system-db, or --source both' >&2
  usage >&2
  exit 2
fi

if [[ "$read_only" != true && -n "$source_scope" ]]; then
  printf '%s\n' '--source is only valid with --read-only' >&2
  usage >&2
  exit 2
fi

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

print_notification_summary() {
  local label output
  label="$1"
  output="$2"
  printf '%s\n' "$output" | python3 -c '
import json
import sys

label = sys.argv[1]
data = json.load(sys.stdin)
connection = data["data"]["notifications"]
edges = connection.get("edges") or []
print(f"{label} totalCount: {connection.get('totalCount')}")
print(f"{label} sampled edge count: {len(edges)}")
for edge in edges:
    node = edge.get("node") or {}
    print(
        f"{label} id={node.get('id')} "
        f"source={node.get('source')} "
        f"appBundleId={node.get('appBundleId')} "
        f"deliveredAt={node.get('deliveredAt')}"
    )
' "$label"
}

list_notifications() {
  local source label output
  source="$1"
  label="$2"
  output="$(graphql "{
  notifications(input: { source: $source, first: 20 }) {
    totalCount
    edges {
      node {
        id
        source
        appBundleId
        deliveredAt
      }
    }
  }
}")"
  print_notification_summary "$label" "$output"
}

validate_notifications_schema() {
  local schema_text schema_label required_mutation_signatures disallowed_mutation_names
  schema_text="$1"
  schema_label="$2"
  required_mutation_signatures="$3"
  disallowed_mutation_names="${4:-}"
  SCHEMA_TEXT="$schema_text" python3 - \
    "$schema_label" \
    "$required_mutation_signatures" \
    "$disallowed_mutation_names" <<'PY'
import os
import re
import sys

schema_label, required_mutation_signatures, disallowed_mutation_names = sys.argv[1:4]
required_query_signatures = [
    "notifications(input: NotificationSearchInput): DeliveredNotificationConnection!",
]
required_mutations = [
    field for field in required_mutation_signatures.split(",") if field
]
disallowed_mutations = [
    field for field in disallowed_mutation_names.split(",") if field
]
required_notification_sources = ["GATEWAY_HELPER", "SYSTEM_DB"]
schema_text = os.environ["SCHEMA_TEXT"]


def type_body(type_name):
    match = re.search(
        r"^type " + re.escape(type_name) + r" \{\n(?P<body>.*?)\n\}",
        schema_text,
        re.M | re.S,
    )
    return "" if match is None else match.group("body")


def root_field_signatures(type_name):
    return {line.strip() for line in type_body(type_name).splitlines() if line.strip()}


def root_field_names(type_name):
    names = set()
    for line in root_field_signatures(type_name):
        field = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(?:\(|:)", line)
        if field is not None:
            names.add(field.group(1))
    return names


def enum_values(enum_name):
    match = re.search(
        r"^enum " + re.escape(enum_name) + r" \{\n(?P<body>.*?)\n\}",
        schema_text,
        re.M | re.S,
    )
    if match is None:
        return set()
    values = set()
    for line in match.group("body").splitlines():
        stripped = line.strip()
        if re.match(r"^[A-Z][A-Z0-9_]*$", stripped):
            values.add(stripped)
    return values


query_signatures = root_field_signatures("Query")
missing_queries = [
    field for field in required_query_signatures if field not in query_signatures
]
if missing_queries:
    raise SystemExit(
        f"{schema_label} missing exact Query root field(s): {', '.join(missing_queries)}"
    )

mutation_signatures = root_field_signatures("Mutation")
missing_mutations = [
    field for field in required_mutations if field not in mutation_signatures
]
if missing_mutations:
    raise SystemExit(
        f"{schema_label} missing exact Mutation root field(s): {', '.join(missing_mutations)}"
    )

mutation_names = root_field_names("Mutation")
unexpected_mutations = [
    field for field in disallowed_mutations if field in mutation_names
]
if unexpected_mutations:
    raise SystemExit(
        f"{schema_label} unexpectedly exposes Mutation root field(s): {', '.join(unexpected_mutations)}"
    )

notification_source_values = enum_values("NotificationSource")
missing_sources = [
    value for value in required_notification_sources if value not in notification_source_values
]
if missing_sources:
    raise SystemExit(
        f"{schema_label} missing NotificationSource enum value(s): {', '.join(missing_sources)}"
    )
PY
}

printf 'Phase 4 Notifications live checklist: impl-plans/live-checklists/phase-4-notifications-live.md\n'

permissions_json="$(run_gateway permissions status --json)"
notification_fda_state="$(printf '%s' "$permissions_json" | json_field "data['data']['notificationDbFullDiskAccess']")"
notifications_helper_state="$(printf '%s' "$permissions_json" | json_field "data['data']['notificationsHelper']")"
printf 'Notifications helper permission: %s\n' "$notifications_helper_state"
printf 'Notification DB Full Disk Access: %s\n' "$notification_fda_state"

full_schema="$(run_gateway schema print --role full)"
reader_schema="$(run_gateway schema print --role reader)"

notification_mutation_signatures="postNotification(input: PostNotificationInput!): PostedNotification!,dismissNotifications(ids: [ID!]!): DismissResult!,dismissAllGatewayNotifications: DismissResult!"
notification_mutation_names="postNotification,dismissNotifications,dismissAllGatewayNotifications"
validate_notifications_schema "$full_schema" "full schema" "$notification_mutation_signatures"
validate_notifications_schema "$reader_schema" "reader schema" "" "$notification_mutation_names"

printf 'Schema readiness: exact Notifications Query root field is present in full and reader roles; exact mutation root fields are full-role only.\n'

if [[ "$read_only" != true ]]; then
  cat <<EOF
Dry-run only. No delivered notifications were listed and the system
notification database was not read.
Rerun with --read-only --source gateway-helper, --source system-db, or
--source both only after the operator accepts read-only live notification
metadata access.
EOF
  exit 0
fi

case "$source_scope" in
  gateway-helper)
    list_notifications "GATEWAY_HELPER" "GATEWAY_HELPER"
    ;;
  system-db)
    if [[ "$notification_fda_state" != "GRANTED" ]]; then
      cat >&2 <<EOF
Refusing --read-only --source system-db because notificationDbFullDiskAccess
is not GRANTED. Grant Full Disk Access manually to the host process, restart it
if required, then rerun this script. Do not automate this grant.
EOF
      exit 4
    fi
    list_notifications "SYSTEM_DB" "SYSTEM_DB"
    ;;
  both)
    list_notifications "GATEWAY_HELPER" "GATEWAY_HELPER"
    if [[ "$notification_fda_state" != "GRANTED" ]]; then
      cat >&2 <<EOF
Refusing SYSTEM_DB portion of --source both because
notificationDbFullDiskAccess is not GRANTED. GATEWAY_HELPER listing already
completed; grant Full Disk Access manually before rerunning for SYSTEM_DB.
EOF
      exit 4
    fi
    list_notifications "SYSTEM_DB" "SYSTEM_DB"
    ;;
esac

printf 'Read-only Notifications readiness completed for source scope: %s\n' "$source_scope"
