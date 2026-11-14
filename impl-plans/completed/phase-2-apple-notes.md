# Phase 2: Apple Notes

**Status**: TASK-001 through TASK-007 implementation complete; live Notes
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
- [x] Page-local Notes list hydration with guarded per-note shared-state and
      attachment fallbacks, plus focused pagination and failure-isolation
      regressions (TASK-007)

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

### TASK-007: Page-Local Metadata Hydration and Failure Isolation

**Status**: Complete

**Workflow mode**: `issue-resolution`

**Issue references**: `comm-001899`, `comm-001903`, `comm-001913`,
`comm-001917`, `comm-001922`, `comm-001923`, `comm-001925`, `comm-001927`,
`comm-001932`

**Codex-agent references**: None supplied; reference-repository mapping,
intentional divergence, and Cursor adapter work are not applicable.

**Parallelizable**: No. The provider contract, live JXA behavior, read-service
orchestration, and regression fixtures describe one two-phase data flow and
must be finalized and verified together. Later work may separate tests into a
new file, but it must not proceed against an unsettled provider contract.

Resolve only the two accepted Notes list-hydration findings. Preserve the
accepted design in
`design-docs/specs/design-apple-notes.md#notes-attachment-metadata-export-and-shared-state-refinement`:
candidate discovery, filtering, deterministic sorting, cursor resolution, and
page slicing use lightweight metadata; shared state and attachment metadata
are fetched only for the selected page and use per-note compatibility
fallbacks. Do not change GraphQL schema, cursor format, body or attachment
export behavior, mutation behavior, other domains, or live-checklist scope.

**Deliverables and implementation tasks**:

1. Define the two-phase metadata boundary in
   `Sources/AppleGatewayCore/Domains/NotesAdapter/NotesProviding.swift` and
   `Sources/AppleGatewayCore/Domains/NotesAdapter/LiveNotesAppleEventAdapter.swift`.
   Preserve existing provider compatibility where safe, expose a lightweight
   summary operation for candidate evaluation, and expose page-detail
   hydration that accepts only selected notes or ids. The live summary and
   detail paths must use vectorized requests bounded by
   `limits.apple_event_batch_size` so JSON argv size remains bounded.
2. Update
   `Sources/AppleGatewayCore/Domains/NotesAdapter/NotesReadService.swift` so it
   filters, sorts, resolves the cursor, and slices the page before requesting
   detail metadata. Pass only page ids to hydration, preserve edge order and
   search snippets while merging detail results, and skip the provider
   hydration call entirely when the page has no edges.
3. Revise `fetchNoteMetadataBatch` and its shared helper fragment in
   `Sources/AppleGatewayCore/Domains/NotesAdapter/NotesJXATemplates.swift`.
   Lightweight mode may bulk-read only identity, scope, lock-state, name, and
   sortable dates. Detail mode must identify the requested notes before
   reading `shared`, `isShared`, or `attachments`; it must not call folder- or
   account-wide shared/attachment accessors. Guard each selected note's
   sharing and attachment collection independently, retain the documented
   `isShared: false` and empty-attachment fallbacks for detail-only failures,
   and continue hydrating remaining selected notes. Do not downgrade failures
   in required lightweight metadata.
4. Add focused service regressions for page-limited hydration and empty-page
   behavior. Record requested summary ids, hydrated ids, and batch sizes in a
   test provider; prove a multi-page candidate set hydrates only the current
   page, a later page hydrates its own ids, snippets and ordering survive the
   merge, and an empty page issues no hydration request.
5. Add executable or fixture-backed JXA regressions proving detail hydration
   never touches unselected notes' shared state or attachments and that a
   selected note with an unavailable sharing property or attachment
   collection falls back without aborting or discarding another selected
   note. Keep permission and timeout errors at the existing bridge boundary.
   Prefer a cohesive new
   `Tests/AppleGatewayCoreTests/NotesHydrationTests.swift`; update
   `Tests/AppleGatewayCoreTests/NotesReadServiceTests.swift` and
   `Tests/AppleGatewayCoreTests/NotesAttachmentTests.swift` only where their
   existing goldens, helpers, or assertions own the behavior. No modified
   non-generated Swift file may exceed 1000 lines.
6. After implementation, update this task's status, checkboxes, and Progress
   Log with exact commands, test counts, environment-only failures, and
   residual permission-gated live Notes risks. Do not mark TASK-007 complete
   until every automated completion criterion passes.

**Dependencies**:

- Accepted design review `comm-001906` and design requirements at
  `design-docs/specs/design-apple-notes.md:253`, `:262`, and `:354`.
- Existing `NotesProviding`, `LiveNotesAppleEventAdapter`,
  `NotesReadService`, static JSON-argv JXA templates, `NoteConnection`
  pagination, snippet retrieval, and Notes test fixtures.
- TASK-001 timeout and error classification and TASK-006 guarded metadata
  helpers remain authoritative; this task narrows when and where detail
  hydration occurs without redesigning either boundary.

**Completion Criteria**:

- [x] Candidate filtering, sorting, cursor resolution, and page slicing use
      lightweight metadata with no shared-state or attachment reads.
- [x] Detailed hydration receives only selected page ids, is chunked by
      `apple_event_batch_size`, and is not invoked for an empty page.
- [x] The live JXA detail path does not evaluate account- or folder-wide
      `shared` or `attachments` collections before selected-id filtering.
- [x] A sharing-property or attachment-access failure for one selected note
      yields only that note's documented fallback and does not abort or erase
      another selected note's details.
- [x] Required identity, scope, lock-state, name, creation-date, and
      modification-date failures remain operation-level errors.
- [x] Missing, locked, or scope/sort-changed page hydration is rejected as
      stale instead of returning the retained lightweight summary.
- [x] Native Notes application-unavailable and connection-invalid errors
      (`-600` and `-609`) propagate through detail guards to the shared bridge
      classifier.
- [x] Lightweight summary requests honor `apple_event_batch_size` instead of
      serializing every candidate id into one subprocess argument.
- [x] Apple Event stdout and stderr captures are owner-only, use a private
      directory, and are cleaned after success and failure.
- [x] Local timeout handling has a bounded termination grace period and
      force-kills a subprocess that ignores termination.
- [x] Hydration merging preserves deterministic edge order, cursor/page info,
      total count, snippets, and body exclusion.
- [x] Focused regressions cover first/later pages, empty pages, unselected-note
      non-access, and per-note failure isolation without live Notes.app.
- [x] Scope remains limited to the listed Notes adapter/service/test files,
      shared bridge classification and tests, the Notes design, and this plan;
      no schema, write-path, export, or other-domain behavior changes.
- [x] All modified non-generated Swift files remain below 1000 lines.
- [x] Focused Notes tests, the prior scoped regression suite, build, lint, and
      diff checks pass.

**Verification commands**:

```bash
swift test --filter AppleEventBridge
swift test --filter NotesHydration
swift test --filter Notes
nix develop -c bash -lc 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault; export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH; swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"'
task build
task lint
git --no-pager diff --no-ext-diff --check -- Sources/AppleGatewayCore/AppleEventBridge/AppleEventBridge.swift Sources/AppleGatewayCore/Domains/NotesAdapter Tests/AppleGatewayCoreTests design-docs/specs/design-apple-notes.md impl-plans/active/phase-2-apple-notes.md
wc -l Sources/AppleGatewayCore/AppleEventBridge/AppleEventBridge.swift Sources/AppleGatewayCore/Domains/NotesAdapter/*.swift Tests/AppleGatewayCoreTests/*.swift
```

**Progress tracking**:

- [x] Provider summary/hydration boundary finalized
- [x] Read service paginates before hydration and skips empty-page hydration
- [x] JXA detail access is selected-id-only and isolated per note
- [x] Stale hydration, application-unavailable, and connection-invalid bridge
      failures are rejected
- [x] Summary argv batching, private capture, cleanup, and hard-timeout
      regressions pass
- [x] Focused pagination, empty-page, non-access, and failure-isolation tests pass
- [x] Scoped regressions, build, lint, diff, and file-length checks pass
- [x] Progress Log records exact results and remaining live-only risks

## Progress Log

- 2026-08-03: Addressed Step 7 adversarial review `comm-001932` for TASK-007.
  `AppleEventBridge` now captures output in a mode-0700 directory with mode-0600
  files and removes the directory on every post-creation exit path. Local
  timeout handling now applies a bounded termination grace period, sends
  `SIGKILL` when termination is ignored, and bounds final reaping.
  `LiveNotesAppleEventAdapter` now honors `apple_event_batch_size` for
  lightweight summary argv payloads. Added stub-process regressions for actual
  capture-file permissions and cleanup, a SIGTERM-ignoring process, and
  summary batching. An initial focused run exposed a test-fixture mistake that
  inspected `/dev/fd` device-node modes; resolving the descriptors with `lsof`
  corrected the fixture. Final Xcode-pinned verification passed:
  `swift test --filter AppleEventBridge` (12 tests),
  `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  (98 tests, including 5 NotesHydration tests), `task build`, and
  `swiftlint --quiet`. Diff and file-length checks passed; the largest relevant
  modified Swift file is 964 lines. Live Notes.app compatibility remains
  permission-gated and macOS-version-dependent.

- 2026-08-03: Addressed Step 7 adversarial review `comm-001927` for TASK-007.
  JXA detail guards now rethrow native connection-invalid `-609` errors from
  both sharing-property and attachment-collection access, and the shared
  `AppleEventBridge` classifies `-609` stderr as `.appUnavailable`. Added
  focused executable regressions for both hydration paths plus bridge
  classification. Verification passed in the Xcode-pinned environment:
  `swift test --filter "NotesHydration|AppleEventBridge"` (14 tests),
  `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  (95 tests), `task build`, and `swiftlint --quiet`. The full
  `swift test` output completed with 249 passing tests and one unrelated
  live EventKit test skipped before the enclosing runner timed out. Diff and
  file-length checks passed; the largest relevant modified Swift file is 964
  lines. Live Notes.app compatibility remains permission-gated and
  macOS-version-dependent.

