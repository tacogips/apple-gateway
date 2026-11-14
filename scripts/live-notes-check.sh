#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
read_only=false

usage() {
  cat <<EOF
Usage:
  scripts/live-notes-check.sh [--read-only]

Runs the Phase 2 Apple Notes live readiness flow. Dry-run is the default and
performs non-prompting checks only. It does not query live Notes data, trigger
Automation prompts, or mutate Notes.

Modes:
  default      Permissions and schema readiness only.
  --read-only  Also runs limited live Notes metadata queries after Notes
               Automation is already GRANTED. This may read private Notes
               account, folder, and note metadata.

Safety:
  - Does not request or change Notes Automation permission.
  - Does not mutate Notes data.
  - Refuses --read-only unless Notes Automation is GRANTED.
  - Read-only mode queries only noteAccounts, noteFolders, and notes(first: 5)
    with small metadata fields.

Environment:
  APPLE_GATEWAY_BIN  Use an existing apple-gateway binary.

Checklist:
  impl-plans/live-checklists/phase-2-apple-notes-live.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      read_only=true
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

printf 'Phase 2 Apple Notes live checklist: impl-plans/live-checklists/phase-2-apple-notes-live.md\n'

permissions_json="$(run_gateway permissions status --json)"
notes_automation_state="$(printf '%s' "$permissions_json" | json_field "data['data']['notesAutomation']")"
printf 'Notes Automation: %s\n' "$notes_automation_state"

full_schema="$(run_gateway schema print --role full)"
reader_schema="$(run_gateway schema print --role reader)"

schema_root_block() {
  local schema root_type
  schema="$1"
  root_type="$2"
  printf '%s\n' "$schema" | awk -v root="type ${root_type} {" '
    $0 == root { in_root = 1; next }
    in_root && $0 == "}" { exit }
    in_root { print }
  '
}

check_root_field_contains() {
  local schema role root_type description expected root_block
  schema="$1"
  role="$2"
  root_type="$3"
  description="$4"
  expected="$5"
  root_block="$(schema_root_block "$schema" "$root_type")"
  if ! printf '%s\n' "$root_block" | grep -Fxq "$expected"; then
    printf '%s schema %s root missing %s: %s\n' "$role" "$root_type" "$description" "$expected" >&2
    exit 1
  fi
}

check_root_field_absent() {
  local schema role root_type description unexpected root_block
  schema="$1"
  role="$2"
  root_type="$3"
  description="$4"
  unexpected="$5"
  root_block="$(schema_root_block "$schema" "$root_type")"
  if printf '%s\n' "$root_block" | grep -Fxq "$unexpected"; then
    printf '%s schema %s root unexpectedly exposes %s: %s\n' "$role" "$root_type" "$description" "$unexpected" >&2
    exit 1
  fi
}

for expected in \
  "  noteAccounts: [NoteAccount!]!" \
  "  noteFolders(accountId: ID): [NoteFolder!]!" \
  "  notes(input: NoteSearchInput!): NoteConnection!" \
  "  note(noteId: ID!): Note"; do
  check_root_field_contains "$full_schema" full Query "Notes query field" "$expected"
  check_root_field_contains "$reader_schema" reader Query "Notes query field" "$expected"
done

for expected in \
  "  createNote(input: CreateNoteInput!): Note!" \
  "  updateNoteBody(input: UpdateNoteBodyInput!): Note!" \
  "  deleteNote(noteId: ID!): DeleteResult!" \
  "  moveNote(noteId: ID!, folderId: ID!): Note!"; do
  check_root_field_contains "$full_schema" full Mutation "Notes mutation field" "$expected"
  check_root_field_absent "$reader_schema" reader Mutation "Notes mutation field" "$expected"
done

printf 'Schema readiness: exact Notes Query root fields are present in full and reader roles; exact Notes Mutation root fields are full-schema only.\n'

if [[ "$read_only" != true ]]; then
  cat <<EOF
Dry-run only. No live Notes query was performed.
Rerun with --read-only only after the operator has granted Notes Automation
and accepted that private Notes metadata may be read.
EOF
  exit 0
fi

if [[ "$notes_automation_state" != "GRANTED" ]]; then
  cat >&2 <<EOF
Refusing --read-only because Notes Automation is not GRANTED.
Grant Notes Automation manually to the host process, restart it if required,
then rerun this script. Do not automate this grant.
EOF
  exit 4
fi

accounts_output="$(graphql '{ noteAccounts { id name isDefault } }')"
account_count="$(printf '%s' "$accounts_output" | json_field "len(data['data']['noteAccounts'])")"
printf 'Notes account count: %s\n' "$account_count"

folders_output="$(graphql '{ noteFolders { id accountId name noteCount } }')"
folder_count="$(printf '%s' "$folders_output" | json_field "len(data['data']['noteFolders'])")"
printf 'Notes folder count: %s\n' "$folder_count"

notes_output="$(graphql 'query($input: NoteSearchInput!) {
  notes(input: $input) {
    totalCount
    edges {
      node {
        id
        folderId
        name
        creationDate
        modificationDate
        snippet
      }
    }
  }
}' '{"input":{"first":5}}')"
note_total="$(printf '%s' "$notes_output" | json_field "data['data']['notes']['totalCount']")"
edge_count="$(printf '%s' "$notes_output" | json_field "len(data['data']['notes']['edges'])")"
printf 'Notes totalCount: %s\n' "$note_total"
printf 'Notes sampled edge count: %s\n' "$edge_count"
printf 'Read-only Notes readiness completed. Scratch write verification remains a manual checklist step.\n'
