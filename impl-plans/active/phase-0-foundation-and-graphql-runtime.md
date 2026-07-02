# Phase 0: Foundation and GraphQL Runtime

**Status**: In Progress
**Design Reference**: `design-docs/specs/design-apple-gateway.md`,
`design-docs/specs/design-graphql-runtime.md`,
`design-docs/specs/design-permissions.md`,
`design-docs/specs/architecture.md`

## Purpose

Restructure the template scaffold into the apple-gateway architecture and
build every cross-cutting component the domain phases depend on: package
targets, config, CLI frame, the GraphQL runtime, the permissions layer,
and the file store. After this phase, `apple-gateway graphql` executes the
`permissions` query end to end and `schema print` renders the (initially
small) SDL.

## Deliverables

- [ ] `Package.swift` with targets `AppleGatewayCore`, `AppleGatewayCLI`
      (`apple-gateway`), `AppleGatewayReaderCLI` (`apple-gateway-reader`),
      `AppleGatewayCoreTests`, `AppleGatewaySmokeTests`; `AppCore`/`AppCLI`
      removed; embedded Info.plist linker flags wired
- [ ] `Sources/AppleGatewayCore/{GraphQLRuntime,CLI,Config,Permissions,FileStore,AppleEventBridge,Domains}/` skeleton
- [ ] Working `graphql`, `schema print`, `permissions status|request`,
      `config validate`, `file download`, `cache prune`, `version` commands
- [ ] Updated `Taskfile.yml` test task running unit + smoke tests
- [ ] `Tests/` and smoke-test scaffolding with fake adapter wiring

## Tasks

### TASK-001: Package restructure and embedded Info.plist

**Parallelizable**: No (everything depends on it)

Rename targets per `architecture.md`; keep executable `main.swift` files
thin (argv + environment in, exit code out). Add
`Resources/AppleGatewayInfo.plist` (bundle ids, EventKit full-access and
legacy usage keys, `NSAppleEventsUsageDescription`) and the
`-sectcreate __TEXT __info_plist` linker flags to both executables.

**Completion Criteria**:

- [ ] `swift build` produces `apple-gateway` and `apple-gateway-reader`
- [ ] `otool -s __TEXT __info_plist .build/debug/apple-gateway` shows the plist
- [ ] `task test` and `swiftlint` pass on the restructured tree

### TASK-002: Config loading

**Parallelizable**: Yes (after TASK-001)

TOML subset parser (port the approach, not the code, from mail-gateway),
defaults for every key in `design-apple-gateway.md#configuration`,
`APPLE_GATEWAY_CONFIG` and `APPLE_GATEWAY_<SECTION>_<KEY>` env overrides
(env wins), `~` expansion for path values, and `config validate`.

**Completion Criteria**:

- [ ] Missing config file yields full defaults (zero-config works)
- [ ] Unit tests cover parse errors, env precedence, path expansion,
      unknown-key rejection

### TASK-003: GraphQL runtime

**Parallelizable**: Yes (after TASK-001)

Implement `GraphQLRuntime/` per `design-graphql-runtime.md`: lexer, parser
(line/column errors), AST, schema registry with role filtering, validator,
variable resolver with coercion, executor, selection-set projection, SDL
printer. Register the `permissions` query field as the first real field.

**Completion Criteria**:

- [ ] Golden tests for lexer/parser including error positions
- [ ] Validator tests: unknown field, missing required arg, enum/list/input
      coercion, variable type mismatch, fragment/directive/multi-op rejection
- [ ] Reader role rejects any mutation with `WRITE_DISABLED_IN_READER`;
      mutation-looking text in strings/comments is not rejected
- [ ] Projection honors aliases and nested selections
- [ ] `schema print --role reader` omits Mutation; snapshot test pinned

### TASK-004: Error model and JSON envelope

**Parallelizable**: Yes (after TASK-001)

`AppleGatewayError` carrying code, message, exit code, details; the
envelope formatter (`data`/`errors`/`extensions` with `requestId`);
exit-code mapping table from the primary spec.

**Completion Criteria**:

- [ ] Every error code constant from the spec table exists with a mapped
      exit code
- [ ] Envelope shape unit-tested for success, single error, multi-root
      partial failure

### TASK-005: Permissions layer and doctor

**Parallelizable**: Yes (after TASK-004)

Non-prompting probes (EventKit statuses, `AEDeterminePermissionToAutomateTarget`,
FDA probe files, shortcuts list), the `PermissionsStatus` resolver,
`permissions status [--json]` and `permissions request --domain`, and the
shared failure-message formatter naming the responsible process.

**Completion Criteria**:

- [ ] `permissions status` runs without triggering any TCC prompt
- [ ] `request --domain calendar` triggers exactly the EventKit prompt
- [ ] Formatter output matches `design-permissions.md#failure-message-contract`

### TASK-006: File store

**Parallelizable**: Yes (after TASK-004)

Download-key codec (domain, source ids, kind; tamper- and
traversal-rejecting), cache-dir layout, `file download`, `cache prune`,
and snapshot-copy helper for SQLite sources (used by Mail and
notifications phases).

**Completion Criteria**:

- [ ] Malformed/forged keys fail with `INVALID_DOWNLOAD_KEY`
- [ ] Written paths always normalize under cache root or `--output-dir`
- [ ] Prune refuses to escape the cache root (adversarial test)

### TASK-007: CLI frame and smoke tests

**Parallelizable**: No (integrates 002-006)

Flag parser (`--flag value` and `--flag=value`, repeated `--key`), command
router, `--pretty`, stdout/stderr discipline, and the
`AppleGatewaySmokeTests` executable running full CLI flows against fake
adapters (mail-gateway smoke pattern).

**Completion Criteria**:

- [ ] `apple-gateway graphql --query '{ permissions { calendars } }'`
      returns a valid envelope on a machine with no config
- [ ] Smoke tests cover: query/query-file exclusivity, variables decode
      errors, pretty output, reader mutation rejection, unknown command
      usage error (exit 2)

## Progress Log

- 2026-07-02: Plan created from approved design docs.