- 2026-08-03: Addressed Step 7 adversarial review `comm-001922` for TASK-007.
  Live hydration now returns observed detail records to `NotesReadService`,
  which rejects missing, duplicate, locked, or changed identity/scope/name/date
  records before merging page-local shared state and attachments. Extended the
  executable JXA bridge guard to rethrow native application-unavailable `-600`
  errors. Added focused regressions for missing/locked/moved hydration results
  and `.appUnavailable` classification. Verification passed in the
  Xcode-pinned environment: `swift test --filter NotesHydration` (5 tests),
  `swift test --filter Notes` (34 tests),
  `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  (94 tests), `task build`, and `swiftlint --quiet`. Diff and file-length checks
  passed after this plan update. Live Notes.app compatibility remains
  permission-gated and macOS-version-dependent.

- 2026-08-03: Addressed Step 7 review `comm-001917` for TASK-007. Wrapped
  selected-note attachment collection access and enumeration in one per-note
  guard so non-bridge enumeration failures produce that note's documented
  empty-attachment fallback, while native automation denial (`-1743`) and
  timeout (`-1712`) errors still propagate through the bridge. Extended
  `Tests/AppleGatewayCoreTests/NotesHydrationTests.swift` with an executable
  lazy-enumeration failure fixture proving another selected note retains its
  hydrated details. Verification passed in the Nix/Xcode-pinned environment:
  `swift test --filter NotesHydration` (4 tests), `swift test --filter Notes`
  (33 tests), `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  (93 tests), `task build`, and `swiftlint --quiet`. TASK-007 completion
  criteria remain satisfied after the review fix; live Notes.app compatibility
  remains permission-gated and macOS-version-dependent.

- 2026-08-03: Addressed Step 7 review `comm-001913` for TASK-007. Updated
  native JXA bridge-failure detection to recognize `error.errorNumber` for
  automation denial (`-1743`) and timeout (`-1712`), while retaining
  `error.number` compatibility. Updated the executable hydration fixture to
  use native JXA error semantics so the permission and timeout propagation
  regressions no longer pass through a synthetic property mismatch.
  Verification passed in the Nix/Xcode-pinned environment:
  `swift test --filter NotesHydration` (4 tests),
  `swift test --filter Notes` (33 tests),
  `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  (93 tests), `task build`, and `swiftlint --quiet`. An initial parallel
  ambient `task build` attempt encountered the known incompatible Nix SDK
  11.3/Xcode Swift 6.3.3 environment plus a concurrent SwiftPM build lock;
  the sequential pinned verification above corrected both conditions.
  `git --no-pager diff --no-ext-diff --check -- Sources/AppleGatewayCore/Domains/NotesAdapter Tests/AppleGatewayCoreTests design-docs/specs/design-apple-notes.md impl-plans/active/phase-2-apple-notes.md`
  passed. File-length verification found every modified non-generated Swift
  file below 1000 lines (largest: 960 lines).

- 2026-08-03: TASK-007 implemented for issue references `comm-001899` and
  `comm-001903` under accepted review `comm-001906`. Added the two-phase
  `NotesProviding` summary/hydration boundary, page-before-hydration service
  orchestration, selected-id-only JXA detail reads, per-note sharing and
  attachment fallbacks, and explicit propagation of Apple Event permission
  (`-1743`) and timeout (`-1712`) failures. Added
  `Tests/AppleGatewayCoreTests/NotesHydrationTests.swift` for first/later page
  selection, empty-page skipping, metadata/snippet preservation, unselected
  note non-access, fallback isolation, and bridge-error classification.
  Verification passed: `swift test --filter NotesHydration` (4 tests),
  `swift test --filter Notes` (33 tests), the Nix/Xcode-pinned
  `swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"`
  suite (93 tests), `task build`, `swiftlint` (0 violations across 130 files),
  and `git --no-pager diff --no-ext-diff --check -- Sources/AppleGatewayCore/Domains/NotesAdapter Tests/AppleGatewayCoreTests design-docs/specs/design-apple-notes.md impl-plans/active/phase-2-apple-notes.md`.
  The Nix-wrapped scoped command printed the complete passing test result
  before the enclosing command runner timed out; no test failed and no test
  process remained. File-length verification found every modified
  non-generated Swift file below 1000 lines (largest: 960 lines). Live
  Notes.app compatibility remains permission-gated and macOS-version-dependent.

- 2026-08-03: TASK-007 implementation plan created in `issue-resolution`
  mode from accepted review `comm-001906` for findings `comm-001899` and
  `comm-001903`. No implementation code was written in this planning step.
  Codex-agent references were not supplied and are not applicable. Plan-file
  verification: `git --no-pager diff --no-ext-diff --check -- impl-plans/active/phase-2-apple-notes.md`.

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
