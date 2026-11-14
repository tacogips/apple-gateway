# apple-gateway Design

## Status

Draft (design approved for implementation planning; no implementation yet)

## Overview

`apple-gateway` is a macOS command line tool and Swift library that exposes
Apple's built-in productivity apps through a single GraphQL API surface:

1. Apple Calendar: full read and write of calendars and events
2. Apple Reminders: full read and write of reminder lists and reminders
3. Alarms: full EventKit alarm (`EKAlarm`) control on events and reminders,
   plus direct accessibility automation for Clock.app alarms
4. Apple Notes: listing, search, and writing of notes
5. Apple Mail: read-only message retrieval
6. Notifications: posting, listing, and dismissal of user notifications

The design and implementation policy is based on the sibling project
`mail-gateway`: zero external package dependencies, a single core library
with thin role-split executables, a one-shot `graphql` CLI command as the
only business API surface, JSON envelope output with machine-readable error
codes and exit codes, TOML configuration, go-task automation, Nix dev shell,
and Homebrew formula/cask release surfaces.

Platform mechanism choices are grounded in
`design-docs/references/macos-platform-research-2026-07.md`.

## Goals

- Every business operation is a GraphQL query or mutation; auxiliary CLI
  commands exist only for config, permissions, schema inspection, and file
  materialization.
- Deterministic, script-friendly behavior for AI-agent and automation
  callers: bounded output, file-based large payloads, stable error codes.
- Zero external SwiftPM dependencies. Foundation, CryptoKit for file-store
  key authentication, EventKit, `libsqlite3`, and UserNotifications
  (helper app only) are the only platform frameworks used.
- Honest platform behavior: capabilities that macOS does not support are
  reported with explicit error codes, never silently degraded.

## Non-Goals

- No GraphQL server / daemon mode in v1 (same decision as mail-gateway v1).
- No mail sending or mail mutation of any kind (mail-gateway owns outbound
  mail).
- No writing to private databases (Notes store, Envelope Index, Notification
  Center DB, Clock alarm store). Private stores are read-only sources.
- No iOS support. macOS 14+ only.
- No sandboxed / Mac App Store distribution.

## Product Surface

### Binaries

| Binary | Schema | Purpose |
| --- | --- | --- |
| `apple-gateway` | Query + Mutation | Full read/write gateway |
| `apple-gateway-reader` | Query only | Read-only gateway safe to hand to untrusted automation |

Both are thin `main.swift` entry points over the `AppleGatewayCore` library.
Write enforcement in the reader is schema-based: the reader executes against
a schema that registers no Mutation type, so any mutation document fails
validation with `WRITE_DISABLED_IN_READER`. This deliberately fixes the
string-scan enforcement weakness identified in mail-gateway's 2026-07
implementation review.

Two binaries (not one per domain) keeps the number of per-binary TCC grants
manageable while preserving the mail-gateway role-split pattern.

### Library

`AppleGatewayCore` is a public SwiftPM library product. Library consumers
call the same executor entry points the CLI uses:

```swift
let result = try executeGraphQL(
  config: config,
  role: .full,            // or .reader
  query: "...",
  variables: [:]          // JSON-decoded variables object
)
// result.body: [String: Any] GraphQL envelope
// result.exitCode: process exit code the CLI would use
```

### Transport

One-shot CLI execution only:

```bash
apple-gateway graphql --query '{ calendars { id title } }'
apple-gateway graphql --query-file ./q.graphql --variables '{"first": 20}'
```

Unlike mail-gateway v1, `--variables` and `--variables-file` are supported
from the start. With six domains the schema is too large for inline-literal
queries to stay ergonomic, and the proper GraphQL parser (see
`design-graphql-runtime.md`) makes variable substitution cheap to support.
This deviation from the base project is recorded in
`design-docs/user-qa/resolved-apple-gateway-defaults.md`.

## Module Layout

