# Apple Notes Design

## Status

Draft

## Mechanism

Apple Events to Notes.app, executed as JXA (JavaScript for Automation)
scripts through the shared `AppleEventBridge` (osascript subprocess,
`-l JavaScript`). JXA is chosen over classic AppleScript because results
are `JSON.stringify`-ed inside the script and parsed with
`JSONSerialization` in Swift: one marshalling format, no AppleScript
record-to-text parsing.

Writing NoteStore.sqlite directly is prohibited (CloudKit sync corruption
risk); a direct-SQLite fast-read mode is a possible future optimization,
recorded as an open question, not part of v1.

### Batching and the Tahoe Timeout Regression

Per-note property access costs one Apple Event round trip. All list/search
metadata operations use bulk property fetch, JXA equivalent of
`get {id, name, modification date} of every note`, chunked by
`limits.apple_event_batch_size` (default 200), each chunk wrapped in an
explicit timeout (`limits.apple_event_timeout_seconds`, default 30) with
one retry on error -1712. Full bodies are never returned during list/search;
only `note(noteId:)` in TASK-003 fetches a complete body, one note at a
time. TASK-002 search may ask Notes.app to evaluate plaintext app-side and
may return only bounded snippets for the current result page.

`AppleEventBridge` contract (shared with any future scripted domain):

```swift
struct AppleEventBridge: Sendable {
  func runJXA(script: String, argumentsJSON: String) throws -> Data
  // throws AppleEventError: .automationDenied, .timeout, .appUnavailable,
  //                         .scriptFailure(message:)
}
```

Scripts are compile-time string templates in Swift; user input travels only
through the JSON `arguments` channel (never spliced into script source), so
script injection is structurally impossible.

### AppleEventBridge Subprocess Boundary

Phase 2 TASK-001 establishes the shared subprocess boundary before any
Notes-specific adapter scripts are added. The boundary is intentionally
small: Swift supplies a static JXA source template and one JSON document of
arguments; `osascript -l JavaScript` returns one JSON document on stdout.
No caller-provided account id, folder id, note id, search text, note title,
HTML, plaintext, file path, or pagination cursor may be interpolated into
the script source. Template selection happens in Swift code by choosing a
known static template.

JXA templates have one entrypoint shape:

```javascript
function run(argv) {
  const input = JSON.parse(argv[0]);
  // Script-specific logic returns JSON.stringify(result).
}
```

The Swift bridge validates that `argumentsJSON` is UTF-8 JSON before launch,
passes it as an argv value after `-e <static template>`, and validates that
successful stdout is JSON before returning bytes to the domain adapter. This
keeps quote, backslash, newline, HTML, and script-like payloads as data
rather than executable source.

Chunking belongs to the adapter/bridge boundary, not to GraphQL resolvers.
Read operations that can address many Notes objects split stable object ids
or fetch windows by `limits.apple_event_batch_size` (default 200). Each
chunk executes as an independent `runJXA` call with the same static template
and a different JSON argument payload. A chunk failure fails the overall
operation with the classified bridge error; later phases may add partial
progress only if the GraphQL contract is extended to represent it.

Timeout handling has two sources:

- Local process timeout: the Swift bridge kills the `osascript` process after
  `limits.apple_event_timeout_seconds` (default 30), classifies the result as
  `.timeout`, and retries once.
- AppleEvent timeout regression: stderr containing `-1712` or equivalent
  timeout wording is classified as `.timeout` and retried once.

After the single retry, the timeout is returned to the caller. Retry does not
change arguments, chunk size, or script template; this prevents retries from
masking persistent Notes or TCC failures.

The bridge error taxonomy is the only boundary visible to domain adapters:

| Error | Classification input | Caller behavior |
| --- | --- | --- |
| `.automationDenied` | TCC/Automation stderr, including `-1743` or not-authorized wording | Surface a permission error with guidance to grant Automation access. |
| `.timeout` | Local timeout, `-1712`, or timeout wording on stderr | Retry once, then fail the operation. |
| `.appUnavailable` | `osascript` launch failure, application-not-running, app-not-found, or `-600` style stderr | Surface application unavailable. |
| `.scriptFailure` | Nonzero exit not otherwise classified, empty/garbage successful stdout, or script-thrown JSON error | Surface an internal script failure without exposing untrusted payload as source. |

