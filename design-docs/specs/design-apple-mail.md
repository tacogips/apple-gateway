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
- emlx/partial-emlx parsers tested against synthetic fixtures including
  multibyte subjects, nested multipart, and missing trailers.
- FDA-denial path tested by pointing `mail.mail_root` at an unreadable
  directory fixture.
- Manual live checklist against the developer's own Mail store in the
  phase plan.
