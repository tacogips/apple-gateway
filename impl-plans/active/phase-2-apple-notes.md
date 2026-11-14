# Phase 2: Apple Notes

**Status**: Implementation complete; live Notes manual verification remains
permission-gated
**Design Reference**: `design-docs/specs/design-apple-notes.md`

## Purpose

Notes listing, search, and writing over batched Apple Events (JXA),
including the shared `AppleEventBridge` that any future scripted domain
reuses.

## Deliverables

- [x] `AppleEventBridge/` (osascript `-l JavaScript` subprocess runner:
      JSON-only argument passing, chunking, timeout, -1712 retry, error
      taxonomy; TASK-001 runner complete, TASK-002 read-side adapter chunk
      orchestration complete)
- [x] `Domains/NotesAdapter/` with JXA script templates for accounts,
      folders, bulk note metadata, body fetch, search, create, update,
      delete, move, attachment export
- [x] Schema module: noteAccounts, noteFolders, notes, note; createNote,
      updateNoteBody, deleteNote, moveNote
- [x] Body inlining rule (64 KiB) with `bodyFile` materialization via the
      Phase 0 file store
- [x] Live readiness helper:
      `scripts/live-notes-check.sh` dry-run permission checks plus exact
      Notes Query/Mutation root-field schema checks and permission-gated
      read-only metadata mode

## Tasks

### TASK-001: AppleEventBridge

**Parallelizable**: No

Subprocess runner per the domain spec contract: script source is
compile-time template only, user data flows through the JSON argument
channel, stderr classified into `.automationDenied` / `.timeout` /
`.appUnavailable` / `.scriptFailure`.

Design details are recorded in
`design-docs/specs/design-apple-notes.md#appleeventbridge-subprocess-boundary`.
TASK-001 implementation is limited to the shared subprocess runner and its
stub-osascript tests; Notes adapter templates and live Notes behavior remain
later Phase 2 tasks.

**Completion Criteria**:

- [x] Stub-osascript tests (fixture executable on PATH) cover success,
      local timeout retry, -1712 retry-then-fail, permission-denied stderr,
      garbage output
- [x] No code path concatenates user input into script source (reviewed +
      adversarial test with quote/backslash payloads)

### TASK-002: Read side (accounts, folders, listing, search)

**Parallelizable**: No (after TASK-001)

Bulk metadata fetch chunked by `apple_event_batch_size`; `whose`-based
body search app-side; metadata filters intersected in Swift; connections;
snippets; bodies excluded from list results.

**Completion Criteria**:

- [x] Generated JXA goldens for each script template
- [x] Search tests: name match, body match via `whose`, date filters,
      folder scoping, pagination
- [x] Locked notes absent; stale locked-note id yields `NOTE_LOCKED`

### TASK-003: Body fetch and inlining rule

**Parallelizable**: Yes (after TASK-002)

`note(noteId:)` single-note body fetch; `max_inline_body_bytes` cutover to
`bodyFile` download keys (PLAINTEXT and HTML kinds); attachment listing
with best-effort export keys.

Design details are recorded in
`design-docs/specs/design-apple-notes.md#task-003-body-fetch-and-file-materialization-contract`.
TASK-003 is limited to the single-note read path and Phase 0 FileStore
download-key materialization. It must preserve TASK-001's static JXA
template plus JSON argv boundary and TASK-002's list/search behavior where
full bodies and body files are absent from connection nodes.

**Completion Criteria**:

- [x] Boundary tests at the inline limit (under, equal, over)
- [x] `PLAINTEXT` and `HTML` bodyFile download keys validate
- [x] `file download` materializes note bodies from Phase 0 FileStore keys
- [x] Attachment listing returns best-effort export keys without live Notes
- [x] TASK-001 JSON-argv static-template boundary remains preserved
- [x] TASK-002 read-side list/search behavior remains preserved

### TASK-004: Write side

