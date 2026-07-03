# Apple Mail Retrieval Design

## Status

Draft

## Scope

Read-only retrieval of Apple Mail (Mail.app) data: accounts, mailboxes,
message listing/search, headers, bodies, raw source, and attachments.
No sending, moving, flagging, or deletion — outbound and mutating mail is
mail-gateway's territory and a hard non-goal here.

## Mechanism

Direct read-only parsing of Mail's local store. AppleScript to Mail.app is
rejected as the primary path: ~1000x slower, requires Mail running, and is
affected by the Tahoe -1712 regression (research reference, section 4).

Two sources, both under the Mail root:

1. `MailData/Envelope Index` (SQLite): message metadata, addresses,
   subjects, summaries, mailboxes, flags. Serves all listing and search.
2. `.emlx` / `.partial.emlx` message files: full RFC 822 source for bodies
   and attachments, materialized on demand through the file store.

### Mail Root Resolution

Probe `~/Library/Mail/V11`, then `V10`, then `V9` at startup (V10 is
current from Ventura through Tahoe; V11 guards against a future bump).
Config `mail.mail_root` overrides probing. No hit yields
`MAIL_STORE_NOT_FOUND`; an `EPERM`/`EACCES` on open yields
`FULL_DISK_ACCESS_REQUIRED` with the manual-grant guidance from
`design-permissions.md`.

For Phase 3 TASK-001, root resolution is a standalone adapter boundary and
does not query messages. The resolver accepts the configured
`mail.mail_root` only when it is non-empty; an override is treated as the
Mail version root that contains `MailData/Envelope Index`. Without an
override, the resolver probes only the supported version roots in descending
order: `~/Library/Mail/V11`, `~/Library/Mail/V10`, then
`~/Library/Mail/V9`. It must not fall back to unrelated Mail directories or
create missing paths.

Resolution validates the existence and readability of
`MailData/Envelope Index` using read-only file-system operations. Missing
version roots or missing `Envelope Index` files classify as
`MAIL_STORE_NOT_FOUND`. Permission failures while inspecting the root,
`MailData`, or `Envelope Index` classify as `FULL_DISK_ACCESS_REQUIRED` and
must include the System Settings deep link
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
plus the same manual Full Disk Access guidance used by the permissions
doctor.

### Envelope Index Access

- Open with SQLite URI `file:...?mode=ro&immutable=1` on a snapshot copy:
  Mail holds a WAL write lock, so the adapter copies `Envelope Index`
  (plus `-wal`/`-shm` when present) into the cache dir and opens the copy.
  The copy refreshes when the source mtime changes or after
  `cache prune`. The live database is never written.
- Uses the system `libsqlite3` via a minimal C-shim wrapper inside
  `MailAdapter` (no external package).
- Dates are Cocoa epoch; converted with offset 978307200.
- Key tables: `messages` (flags, dates, mailbox FK, subject/sender FKs),
  `subjects`, `addresses`, `summaries` (snippet), `mailboxes` (URL).
  Account and mailbox structure derives from `mailboxes.url`
  (`imap://...`, `ews://...`, `local://...`); account display names come
  from `~/Library/Mail/V10/MailData/Accounts.plist` when readable, falling
  back to URL-derived identifiers.

Phase 3 TASK-001 implements only the access substrate:

- A minimal SQLite boundary inside `Domains/MailAdapter/` that can open a
  database URI read-only and immutable, prepare statements, step rows, read
  typed columns, and close/finalize handles deterministically.
- The live `Envelope Index` path is never passed to SQLite. The adapter first
  asks the Phase 0 file-store snapshot helper to copy `Envelope Index` and
  any exact `-wal` / `-shm` sidecars into
  `snapshots/mail/<source-hash>/`, refreshing when source mtime metadata
  changes. SQLite opens only the returned snapshot path.
- The SQLite URI uses `mode=ro&immutable=1`; no code path may request
  `SQLITE_OPEN_READWRITE`, `SQLITE_OPEN_CREATE`, or a mutable URI for Mail.
- The wrapper remains schema-agnostic in TASK-001. It may support smoke
  statements such as `SELECT 1`, but account, mailbox, message, filter,
  pagination, and summary queries remain TASK-002.
- The wrapper is an implementation detail of the Mail adapter. It does not
  register GraphQL fields, alter CLI commands, or expose public query
  behavior in TASK-001.

### TASK-002 Envelope Index Query Contract