Stub-osascript tests cover the boundary without requiring live Notes or TCC
state: success JSON, local timeout retry, `-1712` retry-then-fail,
permission-denied stderr, garbage stdout, and quote/backslash injection
payloads. Live Notes verification remains permission-gated and belongs to
the Phase 2 manual checklist after TASK-001 unit coverage passes.

### TASK-002 Read-Side Contract

TASK-002 implements read-side Notes support only: accounts, folders,
metadata listing, search, connection pagination, snippets for search
results, and locked-note classification. It must not implement TASK-003
body fetch/inlining or TASK-004 mutations.

The adapter uses only static JXA templates selected by Swift code:

| Template | Purpose | Body handling |
| --- | --- | --- |
| `listAccounts` | Return account ids, names, and default-account marker. | No body access. |
| `listFolders` | Return folder ids, account ids, parent ids when available, names, and note counts. | No body access. |
| `listNoteMetadataWindow` | Return note ids and metadata from a folder/account window for listing. | No body access. |
| `fetchNoteMetadataBatch` | Return metadata for a Swift-provided batch of note ids, capped by `apple_event_batch_size`. | No body access. |
| `searchNoteIdsByPlaintext` | Return note ids matching a query using a Notes.app `whose` predicate over plaintext. | App-side predicate only; no full body returned. |
| `fetchSearchSnippetsBatch` | Return bounded snippets for the already-paginated search result ids. | Returns snippet text only, never full plaintext or HTML. |
| `probeNoteVisibility` | Classify explicit note ids as visible, missing, or locked/inaccessible. | No full body returned. |

All templates keep the TASK-001 JSON-argv boundary: filter values,
account ids, folder ids, note ids, query strings, date bounds, page sizes,
and cursors are JSON arguments and are never interpolated into JXA source.

Read-side data flow:

1. Resolve account and folder filters through `listAccounts` and
   `listFolders`. Unknown account or folder ids fail with the domain error
   (`INVALID_ARGUMENT` for an unknown account id, `NOTE_FOLDER_NOT_FOUND`
   for an unknown folder id) before broad note enumeration.
2. Enumerate candidate note ids from account/folder scope without fetching
   bodies. Metadata is fetched with `fetchNoteMetadataBatch` in chunks no
   larger than `limits.apple_event_batch_size`.
3. Apply non-query metadata filters in Swift. Date filters compare
   normalized `DateTime` values with an inclusive lower bound for
   `modifiedAfter` and an exclusive upper bound for `modifiedBefore`.
4. If `query` is present, evaluate the query as
   `(name contains query OR body plaintext contains query)` within the
   account, folder, and date-filtered candidate set. Swift evaluates the
   name side case-insensitively over bulk-fetched note names, asks Notes.app
   for body matches with `searchNoteIdsByPlaintext` using a `whose`
   predicate, unions the name-match ids and body-match ids, then intersects
   that union with the non-query metadata-filtered ids. A body match never
   broadens account, folder, or date scope; a name-only match does not need
   a body match.
5. Sort results by modification date descending, then id ascending for a
   deterministic tie-breaker, and apply cursor pagination in Swift. Cursors
   are opaque base64url JSON containing the sort keys and id; invalid or
   stale cursors return `INVALID_ARGUMENT`.
6. For search results, fetch snippets only for the current page and only
   with `fetchSearchSnippetsBatch`. Snippets are normalized plaintext,
   bounded to 300 Unicode scalar characters, and centered around the query
   when a body match exists. For name-only matches with no body hit, the
   adapter returns an empty snippet rather than fetching full body text.
   List results do not expose `plaintext`, `bodyHtml`, or `bodyFile`; when
   no search snippet is available, `snippet` is the empty string.

