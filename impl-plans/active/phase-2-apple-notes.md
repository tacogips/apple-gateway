# Phase 2: Apple Notes

**Status**: TASK-001 through TASK-006 implementation complete; live Notes
manual verification remains permission-gated
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
      delete, and move
- [x] Live Notes attachment metadata, capability-backed export, nullable-key
      fallback, and best-effort shared-state derivation (TASK-006)
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

### TASK-006: Attachment Metadata, Export, and Shared State

**Status**: Complete

**Parallelizable**: No within the Notes adapter; depends on TASK-003 and uses
the existing FileStore contract

Replace the live adapter's three hardcoded `attachments: []` and
`isShared: false` payload fields with guarded Notes JXA metadata mapping.
Make attachment download keys conditional on a successful best-effort export,
and make `NotesFileMaterializer` serve an exported file instead of
unconditionally returning `FILE_OPERATION_FAILED`.

Design details are recorded in
`design-docs/specs/design-apple-notes.md#notes-attachment-metadata-export-and-shared-state-refinement`.
This task is limited to the Notes feature. Notification-helper date filtering
and permission-domain CLI help belong to separate feature fanout paths and
must not be changed here.

Implementation tasks:

1. Add one shared static JXA helper fragment for attachment metadata and
   shared-state mapping. Compose it into `fetchNoteMetadataBatch`,
   `probeNoteVisibility`, and `fetchNoteBody`; preserve static templates and
   JSON-only argv input.
2. Map attachment `id`, name/file-name fallback, and nullable content
   identifier. Reject null/undefined, JXA missing values, whitespace-only
   values, and normalized sentinel strings. Skip only the malformed
   attachment when its stable id is empty or unavailable; do not synthesize
   ids or transfer binary contents in JSON.
3. Derive `isShared` from a bridge-exposed boolean `shared` or `isShared`
   property. Preserve the documented `false` fallback when neither property
   is usable, without failing the enclosing note lookup.
4. Add a static attachment-export JXA template and a typed provider export
   result with distinct `exported(URL)`, `noteMissing`,
   `attachmentMissing`, and `unavailable` outcomes. Extend `NotesProviding`,
   `LiveNotesAppleEventAdapter`, `UnavailableNotesProvider`, Notes test
   doubles, and smoke fakes together.
5. Add a contained prepared-export location under the existing
   `snapshots/notes/attachments` subtree of the normalized FileStore cache so
   `file prune` already owns cleanup. Build its path only from path-safe
   encoded note/attachment ids and a sanitized filename. Canonicalize the
   root, reject symlink components before export, then revalidate the result
   as a contained non-symlink regular readable file; clean partial files on
   unsuccessful exports.
6. Change `NotesReadService.attachmentWithBestEffortKey` to issue an
   `ATTACHMENT` key only after a prepared export produces a regular readable
   file. During this preparation only, catch and clean up every non-success
   outcome and export-only error, returning the original attachment with
   `downloadKey == nil` without failing the note body response.
7. Change `NotesFileMaterializer.sourceFile` to decode and validate note and
   attachment ids, serve the prepared file when available, and otherwise
   retry provider export into its contained scratch directory. Map missing
   notes to `NOTE_NOT_FOUND`, `attachmentMissing`/`unavailable` stale keys to
   `INVALID_DOWNLOAD_KEY`, preserve Apple Event permission and timeout
   classifications, and reserve `FILE_OPERATION_FAILED` for actual filesystem
   I/O failure.
8. Add or extend Notes tests for canned JXA attachment decoding, shared-state
   true/false/fallback cases, successful export/download, nil-key fallback,
   empty and sentinel ids, filename sanitization, canonical containment,
   symlink rejection, partial-file cleanup, missing-note versus
   missing-attachment mapping, explicit-download permission/timeout
   propagation, filesystem-only `FILE_OPERATION_FAILED`, and
   provider/test-double conformance.
9. Add a generated-source golden for the export template plus adversarial
   tests proving `noteId`, `attachmentId`, and `destinationPath` travel only
   through encoded JSON argv and are never interpolated into script source.
10. Introduce one prepared-export store/root dependency and inject it into
    both `NotesReadService` and `NotesFileMaterializer`. Update
    `NotesServiceFactory`, `NotesServices`, and the live CLI/FileStore
    materializer composition so key preparation and download use the same
    configured storage cache root; preserve explicit test injection.
11. Update this task's checkboxes and Progress Log only after implementation
   and verification complete. Record any permission-gated live Notes result
   separately; automated completion does not require user Notes data.

**Dependencies and deliverables**:

- Existing `NotesProviding`, `LiveNotesAppleEventAdapter`,
  `NotesReadService`, `NotesFileMaterializer`, `NotesServiceFactory`,
  `NotesServices`, live file-materializer composition, FileStore key codec,
  and path-safety helpers remain the owning boundaries.
- Deliverables are the JXA metadata/export templates, provider export
  contract, capability-backed key fallback, working materializer path,
  updated fakes, focused tests, and this design/plan documentation.
- No GraphQL schema change is required: `NoteAttachment.downloadKey` and
  `contentIdentifier` are already nullable, and `Note.isShared` is already
  non-null.

**Completion Criteria**:

- [x] Live-template payload decoding can produce non-empty
      `[NoteAttachment]` with id, display name, and nullable content id
- [x] All three live note payload templates use the same attachment and
      shared-state mapping rules; no hardcoded empty/false placeholders remain
- [x] Shared state is true when exposed as true and false when explicitly
      false or unavailable, with fallback semantics preserved in the spec
- [x] Exportable attachments receive a valid `ATTACHMENT` key and download to
      the exported bytes through `NotesFileMaterializer`
- [x] Unsupported or unavailable export returns `downloadKey: null`; the note
      lookup still succeeds and no always-failing key is issued
- [x] Empty/malformed attachment ids, unsafe filenames, partial files, and
      canonical/symlink-safe cache containment have focused automated coverage
- [x] Provider outcomes distinguish missing note, missing attachment, and
      unavailable export; explicit materialization maps each outcome and
      preserves permission/timeout errors as designed
- [x] Export-template golden and adversarial tests prove all note ids,
      attachment ids, and destination paths remain JSON argv data
- [x] Live service/runtime composition shares one configured prepared-export
      root between key preparation and attachment materialization
- [x] `FILE_OPERATION_FAILED` coverage is limited to genuine filesystem I/O
      failures, not unsupported export or every attachment key
- [x] `UnavailableNotesProvider` and every Notes fake/smoke provider compile
      against the revised provider contract
- [x] `task build`, focused Notes tests, full `task test`, `task lint`, and
      `git diff --check` pass before any commit or push

**Verification commands**:

```bash
task build
swift test --filter Notes
task test
task lint
git diff --check
```

**Progress tracking**:

- [x] JXA metadata and shared-state mapping implemented
- [x] Provider export contract and all conformers updated
- [x] Capability-backed key issuance and materializer export implemented
- [x] Shared prepared-export root wired through live service composition
- [x] Focused Notes tests passing
- [x] Full build, test, lint, and diff verification passing
- [x] Progress Log updated with results and any residual manual-only risk
- [x] SELF-REVIEW-001 resolved by splitting attachment/export tests and
      smoke test doubles into cohesive Swift files below 1000 lines
- [x] SELF-REVIEW-002 resolved with deterministic behavioral coverage for
      normalization, shared false/fallback behavior, filename safety,
      canonical/symlink rejection, and timeout propagation

## Progress Log

- 2026-07-18: TASK-006 self-review revisions completed for
  `SELF-REVIEW-001` and `SELF-REVIEW-002`. Split attachment/export coverage
  into `Tests/AppleGatewayCoreTests/NotesAttachmentTests.swift`; split smoke
  entrypoint and test doubles into
  `Tests/AppleGatewaySmokeTests/AppleGatewaySmokeTests.swift` and
  `Tests/AppleGatewaySmokeTests/SmokeTestDoubles.swift`. All modified
  non-generated Swift files are now below 1000 lines. Added executable JXA
  behavior tests for empty, whitespace, and sentinel attachment values plus
  explicit-false and unavailable shared-state fallback; added unsafe filename,
  canonical escape, post-export symlink, and explicit timeout propagation
  tests. Verification passed with the Xcode SDK/toolchain pinned over the
  ambient incompatible Nix SDK: `swift test --filter Notes` (29 tests),
  `task build`, `task test` (185 tests plus AppleGatewaySmokeTests), and
  `task lint` (0 violations). `git diff --check` is recorded after this plan
  update.

- 2026-07-18: TASK-006 implemented. Added guarded shared JXA metadata helpers,
  typed attachment export outcomes, canonical prepared-export containment,
  capability-backed attachment keys, explicit materializer retry/error
  classification, configured-root service/materializer composition, and
  focused decoding/export/fallback/containment/injection tests. Verification
  passed: `task build`, `swift test --filter Notes` (25 tests), `task test`
  (181 tests plus AppleGatewaySmokeTests), `task lint` (0 violations), and
  `git diff --check`. Live Notes.app export remains optional manual
  verification because TCC and Notes scripting support vary by macOS release.

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
