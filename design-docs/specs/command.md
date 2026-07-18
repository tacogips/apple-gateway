# Command

## Status

Draft (Phase 0 TASK-007 normalizes the shared command frame and smoke-test
contract over the already implemented Phase 0 command surfaces)

## Binaries

| Binary | Capability |
| --- | --- |
| `apple-gateway` | Full schema (Query + Mutation) |
| `apple-gateway-reader` | Read-only schema (Query only); mutations fail with `WRITE_DISABLED_IN_READER` |

Both share the same command surface:

```bash
<binary> [--config <path>] [--pretty] <command>
```

Invoking either binary without arguments prints that binary's help text and
exits successfully. The reader help uses `apple-gateway-reader` in its usage
examples rather than the full-access executable name.

The binary decides only the role passed into `AppleGatewayCore`: `.full`
for `apple-gateway`, `.reader` for `apple-gateway-reader`. All user-visible
command behavior is shared in the core CLI frame. The executable
`main.swift` files do not own command tables, JSON rendering, or business
validation; they pass `CommandLine.arguments` and `ProcessInfo.processInfo`
environment into the core runner and exit with its returned code.

During Phase 0 TASK-001, `apple-gateway-reader` may expose the same
scaffold commands as `apple-gateway` while the GraphQL runtime is not yet
implemented, but the entrypoint must already be role-split so TASK-003 can
enforce reader schema validation without changing executable boundaries.

## Global Flags

| Flag / Env | Meaning |
| --- | --- |
| `--config <path>` | Config file (default `$XDG_CONFIG_HOME/apple-gateway/config.toml`) |
| `APPLE_GATEWAY_CONFIG` | Env override for the config path |
| `--pretty` | Pretty-print JSON output with sorted keys |
| `--help`, `--version`, `version` | Usual meanings |

JSON-producing commands write shared JSON envelopes on stdout. Intentional
non-JSON commands, such as schema SDL, human permission prompts, help, and
version output, also write their business output on stdout but are outside
the JSON envelope contract. Diagnostics go to stderr; the exit code follows
the table in `design-apple-gateway.md#exit-codes`.

### TASK-007 Command Frame Contract

TASK-007 makes the shared core command frame authoritative for both
executables. Global flags are parsed before command dispatch and are removed
from the argument stream passed to subcommand parsing:

```bash
apple-gateway --config ./config.toml --pretty graphql --query '{ permissions { calendars } }'
apple-gateway-reader --pretty graphql --query 'mutation { noop }'
```

`--config <path>` and `--config=<path>` are accepted only as global flags
before the command, except that `config validate [--config <path>]` keeps its
existing command-local spelling as a compatibility alias. If both a global
config path and `APPLE_GATEWAY_CONFIG` are present, the global flag selects
the config file. If `config validate` receives both the global flag and its
command-local alias, the global flag is the selected path and the duplicate
local flag is a usage error so automation does not silently validate a
different file than later commands would use.

`--pretty` is accepted as a global flag before the command and applies to
JSON-producing commands: `graphql`, `config validate`, `permissions status
--json`, `file download`, and `cache prune`. `graphql --pretty` remains an
accepted command-local alias. Non-JSON commands (`schema print`, human
`permissions status`, `permissions request`, `--help`, `--version`, and
`version`) ignore JSON pretty formatting because their output is not an
envelope.

The frame supports `--flag value` and `--flag=value` for value flags and
preserves repeated flags where the command defines repetition, currently
`file download --key`. Unknown commands, unknown flags, missing flag values,
mutually exclusive flag violations, and other routing failures are CLI usage
errors: no stdout, a diagnostic on stderr, and exit code `2`.

Once a JSON-producing command has been selected, business and validation
failures use the shared JSON envelope on stdout and the mapped business exit
code. Stderr is reserved for diagnostics that are not part of the business
payload, such as usage errors or unexpected process failures.

`AppleGatewaySmokeTests` is an executable SwiftPM target linked against
`AppleGatewayCore`. It exercises the same command-line frame used by the
production executables with in-memory fake providers/materializers injected
through core seams. The smoke executable must not add hidden production CLI
test-mode flags and must not use live TCC prompts, Apple Events, UI automation,
Mail stores, notification databases, signing, notarization, or release
workflows.

## graphql

The only business API surface.

```bash
apple-gateway graphql --query '<graphql>'
apple-gateway graphql --query-file <path>
apple-gateway graphql --query-file q.graphql --variables '{"first": 10}'
apple-gateway graphql --query-file q.graphql --variables-file vars.json
```

- Exactly one of `--query` / `--query-file`.
- At most one of `--variables` / `--variables-file`; value must be a JSON
  object.

Examples:

```bash
# List calendars
apple-gateway graphql --query '{ calendars { id title sourceTitle allowsModifications } }'

# This week's events
apple-gateway graphql --query-file events.graphql \
  --variables '{"start": "2026-07-01T00:00:00+09:00", "end": "2026-07-08T00:00:00+09:00"}'

# Create a reminder with an alarm 10 minutes before
apple-gateway graphql --query 'mutation($in: CreateReminderInput!) {
  createReminder(input: $in) { id title dueDate }
}' --variables '{"in": {"title": "Ship release", "dueDate": "2026-07-03T18:00:00+09:00",
  "alarms": [{"relativeOffsetSeconds": -600}]}}'

# Search notes
apple-gateway graphql --query '{ notes(input: { query: "meeting", first: 5 }) {
  edges { node { id name snippet modificationDate } } totalCount } }'

# Create a note from plaintext; bodyText is converted to Notes HTML
apple-gateway graphql --query 'mutation($in: CreateNoteInput!) {
  createNote(input: $in) { id name bodyHtml modificationDate }
}' --variables '{"in": {"title": "Release notes", "bodyText": "Ship checklist\nVerify build"}}'

# Append HTML to a note; Notes HTML round-tripping is lossy
apple-gateway graphql --query 'mutation($in: UpdateNoteBodyInput!) {
  updateNoteBody(input: $in) { id name bodyHtml modificationDate }
}' --variables '{"in": {"noteId": "x-coredata://...", "mode": "APPEND",
  "bodyHtml": "<div>Follow-up</div>"}}'

# Recent unread mail
apple-gateway graphql --query '{ mailMessages(input: { unreadOnly: true, first: 10 }) {
  edges { node { subject from { raw } dateReceived snippet
    files { bodyText { downloadKey } } } } } }'

# Post a notification with actions and wait for the user
apple-gateway graphql --query 'mutation {
  postNotification(input: { title: "Deploy?", actions: ["Yes", "No"], waitSeconds: 60 }) {
    id activation { kind actionLabel } } }'
```

