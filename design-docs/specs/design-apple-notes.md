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
operations use bulk property fetch, JXA equivalent of
`get {id, name, modification date} of every note`, chunked by
`limits.apple_event_batch_size` (default 200), each chunk wrapped in an
explicit timeout (`limits.apple_event_timeout_seconds`, default 30) with
one retry on error -1712. Bodies are never fetched during list/search; only
`note(noteId:)` fetches a body, one note at a time.

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
  snippet: String!         # first 300 chars of plaintext, list/search results
  plaintext: String        # full body; null when over inline limit or not requested via note()
  bodyHtml: String         # Notes HTML subset; same inlining rule
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

Search semantics: metadata filters (name, dates, folder) evaluate against
the bulk-fetched metadata. When `query` must match body text, the adapter
uses the JXA `whose` filter on `plaintext` inside Notes (evaluated
app-side, no body transfer) and intersects with metadata filters.

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

`APPEND` reads the current `body`, concatenates, and writes back; the
read-modify-write is not atomic and the docs say so.

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