Locked notes are absent from account/folder listings, metadata batches, and
search results because Notes.app does not expose them through normal Apple
Events. If a previously captured note id is later supplied to an explicit
visibility or metadata lookup and Notes.app reports it as locked or
inaccessible, the adapter returns `NOTE_LOCKED`; if Notes.app reports no
matching object without a locked-note signal, the adapter returns
`NOTE_NOT_FOUND`.

TASK-002 generated-template goldens cover every template above. Adapter
tests cover name match, body match via `whose`, date filters, folder
scoping, pagination, locked notes absent from listings/search, and stale
locked-note id classification as `NOTE_LOCKED`.

### TASK-003 Body Fetch and File Materialization Contract

TASK-003 adds only the single-note body path. List and search results keep
the TASK-002 behavior: no full `plaintext`, no full `bodyHtml`, and no
`bodyFile` generated for connection nodes. Mutations remain out of scope.

The adapter adds one static JXA template, `fetchNoteBody`, selected by Swift
code and invoked with a JSON argument containing the requested `noteId` and
body kind preference. The template resolves exactly one note id, returns the
same metadata shape used by TASK-002, fetches the complete plaintext and/or
HTML body needed for the requested representation, and lists attachments.
The note id and body kind are JSON arguments and are never interpolated into
JXA source.

Single-note data flow:

1. `note(noteId:)` calls the provider's explicit note lookup. Missing notes
   return `null`; locked or inaccessible notes return `NOTE_LOCKED`.
2. The provider fetches one note body at a time. It does not batch body
   reads, and it does not broaden lookup by account, folder, title, or query.
3. The service measures body size using the UTF-8 byte count of the exact
   string that would be returned to the caller.
4. A body whose byte count is less than or equal to
   `limits.max_inline_body_bytes` is returned inline in `plaintext` or
   `bodyHtml`. The equality case is inline; only strictly greater byte
   counts use `bodyFile`.
5. A body whose byte count is greater than `limits.max_inline_body_bytes` is
   not returned inline. The matching inline field is `null`, and `bodyFile`
   contains a Phase 0 FileStore download key with `domain: notes`, a
   reversible path-safe encoding of the note id as `sourceId`,
   and `kind: PLAINTEXT` or `HTML`. `NoteBodyFile.byteSize` carries the
   UTF-8 byte count beside the key; byte size is not part of the signed
   FileStore key payload. The source-id encoding is required because Notes ids
   may be URI-like values while FileStore payload ids must be single path
   segments.
6. `file download` decodes the key, validates the FileStore MAC and payload
   fields, refetches/materializes the requested body through the Notes file
   materializer, and writes `body.txt` for `PLAINTEXT` or `body.html` for
   `HTML` unless the key payload carries an explicit filename.

Because the current GraphQL type exposes one `bodyFile`, TASK-003 treats the
download key as representing one requested body representation at a time.
Plaintext is the default body representation; HTML uses the same cutoff and
FileStore path when the resolver or domain caller requests the HTML body
case. A future schema change may expose multiple body files, but TASK-003
does not add that schema surface.

Attachment handling is read-only and best-effort. `note(noteId:)` lists
attachment ids, display names, and content identifiers when Notes.app
exposes them. For each attachment, the adapter may issue a FileStore key
with `domain: notes`, the same reversible note-id encoding as `sourceId`,
an encoded `sourceIds.attachmentId`, `kind: ATTACHMENT`, and a sanitized
filename. If Notes.app cannot address or export the attachment reliably, the
attachment remains in the list with `downloadKey: null`. Attachment export
failures do not fail the note body fetch unless the whole note lookup fails.

TASK-003 tests run against fake providers and fake materializers, with no
live Notes dependency. Required coverage includes inline cutoff boundaries
for under, equal, and over `max_inline_body_bytes`; validation of
`PLAINTEXT` and `HTML` bodyFile keys; `file download` materializing body
contents from those keys; attachment listing with both keyed and unkeyed
attachments; and regression checks that TASK-001 static-template JSON argv
behavior and TASK-002 read-side list/search body exclusion remain intact.

### TASK-004 Write-Side Contract

