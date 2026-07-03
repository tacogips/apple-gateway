# Phase 3: Apple Mail Retrieval

**Status**: In Progress (TASK-001 ready for implementation planning; blocked where Phase 0 snapshot behavior is missing)
**Design Reference**: `design-docs/specs/design-apple-mail.md`
**Workflow Mode**: issue-resolution
**Issue Reference**: Phase 3 TASK-001: Apple Mail SQLite access layer and mail-root resolution

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

Implement the accepted Step 3 design update only. Build the read-only
access substrate for `MailData/Envelope Index`; do not add message
queries, emlx parsing, GraphQL schema fields, CLI output, or SDL updates.

#### TASK-001 Deliverables

- [ ] `Sources/AppleGatewayCore/Domains/MailAdapter/MailRootResolver.swift`
      resolves the Mail version root from `mail.mail_root` when non-empty,
      otherwise probes `~/Library/Mail/V11`, then `V10`, then `V9`.
- [ ] The resolver treats the override as the version root containing
      `MailData/Envelope Index`; it does not create missing paths or fall
      back to unrelated Mail directories.
- [ ] Missing roots, missing `MailData`, or missing `Envelope Index`
      classify as `MAIL_STORE_NOT_FOUND`.
- [ ] Permission failures while inspecting the root, `MailData`, or
      `Envelope Index` classify as `FULL_DISK_ACCESS_REQUIRED`, including
      the System Settings deep link
      `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
      and manual Full Disk Access guidance consistent with the permissions
      doctor.
- [ ] `Sources/AppleGatewayCore/Domains/MailAdapter/MailSQLite.swift`
      provides a minimal schema-agnostic `libsqlite3` boundary for
      read-only immutable database URI open, prepare, step, typed column
      reads, finalize, and close.
- [ ] The SQLite boundary uses `mode=ro&immutable=1` and must not request
      `SQLITE_OPEN_READWRITE`, `SQLITE_OPEN_CREATE`, or mutable Mail
      database access.
- [ ] `Sources/AppleGatewayCore/Domains/MailAdapter/MailEnvelopeIndexStore.swift`
      resolves the live index, asks the Phase 0 file-store snapshot helper
      to copy `Envelope Index` plus exact `-wal` and `-shm` sidecars into
      `snapshots/mail/<source-hash>/`, and opens only the returned
      snapshot path.
- [ ] The snapshot source identifier passed into the helper must be a safe,
      deterministic identifier for the Mail root or an already-hashed value;
      raw absolute paths must not violate file-store path-segment safety.
- [ ] `Tests/AppleGatewayCoreTests/MailAdapterTests.swift` covers override
      precedence, V11-to-V9 probe order, missing-store classification,
      unreadable-root and unreadable-index FDA classification, immutable
      read-only snapshot open semantics, and mtime/sidecar snapshot refresh
      through the Phase 0 helper contract.

**Completion Criteria**:

- [ ] Wrapper never opens the live index writable (code review + test
      asserting URI flags)
- [ ] Unreadable-root fixture yields the FDA error with settings deep link
- [ ] Live `Envelope Index` path is never passed to SQLite in production
      code or test open records
- [ ] TASK-002, TASK-003, and TASK-004 behavior remains absent and
      unchanged

#### TASK-001 Dependencies

- Phase 0 file-store snapshot helper supports SQLite snapshot copying,
  mtime-based refresh, and exact `-wal` / `-shm` sidecar copying.
- Config decoding exposes `mail.mail_root` as an optional override with an
  empty string treated as unset.
- Shared error envelope includes `FULL_DISK_ACCESS_REQUIRED` and
  `MAIL_STORE_NOT_FOUND`.
- Tests can inject fake file-system, snapshot, and SQLite-open boundaries
  without requiring a real Apple Mail store.

#### TASK-001 Implementation Order

1. Add or refine injectable boundaries for Mail file-system checks,
   snapshot creation, and SQLite opening so tests can observe paths, URI
   strings, and open flags.
2. Implement root resolution and error classification before SQLite work;
   verify configured override precedence and V11-to-V9 probe order.
3. Connect the snapshot helper with a deterministic safe source identifier
   and assert that the helper, not SQLite, receives the live index path.
4. Implement the minimal SQLite wrapper and ensure handle finalization and
   close paths are deterministic.
5. Add focused TASK-001 tests before broader build and lint verification.

#### TASK-001 Verification

Run narrow checks first:

```bash
swift test --filter MailAdapterTests
swift test --filter FileStoreTests
```

Then run shared verification because TASK-001 touches shared config,
file-store, errors, or package linking:

```bash
task build
task test
task lint
swift run apple-gateway --help
```

If `swiftlint` is unavailable outside the Nix or direnv shell, record that
explicitly in the progress log and rerun inside the project dev shell.

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

This may run in parallel with TASK-002 only after TASK-001 completes,
because TASK-002 writes Envelope Index query code while TASK-003 writes
emlx parsing and file materialization code. Shared file-store or model
changes must be serialized.

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
- 2026-07-03: Step 4 plan revised after Step 3 accepted the design for
  issue-resolution mode. TASK-001 implementation tasks, dependencies,
  disjoint write-scope guidance, verification commands, and completion
  criteria were made explicit. No Codex-agent references were provided.

## Progress Log Expectations

- Add one dated entry for each implementation pass, review pass, and
  verification pass.
- Record exact commands run and whether they passed, failed, or were
  skipped with a reason.
- Record any intentional divergence from
  `design-docs/specs/design-apple-mail.md`; otherwise treat that design as
  the source of truth.
- Do not log secret values, real Mail message content, or local private
  Mail paths beyond synthetic fixture paths.

## Risks

- Mail-store permission checks on macOS can report unreadable roots through
  different file-system APIs; tests should force both root-level and
  Envelope Index-level FDA paths.
- A raw absolute Mail root path may be unsafe as a file-store path segment;
  TASK-001 should hash or otherwise sanitize before snapshot storage.
- Opening a copied SQLite database without matching WAL/SHM sidecars can
  produce stale or inconsistent reads; sidecar snapshot coverage is
  required.
- GraphQL and CLI behavior must remain unchanged until TASK-004 even if the
  substrate is complete.