TASK-002 builds on the TASK-001 snapshot and SQLite boundary only. It adds
Mail adapter query behavior for accounts, mailboxes, and message
listing/search, but it must not register Mail GraphQL fields, update SDL,
change CLI behavior, parse `.emlx` files, materialize files, or perform the
TASK-004 smoke/manual checklist work.

Accounts derive from distinct account roots in `mailboxes.url`. The parser
classifies URL schemes into `imap`, `exchange`, `local`, `pop`, or
`unknown`; extracts a stable URL-derived account key; and creates a stable
account id from that key. When `MailData/Accounts.plist` is readable, it may
provide display names for matching account identifiers or host/user
components. If the plist is absent, unreadable, or does not match a mailbox
URL, the adapter falls back to a deterministic URL-derived display name. An
unreadable `Accounts.plist` is not a Full Disk Access failure because the
Envelope Index remains the authoritative query source.

Mailboxes derive from every readable row in the `mailboxes` table. Each
mailbox receives a stable id from the Envelope Index mailbox primary key and
URL-derived account key, an `accountId`, a leaf `name`, and a full `path`.
Counts are computed from indexed `messages` rows scoped to the mailbox:
`totalCount` includes all listed messages and `unreadCount` includes only
messages whose read flag indicates unread. Rows with malformed or unknown
URL schemes remain visible under an `unknown` account instead of being
dropped.

Message listing/search accepts only these TASK-002 inputs:
`accountId`, `mailboxId`, `query`, `from`, `to`, `subject`,
`receivedAfter`, `receivedBefore`, `unreadOnly`, `flaggedOnly`, `first`, and
`after`. Any internally exposed field outside this set fails before SQL
execution with `INVALID_ARGUMENT`; unsupported fields are not silently
ignored. Unknown `accountId` or `mailboxId` values also fail with
`INVALID_ARGUMENT`.

Filters compile to parameter-bound SQL against the snapshot copy:

- `accountId` restricts to mailbox URLs belonging to the derived account.
- `mailboxId` restricts to one mailbox row after validating the mailbox id.
- `query` matches subject, sender address/display text, and summary snippet.
- `from`, `to`, and `subject` match their corresponding address or subject
  text.
- `receivedAfter` and `receivedBefore` compare converted Cocoa-epoch
  `messages` received dates, with `receivedAfter` inclusive and
  `receivedBefore` exclusive.
- `unreadOnly` and `flaggedOnly` add flag predicates only when true.

All subject, address, and summary text filters use `LIKE` with an explicit
escape character. The adapter escapes `%`, `_`, and the escape character in
user input before adding wildcard prefixes or suffixes, and every value is
bound as a SQLite parameter. Search input must never be concatenated into SQL
text.

Dates stored in the Envelope Index are Cocoa epoch seconds and convert to
Unix time by adding `978307200` seconds before DateTime comparison or
response formatting. Null or invalid date columns produce null response
dates, but invalid client DateTime input fails with `INVALID_ARGUMENT`.

Messages are sorted by `dateReceived` descending with the Envelope Index
message row id as a deterministic descending tie-breaker. Pagination uses a
cursor containing the last edge's converted `dateReceived` value and row id;
`after` resumes strictly after that tuple so inserts with equal timestamps do
not duplicate or skip rows within the snapshot. `first` defaults to the
domain page size and must be a positive bounded integer; malformed, stale,
or cross-query cursors fail with `INVALID_ARGUMENT`.

`MailMessage.snippet` is populated from the Envelope Index summary text only.
TASK-002 does not open message files to refine snippets, fill bodies, detect
attachments beyond available index metadata, or create download keys.

TASK-002 fixture database tests must cover account and mailbox derivation,
readable and unreadable `Accounts.plist` fallback behavior, every supported
filter, representative filter combinations, adversarial LIKE escaping for
`%`, `_`, and the escape character, Cocoa epoch conversion, unread and
flagged predicates, stable dateReceived-desc pagination including equal-date
ties, snippets from summaries, and `INVALID_ARGUMENT` handling for
unsupported internally exposed filters.

### Message Body Materialization

`.emlx` layout: first line is the byte count, then raw RFC 822, then an XML
plist trailer with flags. `.partial.emlx` messages reassemble attachment
parts from the sibling `Attachments/` directory. The adapter implements:

- emlx framing parser (count line, payload slice, plist trailer)
- MIME walk to extract `text/plain`, `text/html`, and attachment parts
- partial-emlx reassembly to reconstruct full raw source

