# Phase 3: Apple Mail Retrieval

**Status**: Implementation complete; live Mail verification remains manual
**Design Reference**: `design-docs/specs/design-apple-mail.md`
**Workflow Mode**: issue-resolution
**Issue Reference**: Phase 3 TASK-001: Apple Mail SQLite access layer and mail-root resolution

## Purpose

Read-only Mail retrieval: accounts, mailboxes, message search/listing from
the Envelope Index, and body/attachment materialization from
.emlx/.partial.emlx files.

## Deliverables

- [x] `Domains/MailAdapter/` with SQLite C-shim wrapper, snapshot-copy
      access, mail-root probing, emlx and partial-emlx parsers, MIME walk
- [x] Schema module: mailAccounts, mailboxes, mailMessages, mailMessage
      (Query only; this domain defines no mutations)
- [x] Mail file kinds wired into the Phase 0 file store (BODY_TEXT,
      BODY_HTML, RAW_SOURCE, ATTACHMENT)
- [x] Synthetic fixture databases and emlx fixtures in Mail-focused tests
- [x] Manual live checklist artifact:
      `impl-plans/live-checklists/phase-3-apple-mail-live.md`
- [x] Safe live readiness helper:
      `scripts/live-mail-check.sh`

## Tasks

### TASK-001: SQLite access layer and mail-root resolution

**Parallelizable**: No

Implement the accepted Step 3 design update only. Build the read-only
access substrate for `MailData/Envelope Index`; do not add message
queries, emlx parsing, GraphQL schema fields, CLI output, or SDL updates.

#### TASK-001 Deliverables

- [x] `Sources/AppleGatewayCore/Domains/MailAdapter/MailRootResolver.swift`
      resolves the Mail version root from `mail.mail_root` when non-empty,
      otherwise probes `~/Library/Mail/V11`, then `V10`, then `V9`.
- [x] The resolver treats the override as the version root containing
      `MailData/Envelope Index`; it does not create missing paths or fall
      back to unrelated Mail directories.
- [x] Missing roots, missing `MailData`, or missing `Envelope Index`
      classify as `MAIL_STORE_NOT_FOUND`.
- [x] Permission failures while inspecting the root, `MailData`, or
      `Envelope Index` classify as `FULL_DISK_ACCESS_REQUIRED`, including
      the System Settings deep link
      `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
      and manual Full Disk Access guidance consistent with the permissions
      doctor.
- [x] `Sources/AppleGatewayCore/Domains/MailAdapter/MailSQLite.swift`
      provides a minimal schema-agnostic `libsqlite3` boundary for
      read-only immutable database URI open, prepare, step, typed column
      reads, finalize, and close.
- [x] The SQLite boundary uses `mode=ro&immutable=1` and must not request
      `SQLITE_OPEN_READWRITE`, `SQLITE_OPEN_CREATE`, or mutable Mail
      database access.
- [x] `Sources/AppleGatewayCore/Domains/MailAdapter/MailEnvelopeIndexStore.swift`
      resolves the live index, asks the Phase 0 file-store snapshot helper
      to copy `Envelope Index` plus exact `-wal` and `-shm` sidecars into
      `snapshots/mail/<source-hash>/`, and opens only the returned
      snapshot path.
- [x] The snapshot source identifier passed into the helper must be a safe,
      deterministic identifier for the Mail root or an already-hashed value;
      raw absolute paths must not violate file-store path-segment safety.
- [x] `Tests/AppleGatewayCoreTests/MailAdapterTests.swift` covers override
      precedence, V11-to-V9 probe order, missing-store classification,
      unreadable-root and unreadable-index FDA classification, immutable
      read-only snapshot open semantics, and mtime/sidecar snapshot refresh
      through the Phase 0 helper contract.

**Completion Criteria**:

- [x] Wrapper never opens the live index writable (code review + test
      asserting URI flags)
- [x] Unreadable-root fixture yields the FDA error with settings deep link
- [x] Live `Envelope Index` path is never passed to SQLite in production
      code or test open records
- [x] TASK-002, TASK-003, and TASK-004 behavior remains absent and
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

- [x] Fixture-DB tests for every filter and combination, LIKE-escape
      adversarial cases, pagination stability
- [x] Unsupported filters fail `INVALID_ARGUMENT`

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

- [x] Fixture tests: multibyte headers, nested multipart, missing trailer,
      partial reassembly
- [x] Evicted-body case lists fine and fails download with the documented
      details message

### TASK-004: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the mail schema module (Query only), smoke flows over fakes and
fixture DBs, SDL snapshot update, and reusable manual checklist
`impl-plans/live-checklists/phase-3-apple-mail-live.md` for a real Mail
store (grant terminal FDA only by operator opt-in, verify counts against
Mail.app, download a body and an attachment).

**Completion Criteria**:

- [x] No mutation field exists in the mail module (asserted in tests)
- [x] Manual checklist artifact exists; live execution was skipped in this
      non-interactive run with reason logged below

## Progress Log

- 2026-07-02: Plan created from approved design docs.
- 2026-07-03: Step 4 plan revised after Step 3 accepted the design for
  issue-resolution mode. TASK-001 implementation tasks, dependencies,
  disjoint write-scope guidance, verification commands, and completion
  criteria were made explicit. No Codex-agent references were provided.
- 2026-07-03: Step 6 implementation verified TASK-001 substrate files and
  added focused MailAdapter coverage for unreadable Envelope Index FDA
  classification, live libsqlite3 read-only immutable snapshot smoke access,
  and mtime-based refresh of `Envelope Index` plus exact `-wal` / `-shm`
  sidecars. No design divergence. No TASK-002 message queries, TASK-003 emlx
  parsing, or TASK-004 GraphQL/CLI registration added. Initial
  `swift test --filter MailAdapterTests` failed before compile because the
  inherited direnv/Nix SDK (`apple-sdk-11.3`) was incompatible with Xcode
  Swift 6.3.3; verification was rerun with `DEVELOPER_DIR`, `SDKROOT`, and
  `TOOLCHAINS` unset.
- 2026-07-03: Step 6 verification passed:
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS swift test --filter MailAdapterTests`;
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS swift test --filter FileStoreTests`;
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS task build`;
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS task test`;
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS task lint`;
  `env -u DEVELOPER_DIR -u SDKROOT -u TOOLCHAINS swift run apple-gateway --help`.
