#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
read_only=false
account_id="${APPLE_GATEWAY_MAIL_LIVE_ACCOUNT_ID:-}"
mailbox_id="${APPLE_GATEWAY_MAIL_LIVE_MAILBOX_ID:-}"

usage() {
  cat <<EOF
Usage:
  scripts/live-mail-check.sh [--read-only] [--account-id ID] [--mailbox-id ID]

Runs the Phase 3 Mail live readiness flow. Dry-run is the default and performs
non-prompting checks only. It does not read the live Mail store, download Mail
files, request Full Disk Access, or print private Mail paths.

Modes:
  default      Permissions and schema readiness only.
  --read-only  Also runs limited live Mail read queries after Full Disk Access
               is already GRANTED. This may read private Mail metadata.

Safety:
  - Does not request or change Full Disk Access.
  - Does not mutate Mail data.
  - Does not download message bodies or attachments.
  - Prints only counts and gateway ids from live reads.

Environment:
  APPLE_GATEWAY_BIN                   Use an existing apple-gateway binary.
  APPLE_GATEWAY_MAIL_LIVE_ACCOUNT_ID  Optional account id for --read-only.
  APPLE_GATEWAY_MAIL_LIVE_MAILBOX_ID  Optional mailbox id for --read-only.

Checklist:
  impl-plans/live-checklists/phase-3-apple-mail-live.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      read_only=true
      shift
      ;;
    --account-id)
      account_id="${2:-}"
      shift 2
      ;;
    --mailbox-id)
      mailbox_id="${2:-}"
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

printf 'Phase 3 Mail live checklist: impl-plans/live-checklists/phase-3-apple-mail-live.md\n'

permissions_json="$(run_gateway permissions status --json)"
mail_fda_state="$(printf '%s' "$permissions_json" | json_field "data['data']['mailFullDiskAccess']")"
printf 'Mail Full Disk Access: %s\n' "$mail_fda_state"

full_schema="$(run_gateway schema print --role full)"
reader_schema="$(run_gateway schema print --role reader)"

validate_mail_query_fields() {
  local role schema missing
  role="$1"
  schema="$2"
  missing="$(
    printf '%s\n' "$schema" | python3 -c '
import sys

expected = [
    "mailAccounts: [MailAccount!]!",
    "mailboxes(accountId: ID): [Mailbox!]!",
    "mailMessages(input: MailSearchInput!): MailMessageConnection!",
    "mailMessage(messageId: ID!): MailMessage",
]

def root_fields(type_name):
    fields = []
    in_root = False
    for line in sys.stdin:
        stripped = line.strip()
        if stripped in ("type %s {" % type_name, "extend type %s {" % type_name):
            in_root = True
            continue
        if in_root and stripped == "}":
            in_root = False
            continue
        if in_root and stripped and not stripped.startswith("#"):
            fields.append(stripped)
    return fields

query_fields = set(root_fields("Query"))
for field in expected:
    if field not in query_fields:
        print(field)
'
  )"
  if [[ -n "$missing" ]]; then
    printf '%s schema missing exact Mail Query root field(s):\n%s\n' "$role" "$missing" >&2
    exit 1
  fi
}

validate_mail_query_fields full "$full_schema"
validate_mail_query_fields reader "$reader_schema"

mail_mutation_fields="$(
  printf '%s\n' "$full_schema" | python3 -c '
import sys

def root_fields(type_name):
    fields = []
    in_root = False
    for line in sys.stdin:
        stripped = line.strip()
        if stripped in ("type %s {" % type_name, "extend type %s {" % type_name):
            in_root = True
            continue
        if in_root and stripped == "}":
            in_root = False
            continue
        if in_root and stripped and not stripped.startswith("#"):
            fields.append(stripped)
    return fields

for signature in root_fields("Mutation"):
    field_name = signature.split("(", 1)[0].split(":", 1)[0].strip()
    if "mail" in field_name.lower():
        print(signature)
'
)"
if [[ -n "$mail_mutation_fields" ]]; then
  printf 'full schema exposes Mail Mutation root field(s):\n%s\n' "$mail_mutation_fields" >&2
  exit 1
fi

printf 'Schema readiness: exact Mail Query root fields present in full and reader roles; no Mail Mutation root fields detected.\n'

if [[ "$read_only" != true ]]; then
  cat <<EOF
Dry-run only. No live Mail store was queried.
Rerun with --read-only only after the operator has granted Full Disk Access
and accepted that private Mail metadata may be read.
EOF
  exit 0
fi

if [[ "$mail_fda_state" != "GRANTED" ]]; then
  cat >&2 <<EOF
Refusing --read-only because Mail Full Disk Access is not GRANTED.
Grant Full Disk Access manually to the host process, restart it if required,
then rerun this script. Do not automate this grant.
EOF
  exit 4
fi

accounts_output="$(graphql '{ mailAccounts { id name kind } }')"
account_count="$(printf '%s' "$accounts_output" | json_field "len(data['data']['mailAccounts'])")"
printf 'Mail account count: %s\n' "$account_count"

mailbox_variables="$(python3 -c 'import json, sys; account=sys.argv[1] or None; print(json.dumps({"accountId": account}))' "$account_id")"
mailboxes_output="$(graphql 'query($accountId: ID) { mailboxes(accountId: $accountId) { id accountId name totalCount unreadCount } }' "$mailbox_variables")"
mailbox_count="$(printf '%s' "$mailboxes_output" | json_field "len(data['data']['mailboxes'])")"
printf 'Mailbox count%s: %s\n' "$([[ -n "$account_id" ]] && printf ' for selected account' || true)" "$mailbox_count"

search_variables="$(
  python3 - "$account_id" "$mailbox_id" <<'PY'
import json
import sys

account_id = sys.argv[1] or None
mailbox_id = sys.argv[2] or None
payload = {"input": {"first": 5}}
if account_id:
    payload["input"]["accountId"] = account_id
if mailbox_id:
    payload["input"]["mailboxId"] = mailbox_id
print(json.dumps(payload))
PY
)"
messages_output="$(graphql 'query($input: MailSearchInput!) {
  mailMessages(input: $input) {
    totalCount
    edges {
      node {
        id
        mailboxId
        dateReceived
        isRead
        isFlagged
        hasAttachments
        files {
          bodyText { kind filename byteSize downloadKey }
          bodyHtml { kind filename byteSize downloadKey }
          rawSource { kind filename byteSize downloadKey }
          attachments { kind filename mimeType byteSize downloadKey }
        }
      }
    }
  }
}' "$search_variables")"
message_total="$(printf '%s' "$messages_output" | json_field "data['data']['mailMessages']['totalCount']")"
edge_count="$(printf '%s' "$messages_output" | json_field "len(data['data']['mailMessages']['edges'])")"
printf 'Mail message totalCount: %s\n' "$message_total"
printf 'Mail message sampled edge count: %s\n' "$edge_count"
printf 'Read-only Mail readiness completed. Body and attachment downloads remain manual checklist steps.\n'