Bodies and attachments are never inlined in GraphQL responses (base
project policy). They surface as download keys; `file download`
materializes `body.txt`, `body.html`, `raw.eml`, and attachment files
under the cache root. When Mail's storage optimization has evicted a
body (`.emlx` missing), the message still lists with its Envelope Index
snippet, and downloading its body fails with `MESSAGE_NOT_FOUND` details
saying the body is not stored locally.

## GraphQL Types

```graphql
type MailAccount {
  id: ID!               # stable hash of account directory / URL prefix
  name: String!
  kind: String!         # imap | exchange | local | pop | unknown
}

type Mailbox {
  id: ID!
  accountId: ID!
  name: String!
  path: String!         # full mailbox path, e.g. "INBOX/Receipts"
  totalCount: Int!
  unreadCount: Int!
}

type MailAddress { raw: String!, name: String, email: String }

type MailMessage {
  id: ID!               # Envelope Index ROWID scoped key
  mailboxId: ID!
  accountId: ID!
  messageId: String     # RFC 822 Message-ID when present
  subject: String
  snippet: String       # Envelope Index summary
  from: MailAddress
  to: [MailAddress!]!
  cc: [MailAddress!]!
  dateSent: DateTime
  dateReceived: DateTime
  isRead: Boolean!
  isFlagged: Boolean!
  hasAttachments: Boolean!
  files: MailMessageFileSet!
}

type MailMessageFileSet {
  bodyText: MailMessageFile
  bodyHtml: MailMessageFile
  rawSource: MailMessageFile
  attachments: [MailMessageFile!]!
}

type MailMessageFile {
  downloadKey: String!
  kind: MailFileKind!    # BODY_TEXT | BODY_HTML | RAW_SOURCE | ATTACHMENT
  filename: String
  mimeType: String
  byteSize: Int
}
enum MailFileKind { BODY_TEXT, BODY_HTML, RAW_SOURCE, ATTACHMENT }

input MailSearchInput {
  accountId: ID
  mailboxId: ID
  query: String          # matches subject, sender, and summary snippet
  from: String
  to: String
  subject: String
  receivedAfter: DateTime
  receivedBefore: DateTime
  unreadOnly: Boolean
  flaggedOnly: Boolean
  first: Int
  after: String
}

type MailMessageConnection {
  edges: [MailMessageEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}
type MailMessageEdge { cursor: String!, node: MailMessage! }
```

Search compiles to indexed SQL over the snapshot copy (`LIKE` with
escaping on subject/address/summary joins; date/flag predicates on
`messages` columns). Sort: `dateReceived` descending. Unsupported filter
fields fail with `INVALID_ARGUMENT`.

### TASK-004 GraphQL Registration and Smoke Contract

TASK-004 makes the existing TASK-001 through TASK-003 Mail adapter work
visible through the GraphQL runtime and CLI without adding any Mail write
surface. The Mail schema module registers the types above and exactly these
root Query fields:

```graphql
type Query {
  mailAccounts: [MailAccount!]!
  mailboxes(accountId: ID): [Mailbox!]!
  mailMessages(input: MailSearchInput!): MailMessageConnection!
  mailMessage(messageId: ID!): MailMessage
}
```

The module's `mutationFields` collection is always empty. This is true for
both full and reader schema construction: full mode may expose mutations
from other domains, but it must not expose any Mail mutation field. Reader
mode continues to reject every mutation operation at the GraphQL operation
boundary with `WRITE_DISABLED_IN_READER`.

Resolvers must be thin adapters over the Mail query/materialization services:

- `mailAccounts` returns the derived accounts from the Envelope Index and
  readable `Accounts.plist` fallback rules from TASK-002.
- `mailboxes(accountId:)` returns all derived mailboxes when `accountId` is
  absent and only that account's mailboxes when present. An unknown account
  id fails with `INVALID_ARGUMENT`.
- `mailMessages(input:)` maps GraphQL input fields one-for-one to
  `MailSearchInput`, preserving unsupported-field, date-range, account,
  mailbox, SQL-escaping, sorting, and cursor validation from TASK-002.
- `mailMessage(messageId:)` looks up by the stable `MailMessage.id`
  identifier, returns `null` when no message exists, and does not treat the
  RFC 822 `Message-ID` header as the GraphQL id.