- 2026-07-03: TASK-002 design update routed through Riela session
  `codex-design-and-implement-review-loop-session-377`. Step 2 updated
  `design-docs/specs/design-apple-mail.md` with the Envelope Index query
  contract. The Riela process then failed entering design self-review with
  `codex-agent failed with exit code 1`; `riela session resume` failed with
  the same provider error, so implementation proceeded from the completed
  Riela design output. No commit or push performed.
- 2026-07-03: TASK-002 implemented. Added Mail domain query models, mailbox
  URL/account derivation, parameter-bound SQLite query support, account and
  mailbox derivation from `mailboxes.url` plus readable `Accounts.plist`
  display-name fallback, message filters for account, mailbox, query, from,
  to, subject, received date range, unread, flagged, and cursor pagination.
  Preserved CLI and GraphQL behavior; no Mail schema registration, SDL
  update, TASK-003 emlx parsing/materialization, or TASK-004 smoke/manual
  checklist work was added.
- 2026-07-03: TASK-002 verification passed with the Xcode SDK environment:
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift test --filter "MailEnvelopeIndexQueryTests|MailAdapterTests"`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task build`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task test`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task lint`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run apple-gateway --help`;
  `git diff --check`.
- 2026-07-03: TASK-003 routed through Riela session
  `codex-design-and-implement-review-loop-session-378`. The workflow
  reached Step 2 design-doc update and then stalled with a silence warning;
  the process was cancelled and persisted as a failed session. No TASK-003
  design update output was produced, so implementation proceeded from the
  existing `design-docs/specs/design-apple-mail.md` Message Body
  Materialization section. No commit or push performed.
- 2026-07-03: TASK-003 implemented. Added emlx framing parse for byte-count
  payloads with optional XML plist trailers, partial-emlx attachment
  reassembly from sibling `Attachments/`, MIME header/transfer decoding with
  nested multipart walking, BODY_TEXT/BODY_HTML/RAW_SOURCE/ATTACHMENT
  download-key production, and Mail file-store materialization with
  MESSAGE_NOT_FOUND details for locally evicted body or attachment files.
  Preserved CLI and GraphQL behavior; no Mail schema registration, SDL
  update, TASK-004 smoke flows, or manual checklist work was added.
- 2026-07-03: TASK-003 verification passed with the Xcode SDK environment:
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift test --filter "MailEMLXParserTests|MailEnvelopeIndexQueryTests|MailAdapterTests"`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task build`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task test`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task lint`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run apple-gateway --help`;
  `git diff --check`.