```
AppleGatewayCore (library)
  GraphQLRuntime/     lexer, parser, schema registry, executor, SDL printer
  CLI/                command routing, flag parsing, output formatting
  Config/             TOML subset parser, env overrides, validation
  Permissions/        TCC probes, permission requests, doctor report
  FileStore/          materialized-file cache, download keys, path safety
  AppleEventBridge/   osascript JXA runner: batching, timeouts, retry
  Domains/
    CalendarKitAdapter/     EventKit events + calendars (+ EKAlarm)
    RemindersAdapter/       EventKit reminders (+ EKAlarm)
    ClockAlarmsAdapter/     JXA accessibility automation for Clock.app alarms
    NotesAdapter/           Apple Events (JXA) to Notes.app
    MailAdapter/            Envelope Index SQLite + .emlx parsing
    NotificationsAdapter/   helper app driver + usernoted DB reader

AppleGatewayCLI        (executable apple-gateway)
AppleGatewayReaderCLI  (executable apple-gateway-reader)
AppleGatewayNotifier   (helper .app target, UNUserNotificationCenter)
AppleGatewayCoreTests  (swift-testing unit tests)
AppleGatewaySmokeTests (executable smoke tests, fake adapters)
```

Each domain adapter implements a protocol boundary (the analog of
mail-gateway's `MailProviderAdapter`) so tests substitute fakes and future
mechanisms (for example a direct-SQLite Notes fast-read) slot in without
schema changes:

```swift
protocol CalendarProviding: Sendable { ... }
protocol RemindersProviding: Sendable { ... }
protocol ClockAlarmsProviding: Sendable { ... }
protocol NotesProviding: Sendable { ... }
protocol MailProviding: Sendable { ... }
protocol NotificationsProviding: Sendable { ... }
```

## Mechanism Decisions Per Domain

| Domain | Mechanism | Rationale |
| --- | --- | --- |
| Calendar, Reminders, EK alarms | EventKit direct | Full CRUD, fast, works from bare CLI; AppleScript alternative is minutes-slow |
| Clock alarms | JXA accessibility automation | Clock has no public alarm API or AppleScript dictionary |
| Notes | Batched Apple Events (JXA via osascript) | Only writable path; store SQLite is read-only in practice |
| Mail | Envelope Index SQLite (immutable) + .emlx | ~1000x faster than AppleScript, no Mail.app needed, immune to Tahoe -1712 regression |
| Notifications post/dismiss-own | Bundled `AppleGatewayNotifier.app` | UNUserNotificationCenter requires a real .app; enables actions, reply, removal |
| Notifications system-wide list | usernoted db2 SQLite (read-only copy) | No public API exists; FDA-gated |

Details per domain live in dedicated specs:

- `design-calendar-reminders.md`
- `design-alarms.md`
- `design-apple-notes.md`
- `design-apple-mail.md`
- `design-notifications.md`
- `design-graphql-runtime.md`
- `design-permissions.md`

## GraphQL Schema

GraphQL is the only business API surface. The canonical schema follows.
`apple-gateway-reader` serves the same schema minus the `Mutation` type.

### Scalars and Shared Types

```graphql
"ISO 8601 / RFC 3339 timestamp with timezone offset"
scalar DateTime

type PageInfo {
  hasNextPage: Boolean!
  endCursor: String
}

enum PermissionState {
  GRANTED
  DENIED
  NOT_DETERMINED
  WRITE_ONLY      # EventKit legacy grant; insufficient for reads
  NOT_REQUIRED
  UNKNOWN
}

type PermissionsStatus {
  calendars: PermissionState!
  reminders: PermissionState!
  notesAutomation: PermissionState!
  mailFullDiskAccess: PermissionState!
  notificationsHelper: PermissionState!
  notificationDbFullDiskAccess: PermissionState!
  clockAutomation: PermissionState!
}
```

### Query Root

```graphql
type Query {
  # Cross-cutting
  permissions: PermissionsStatus!

  # Calendar
  calendars(entityType: CalendarEntityType): [Calendar!]!
  events(input: EventSearchInput!): EventConnection!
  event(eventId: ID!, occurrenceDate: DateTime): CalendarEvent

  # Reminders
  reminderLists: [Calendar!]!
  reminders(input: ReminderSearchInput!): ReminderConnection!
  reminder(reminderId: ID!): Reminder

  # Clock alarms (Accessibility and System Events automation required)
  clockAlarms: [ClockAlarm!]!

  # Notes
  noteAccounts: [NoteAccount!]!
  noteFolders(accountId: ID): [NoteFolder!]!
  notes(input: NoteSearchInput!): NoteConnection!
  note(noteId: ID!): Note

  # Mail (read-only domain)
  mailAccounts: [MailAccount!]!
  mailboxes(accountId: ID): [Mailbox!]!
  mailMessages(input: MailSearchInput!): MailMessageConnection!
  mailMessage(messageId: ID!): MailMessage

  # Notifications
  notifications(input: NotificationSearchInput): DeliveredNotificationConnection!
}
```

### Mutation Root (absent in reader schema)

```graphql
type Mutation {
  # Calendar
  createCalendar(input: CreateCalendarInput!): Calendar!
  deleteCalendar(calendarId: ID!): DeleteResult!
  createEvent(input: CreateEventInput!): CalendarEvent!
  updateEvent(input: UpdateEventInput!): CalendarEvent!
  deleteEvent(eventId: ID!, span: RecurrenceSpan = THIS_EVENT): DeleteResult!

  # Reminders
  createReminderList(input: CreateReminderListInput!): Calendar!
  createReminder(input: CreateReminderInput!): Reminder!
  updateReminder(input: UpdateReminderInput!): Reminder!
  deleteReminder(reminderId: ID!): DeleteResult!
  setReminderCompleted(reminderId: ID!, completed: Boolean!): Reminder!

  # EventKit alarms (also settable inline in create/update inputs)
  setEventAlarms(eventId: ID!, alarms: [AlarmInput!]!,
                 span: RecurrenceSpan = THIS_EVENT): CalendarEvent!
  setReminderAlarms(reminderId: ID!, alarms: [AlarmInput!]!): Reminder!

  # Clock alarms (direct Clock.app accessibility automation)
  createClockAlarm(input: CreateClockAlarmInput!): ClockAlarmResult!
  toggleClockAlarm(input: ToggleClockAlarmInput!): ClockAlarmResult!
  updateClockAlarm(input: UpdateClockAlarmInput!): ClockAlarmResult!
  deleteClockAlarm(input: DeleteClockAlarmInput!): ClockAlarmResult!

  # Notes
  createNote(input: CreateNoteInput!): Note!
  updateNoteBody(input: UpdateNoteBodyInput!): Note!
  deleteNote(noteId: ID!): DeleteResult!
  moveNote(noteId: ID!, folderId: ID!): Note!

  # Notifications
  postNotification(input: PostNotificationInput!): PostedNotification!
  dismissNotifications(ids: [ID!]!): DismissResult!
  dismissAllGatewayNotifications: DismissResult!
}

type DeleteResult {
  success: Boolean!
}
```

Domain type definitions (`Calendar`, `CalendarEvent`, `Reminder`, `Alarm`,
`RecurrenceRule`, `ClockAlarm`, `Note`, `MailMessage`,
`DeliveredNotification`, and all inputs/connections) are specified in the
per-domain specs listed above. The full assembled SDL is printable at
runtime via `apple-gateway schema print`.

## Large Payload Policy (File Materialization)

Following mail-gateway's resolved decision that inline payloads waste AI
tokens, large content is exposed through the file materialization pattern:

- Mail message bodies (text, HTML, raw source) and attachments are never
  inlined. List/search results carry `snippet` (from Envelope Index
  summaries) plus a `files` set of `downloadKey` entries.
- Note bodies are inlined up to `limits.max_inline_body_bytes` (default
  65536). Larger bodies return `plaintext: null` plus a `bodyFile`
  download key. Note attachments are export-only download keys
  (best-effort; see `design-apple-notes.md`).
- `apple-gateway file download --key <key> [--output-dir <dir>]`
  materializes files under the cache root; `apple-gateway cache prune`
  clears them. Download keys encode domain, source identifiers, and kind,
  and are validated before any filesystem access. Materialized paths are
  always normalized under the configured cache root or explicit output
  directory.

### TASK-006 File Store Contract

Phase 0 TASK-006 owns the cross-domain file-store foundation only. It adds
the key codec, cache layout, path-safety rules, SQLite snapshot helper, and
`file download` / `cache prune` command behavior, but it does not implement
Mail, Notes, Notifications, or other domain adapters.

Download keys are opaque to callers but versioned for the implementation:

```text
agdk1.<base64url-canonical-payload>.<base64url-mac>
```

The payload includes `domain`, `sourceId`, optional additional source
identifiers, `kind`, and an optional suggested filename. The payload never
contains trusted filesystem paths. A key is valid only when its version,
base64url encoding, canonical payload schema, allowed domain/kind values,
path-component fields, and keyed MAC all validate. The MAC uses HMAC-SHA256
with CryptoKit and a local per-cache-root secret, without adding an external
SwiftPM package. Malformed, truncated, unknown-version, unknown-kind, or
tampered keys fail with `INVALID_DOWNLOAD_KEY` before any source file,
output path, cache directory, or SQLite sidecar is touched.

Every path component derived from a key or provider-suggested filename must
be a single relative segment. Empty values, absolute paths, `.` / `..`, path
separators, NUL bytes, tilde expansion, and symlink-mediated escapes are
rejected. Source identifiers are identifiers, not path fragments.

The file store owns these managed cache subdirectories under
`storage.cache_dir`:

- `downloads/` for materialized files when `--output-dir` is absent
- `snapshots/` for SQLite database copies and their `-wal` / `-shm` sidecars
- `keys/` for local key material or key metadata needed to validate issued
  keys

`file download` resolves the configured cache root before decoding keys.
If `--output-dir` is omitted, each written file lands under
`<cache_dir>/downloads/<domain>/<source-hash>/<kind>/<filename>`. If
`--output-dir` is present, it becomes the output root after normalizing it
against the current working directory. In both cases the final destination
must remain inside that root after lexical normalization and filesystem
resolution; otherwise the command fails before opening the source or
destination. Repeated `--key` values are processed independently and the
JSON manifest reports every successfully written path.

`cache prune` deletes only managed content under `storage.cache_dir`.
It refuses empty roots, filesystem roots, missing normalization anchors, and
any candidate whose resolved path is outside the cache root. Symlinks under
managed cache directories are not followed during traversal. `cache prune`
preserves key validation material by default; `cache prune --all` may remove
all managed cache contents and invalidate previously issued download keys,
but it still leaves the cache root itself in place.

SQLite snapshot copying is a shared helper for later Mail and Notifications
adapters. Given a live source database path, it copies the database file and
the exact sibling sidecars `<source>-wal` and `<source>-shm` when present
into `snapshots/<domain>/<source-hash>/`. It refreshes the copy when source
metadata changes, opens no write handle to the live database, and never
creates, truncates, renames, chmods, or deletes live source files. Snapshot
paths are validated with the same cache-root containment rules as downloads.

## Configuration

TOML subset (same hand-rolled parser policy as mail-gateway), default path
`$XDG_CONFIG_HOME/apple-gateway/config.toml`
(fallback `~/.config/apple-gateway/config.toml`), overridable via
`APPLE_GATEWAY_CONFIG` env var or `--config`. A missing config file is
valid: every key has a default so the tool works with zero configuration.
When both a config-path env var and `--config` are present, the explicit
CLI flag selects the file. Config value precedence is always defaults,
then file values, then environment value overrides.

```toml
[storage]
cache_dir = "~/.cache/apple-gateway"          # materialized files

[limits]
default_page_size = 20
max_page_size = 200
max_inline_body_bytes = 65536
apple_event_timeout_seconds = 30
apple_event_batch_size = 200

[domains]
# Each domain can be disabled; disabled domains resolve to
# DOMAIN_DISABLED errors instead of triggering permission prompts.
calendar = true
reminders = true
clock_alarms = true
notes = true
mail = true
notifications = true

[mail]
# Override auto-probed ~/Library/Mail/V1x root when needed.
mail_root = ""

[notifications]
# Override the helper app path (default: resolved next to the binary,
# then standard install locations).
helper_app_path = ""
```

Env overrides use the `APPLE_GATEWAY_<SECTION>_<KEY>` pattern
(for example `APPLE_GATEWAY_STORAGE_CACHE_DIR`); env wins over TOML,
matching the base project rule.

### TASK-002 Config Scope

The Phase 0 TASK-002 parser intentionally implements only the TOML subset
needed by the configuration above:

- section headers (`[storage]`) and `key = value` assignments
- blank lines and `#` comments
- string, integer, and boolean scalar values
- no arrays, inline tables, dotted keys, repeated sections, or repeated keys

Unknown sections, unknown keys, duplicate keys, malformed syntax, and type
conversion failures are `CONFIG_INVALID` errors with line/column details
when the source is a file value. Environment override errors identify the
env var name instead of a line number. Unknown `APPLE_GATEWAY_*` variables
are ignored unless they match the override prefix shape
`APPLE_GATEWAY_<SECTION>_<KEY>`; shaped variables with no known config key
are rejected so misspelled overrides cannot silently change behavior.

The supported env override names are derived directly from the TOML schema:
`APPLE_GATEWAY_STORAGE_CACHE_DIR`,
`APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE`,
`APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE`,
`APPLE_GATEWAY_LIMITS_MAX_INLINE_BODY_BYTES`,
`APPLE_GATEWAY_LIMITS_APPLE_EVENT_TIMEOUT_SECONDS`,
`APPLE_GATEWAY_LIMITS_APPLE_EVENT_BATCH_SIZE`,
`APPLE_GATEWAY_DOMAINS_CALENDAR`,
`APPLE_GATEWAY_DOMAINS_REMINDERS`,
`APPLE_GATEWAY_DOMAINS_CLOCK_ALARMS`,
`APPLE_GATEWAY_DOMAINS_NOTES`,
`APPLE_GATEWAY_DOMAINS_MAIL`,
`APPLE_GATEWAY_DOMAINS_NOTIFICATIONS`,
`APPLE_GATEWAY_MAIL_MAIL_ROOT`, and
`APPLE_GATEWAY_NOTIFICATIONS_HELPER_APP_PATH`.

Path-valued fields are expanded after file/env precedence is resolved:
`storage.cache_dir`, non-empty `mail.mail_root`, and non-empty
`notifications.helper_app_path` expand a leading `~` to the current user's
home directory. The selected config file path from `--config` or
`APPLE_GATEWAY_CONFIG` follows the same leading-tilde expansion rule.

Validation rules are deliberately local to configuration loading in
TASK-002. They do not probe TCC permissions, check whether apps are
installed, create cache directories, operate application UI, or validate GraphQL
runtime behavior. Required numeric limits must be positive and
`limits.default_page_size` must not exceed `limits.max_page_size`.
`storage.cache_dir` must resolve to a non-empty path. Optional override
paths may remain empty to request auto-probing in their later domain
implementations.

## Error Model

TASK-004 standardizes all business failures behind `AppleGatewayError`.
The error value carries four stable fields:

- `code`: one of the codes in the table below
- `message`: a human-readable failure summary safe to print to stderr or
  embed in JSON
- `exitCode`: the mapped process exit code for this failure
- `details`: optional structured diagnostics such as config source
  location, GraphQL location/path, domain name, file key, provider status,
  or responsible process hint

The shared JSON response envelope is GraphQL-shaped and is used by
`graphql`, `config validate`, and later JSON-producing commands. Canonical
request correlation lives at `extensions.requestId`; individual errors keep
machine fields in their own `extensions`.

Successful command output:

```json
{
  "data": {
    "permissions": {
      "status": "unknown"
    }
  },
  "extensions": {
    "requestId": "uuid"
  }
}
```

Single-error output:

```json
{
  "data": null,
  "errors": [{
    "message": "Calendar access denied for this process",
    "extensions": {
      "code": "PERMISSION_DENIED",
      "exitCode": 4,
      "details": { "domain": "calendar", "responsibleProcessHint": "iTerm2" }
    }
  }],
  "extensions": {
    "requestId": "uuid"
  }
}
```

Multi-root partial failure output keeps successful root fields, sets only
the failed root to `null`, and records a path-scoped error. Resolvers run
sequentially in document order; a root-field failure does not cancel later
roots unless the runtime cannot safely continue.

```json
{
  "data": {
    "calendars": null,
    "reminders": [{ "id": "reminder-list-1", "title": "Inbox" }]
  },
  "errors": [{
    "message": "Calendar access denied for this process",
    "path": ["calendars"],
    "extensions": {
      "code": "PERMISSION_DENIED",
      "exitCode": 4,
      "details": { "domain": "calendar", "responsibleProcessHint": "iTerm2" }
    }
  }],
  "extensions": {
    "requestId": "uuid"
  }
}
```

When an envelope contains one or more errors, the command process exit code
is the mapped `exitCode` of the first `AppleGatewayError` in `errors[]`.
Errors are appended in encounter order, which for GraphQL root fields follows
document order. Later errors may carry different per-error
`extensions.exitCode` values, but they do not change the aggregate process
exit selected for the command. Envelopes without `errors` exit 0.

`CONFIG_INVALID` is no longer formatted by a config-only envelope; the config
validator adapts its existing file/env diagnostics into `AppleGatewayError`
details and emits the same shared envelope. GraphQL parse, validation, role,
and resolver failures also adapt into `AppleGatewayError` while preserving
GraphQL `locations` and root-field `path` data where available.

TASK-004 does not add permission probes, file-store materialization, smoke
tests, or the broader TASK-007 command frame. Unknown commands and malformed
CLI flags remain usage errors with exit code 2; JSON business commands that
already emit envelopes should use `INVALID_ARGUMENT` only for invalid API
input after command routing has selected a JSON-producing command.

### Error Codes

| Code | Meaning |
| --- | --- |
| `INVALID_ARGUMENT` | Bad input value or unsupported filter field |
| `GRAPHQL_PARSE_ERROR` | Query does not parse |
| `GRAPHQL_VALIDATION_ERROR` | Unknown field/type, wrong arg shape |
| `WRITE_DISABLED_IN_READER` | Mutation sent to `apple-gateway-reader` |
| `PERMISSION_DENIED` | TCC denied (calendars, reminders, automation) |
| `PERMISSION_NOT_DETERMINED` | Prompt required; run `permissions request` |
| `WRITE_ONLY_ACCESS` | EventKit legacy write-only grant; reads impossible |
| `FULL_DISK_ACCESS_REQUIRED` | Mail root or notification DB unreadable |
| `AUTOMATION_DENIED` | Apple Events to target app denied |
| `DOMAIN_DISABLED` | Domain switched off in config |
| `CALENDAR_NOT_FOUND` / `EVENT_NOT_FOUND` / `REMINDER_NOT_FOUND` | Lookup miss |
| `CALENDAR_READ_ONLY` | Target calendar disallows modifications |
| `NOTE_NOT_FOUND` / `NOTE_LOCKED` / `NOTE_FOLDER_NOT_FOUND` | Notes lookups |
| `MAILBOX_NOT_FOUND` / `MESSAGE_NOT_FOUND` / `MAIL_STORE_NOT_FOUND` | Mail lookups |
| `NOTIFIER_HELPER_MISSING` | Helper .app not found/launchable |
| `NOTIFICATION_DB_UNAVAILABLE` | usernoted DB missing or unreadable |
| `APPLE_EVENT_TIMEOUT` | -1712 or timeout after retries |
| `INVALID_DOWNLOAD_KEY` / `FILE_OPERATION_FAILED` | File materialization |
| `CONFIG_INVALID` | Config file failed validation |
| `UNSUPPORTED_OS_VERSION` | Feature requires newer macOS |
| `UNEXPECTED_ERROR` | Anything else |

### Exit Codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Unexpected failure |
| 2 | CLI usage error |
| 3 | Config error |
| 4 | Permission error (TCC / FDA / Automation) |
| 5 | GraphQL execution error |
| 6 | Platform/provider error (Apple Events, SQLite, UI automation, helper) |

### Error-Code Exit Mapping

Every primary error code maps to one process exit code:

| Error code | Exit code |
| --- | --- |
| `INVALID_ARGUMENT` | 5 |
| `GRAPHQL_PARSE_ERROR` | 5 |
| `GRAPHQL_VALIDATION_ERROR` | 5 |
| `WRITE_DISABLED_IN_READER` | 5 |
| `PERMISSION_DENIED` | 4 |
| `PERMISSION_NOT_DETERMINED` | 4 |
| `WRITE_ONLY_ACCESS` | 4 |
| `FULL_DISK_ACCESS_REQUIRED` | 4 |
| `AUTOMATION_DENIED` | 4 |
| `DOMAIN_DISABLED` | 5 |
| `CALENDAR_NOT_FOUND` | 5 |
| `EVENT_NOT_FOUND` | 5 |
| `REMINDER_NOT_FOUND` | 5 |
| `CALENDAR_READ_ONLY` | 5 |
| `NOTE_NOT_FOUND` | 5 |
| `NOTE_LOCKED` | 5 |
| `NOTE_FOLDER_NOT_FOUND` | 5 |
| `MAILBOX_NOT_FOUND` | 5 |
| `MESSAGE_NOT_FOUND` | 5 |
| `MAIL_STORE_NOT_FOUND` | 5 |
| `NOTIFIER_HELPER_MISSING` | 6 |
| `NOTIFICATION_DB_UNAVAILABLE` | 6 |
| `APPLE_EVENT_TIMEOUT` | 6 |
| `INVALID_DOWNLOAD_KEY` | 5 |
| `FILE_OPERATION_FAILED` | 6 |
| `CONFIG_INVALID` | 3 |
| `UNSUPPORTED_OS_VERSION` | 6 |
| `UNEXPECTED_ERROR` | 1 |

## Permissions and Security

Summarized here; full treatment in `design-permissions.md`.

- Executables embed an Info.plist (`-sectcreate __TEXT __info_plist`) with
  `CFBundleIdentifier`, `NSCalendarsFullAccessUsageDescription`,
  `NSRemindersFullAccessUsageDescription`, legacy fallbacks, and
  `NSAppleEventsUsageDescription`.
- Interactive TCC prompts attribute to the hosting terminal; every
  permission failure message names the responsible process and points at
  the exact System Settings pane. `apple-gateway permissions status`
  reports all domains without triggering prompts;
  `apple-gateway permissions request --domain <d>` triggers them
  deliberately.
- Full Disk Access (Mail, notification DB) cannot be prompted; the doctor
  output prints the manual-grant deep link.
- Private databases are opened read-only (`immutable=1` where applicable)
  and copied to the cache dir before parsing when a live WAL lock exists.
- Release binaries and the notifier helper app are Developer ID signed and
  notarized so TCC grants survive updates.
- File paths returned by the gateway are always under the cache root or a
  caller-specified output directory; download keys are validated against
  path traversal.

## Concurrency Policy

Same as the base project: synchronous, single-request execution. Async
platform callbacks (EventKit access requests, helper-app IPC) are bridged
with `DispatchSemaphore` plus `NSLock`-guarded result boxes; value types
are `Sendable`; Swift 6 strict language mode. No actors, no async/await in
public signatures, keeping the library trivially callable from any context.

## Testing Policy

- Unit tests (swift-testing `@Test`) for the GraphQL runtime (lexer,
  parser, validation, variables, projection), config parsing, download-key
  codec, date conversion (Cocoa epoch, DateComponents), emlx parsing, and
  JXA script generation.
- Adapter protocols get in-memory fakes; smoke tests
  (`AppleGatewaySmokeTests` executable) run full CLI flows against fakes,
  mirroring mail-gateway's smoke-test pattern.
- SQLite-backed adapters (Mail, notifications) are tested against fixture
  databases committed under `Tests/Fixtures/`.
- Live integration against real EventKit/Notes/Mail is manual-only,
  documented per domain, never in CI (Linux CI cannot run it; local TCC
  prompts make it non-deterministic).

## Phased Delivery

| Phase | Content | Plan |
| --- | --- | --- |
| 0 | Target restructure, config, CLI frame, GraphQL runtime, permissions/doctor, file store | `impl-plans/active/phase-0-foundation-and-graphql-runtime.md` |
| 1 | Calendar + Reminders + EventKit alarms | `impl-plans/active/phase-1-calendar-reminders.md` |
| 2 | Apple Notes | `impl-plans/active/phase-2-apple-notes.md` |
| 3 | Apple Mail retrieval | `impl-plans/active/phase-3-apple-mail.md` |
| 4 | Notifications (helper app, post/list/dismiss) | `impl-plans/active/phase-4-notifications.md` |
| 5 | Clock alarms bridge + packaging updates | `impl-plans/active/phase-5-clock-alarms-and-packaging.md` |

## References

- `design-docs/references/macos-platform-research-2026-07.md`
- mail-gateway specs: sibling `mail-gateway/design-docs/specs/` checkout
- Resolved defaults: `design-docs/user-qa/resolved-apple-gateway-defaults.md`