**Parallelizable**: Yes (after TASK-003)

createNote (bodyText-to-HTML conversion), updateNoteBody REPLACE/APPEND,
deleteNote (Recently Deleted), moveNote; result refetch for returned Note.

**Completion Criteria**:

- [x] Exactly-one-of bodyHtml/bodyText enforced with `INVALID_ARGUMENT`
- [x] APPEND read-modify-write covered by fake-bridge tests
- [x] Lossy-HTML limitation stated in spec and command examples (docs
      check, no code)

### TASK-005: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the Notes GraphQL schema module for both full and reader roles,
wire resolvers through the existing `NotesReadService` and
`NotesWriteService`, extend fake-backed smoke coverage, update schema print
coverage or stored SDL snapshots, and add the permission-gated live Notes
manual checklist.

Design details are recorded in
`design-docs/specs/design-apple-notes.md#task-005-schema-registration-smoke-flows-and-live-checklist-contract`.
TASK-005 is limited to the GraphQL/CLI integration boundary and live
verification checklist. It must not introduce a second Notes data path and
must preserve TASK-001 static JXA template plus JSON-argv behavior,
TASK-002/TASK-003 read behavior, and TASK-004 write behavior.

Implementation tasks:

1. Register the Notes query surface in full and reader schema roles:
   `noteAccounts`, `noteFolders`, `notes`, and `note`.
2. Register the Notes mutation surface in full mode only:
   `createNote`, `updateNoteBody`, `deleteNote`, and `moveNote`.
3. Ensure `apple-gateway-reader` serves Notes read queries but rejects Notes
   mutations at the GraphQL operation boundary with `WRITE_DISABLED_IN_READER`
   before resolver dispatch.
4. Wire query resolvers only through `NotesReadService` so account/folder
   validation, search intersection, pagination, body inlining, FileStore keys,
   and locked-note classification remain owned by the existing read service.
5. Wire mutation resolvers only through `NotesWriteService` so body validation,
   `bodyText` conversion, `APPEND` sequencing, delete-to-Recently-Deleted,
   move behavior, and returned-note refetch remain owned by the existing write
   service.
6. Preserve fake `NotesProviding` and `NotesWriting` injection for GraphQL
   tests and CLI smoke flows. Live defaults may construct
   `LiveNotesAppleEventAdapter`, but automated tests must not require live
   Notes.app, TCC state, or user Notes data.
7. Extend fake-backed smoke coverage for create, search/list,
   append-or-update, move, delete, and reader-mode mutation rejection. Smoke
   assertions should prove resolver-to-service wiring and response shape
   without duplicating every lower-level Notes service test.
8. Update stored SDL snapshots when present; otherwise add or update schema
   coverage assertions for the exact reader/full field exposure rules.
9. Add or update a live manual checklist under
   `impl-plans/live-checklists/` for scratch folder create/search/
   append-or-update/move/delete, first-run Automation prompt behavior,
   reader read success, reader mutation rejection, and macOS 26 Tahoe
   timeout/chunking observation.
10. Record implementation results, verification commands, live checklist
    status, permission blockers, and any follow-up findings in this plan's
    Progress Log.

**Completion Criteria**:

- [x] Full schema exposes all Notes query and mutation fields listed above
- [x] Reader schema/execution exposes Notes read queries and rejects Notes
      mutations with `WRITE_DISABLED_IN_READER` before writer dispatch
- [x] GraphQL resolvers use `NotesReadService` and `NotesWriteService`;
      there is no alternate Notes provider/writer path
- [x] Fake-backed smoke tests cover create, search/list, append-or-update,
      move, delete, and reader-mode mutation rejection
- [x] SDL snapshot or schema coverage explicitly verifies reader/full Notes
      field exposure
- [x] Live manual checklist file exists for scratch-only Notes verification,
      including first-run Automation prompt behavior and macOS 26 Tahoe
      timeout/chunking observation
