# Phase 2: Apple Notes

**Status**: In Progress (blocked on Phase 0)
**Design Reference**: `design-docs/specs/design-apple-notes.md`

## Purpose

Notes listing, search, and writing over batched Apple Events (JXA),
including the shared `AppleEventBridge` that any future scripted domain
reuses.

## Deliverables

- [ ] `AppleEventBridge/` (osascript `-l JavaScript` subprocess runner:
      JSON-only argument passing, chunking, timeout, -1712 retry, error
      taxonomy)
- [ ] `Domains/NotesAdapter/` with JXA script templates for accounts,
      folders, bulk note metadata, body fetch, search, create, update,
      delete, move, attachment export
- [ ] Schema module: noteAccounts, noteFolders, notes, note; createNote,
      updateNoteBody, deleteNote, moveNote
- [ ] Body inlining rule (64 KiB) with `bodyFile` materialization via the
      Phase 0 file store

## Tasks

### TASK-001: AppleEventBridge

**Parallelizable**: No

Subprocess runner per the domain spec contract: script source is
compile-time template only, user data flows through the JSON argument
channel, stderr classified into `.automationDenied` / `.timeout` /
`.appUnavailable` / `.scriptFailure`.

**Completion Criteria**:

- [ ] Stub-osascript tests (fixture executable on PATH) cover success,
      -1712 retry-then-fail, permission-denied stderr, garbage output
- [ ] No code path concatenates user input into script source (reviewed +
      adversarial test with quote/backslash payloads)

### TASK-002: Read side (accounts, folders, listing, search)

**Parallelizable**: No (after TASK-001)

Bulk metadata fetch chunked by `apple_event_batch_size`; `whose`-based
body search app-side; metadata filters intersected in Swift; connections;
snippets; bodies excluded from list results.

**Completion Criteria**:

- [ ] Generated JXA goldens for each script template
- [ ] Search tests: name match, body match via `whose`, date filters,
      folder scoping, pagination
- [ ] Locked notes absent; stale locked-note id yields `NOTE_LOCKED`

### TASK-003: Body fetch and inlining rule

**Parallelizable**: Yes (after TASK-002)

`note(noteId:)` single-note body fetch; `max_inline_body_bytes` cutover to
`bodyFile` download keys (PLAINTEXT and HTML kinds); attachment listing
with best-effort export keys.

**Completion Criteria**:

- [ ] Boundary tests at the inline limit (under, equal, over)
- [ ] `file download` materializes note bodies; keys validated

### TASK-004: Write side

**Parallelizable**: Yes (after TASK-002)

createNote (bodyText-to-HTML conversion), updateNoteBody REPLACE/APPEND,
deleteNote (Recently Deleted), moveNote; result refetch for returned Note.

**Completion Criteria**:

- [ ] Exactly-one-of bodyHtml/bodyText enforced with `INVALID_ARGUMENT`
- [ ] APPEND read-modify-write covered by fake-bridge tests
- [ ] Lossy-HTML limitation stated in spec and command examples (docs
      check, no code)

### TASK-005: Schema registration, smoke flows, manual checklist

**Parallelizable**: No

Register the notes schema module, extend smoke tests over a fake provider,
update the SDL snapshot, and run the manual live checklist (scratch folder
create/search/append/move/delete; first-run Automation prompt behavior)
recording results below.

**Completion Criteria**:

- [ ] Reader serves reads, rejects notes mutations
- [ ] Manual checklist executed, including on macOS 26 (Tahoe timeout
      regression) with chunking observed to hold

## Progress Log

- 2026-07-02: Plan created from approved design docs.
