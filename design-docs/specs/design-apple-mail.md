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
- Manual live checklist against the developer's own Mail store in the
  phase plan.

TASK-001 verification commands are the narrow relevant Swift tests for the
Mail adapter and file-store snapshot integration first, then `task build`,
`task test`, `task lint`, and `swift run apple-gateway --help` when the
implementation touches shared behavior or command wiring. TASK-001 does not
require SDL snapshot updates because GraphQL schema registration is TASK-004.
