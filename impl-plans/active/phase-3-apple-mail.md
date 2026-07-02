# Phase 3: Apple Mail Retrieval

**Status**: In Progress (blocked on Phase 0)
**Design Reference**: `design-docs/specs/design-apple-mail.md`

## Purpose

Read-only Mail retrieval: accounts, mailboxes, message search/listing from
the Envelope Index, and body/attachment materialization from
.emlx/.partial.emlx files.

## Deliverables

- [ ] `Domains/MailAdapter/` with SQLite C-shim wrapper, snapshot-copy
      access, mail-root probing, emlx and partial-emlx parsers, MIME walk
- [ ] Schema module: mailAccounts, mailboxes, mailMessages, mailMessage
      (Query only; this domain defines no mutations)
- [ ] Mail file kinds wired into the Phase 0 file store (BODY_TEXT,
      BODY_HTML, RAW_SOURCE, ATTACHMENT)
- [ ] Fixture databases and emlx fixtures under `Tests/Fixtures/mail/`

## Tasks

### TASK-001: SQLite access layer and mail-root resolution

**Parallelizable**: No

Minimal `libsqlite3` wrapper (prepare/step/column, read-only immutable
open), V11-to-V9 root probing with `mail.mail_root` override, snapshot
copy with mtime-based refresh, FDA failure classification
(`FULL_DISK_ACCESS_REQUIRED` vs `MAIL_STORE_NOT_FOUND`).

**Completion Criteria**:

- [ ] Wrapper never opens the live index writable (code review + test
      asserting URI flags)
- [ ] Unreadable-root fixture yields the FDA error with settings deep link

### TASK-002: Envelope Index queries

**Parallelizable**: No (after TASK-001)

Account/mailbox derivation from `mailboxes.url` and Accounts.plist,
message listing with all `MailSearchInput` filters compiled to indexed
SQL (escaped LIKE, Cocoa-epoch date predicates, flag columns), connection
pagination, snippet from `summaries`.

**Completion Criteria**:

- [ ] Fixture-DB tests for every filter and combination, LIKE-escape
      adversarial cases, pagination stability
- [ ] Unsupported filters fail `INVALID_ARGUMENT`

### TASK-003: emlx parsing and file materialization

**Parallelizable**: Yes (after TASK-001)

emlx framing (count line, RFC 822 payload, plist trailer), partial-emlx
reassembly from `Attachments/`, MIME walk for text/html/attachment parts,
download-key production, `file download` integration, missing-body
handling for storage-optimized messages.

**Completion Criteria**:

- [ ] Fixture tests: multibyte headers, nested multipart, missing trailer,
      partial reassembly
- [ ] Evicted-body case lists fine and fails download with the documented
      details message

### TASK-004: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the mail schema module (Query only), smoke flows over fakes and
fixture DBs, SDL snapshot update, manual checklist against a real Mail
store (grant terminal FDA, verify counts against Mail.app, download a
body and an attachment).

**Completion Criteria**:

- [ ] No mutation field exists in the mail module (asserted in tests)
- [ ] Manual checklist executed and logged below

## Progress Log

- 2026-07-02: Plan created from approved design docs.