TASK-004 adds only Notes mutations at the domain/provider boundary:
`createNote`, `updateNoteBody`, `deleteNote`, and `moveNote`. It must not
register new GraphQL schema wiring, smoke flows, or manual checklist work
reserved for TASK-005. Read behavior from TASK-002 and body/file behavior
from TASK-003 remain unchanged.

The adapter uses static JXA templates selected by Swift code:

| Template | Purpose | Body handling |
| --- | --- | --- |
| `createNote` | Create a note in the requested folder/account or defaults. | Accepts sanitized HTML derived from exactly one input body source. |
| `replaceNoteBody` | Replace the complete note body. | Writes the resolved HTML body directly. |
| `appendNoteBody` | Read the current body, append resolved HTML, and write back. | Read-modify-write; not atomic and explicitly lossy. |
| `deleteNote` | Move a note to Notes.app's Recently Deleted folder. | Does not permanently delete. |
| `moveNote` | Move a note to a target folder within existing Notes account/folder boundaries. | No body transfer. |

All mutation templates keep the TASK-001 JSON-argv boundary: note ids,
account ids, folder ids, titles, HTML, plaintext, and update modes are JSON
arguments and are never interpolated into JXA source.

Write-side validation and data flow:

1. `CreateNoteInput` and `UpdateNoteBodyInput` enforce exactly one of
   `bodyHtml` or `bodyText`. Supplying neither or both fails before the
   bridge call with `INVALID_ARGUMENT`.
2. `bodyText` is converted to the Notes HTML subset before calling the
   adapter. The conversion escapes HTML metacharacters, preserves line
   breaks as simple block/line markup, and intentionally does not attempt to
   represent checklists, rich text styles, or attachments.
3. `createNote` resolves the requested account/folder using the existing
   Notes domain boundaries. If omitted, it uses Notes.app defaults for the
   account and folder. Unknown accounts fail with `INVALID_ARGUMENT`;
   unknown folders fail with `NOTE_FOLDER_NOT_FOUND`.
4. `updateNoteBody` supports `REPLACE` and `APPEND`. `REPLACE` writes the
   resolved HTML body as the full body. `APPEND` fetches the current HTML
   body through the bridge, concatenates the resolved HTML body, and writes
   the combined HTML back. Concurrent edits can be lost because the
   read-modify-write sequence is not atomic.
5. `deleteNote` moves the note to Recently Deleted and returns
   `DeleteResult` for the addressed id. Missing notes return
   `NOTE_NOT_FOUND`; locked or inaccessible notes return `NOTE_LOCKED` when
   Notes.app exposes that classification.
6. `moveNote` moves the note to the requested Notes folder/account only
   within the existing domain model. Cross-boundary behavior follows
   Notes.app capabilities exposed by the adapter; unsupported or missing
   destinations fail with the existing domain errors rather than falling
   back to broad search.
7. Mutations returning `Note` refetch the note after the write using the
   TASK-003 single-note lookup path. The returned value is the observed
   post-write Notes state, not a synthetic echo of the input.

The Notes HTML subset remains lossy. `bodyText` conversion cannot preserve
rich text, checklists, embedded media, or arbitrary CSS. `APPEND` and
`REPLACE` may normalize or discard formatting when Notes.app stores the
updated body. This limitation is documented in command examples rather than
encoded as a per-mutation warning because Notes.app does not report a
machine-readable fidelity signal.

TASK-004 tests run against fake providers and fake bridges, with no live
Notes dependency. Required coverage includes exactly-one-of validation,
`bodyText`-to-HTML conversion, `APPEND` read-modify-write sequencing,
delete-to-Recently-Deleted behavior, move behavior within existing
account/folder boundaries, refetch-after-write for returned `Note` values,
and regressions that TASK-001 static-template JSON argv behavior plus
TASK-002/TASK-003 read behavior remain preserved.

### TASK-005 Schema Registration, Smoke Flows, and Live Checklist Contract

