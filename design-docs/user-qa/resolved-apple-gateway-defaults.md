# Resolved Design Defaults for apple-gateway v1

**Status**: Resolved (design-time defaults chosen by the designing agent;
revisit any of them by reopening a question here)
**Created**: 2026-07-02
**Category**: apple-gateway Product Design

These decisions were taken while adapting the mail-gateway baseline to the
Apple-apps domain. Each lists the choice and the reasoning.

## Decision 1: Two binaries, not one and not six

Chosen: `apple-gateway` (full) and `apple-gateway-reader` (read-only).

Keeps mail-gateway's role-split pattern (a reader binary is safe to hand
to untrusted automation) while avoiding per-domain binaries, which would
multiply per-binary TCC grants and prompts.

## Decision 2: Schema-based write enforcement

Chosen: the reader executes against a schema registry with no Mutation
type; enforcement happens in validation, not string scanning.

mail-gateway's 2026-07 review rated its substring-scan enforcement a
critical weakness. The real parser (Decision 3) makes schema-based
enforcement free.

## Decision 3: Hand-rolled real GraphQL parser; keep zero dependencies

Chosen: lexer + recursive-descent parser + code-defined schema registry.
Graphiti/GraphQLSwift rejected (they pull swift-nio, breaking the
zero-dependency policy inherited from the base project).

## Decision 4: Support GraphQL variables from v1

Chosen: `--variables` / `--variables-file` supported at launch.

Deviates from mail-gateway v1 (which rejects variables). With six domains
the schema is too large for inline-literal-only queries, and the real
parser makes variables cheap. Fragments, directives, and subscriptions
remain rejected.

## Decision 5: Mechanism per domain

- Calendar/Reminders/EK alarms: EventKit direct (AppleScript is
  minutes-slow and needs GUI apps).
- Clock alarms: JXA accessibility automation owned by apple-gateway. Clock
  exposes neither a public alarm API nor an AppleScript dictionary, and private
  alarm stores are never written.
- Notes: batched Apple Events as JXA through osascript (only writable
  path; NoteStore.sqlite writing risks CloudKit corruption).
- Mail: read-only Envelope Index SQLite snapshot + .emlx parsing
  (~1000x faster than AppleScript; no Mail.app dependency). AppleScript
  not used at all in v1.
- Notifications: bundled signed helper .app for post/dismiss/list-own;
  usernoted DB read-only snapshot for system-wide listing; system-wide
  dismissal not offered (Accessibility UI scripting rejected as too
  fragile).

Grounding: `design-docs/references/macos-platform-research-2026-07.md`.

## Decision 6: Mail is retrieval-only

Chosen: no mail mutations of any kind. Outbound mail belongs to
mail-gateway; duplicating it here would fork credential and MIME logic.

## Decision 7: Resolvers never trigger TCC prompts implicitly

Chosen: a `.notDetermined` permission fails the resolver with
`PERMISSION_NOT_DETERMINED`; only `permissions request` prompts.

Agent-driven GraphQL calls must not spam the user with permission dialogs
mid-query; prompting becomes an explicit, auditable step.

## Decision 8: Large payloads via file materialization

Chosen: mail bodies/attachments are file-only (download keys), note bodies
inline up to 64 KiB then file-based, matching the base project's
token-economy policy for AI callers.

## Decision 9: Concurrency style follows the base project

Chosen: synchronous execution with semaphore-bridged platform callbacks,
Sendable value models, Swift 6 strict mode, no async/await in public
signatures.

## Decision 10: JXA over classic AppleScript for scripted domains

Chosen: osascript `-l JavaScript` with JSON-only argument passing and
JSON.stringify output; user input never spliced into script source.
One marshalling format and structural immunity to script injection.

## Impact

These defaults are reflected across `design-docs/specs/*.md` and the
phase plans in `impl-plans/active/`.
