# Command

## Status

Draft (designed surface; current implementation is the `--help`/`--version`
scaffold only)

## Binaries

| Binary | Capability |
| --- | --- |
| `apple-gateway` | Full schema (Query + Mutation) |
| `apple-gateway-reader` | Read-only schema (Query only); mutations fail with `WRITE_DISABLED_IN_READER` |

Both share the same command surface:

```bash
<binary> [--config <path>] [--pretty] <command>
```

## Global Flags

| Flag / Env | Meaning |
| --- | --- |
| `--config <path>` | Config file (default `$XDG_CONFIG_HOME/apple-gateway/config.toml`) |
| `APPLE_GATEWAY_CONFIG` | Env override for the config path |
| `--pretty` | Pretty-print JSON output with sorted keys |
| `--help`, `--version`, `version` | Usual meanings |

All command output is JSON on stdout; diagnostics go to stderr; the exit
code follows the table in `design-apple-gateway.md#exit-codes`.

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
apple-gateway permissions request --domain calendar|reminders|notes|notifications
```

`status` never triggers TCC prompts. `request` deliberately does. Full
Disk Access and the Shortcuts bridge cannot be requested programmatically;
`status` prints manual instructions for them (see
`design-permissions.md`).

## config

```bash
apple-gateway config validate [--config <path>]
```

Validates the TOML file and resolved env overrides; reports
`CONFIG_INVALID` details.

## file

```bash
apple-gateway file download --key <key> [--key <key> ...] [--output-dir <dir>]
```

Materializes files referenced by `downloadKey` values from GraphQL results
(mail bodies/attachments, oversized note bodies, note attachments).
Outputs a JSON manifest of written paths.

## cache

```bash
apple-gateway cache prune [--all]
```

Clears materialized files and database snapshot copies under
`storage.cache_dir`.

## Alarm Bridge Setup

Clock-alarm mutations require the bridge shortcuts to be installed once:

```bash
open packaging/shortcuts/apple-gateway-get-alarms.shortcut   # etc.
apple-gateway permissions status    # reports shortcutsClockBridge
```

See `design-alarms.md` and `packaging/shortcuts/README.md`.