- [x] TASK-001 static JXA JSON-argv boundary and TASK-002/TASK-003/TASK-004
      behavior remain covered by the relevant existing tests
- [x] Verification passes with `task build`, `task test`, `task lint`, and
      `swift run apple-gateway --help`

## Progress Log

- 2026-07-02: Plan created from approved design docs.
- 2026-07-03: TASK-001 design boundary refined for static JXA templates,
  JSON-only argv arguments, chunking ownership, timeout retry behavior,
  stderr classification, stub-osascript coverage, and permission-gated live
  verification.
- 2026-07-03: TASK-001 implementation completed via Riela session
  `codex-design-and-implement-review-loop-session-363` intake; the session
  completed `step2-design-doc-update` after recording the design boundary,
  then failed during `step2-design-self-review`, so local implementation
  continued against the accepted intake and completed design update.
  Added the shared `AppleEventBridge` runner and stub-osascript tests for
  JSON argv passing, timeout retry, -1712 retry-then-fail,
  permission-denied stderr, garbage stdout, invalid argument JSON, and
  quote/backslash injection payload separation. Verification passed:
  `swift build`, `swift test --filter AppleEventBridge`, `task test`,
  `swiftlint`, and `swift run apple-gateway --help`.
- 2026-07-03: TASK-002 design boundary routed through Riela session
  `codex-design-and-implement-review-loop-session-365`; intake and
  `step2-design-doc-update` completed and refined the read-side contract to
  seven static JXA templates, account/folder validation, metadata batching,
  Swift-side filter intersection, body-id search via `whose`, page-only
  snippets, opaque cursors, and locked-note classification. Riela
  self-review first requested a query-semantics clarification, then accepted
  the design update; the live stream was stopped during
  `step3-design-review`, leaving the session status failed at that step.
  Implemented Notes read models, `NotesProviding`,
  `LiveNotesAppleEventAdapter`, `NotesReadService`, and fake-provider tests.
  Verification passed: `swift build`, `swift test --filter Notes`,
  `task test`, `swiftlint`, and `git diff --check`.
- 2026-07-03: TASK-003 design-doc update routed through Riela session
  `codex-design-and-implement-review-loop-session-367`; documented the
  single-note body fetch contract, strict-over inline cutoff semantics,
  Phase 0 FileStore key payloads for `PLAINTEXT` and `HTML`, `file download`
  body materialization, best-effort attachment export keys, and fake-provider
  test boundaries. TASK-004 mutations and TASK-005 schema registration remain
  out of scope.
- 2026-07-03: TASK-003 implementation completed from Riela session
  `codex-design-and-implement-review-loop-session-367`; Riela accepted
  intake, design-doc update, self-review, and independent design review with
  one low clarification about `NoteBodyFile.byteSize` not being part of the
  signed FileStore key payload. The live stream was then stopped and the
  persisted session ended failed at `step3-design-review`. Added
  `fetchNoteBody`, single-note body fetch, UTF-8 inline cutoff, reversible
  path-safe Notes source ids for FileStore payloads, `PLAINTEXT`/`HTML`
  bodyFile keys, `NotesFileMaterializer`, and best-effort attachment keys.
  Verification passed: `swift build`, `swift test --filter Notes`,
  `task test`, `swiftlint`, and `git diff --check`.
- 2026-07-03: TASK-004 implementation completed from Riela session
  `codex-design-and-implement-review-loop-session-369`; Riela accepted the
  TASK-004 design-doc update and independent design review with no findings.
  Added Notes write inputs/requests, `NotesWriting`, `NotesWriteService`,
  live adapter write templates for create/replace/delete/move, and
  fake-provider write tests for exactly-one body validation,
  bodyText-to-HTML conversion, REPLACE, APPEND read-modify-write sequencing,
  delete-to-Recently-Deleted behavior, move refetch behavior, and lossy-HTML
  docs coverage. TASK-005 schema registration and live smoke/manual flows
  remain out of scope. Verification passed with the Xcode SDK environment:
  `swift build`, `swift test --filter Notes`, `task test`, `swiftlint`, and
  `git diff --check`.