- 2026-07-03: TASK-004 routed through Riela session
  `codex-design-and-implement-review-loop-session-380`. Intake completed
  and identified the required Query-only schema, resolver, smoke, SDL, and
  checklist acceptance signals. The workflow then stalled in Step 2
  design-doc update with stale backend timing and no accepted design output;
  it was cancelled and persisted as a failed session. Implementation
  proceeded from the existing TASK-004 contract in
  `design-docs/specs/design-apple-mail.md`. No commit or push performed.
- 2026-07-03: TASK-004 implemented. Added `MailReadService`/`MailProviding`
  boundaries, live Envelope Index provider construction, Mail Query schema
  registration for `mailAccounts`, `mailboxes`, `mailMessages`, and
  `mailMessage`, Mail model serialization, single-message lookup by stable
  `MailMessage.id`, account-scoped mailbox validation, Mail file-set
  resolution through the TASK-003 file factory, default Mail file
  materialization for `file download`, GraphQL runtime/CLI dependency
  injection, fake-backed Mail smoke flows, fixture-DB GraphQL coverage, and
  SDL/no-mutation assertions. No Mail mutation fields were added.
- 2026-07-03: TASK-004 manual live checklist status:
  skipped in this non-interactive implementation run. Terminal Full Disk
  Access was not changed, no private live Mail store was queried, no Mail.app
  counts were compared, and no real body or attachment was downloaded.
  Synthetic fixture DBs and emlx files covered the automated checklist
  behaviors without logging real message content or local private Mail paths.
- 2026-07-03: TASK-004 verification passed with the Xcode SDK environment:
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift test --filter "MailEMLXParserTests|MailGraphQLRuntimeTests|MailEnvelopeIndexQueryTests"`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift test --filter "MailGraphQLRuntimeTests|GraphQLRuntimeTests|CommandTests|FileStoreTests"`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run AppleGatewaySmokeTests`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task build`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task test`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" task lint`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run apple-gateway schema print --role full`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run apple-gateway schema print --role reader`;
  `env -u SDKROOT -u DEVELOPER_DIR PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" swift run apple-gateway --help`;
  `git diff --check`.
- 2026-07-03: Riela work package
  `codex-simple-work-package-session-412` added the missing Phase 3 Apple
  Mail live manual checklist artifact at
  `impl-plans/live-checklists/phase-3-apple-mail-live.md` and clarified
  TASK-004 status so the plan records that implementation is complete while
  live Mail verification remains manual/skipped in this non-interactive run.
  The checklist covers environment capture, Full Disk Access readiness and
  manual grant rules, configured `mail.mail_root` presence, non-mutating
  schema/readiness checks, Mail.app account/mailbox/message count comparison,
  body download, attachment download, reader behavior, cleanup, privacy
  rules, and follow-up recording. Local review after the interrupted Riela
  run aligned checklist GraphQL snippets with the implemented schema
  (`mailAccounts { id name kind }` and nested
  `MailMessageFileSet.downloadKey` fields). Verification:
  `test -f impl-plans/live-checklists/phase-3-apple-mail-live.md`, targeted
  `rg` checks for checklist terms and stale live-execution claims, and
  `git diff --check`.
- 2026-07-03: Safe Mail live readiness helper routed through Riela session
  `codex-simple-work-package-session-413`; the workflow stalled during
  implementation and was cancelled, so local implementation continued under
  the accepted shell/docs-only scope. Added `scripts/live-mail-check.sh`.
  The script defaults to non-prompting readiness only: it checks permissions
  status and full/reader schema Mail fields without reading the live Mail
  store. Its explicit `--read-only` mode refuses unless `mailFullDiskAccess`
  is already `GRANTED`, then runs limited Mail metadata queries and leaves
  body/attachment downloads to the manual checklist. Updated the live
  checklist to reference the script. Verification: `bash -n
  scripts/live-mail-check.sh`, dry-run script execution, `--read-only`
  refusal with `mailFullDiskAccess` not granted, targeted `rg` checks for
  safety wording and references, and `git diff --check`.
- 2026-07-03: Riela work package
  `codex-simple-work-package-session-429` hardened the default dry-run Mail
  readiness schema checks without changing live behavior. The helper now
  validates exact Query root field signatures for full and reader schemas:
  `mailAccounts: [MailAccount!]!`,
  `mailboxes(accountId: ID): [Mailbox!]!`,
  `mailMessages(input: MailSearchInput!): MailMessageConnection!`, and
  `mailMessage(messageId: ID!): MailMessage`. The no-Mail-mutations check
  now inspects Mutation root field names/signatures instead of broad schema
  text. The dry-run remains non-prompting and does not query the live Mail
  store.

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