TASK-005 is the integration boundary that makes the TASK-002 through
TASK-004 Notes domain services available through the GraphQL runtime and CLI.
It registers the Notes schema module for both full and reader roles, wires
full-mode resolvers to `NotesReadService` and `NotesWriteService`, keeps
reader-mode mutation rejection at the GraphQL operation boundary, extends
fake-backed smoke coverage, updates schema-print coverage or snapshots where
stored, and records live Notes verification steps.

The registered query surface is:

- `noteAccounts: [NoteAccount!]!`
- `noteFolders(accountId: ID): [NoteFolder!]!`
- `notes(input: NoteSearchInput!): NoteConnection!`
- `note(noteId: ID!): Note`

The registered mutation surface is:

- `createNote(input: CreateNoteInput!): Note!`
- `updateNoteBody(input: UpdateNoteBodyInput!): Note!`
- `deleteNote(noteId: ID!): DeleteResult!`
- `moveNote(noteId: ID!, folderId: ID!): Note!`

Reader mode must expose the Notes read queries in SDL and execution, but it
must not expose executable Notes mutations. A Notes mutation submitted through
`apple-gateway-reader` fails before resolver dispatch with
`WRITE_DISABLED_IN_READER`, the same operation-level guard used for other
domains. This keeps read-only behavior structural instead of relying on each
Notes resolver to reject writes. Full mode exposes both query and mutation
fields and uses the same domain validation already defined by TASK-002,
TASK-003, and TASK-004.

Schema registration does not add a second Notes data path. Resolvers call the
existing services:

1. Query fields call `NotesReadService` so account/folder validation,
   search intersection, cursor pagination, body inlining, FileStore keys, and
   locked-note classification remain unchanged from TASK-002 and TASK-003.
2. Mutation fields call `NotesWriteService` so exactly-one-of body validation,
   `bodyText` conversion, `APPEND` read-modify-write behavior, delete-to-
   Recently-Deleted semantics, move behavior, and post-write refetch remain
   unchanged from TASK-004.
3. The CLI and GraphQL execution context must allow fake `NotesProviding` and
   `NotesWriting` injection for tests and smoke flows. Live CLI defaults may
   still construct the `LiveNotesAppleEventAdapter`, but tests must not depend
   on live Notes.app, TCC state, or user data.
4. Schema printing must include the Notes query fields in reader and full
   roles, and Notes mutation fields in full role only. If the repository stores
   SDL snapshots, update the snapshots; otherwise, add or update schema
   coverage assertions that check the field names explicitly.

Smoke tests run over fake Notes providers and writers. Required smoke flows
cover create, search/list, append-or-update, move, delete, and reader-mode
mutation rejection. The fake should exercise resolver-to-service wiring and
observable response shape, not duplicate every lower-level Notes unit test.
It should still preserve regression coverage that no smoke path bypasses the
TASK-001 static JXA JSON-argv boundary or the TASK-002/TASK-003/TASK-004
domain behavior.

The live manual checklist is permission-gated and destructive only inside a
scratch Notes folder. It must record:

1. First-run Automation prompt behavior for the hosting terminal or test
   process, including whether the prompt appears before the first Notes
   query/mutation and whether granting access allows the command to proceed.
2. Scratch folder creation or selection, then create, search, append-or-
   update, move, and delete flows against scratch data only.
3. Reader-mode read query success and Notes mutation rejection through
   `apple-gateway-reader`.
4. macOS 26 Tahoe timeout/chunking observation: list/search work must be
   chunked by `limits.apple_event_batch_size`; an observed `-1712` or timeout
   must retry once and then either recover or fail with the bridge timeout
   classification instead of hanging indefinitely.

Verification for TASK-005 must explicitly include:

```bash
task build
task test
task lint
swift run apple-gateway --help
```

## GraphQL Types