- 2026-07-03: TASK-005 design and implementation routed through Riela
  session `codex-design-and-implement-review-loop-session-371`; Riela
  accepted intake, design-doc update, self-review, independent design review,
  and the implementation plan with no blocking findings. Added the Notes
  GraphQL schema module, full/reader schema registration, Notes read/write
  service injection through `GraphQLRuntime` and `AppleGatewayCommand`,
  unavailable/live Notes service factories, schema coverage tests for
  full/reader field exposure, GraphQL fake-service tests for read and write
  resolver wiring, fake-backed CLI smoke flows for create/search/append/move/
  delete and reader mutation rejection, and
  `impl-plans/live-checklists/phase-2-apple-notes-live.md`. Live manual
  execution remains permission-gated and was not run in this automated pass.
  Verification passed with the Xcode SDK environment: `task build`,
  `task test`, `task lint`, `swift run apple-gateway --help`, and
  `git diff --check`.
- 2026-07-03: Documentation/status cleanup routed through Riela session
  `codex-simple-work-package-session-395`; the workflow identified the stale
  unchecked NotesAdapter deliverable, then the local process was stopped
  before file edits. Updated the deliverable checkbox to match the completed
  JXA template, adapter, read/write, schema, smoke, and live-checklist
  evidence already recorded above. Live manual verification remains
  permission-gated. Verification: `git diff --check`, `task build`, and
  `swift run apple-gateway --help`.
- 2026-07-03: Documentation-only Phase 2 status cleanup completed via Riela
  session `codex-simple-work-package-session-410`. Updated the top-level
  status to state implementation complete while preserving the live Notes
  manual verification permission-gated blocker. Verified with `rg` that the
  document preserves the permission-gated manual verification blocker.
  Verification: `rg` status/blocker checks and `git diff --check`.
- 2026-07-03: Added Phase 2 Notes live readiness helper via
  `codex-simple-work-package-session-418`. The default
  `scripts/live-notes-check.sh` path is dry-run, non-prompting, and
  non-mutating: it prints the live checklist path, runs
  `permissions status --json`, reports `notesAutomation`, checks exact Query
  root fields `noteAccounts`, `noteFolders`, `notes`, and `note` in full and
  reader schemas, checks exact Mutation root fields `createNote`,
  `updateNoteBody`, `deleteNote`, and `moveNote` are full-schema only, and
  states that no live Notes query was performed. The explicit `--read-only`
  mode refuses unless Notes Automation is `GRANTED`; when granted it is
  limited to metadata reads for `noteAccounts`, `noteFolders`, and
  `notes(input: { first: 5 })`. Scratch write verification remains a
  permission-gated manual checklist step.
- 2026-07-03: Hardened the default Phase 2 Notes live readiness helper via
  Riela session `codex-simple-work-package-session-430` so dry-run schema
  readiness extracts the `type Query` and `type Mutation` root blocks before
  exact-line checks. The dry-run validates full and reader schemas expose
  exact Notes Query root fields `noteAccounts: [NoteAccount!]!`,
  `noteFolders(accountId: ID): [NoteFolder!]!`,
  `notes(input: NoteSearchInput!): NoteConnection!`, and
  `note(noteId: ID!): Note`; validates the full schema exposes exact Notes
  Mutation root fields `createNote(input: CreateNoteInput!): Note!`,
  `updateNoteBody(input: UpdateNoteBodyInput!): Note!`,
  `deleteNote(noteId: ID!): DeleteResult!`, and
  `moveNote(noteId: ID!, folderId: ID!): Note!`; and validates reader schema
  does not expose those Mutation root fields. Default dry-run remains
  non-prompting, non-mutating, and does not query live Notes metadata.