## schema

```bash
apple-gateway schema print [--role full|reader]
```

Prints the SDL rendered from the runtime schema registry (always in sync
with execution behavior).

## permissions

```bash
apple-gateway permissions status [--json]
apple-gateway permissions request --domain calendar|reminders|notes|notifications|clock-alarms
```

`status` never triggers TCC prompts. `request` deliberately does. Full Disk
Access cannot be requested programmatically; `status` prints manual
instructions for it (see `design-permissions.md`).

`status --json` returns the same permission-state fields exposed by
GraphQL `PermissionsStatus`: `calendars`, `reminders`, `notesAutomation`,
`mailFullDiskAccess`, `notificationsHelper`,
`notificationDbFullDiskAccess`, and `clockAutomation`. States use the
`PermissionState` vocabulary from `design-apple-gateway.md`. The JSON form
may include per-field diagnostic details, but the state fields remain stable
for clients.

`request --domain calendar` must trigger only the EventKit calendar request
path. The other prompt-capable request domains are isolated the same way:
reminders uses EventKit reminders, notes uses Notes automation, clock-alarms
uses Accessibility plus System Events automation, and notifications uses an
already installed and configured notifier helper. If
the helper is not configured or cannot be resolved, the notifications request
reports an unavailable `UNKNOWN` diagnostic; TASK-005 does not create,
install, sign, package, or launch `AppleGatewayNotifier.app`. Non-requestable
domains continue to be reported by `status` with manual remediation text.

Permission-domain discovery uses the same complete value list everywhere:
`calendar|reminders|notes|notifications|clock-alarms`. Both top-level `--help`
and the usage diagnostic produced when `permissions request` omits `--domain`
must include that list. Regression tests cover both surfaces so a supported
request domain cannot remain callable while disappearing from CLI guidance.

## config

```bash
apple-gateway config validate [--config <path>]
```

Validates the TOML file and resolved env overrides; reports
`CONFIG_INVALID` details. A missing config file is valid and resolves to
the full default configuration. `--config` selects the file before
`APPLE_GATEWAY_CONFIG`; value precedence remains defaults, then file
values, then `APPLE_GATEWAY_<SECTION>_<KEY>` overrides.

Successful validation prints JSON describing the resolved config source and
normalized values without performing permission probes or creating files.
Failure prints the standard error envelope with `CONFIG_INVALID`, including
the invalid file location or environment variable name. Unknown commands or
bad flags are still usage errors; only invalid config content is
`CONFIG_INVALID`.

## file

```bash
apple-gateway file download --key <key> [--key <key> ...] [--output-dir <dir>]
```

Materializes files referenced by `downloadKey` values from GraphQL results
(mail bodies/attachments, oversized note bodies, note attachments).
At least one `--key` is required. Repeated `--key` flags are allowed; each
key is decoded and validated independently before any filesystem access.

Without `--output-dir`, written files are rooted under
`storage.cache_dir` in the file store's managed `downloads/` layout. With
`--output-dir`, that directory becomes the output root after normalization.
The command rejects malformed or forged keys, unknown key versions,
unknown domain/kind pairs, unsafe suggested filenames, and any final
destination that would escape its root. These failures use the shared
JSON error envelope with `INVALID_DOWNLOAD_KEY` when the key is invalid
and `FILE_OPERATION_FAILED` when a validated operation cannot be completed.

Success prints a shared JSON envelope whose `data.files` array is the
manifest of materialized files:

```json
{
  "data": {
    "files": [{
      "downloadKey": "agdk1...",
      "domain": "mail",
      "kind": "BODY_TEXT",
      "path": "~/.cache/apple-gateway/downloads/mail/.../body.txt"
    }]
  },
  "extensions": {
    "requestId": "uuid"
  }
}
```

## cache

```bash
apple-gateway cache prune [--all]
```

Clears materialized files and database snapshot copies under the managed
subdirectories of `storage.cache_dir`. The command normalizes the cache
root first, refuses empty roots and filesystem roots, never follows
symlinks out of the cache, and refuses to delete any candidate path whose
resolved location is outside `storage.cache_dir`.

`cache prune` preserves key validation material by default so previously
issued keys can still be validated after cached bytes are removed.
`cache prune --all` may remove all managed cache contents, including key
validation material, which can invalidate old download keys. Both modes
leave the cache root directory itself in place and report a JSON envelope
with counts of removed files/directories.

## Clock Alarm Automation Setup

Clock-alarm operations require Accessibility and Automation permissions for
the responsible terminal or installed executable:

```bash
apple-gateway permissions request --domain clock-alarms
scripts/live-clock-alarms-check.sh
apple-gateway permissions status    # reports clockAutomation
```

See `design-alarms.md` for the self-contained Clock.app accessibility adapter.