```graphql
type NoteAccount {
  id: ID!
  name: String!            # e.g. "iCloud", "On My Mac"
  isDefault: Boolean!
}

type NoteFolder {
  id: ID!
  accountId: ID!
  name: String!
  parentFolderId: ID
  noteCount: Int!
}

type Note {
  id: ID!                  # Notes AppleScript id (x-coredata:// URI)
  accountId: ID!
  folderId: ID!
  name: String!
  snippet: String!         # bounded preview; search gets body-derived snippets
  plaintext: String        # full body; null outside TASK-003 note()
  bodyHtml: String         # Notes HTML subset; null outside TASK-003 note()
  bodyFile: NoteBodyFile   # set when body exceeds limits.max_inline_body_bytes
  isPasswordProtected: Boolean!
  isShared: Boolean!
  creationDate: DateTime!
  modificationDate: DateTime!
  attachments: [NoteAttachment!]!
}

type NoteBodyFile {
  downloadKey: String!
  kind: NoteBodyKind!      # PLAINTEXT | HTML
  byteSize: Int!
}
enum NoteBodyKind { PLAINTEXT, HTML }

type NoteAttachment {
  id: ID!
  name: String!
  contentIdentifier: String
  downloadKey: String      # null when export is unavailable (best-effort)
}

input NoteSearchInput {
  accountId: ID
  folderId: ID
  query: String            # case-insensitive match on name and plaintext
  modifiedAfter: DateTime
  modifiedBefore: DateTime
  first: Int
  after: String
}

type NoteConnection {
  edges: [NoteEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}
type NoteEdge { cursor: String!, node: Note! }
```

Search semantics: account, folder, and date filters evaluate against the
bulk-fetched metadata first. When `query` is present, result membership is
`(case-insensitive name contains query OR Notes.app whose plaintext contains
query)` intersected with those account, folder, and date filters. The body
side uses the JXA `whose` filter on `plaintext` inside Notes (evaluated
app-side, no full body transfer). Search result snippets are bounded
previews, not body inlining; name-only matches may have an empty snippet.

## Mutations

```graphql
input CreateNoteInput {
  accountId: ID            # default account when omitted
  folderId: ID             # account's default folder when omitted
  title: String!
  bodyHtml: String         # exactly one of bodyHtml / bodyText
  bodyText: String         # converted to <div> paragraphs
}

enum NoteBodyUpdateMode { REPLACE, APPEND }

input UpdateNoteBodyInput {
  noteId: ID!
  mode: NoteBodyUpdateMode = REPLACE
  bodyHtml: String
  bodyText: String         # exactly one of the two
}

createNote(input: CreateNoteInput!): Note!
updateNoteBody(input: UpdateNoteBodyInput!): Note!
deleteNote(noteId: ID!): DeleteResult!       # moves to Recently Deleted
moveNote(noteId: ID!, folderId: ID!): Note!
```

`createNote` and `updateNoteBody` enforce exactly one of `bodyHtml` or
`bodyText`; invalid combinations return `INVALID_ARGUMENT` before any bridge
call. `bodyText` is converted to simple Notes HTML. `APPEND` reads the
current body, concatenates, and writes back; the read-modify-write is not
atomic. Mutations returning `Note` refetch the note after the write so the
response reflects observed Notes state.

## Documented Platform Limits

Surfaced in the spec, the README, and error messages, so callers are not
surprised:

- Password-locked notes are invisible to Apple Events; reads return
  `NOTE_LOCKED` when addressed by a stale id, and locked notes are absent
  from listings.
- The Notes HTML subset is lossy: tags, checklists, and styling beyond
  basic markup do not round-trip. `updateNoteBody` with `REPLACE` on a note
  containing checklists will destroy them; the mutation result carries no
  warning because Notes gives no signal, and the limitation is documented
  instead.
- Attachments cannot be created via Apple Events; `NoteAttachment.downloadKey`
  export is best-effort (`save attachment` is flaky across OS releases) and
  null signals unavailability.
- First mutation/query triggers the Automation TCC prompt (attributed to
  the hosting terminal); Notes.app is launched by Apple Events if not
  running.

## Testing

- `NotesProviding` fake for resolver/connection tests.
- JXA script templates unit-tested by asserting generated source and
  argument JSON (goldens), plus decoding tests over canned osascript
  output including -1712 and permission-denied stderr shapes.
- Manual live checklist in the phase plan (create/search/append/move/delete
  in a scratch folder).