Mail file download keys are issued through the existing Phase 0 file store
only. `MailMessage.files` may include `BODY_TEXT`, `BODY_HTML`,
`RAW_SOURCE`, and `ATTACHMENT` keys created by the TASK-003 Mail file
factory. The key payload domain is `mail`; the file-store kind is the same
value exposed in `MailFileKind`; the source id must be the existing Mail
file-store identifier for the local `.emlx` or `.partial.emlx` path, not a
raw unsafe cache path segment. `file download` materializes these keys
through the registered Mail materializer and preserves Phase 0 validation:
forged keys, unknown domain/kind pairs, unsafe filenames, and output escape
attempts fail before writing outside the output root.

GraphQL schema print expectations are updated as part of TASK-004. Full and
reader SDL must both include the four Mail Query fields and Mail object,
enum, input, and connection types. Full SDL may include `type Mutation`
for other domains, but no line in that type may reference a Mail mutation;
reader SDL omits `type Mutation` entirely.

Smoke coverage must exercise both fake-backed runtime wiring and fixture DB
behavior:

- Fake-backed GraphQL smoke proves CLI execution can resolve
  `mailAccounts`, `mailboxes`, `mailMessages`, and `mailMessage` without a
  real Mail store and that `file download` can materialize a Mail
  `BODY_TEXT` key through the same Phase 0 file-store command path.
- Fixture-DB GraphQL tests prove the registered resolvers preserve TASK-002
  account, mailbox, filter, pagination, and single-message behavior against
  synthetic Envelope Index data.
- Schema tests assert the Mail module exposes no mutation fields and that
  reader-mode mutation rejection remains owned by the runtime, not by Mail
  resolver code.

The manual checklist status for a real Mail store is logged in
`impl-plans/active/phase-3-apple-mail.md`. The checklist records whether the
developer granted Terminal Full Disk Access, whether Mail.app counts matched
representative `mailAccounts`/`mailboxes`/`mailMessages` results, whether a
body and attachment download succeeded, or why any live step was skipped.
It must not record real message content, private mailbox names beyond what
is necessary to identify the check, secret values, or local private Mail
paths.

## Permissions

Reading the Mail root requires Full Disk Access for the responsible
process (interactive: the terminal). There is no prompt API; the doctor
prints the System Settings deep link. `to`/`cc` recipient details beyond
the index may require the `.emlx` header parse; both paths sit behind the
same FDA gate.

## Testing

- Fixture Envelope Index databases (built by a test helper from SQL
  scripts, committed under `Tests/Fixtures/mail/`) drive query tests
  without real mail.
- TASK-001 tests use fake Mail roots and an injectable snapshot/SQLite-open
  boundary. They prove configured `mail.mail_root` wins over probing,
  probing checks V11 before V10 before V9, missing roots produce
  `MAIL_STORE_NOT_FOUND`, and unreadable roots or unreadable
  `MailData/Envelope Index` paths produce `FULL_DISK_ACCESS_REQUIRED` with
  the Full Disk Access settings deep link.
- TASK-001 tests assert that the SQLite layer opens the snapshot URI with
  read-only immutable semantics and never opens the live `Envelope Index`
  path writable. The test surface should record open flags or URIs rather
  than rely on a real user Mail database.
- TASK-001 snapshot tests assert mtime-based refresh behavior through the
  Phase 0 file-store snapshot helper contract, including sidecar copying
  where `Envelope Index-wal` or `Envelope Index-shm` exists.
- emlx/partial-emlx parsers tested against synthetic fixtures including
  multibyte subjects, nested multipart, and missing trailers.
- TASK-004 tests assert the Mail schema module is Query-only, the runtime
  schema includes `mailAccounts`, `mailboxes`, `mailMessages`, and
  `mailMessage`, no full-mode Mail mutation exists, and reader mode still
  rejects mutation operations before resolver dispatch.
- TASK-004 smoke tests run Mail GraphQL flows over fake services and fixture
  databases, update SDL/schema-print expectations, and cover Mail file
  download/materialization through the Phase 0 file-store command path.
- Manual live checklist against the developer's own Mail store in the
  phase plan.

TASK-001 verification commands are the narrow relevant Swift tests for the
Mail adapter and file-store snapshot integration first, then `task build`,
`task test`, `task lint`, and `swift run apple-gateway --help` when the
implementation touches shared behavior or command wiring. TASK-001 does not
require SDL snapshot updates because GraphQL schema registration is TASK-004.
TASK-004 verification starts with focused Mail GraphQL runtime, Mail
adapter, Mail parser/materializer, file-store, and smoke tests, then broadens
to `task build`, `task test`, `task lint`, `swift run apple-gateway
schema print --role full`, `swift run apple-gateway schema print --role
reader`, and `swift run apple-gateway --help`.
