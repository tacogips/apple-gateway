# Phase 0: Foundation and GraphQL Runtime

**Status**: Complete
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

- [x] `Package.swift` with targets `AppleGatewayCore`, `AppleGatewayCLI`
      (`apple-gateway`), `AppleGatewayReaderCLI` (`apple-gateway-reader`),
      `AppleGatewayCoreTests`, `AppleGatewaySmokeTests`; `AppCore`/`AppCLI`
      removed; embedded Info.plist linker flags wired
- [x] `Sources/AppleGatewayCore/{GraphQLRuntime,CLI,Config,Permissions,FileStore,AppleEventBridge,Domains}/` skeleton
- [x] Working `graphql`, `schema print`, `permissions status|request`,
      `config validate`, `file download`, `cache prune`, `version` commands
- [x] Updated `Taskfile.yml` test task running unit + smoke tests
- [x] `Tests/` and smoke-test scaffolding with fake adapter wiring

## Tasks

### TASK-001: Package restructure and embedded Info.plist

**Parallelizable**: No (everything depends on it)

Rename targets per `architecture.md`; keep executable `main.swift` files
thin (argv + environment in, exit code out). Add
`Resources/AppleGatewayInfo.plist` (bundle ids, EventKit full-access and
legacy usage keys, `NSAppleEventsUsageDescription`) and the
`-sectcreate __TEXT __info_plist` linker flags to both executables.

**Source Design References**:

- `design-docs/specs/architecture.md#phase-0-package-boundary`
- `design-docs/specs/command.md#binaries`
- `design-docs/specs/design-permissions.md#embedded-infoplist`
- `design-docs/user-qa/pending-apple-gateway-questions.md#question-6-reader-specific-embedded-bundle-identifier`

**Implementation Tasks**:

- [x] Update `Package.swift` products and targets:
      `AppCore` -> `AppleGatewayCore`, `AppCLI` -> `AppleGatewayCLI`,
      add executable product `apple-gateway-reader` targeting
      `AppleGatewayReaderCLI`, and rename the test target to
      `AppleGatewayCoreTests`.
- [x] Move source and test directories to the new target names:
      `Sources/AppCore` -> `Sources/AppleGatewayCore`,
      `Sources/AppCLI` -> `Sources/AppleGatewayCLI`,
      `Tests/AppCoreTests` -> `Tests/AppleGatewayCoreTests`.
- [x] Update Swift imports, test module references, and any package target
      name strings from `AppCore`/`AppCLI`/`AppCoreTests` to
      `AppleGatewayCore`/`AppleGatewayCLI`/`AppleGatewayCoreTests`.
- [x] Add `Sources/AppleGatewayReaderCLI/main.swift` as a thin reader
      executable entrypoint that delegates to the shared core CLI path.
      Until TASK-003 adds role-specific GraphQL enforcement, it may expose
      the same scaffold behavior as `apple-gateway`, but the role boundary
      must be explicit in the entrypoint or shared core API.
- [x] Keep executable `main.swift` files free of command tables, JSON
      formatting, and business validation. They should only pass
      `CommandLine.arguments` and `ProcessInfo.processInfo.environment` to
      the core runner and exit with its returned code.
- [x] Add `Resources/AppleGatewayInfo.plist` using the shared
      `CFBundleIdentifier` `me.tacogips.apple-gateway`, `CFBundleName`,
      `CFBundleShortVersionString`, `NSCalendarsFullAccessUsageDescription`,
      `NSCalendarsUsageDescription`,
      `NSRemindersFullAccessUsageDescription`,
      `NSRemindersUsageDescription`, and
      `NSAppleEventsUsageDescription`.
- [x] Add identical SwiftPM linker settings to `AppleGatewayCLI` and
      `AppleGatewayReaderCLI` to embed
      `Resources/AppleGatewayInfo.plist` into the `__TEXT,__info_plist`
      section. Do not introduce target-specific plist generation in
      TASK-001; the reader-specific bundle identifier remains deferred in
      user QA.
- [x] Run the focused build and verification commands listed below; update
      this progress log with date, result, and any follow-up discovered.

**Deliverables**:

- Updated `Package.swift` target/product graph with no remaining
  `AppCore` or `AppCLI` package targets.
- Renamed source and test directories under `Sources/AppleGatewayCore`,
  `Sources/AppleGatewayCLI`, `Sources/AppleGatewayReaderCLI`, and
  `Tests/AppleGatewayCoreTests`.
- Shared `Resources/AppleGatewayInfo.plist` embedded into both debug
  executables.
- Tests updated to compile against `AppleGatewayCore`.

**Dependencies**:

- Step 3 accepted design update for TASK-001.
- Existing scaffold behavior in `Sources/AppCore` and `Sources/AppCLI`.
- Deferred user decision on a reader-specific `CFBundleIdentifier`; this
  is explicitly non-blocking for TASK-001.

**Verification Commands**:

- `swift build`
- `otool -s __TEXT __info_plist .build/debug/apple-gateway`
- `otool -s __TEXT __info_plist .build/debug/apple-gateway-reader`
- `task test`
- `swiftlint`

**Completion Criteria**:

- [x] `swift build` produces `apple-gateway` and `apple-gateway-reader`
- [x] `otool -s __TEXT __info_plist .build/debug/apple-gateway` shows the plist
- [x] `otool -s __TEXT __info_plist .build/debug/apple-gateway-reader` shows the plist
- [x] Source, test, and package target names no longer reference
      `AppCore`, `AppCLI`, or `AppCoreTests`, except in historical design
      notes if intentionally preserved
- [x] Reader entrypoint exists and delegates through the shared core CLI
      behavior rather than duplicating command handling
- [x] `task test` and `swiftlint` pass on the restructured tree

### TASK-002: Config loading

**Parallelizable**: Yes (after TASK-001)

TOML subset parser (port the approach, not the code, from mail-gateway),
defaults for every key in `design-apple-gateway.md#configuration`,
`APPLE_GATEWAY_CONFIG` and `APPLE_GATEWAY_<SECTION>_<KEY>` env overrides
(env wins), `~` expansion for path values, and `config validate`.

**Source Design References**:

- `design-docs/specs/design-apple-gateway.md#configuration`
- `design-docs/specs/design-apple-gateway.md#task-002-config-scope`
- `design-docs/specs/command.md#config`
- `impl-plans/active/phase-0-foundation-and-graphql-runtime.md#task-002-config-loading`

**Implementation Tasks**:

- [x] Add `Sources/AppleGatewayCore/Config/` with schema types for the
      resolved config, defaults, source metadata, and typed parse/validation
      errors that can later map to `CONFIG_INVALID`.
- [x] Implement config path selection with precedence
      `--config` over `APPLE_GATEWAY_CONFIG` over
      `$XDG_CONFIG_HOME/apple-gateway/config.toml` over
      `~/.config/apple-gateway/config.toml`; expand a leading `~` in the
      selected path before reading.
- [x] Implement the TASK-002 TOML subset parser only: section headers,
      `key = value` assignments, blank lines, `#` comments, and string,
      integer, and boolean scalar values. Reject arrays, inline tables,
      dotted keys, repeated sections, repeated keys, malformed syntax,
      unknown sections, and unknown keys with line/column diagnostics.
- [x] Build the config resolver with precedence defaults, then file values,
      then env overrides. Missing default-path config files are valid and
      produce full defaults; missing explicit `--config` or
      `APPLE_GATEWAY_CONFIG` paths should be reported as config load failures.
- [x] Support only the accepted override names:
      `APPLE_GATEWAY_STORAGE_CACHE_DIR`,
      `APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE`,
      `APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE`,
      `APPLE_GATEWAY_LIMITS_MAX_INLINE_BODY_BYTES`,
      `APPLE_GATEWAY_LIMITS_APPLE_EVENT_TIMEOUT_SECONDS`,
      `APPLE_GATEWAY_LIMITS_APPLE_EVENT_BATCH_SIZE`,
      `APPLE_GATEWAY_DOMAINS_CALENDAR`,
      `APPLE_GATEWAY_DOMAINS_REMINDERS`,
      `APPLE_GATEWAY_DOMAINS_CLOCK_ALARMS`,
      `APPLE_GATEWAY_DOMAINS_NOTES`,
      `APPLE_GATEWAY_DOMAINS_MAIL`,
      `APPLE_GATEWAY_DOMAINS_NOTIFICATIONS`,
      `APPLE_GATEWAY_MAIL_MAIL_ROOT`, and
      `APPLE_GATEWAY_NOTIFICATIONS_HELPER_APP_PATH`. Ignore unrelated
      `APPLE_GATEWAY_*` variables, but reject shaped
      `APPLE_GATEWAY_<SECTION>_<KEY>` variables with no schema key.
- [x] Apply post-precedence validation: positive numeric limits,
      `limits.default_page_size <= limits.max_page_size`, and non-empty
      resolved `storage.cache_dir`.
- [x] Expand a leading `~` after file/env precedence for
      `storage.cache_dir`, non-empty `mail.mail_root`, and non-empty
      `notifications.helper_app_path`; leave optional empty path values empty
      for later domain auto-probing.
- [x] Add `config validate [--config <path>]` routing to the existing core CLI
      runner without implementing the broader TASK-007 command frame. Success
      prints JSON with the resolved source and normalized values. Failure
      prints the standard error envelope shape with `CONFIG_INVALID`, file
      line/column details or env var name, and exits nonzero. Unknown commands
      and bad flags remain usage errors.
- [x] Add focused unit tests under `Tests/AppleGatewayCoreTests/Config/` for
      defaults, path precedence, file/env value precedence, parse errors,
      env override errors, tilde expansion, unknown-key rejection, duplicate
      rejection, numeric validation, and `config validate` success/failure
      behavior.
- [x] Update this progress log with date, result, verification commands, and
      any follow-up discovered.

**Deliverables**:

- `Sources/AppleGatewayCore/Config/` containing the config schema, default
  values, parser, resolver, path expansion, and validation code.
- CLI support for `apple-gateway config validate [--config <path>]` scoped to
  config validation only.
- Unit tests covering missing config defaults, parse errors, env precedence,
  path expansion, unknown-key rejection, duplicate rejection, and validation
  boundaries.

**Dependencies**:

- Completed TASK-001 package restructure and thin executable entrypoints.
- Accepted Step 3 design update for TASK-002.
- Existing `AppleGatewayCommandLine.run` argv/environment seam from TASK-001.
- No dependency on GraphQL runtime, permissions probes, file store, smoke
  tests, release workflows, commits, or pushes.

**Verification Commands**:

- `swift build`
- `swift test --filter Config`
- `task test`
- `swiftlint`

**Completion Criteria**:

- [x] Missing config file yields full defaults (zero-config works)
- [x] Unit tests cover parse errors, env precedence, path expansion,
      unknown-key rejection
- [x] `--config` selects the file before `APPLE_GATEWAY_CONFIG`; value
      precedence remains defaults, then file values, then env overrides
- [x] Supported env overrides resolve to typed values; shaped unknown
      overrides are rejected and unrelated env vars are ignored
- [x] Path-valued fields and selected config paths expand leading `~` exactly
      after the accepted precedence rules
- [x] `config validate` prints resolved-source/normalized-value JSON on
      success and `CONFIG_INVALID` envelope details on invalid config content
- [x] Validation remains local to config loading and does not probe
      permissions, create directories, operate application UI, or validate GraphQL
      behavior

### TASK-003: GraphQL runtime

**Parallelizable**: Yes (after TASK-001)

Implement `GraphQLRuntime/` per `design-graphql-runtime.md`: lexer, parser
(line/column errors), AST, schema registry with role filtering, validator,
variable resolver with coercion, executor, selection-set projection, SDL
printer. Register the `permissions` query field as the first real field.

**Source Design References**:

- `design-docs/specs/design-graphql-runtime.md#phase-0-task-003-scope`
- `design-docs/specs/design-graphql-runtime.md#supported-language-subset`
- `design-docs/specs/design-graphql-runtime.md#components`
- `design-docs/specs/design-graphql-runtime.md#permissions-field`
- `design-docs/specs/design-graphql-runtime.md#execution-flow`
- `design-docs/specs/design-graphql-runtime.md#reader-enforcement`
- `design-docs/specs/design-graphql-runtime.md#cli-contract`
- `design-docs/specs/design-graphql-runtime.md#testing`
- `design-docs/user-qa/pending-apple-gateway-questions.md#question-5-graphql-server-mode`

**Implementation Tasks**:

- [x] Add `Sources/AppleGatewayCore/GraphQLRuntime/AST.swift` and
      `Lexer.swift` with token kinds for names, numbers, strings, comments,
      and punctuators. Track 1-based line and column on every token and
      report lexical failures with those positions.
- [x] Add `Parser.swift` for the accepted executable subset: one `query` or
      `mutation` operation, optional operation name, variable definitions
      with type refs and default values, field aliases, arguments, nested
      selection sets, and literal values. Reject fragments, directives,
      subscriptions, and multiple operations with validation-shaped errors
      instead of ignoring them.
- [x] Add code-defined schema types in `SchemaRegistry.swift`, including
      object, scalar, enum, list, non-null, and input object references;
      field and argument definitions; resolver closure contracts; and
      role-specific registry construction where `.reader` drops mutation
      fields and the `Mutation` type.
- [x] Register a bootstrap `permissions` query module before later domain
      modules. The resolver must return safe placeholder/config-derived data
      only and must not prompt, run Apple Events, automate application UI, write
      cache files, or depend on TASK-005 permission probes.
- [x] Add `Validator.swift` for unknown field/argument/type checks, required
      argument checks, operation-kind checks, enum/list/input coercion checks,
      and variable declaration/reference compatibility against the
      role-specific registry.
- [x] Add `VariableResolver.swift` to merge literal arguments, variable
      values from a decoded JSON object, defaults, and non-null/list/input
      coercion into resolver-ready typed argument values.
- [x] Add `Executor.swift` and `Projection.swift` to resolve root fields
      sequentially in document order, preserve aliases, project nested
      selections from resolver results, and return GraphQL-style
      `{ "data": ... }` or `{ "data": null, "errors": [...] }` envelopes
      without implementing the full TASK-004 error model.
- [x] Add `SDLPrinter.swift` to render SDL from the same registry used by
      validation and execution. `schema print --role reader` must omit
      `type Mutation` and mutation fields.
- [x] Wire only the scoped CLI paths needed for TASK-003 in
      `Sources/AppleGatewayCore/Command.swift`: `graphql --query|--query-file`
      with optional `--variables|--variables-file` and `--pretty`, plus
      `schema print [--role full|reader]`. Keep unrelated TASK-004 error
      model work, TASK-005 permission probes, TASK-006 file store behavior,
      TASK-007 smoke-test frame, commits, and pushes out of scope.
- [x] Add focused tests under `Tests/AppleGatewayCoreTests/GraphQLRuntime/`
      and command-level tests where CLI wiring is required. Cover lexer and
      parser error positions, unknown field, missing required argument,
      enum/list/input coercion, variable mismatch, fragment/directive/
      multi-operation rejection, reader mutation rejection without string
      scanning, projection aliases/nesting, and reader SDL mutation omission.
- [x] Update this progress log with date, result, verification commands, and
      any follow-up discovered.

**Deliverables**:

- `Sources/AppleGatewayCore/GraphQLRuntime/` containing lexer, parser, AST,
  schema registry, validator, variable resolver/coercer, executor,
  projection, and SDL printer.
- A registered `permissions` query field that exercises the full runtime
  without prompting or depending on the later permissions layer.
- Scoped CLI support for `graphql` and `schema print` sufficient to exercise
  TASK-003 behavior from both `apple-gateway` and `apple-gateway-reader`.
- Focused GraphQL runtime and CLI tests covering accepted success paths and
  explicit rejection paths.

**Dependencies**:

- Completed TASK-001 package restructure and explicit full/reader role
  entrypoints.
- Completed TASK-002 config resolver for safe placeholder/config-derived
  context where needed.
- Step 3 accepted TASK-003 design review from communication `comm-000518`.
- No dependency on TASK-004 final error model, TASK-005 permission probes,
  TASK-006 file store, TASK-007 smoke tests, release workflows, commits, or
  pushes.

**Parallelization Notes**:

- Lexer/parser/AST tests can proceed in parallel with schema registry and SDL
  printer work because their write scopes are disjoint under
  `GraphQLRuntime/` files and focused test files.
- CLI wiring should wait until the runtime facade, registry, and SDL printer
  APIs are stable.
- Executor/projection should wait until AST, schema definitions, validator,
  and variable resolver value models are settled enough to avoid churn.

**Verification Commands**:

- `swift build`
- `swift test --filter GraphQL`
- `task test`
- `swiftlint`

**Completion Criteria**:

- [x] Golden tests for lexer/parser including error positions
- [x] Validator tests: unknown field, missing required arg, enum/list/input
      coercion, variable type mismatch, fragment/directive/multi-op rejection
- [x] Reader role rejects any mutation with `WRITE_DISABLED_IN_READER`;
      mutation-looking text in strings/comments is not rejected
- [x] Projection honors aliases and nested selections
- [x] `schema print --role reader` omits Mutation; snapshot test pinned
- [x] `apple-gateway graphql --query '{ permissions { status } }'` returns a
      valid JSON envelope with placeholder/non-prompting permissions data
- [x] `apple-gateway-reader schema print --role reader` and
      `apple-gateway schema print --role reader` both render reader-filtered
      SDL from the shared registry
- [x] All TASK-003 verification commands pass or any environment-only failure
      is recorded in the progress log with the exact rerun command that
      passed

### TASK-004: Error model and JSON envelope

**Parallelizable**: Yes (after TASK-001)

`AppleGatewayError` carrying code, message, exit code, details; the
envelope formatter (`data`/`errors`/`extensions` with `requestId`);
exit-code mapping table from the primary spec.

**Source Design References**:

- `design-docs/specs/design-apple-gateway.md#error-model`
- `design-docs/specs/design-apple-gateway.md#error-codes`
- `design-docs/specs/design-apple-gateway.md#exit-codes`
- `design-docs/specs/design-apple-gateway.md#error-code-exit-mapping`
- `impl-plans/active/phase-0-foundation-and-graphql-runtime.md#task-004-error-model-and-json-envelope`
- Step 3 design review communication `comm-000532`

**Implementation Tasks**:

- [x] Add `AppleGatewayError` and `AppleGatewayErrorCode` in a shared core
      error-model location, carrying stable `code`, `message`, mapped
      `exitCode`, and optional structured `details`.
- [x] Define every error code from the primary spec table, including
      GraphQL, config, permissions, domain lookup, file materialization,
      platform/provider, OS-version, and unexpected-error codes.
- [x] Implement the complete exit-code mapping exactly as accepted in
      `design-apple-gateway.md#error-code-exit-mapping`: config failures to
      3, permission/FDA/automation access failures to 4, GraphQL and
      business input/domain failures to 5, platform/provider/file operation
      failures to 6, and `UNEXPECTED_ERROR` to 1.
- [x] Add a shared JSON envelope formatter for success, single-error, and
      multi-error responses. The canonical envelope shape must support
      `data`, `errors`, and top-level `extensions.requestId`; each error
      must include `message` and `extensions.code`, `extensions.exitCode`,
      and optional `extensions.details`.
- [x] Preserve GraphQL `locations` and path-scoped errors when adapting
      parser, validation, role, or resolver failures. Multi-root partial
      failures must keep successful root values, set only failed roots to
      `null`, append errors in encounter/document order, and select the
      aggregate process exit from the first error in `errors[]`.
- [x] Replace the TASK-002 config-only failure envelope in
      `ConfigValidationJSON` with the shared envelope formatter while
      preserving existing `CONFIG_INVALID` diagnostics such as file
      line/column, env var name, and validation details.
- [x] Update GraphQL runtime envelope generation to use the shared formatter
      and `AppleGatewayError` adapters for parse, validation,
      `WRITE_DISABLED_IN_READER`, variable decoding/coercion, projection, and
      resolver errors without broadening into TASK-005 permissions probes,
      TASK-006 file store behavior, or TASK-007 smoke-test frame.
- [x] Update command-line exit handling so JSON-producing business commands
      return 0 for envelopes without errors and the first error's mapped
      `exitCode` for envelopes with errors. Unknown commands and malformed
      CLI flags must remain usage errors with exit code 2.
- [x] Add focused unit tests for the full error-code mapping table, shared
      envelope success shape with `extensions.requestId`, single-error
      envelope shape, config `CONFIG_INVALID` adaptation, GraphQL error
      adaptation, and multi-root partial failure first-error exit selection.
- [x] Update this progress log with date, result, verification commands, and
      any follow-up discovered.

**Deliverables**:

- Shared error model and envelope formatter under `Sources/AppleGatewayCore/`
  with no command-specific duplicate envelope structs.
- Config validation failures adapted to `AppleGatewayError(CONFIG_INVALID)`
  and emitted through the shared JSON envelope shape.
- GraphQL runtime and command path adapted to the shared envelope and mapped
  exit-code behavior, including deterministic first-error aggregate exit
  selection.
- Focused tests under `Tests/AppleGatewayCoreTests/` for all mapping and
  envelope requirements accepted in Step 3.

**Dependencies**:

- Completed TASK-001 package restructure and shared core CLI entrypoints.
- Completed TASK-002 config resolver, including existing `CONFIG_INVALID`
  diagnostics to adapt.
- Completed TASK-003 GraphQL runtime and scoped `graphql` / `schema print`
  CLI wiring.
- Step 3 accepted TASK-004 design review from communication `comm-000532`.
- No dependency on TASK-005 permission probes, TASK-006 file store,
  TASK-007 smoke tests, release workflows, commits, or pushes.

**Parallelization Notes**:

- Error-code mapping tests and shared envelope formatter tests can proceed in
  parallel with config-error adaptation because their write scopes can remain
  disjoint under new shared error-model tests and `Config/` files.
- GraphQL runtime adaptation should wait until the shared envelope formatter
  and error adapters are stable enough to avoid duplicate envelope models.
- Command-line exit handling should wait until config and GraphQL adapters
  expose first-error exit information through the shared model.

**Verification Commands**:

- `swift build`
- `swift test --filter Error`
- `swift test --filter GraphQL`
- `task test`
- `swiftlint`

**Completion Criteria**:

- [x] Every error code constant from the spec table exists with a mapped
      exit code
- [x] Envelope shape unit-tested for success, single error, multi-root
      partial failure
- [x] `CONFIG_INVALID` uses the shared envelope with top-level
      `extensions.requestId` and exits 3
- [x] GraphQL parse, validation, role, and resolver failures use
      `AppleGatewayError` with mapped exit codes and preserve available
      `locations` / root `path`
- [x] Multi-root partial failure selects the command process exit from the
      first error in `errors[]`, while later errors retain their own
      `extensions.exitCode`
- [x] Unknown commands and malformed CLI flags still exit 2 outside the
      business JSON envelope path

### TASK-005: Permissions layer and doctor

**Parallelizable**: Yes (after TASK-004)

Non-prompting probes (EventKit statuses, `AEDeterminePermissionToAutomateTarget`,
Accessibility trust, FDA probe files), the `PermissionsStatus` resolver,
`permissions status [--json]` and `permissions request --domain`, and the
shared failure-message formatter naming the responsible process.

**Source Design References**:

- `design-docs/specs/design-permissions.md#detection-and-the-doctor-surface`
- `design-docs/specs/design-permissions.md#task-005-behavioral-boundary`
- `design-docs/specs/design-permissions.md#failure-message-contract`
- `design-docs/specs/command.md#permissions`
- `design-docs/specs/design-apple-gateway.md#query-root`
- Step 3 design review communication `comm-000545`

**Implementation Tasks**:

- [x] Inspect current TASK-004-era command, GraphQL registry, config, error
      envelope, and tests before editing. Preserve the existing SwiftPM target
      boundaries and do not add new modules. Record any file over 1000 lines
      and split only if TASK-005 edits would otherwise worsen the boundary.
- [x] Add `Sources/AppleGatewayCore/Permissions/` with the core model:
      `PermissionState` values aligned to the GraphQL enum, a
      `PermissionsStatus` result with fields `calendars`, `reminders`,
      `notesAutomation`, `mailFullDiskAccess`, `notificationsHelper`,
      `notificationDbFullDiskAccess`, and `clockAutomation`, structured
      diagnostic details, and requestable-domain parsing for
      `calendar`, `reminders`, `notes`, `notifications`, and `clock-alarms`.
- [x] Add injectable protocol seams for status probes, prompt-capable request
      providers, protected-file opening, responsible-process detection,
      Accessibility/automation status, and notification-helper authorization IPC. Test fakes
      must be able to prove that status paths never call request methods.
- [x] Implement calendar and reminders status with EventKit authorization
      status APIs only, mapping full access to allowed, denied/restricted to
      denied, not determined to `NOT_DETERMINED`, write-only or other
      unavailable states to the accepted non-allowed state plus diagnostics.
      These probes must never call EventKit request APIs.
- [x] Implement Notes automation status with
      `AEDeterminePermissionToAutomateTarget` for `com.apple.Notes` and
      `askUserIfNeeded=false`. The status probe must not send a prompting
      Notes Apple Event.
- [x] Implement Full Disk Access status by read-only opening the accepted
      probe files for the Mail Envelope Index and usernoted database path.
      Treat `EPERM` as missing FDA, missing/unresolvable paths as `UNKNOWN`
      with diagnostics, and never create, modify, chmod, delete, copy, or
      cache probe files.
- [x] Implement notification-helper status and request only against an
      already configured helper path from config. If the helper is empty,
      missing, unsigned, unreachable, or lacks the expected authorization IPC,
      return `UNKNOWN` with an unavailable diagnostic. TASK-005 must not
      scaffold, install, sign, notarize, package, upload, or launch
      `AppleGatewayNotifier.app`.
- [x] Implement Clock automation status with non-prompting Accessibility and
      System Events automation probes.
- [x] Apply config-disabled-domain behavior consistently: disabled domains
      report `NOT_REQUIRED`, skip their underlying probe/request work, and
      include enough diagnostics for human doctor output and JSON details.
- [x] Implement `permissions status [--json]` in the existing command frame.
      Human output is the doctor report with best-effort responsible-process
      hints, System Settings pane guidance, `tccutil reset` commands where
      applicable, and manual remediation for Full Disk Access and Accessibility.
      JSON output exposes the stable `PermissionsStatus` field names and a
      per-field details object while preserving stdout/stderr and exit-code
      discipline from TASK-004.
- [x] Implement `permissions request --domain
      calendar|reminders|notes|notifications|clock-alarms`. Each domain must call only its
      corresponding request path: calendar EventKit calendar request,
      reminders EventKit reminders request, notes minimal Notes automation
      prompt path, and notifications preconfigured helper authorization path.
      Non-requestable domains remain available only through status guidance.
- [x] Replace the TASK-003 placeholder GraphQL `permissions` resolver with
      the real status service and full `PermissionsStatus` fields. GraphQL
      status must never trigger prompts, including when a field is
      `NOT_DETERMINED` or `UNKNOWN`.
- [x] Add the shared permission failure-message formatter. Its exact line
      ordering and labels come from
      `design-permissions.md#failure-message-contract`, and it must print
      `Responsible app (best effort): unknown` when the hint is absent. Route
      CLI and GraphQL permission failures through this formatter and include
      the same structured content in GraphQL error `extensions.details`.
- [x] Add focused tests for request-domain parsing, status/request argument
      parsing, no-prompt status behavior through fakes, request-domain
      isolation, disabled-domain `NOT_REQUIRED`, notification-helper
      unavailable `UNKNOWN`, Full Disk Access read-only probe mapping,
      Clock automation status behavior, GraphQL `PermissionsStatus` fields,
      and formatter contract output.
- [x] Update this progress log with date, result, verification commands,
      environment-specific toolchain notes, and any follow-up discovered. Do
      not mark TASK-005 complete until verification has run or any blocker is
      recorded with the exact failed command.

**Deliverables**:

- `Sources/AppleGatewayCore/Permissions/` containing permission models,
  status service, request service, probe/request protocols, platform probe
  implementations, responsible-process hinting, and shared failure formatter.
- Existing CLI command routing extended for `permissions status [--json]`
  and `permissions request --domain ...`, scoped only to TASK-005 behavior.
- GraphQL registry/resolver updated so `Query.permissions` returns real
  non-prompting `PermissionsStatus` values instead of the TASK-003
  placeholder.
- Focused permissions, command, and GraphQL tests covering the accepted
  behavior and no-prompt boundaries.

**Dependencies**:

- Completed TASK-001 package restructure and explicit full/reader
  executable entrypoints.
- Completed TASK-002 config resolver, especially domain enablement and
  `notifications.helper_app_path`.
- Completed TASK-003 GraphQL runtime and bootstrap permissions field.
- Completed TASK-004 shared error model, JSON envelope, and command exit
  mapping.
- Accepted Step 3 TASK-005 design review from communication `comm-000545`.
- No dependency on TASK-006 file store, TASK-007 smoke frame, Phase 4 helper
  app creation/distribution, release workflows, commits, pushes, signing,
  notarization, uploads, or manual/external release gates.

**Parallelization Notes**:

- Permission model/formatter tests and responsible-process detector work can
  proceed in parallel because they write disjoint files under
  `Permissions/` and focused test files.
- Platform probe implementations can proceed in parallel after the protocol
  seams are defined, provided each probe owns separate files.
- CLI routing and GraphQL resolver replacement should wait until the status
  service facade and JSON model are stable.
- Request-path implementation should wait until request-domain parsing and
  provider protocols are stable enough to prove request isolation in tests.

**Intentional Divergences / Deferred Work**:

- Reader-specific bundle-id ambiguity remains deferred in
  `design-docs/user-qa/pending-apple-gateway-questions.md` and does not
  change TASK-005 behavior.
- Notification helper scaffolding, installation, signing, packaging,
  launching, and notarization are intentionally out of scope. TASK-005 only
  talks to an already configured helper if one exists.
- File store/cache creation and smoke-test frame work remain TASK-006 and
  TASK-007.

**Completion Criteria**:

- [x] `permissions status` runs without triggering any TCC prompt
- [x] `request --domain calendar` triggers exactly the EventKit prompt
- [x] `request --domain notifications` calls only a preconfigured notifier
      helper when available; absent/unresolvable helper reports an
      unavailable `UNKNOWN` diagnostic and does not implement Phase 4 helper
      scaffolding
- [x] Formatter output matches `design-permissions.md#failure-message-contract`
- [x] `apple-gateway graphql --query '{ permissions { calendars reminders notesAutomation mailFullDiskAccess notificationsHelper notificationDbFullDiskAccess clockAutomation } }'`
      returns a valid JSON envelope using `PermissionState` field values
- [x] Disabled configured domains return `NOT_REQUIRED` without calling the
      underlying probe or request provider
- [x] Full Disk Access is reported with manual remediation; Clock automation
      permissions are requestable through `permissions request`

**Verification Commands**:

- `swift build`
- `swift test --filter Permissions`
- `swift test --filter GraphQL`
- `swift test --filter Command`
- `swift test`
- `task test`
- `swiftlint`

### TASK-006: File store

**Parallelizable**: Yes (after TASK-004)

Download-key codec (domain, source ids, kind; tamper- and
traversal-rejecting), cache-dir layout, `file download`, `cache prune`,
and snapshot-copy helper for SQLite sources (used by Mail and
notifications phases).

**Source Design References**:

- `design-docs/specs/design-apple-gateway.md#large-payload-policy-file-materialization`
- `design-docs/specs/design-apple-gateway.md#task-006-file-store-contract`
- `design-docs/specs/command.md#file`
- `design-docs/specs/command.md#cache`
- `design-docs/specs/design-apple-mail.md#envelope-index-access`
- `design-docs/specs/design-apple-mail.md#message-body-materialization`
- `design-docs/specs/design-apple-notes.md`
- Riela session `codex-design-and-implement-review-loop-session-343`
  design update communication `comm-000559`

**Implementation Tasks**:

- [x] Add `Sources/AppleGatewayCore/FileStore/` with download-key payload
      models, manifest/report DTOs, a file materializer protocol for later
      domain adapters, and an unavailable default materializer.
- [x] Implement `agdk1.<payload>.<mac>` download keys with canonical JSON
      payloads, base64url encoding, CryptoKit HMAC-SHA256 authentication,
      local per-cache-root validation material, and deterministic rejection
      for malformed, forged, unknown-version, unknown-kind, or unsafe keys.
- [x] Validate all key-derived source identifiers and filenames as single
      relative path segments; reject empty values, absolute/path separators,
      dot segments, NUL, and tilde expansion before filesystem writes.
- [x] Implement cache-root layout for `downloads/`, `snapshots/`, and
      `keys/`; materialize downloads under managed cache layout or explicit
      `--output-dir` while keeping final paths contained inside the selected
      root.
- [x] Implement `file download --key <key> [--key ...] [--output-dir <dir>]`
      in the existing command frame, with shared JSON success/error envelopes
      and mapped `INVALID_DOWNLOAD_KEY` / `FILE_OPERATION_FAILED` behavior.
- [x] Implement `cache prune [--all]`, preserving key validation material by
      default, deleting only managed cache subdirectories, refusing empty or
      filesystem-root cache roots, not following symlink targets, and leaving
      the cache root itself in place.
- [x] Implement SQLite snapshot copying under
      `snapshots/<domain>/<source-hash>/`, including exact `-wal` and `-shm`
      sidecars when present, without mutating live source files.
- [x] Add focused tests for key round-trip/tamper rejection, traversal
      rejection, cache-root and explicit-output materialization,
      malformed-key command envelopes, prune root refusal, symlink escape
      behavior, `--all` key-material removal, and snapshot sidecar copying.
- [x] Update this progress log with Riela status, verification commands, and
      any follow-up discovered.

**Deliverables**:

- `Sources/AppleGatewayCore/FileStore/` with key codec, path-safety helpers,
  file-store materialization/prune/snapshot logic, and adapter protocol seams.
- Existing command routing extended for `file download` and `cache prune`
  without broadening into TASK-007 smoke-frame work.
- Focused file-store tests under `Tests/AppleGatewayCoreTests/`.

**Dependencies**:

- Completed TASK-002 config resolver, especially `storage.cache_dir`.
- Completed TASK-004 shared error model and JSON envelope.
- Riela TASK-006 design update from session
  `codex-design-and-implement-review-loop-session-343`.
- No dependency on Mail/Notes/Notifications domain adapters, TASK-007 smoke
  frame, release workflows, commits, pushes, signing, notarization, uploads,
  or external release gates.

**Completion Criteria**:

- [x] Malformed/forged keys fail with `INVALID_DOWNLOAD_KEY`
- [x] Written paths always normalize under cache root or `--output-dir`
- [x] Prune refuses to escape the cache root (adversarial test)

**Verification Commands**:

- `swift build`
- `swift test --filter FileStore`
- `swift test --filter Command`
- `swift test`
- `task test`
- `swiftlint`

### TASK-007: CLI frame and smoke tests

**Parallelizable**: No (integrates 002-006)

Flag parser (`--flag value` and `--flag=value`, repeated `--key`), command
router, `--pretty`, stdout/stderr discipline, and the
`AppleGatewaySmokeTests` executable running full CLI flows against fake
adapters (mail-gateway smoke pattern).

**Source Design References**:

- `design-docs/specs/command.md#task-007-command-frame-contract`
- `design-docs/specs/command.md#global-flags`
- `design-docs/specs/design-apple-gateway.md#error-model`
- `design-docs/specs/design-apple-gateway.md#testing-policy`
- `design-docs/specs/architecture.md#targets`

**Accepted Review Trace**:

- Workflow mode: `issue-resolution`
- Issue reference:
  `workflowExecutionId:codex-design-and-implement-review-loop-session-346; communicationId:comm-000563; GitHub issue URL/number not provided`
- Step 3 acceptance: `comm-000569`,
  `reviewDecision=accepted_no_high_or_mid_findings`, no findings.
- Codex-agent references:
  `AGENTS.md`,
  `.codex/skills/swift-coding-agent/SKILL.md`,
  `design-docs/specs/command.md`,
  `impl-plans/active/phase-0-foundation-and-graphql-runtime.md`,
  `Package.swift`, and `Taskfile.yml`.
- Intentional scope limits from the accepted design: do not implement live
  domain adapters, release workflows, signing, notarization, commits, pushes,
  GitHub releases, tap rendering, or cask packaging.

**Implementation Tasks**:

- [x] Inspect the current command router, executable entrypoints,
      `Package.swift`, `Taskfile.yml`, and command tests before editing.
      Preserve the existing SwiftPM target boundaries and keep production
      `main.swift` files thin.
- [x] Add a shared global-frame parse step in `AppleGatewayCommand` /
      `AppleGatewayCommandLine` that accepts `--config <path>`,
      `--config=<path>`, and `--pretty` before the command, removes those
      flags before subcommand dispatch, and keeps unknown global flags as
      usage errors with no stdout and exit code 2.
- [x] Route the global config path into every config-dependent command so it
      overrides `APPLE_GATEWAY_CONFIG`: `graphql`, `config validate`,
      `permissions status`, `permissions request`, `file download`, and
      `cache prune`. Keep `config validate [--config <path>]` as a
      command-local compatibility alias; if both global and local config
      flags are supplied, use the global path and reject the local duplicate
      as a usage error.
- [x] Route global `--pretty` into all JSON-producing command envelopes:
      `graphql`, `config validate`, `permissions status --json`,
      `file download`, and `cache prune`. Preserve `graphql --pretty` as a
      command-local alias. Do not alter non-JSON output for `schema print`,
      human permissions output, permission requests, help, version, or
      `version`.
- [x] Normalize stdout/stderr discipline in `AppleGatewayCommandLine`: JSON
      success and JSON business/error envelopes go to stdout; usage errors
      and unexpected process diagnostics go to stderr; usage errors exit 2.
      Config load failures after a JSON-producing command is selected should
      use the shared JSON error envelope and mapped config exit code rather
      than a raw stderr-only payload.
- [x] Preserve existing command semantics for `--flag value` and
      `--flag=value`, query/query-file exclusivity, variables/variables-file
      exclusivity, repeated `file download --key`, reader mutation rejection,
      file-store path safety, cache pruning, and permission no-prompt status
      behavior.
- [x] Add `AppleGatewaySmokeTests` to `Package.swift` as an executable
      target, and add an executable product only if needed for
      `swift run AppleGatewaySmokeTests` in this package layout. The target
      links against `AppleGatewayCore` and exercises the same command frame
      with in-memory fake providers/materializers through existing core
      injection seams; it must not add hidden production test-mode flags or
      call live TCC, Apple Events, application UI, Mail, notification DB, signing,
      notarization, release, commit, or push paths.
- [x] Update `Taskfile.yml` so `task test` runs the unit test suite and the
      smoke executable. Keep release, signing, notarization, cask, tap, and
      upload tasks untouched.
- [x] Add focused unit tests under
      `Tests/AppleGatewayCoreTests/CommandTests.swift` for global flag
      parsing, global config precedence over `APPLE_GATEWAY_CONFIG`,
      duplicate global/local config handling for `config validate`, global
      pretty formatting, stdout/stderr channel discipline, and unknown
      command exit 2.
- [x] Add smoke executable coverage for query/query-file exclusivity,
      variables decode errors, pretty output with sorted keys, reader
      mutation rejection, unknown command usage exit 2, no-config
      permissions GraphQL envelope, and at least one fake-backed file-store
      or permission path proving the smoke target does not depend on live
      adapters.
- [x] Update this progress log with date, result, verification commands, and
      any follow-up discovered. Do not mark TASK-007 complete until all
      verification has run or any blocker is recorded with the exact failed
      command.

**Deliverables**:

- Shared core command frame supporting global `--config` and global
  `--pretty` consistently across both production executables.
- JSON/business output and diagnostics split across stdout/stderr according
  to the command contract, including usage exit 2 behavior.
- `AppleGatewaySmokeTests` executable target covering deterministic full CLI
  flows against fake seams.
- `Taskfile.yml` test task running both unit tests and smoke tests.

**Dependencies**:

- Completed TASK-002 config resolver and path precedence behavior.
- Completed TASK-003 GraphQL runtime and reader-role schema enforcement.
- Completed TASK-004 shared error envelope and exit-code mapping.
- Completed TASK-005 permissions provider seams and no-prompt status service.
- Completed TASK-006 file-store materializer seams and cache safety behavior.
- No dependency on later domain adapters, release workflows, signing,
  notarization, commits, pushes, GitHub releases, tap rendering, or cask
  packaging.

**Completion Criteria**:

- [x] `apple-gateway graphql --query '{ permissions { calendars } }'`
      returns a valid envelope on a machine with no config
- [x] Smoke tests cover: query/query-file exclusivity, variables decode
      errors, pretty output, reader mutation rejection, unknown command
      usage error (exit 2)
- [x] `apple-gateway --config <path> graphql ...` selects that file before
      `APPLE_GATEWAY_CONFIG`
- [x] `apple-gateway --pretty graphql ...` and JSON-producing command paths
      pretty-print deterministic sorted-key JSON where specified
- [x] Usage errors write diagnostics to stderr only and exit 2; JSON
      business envelopes write to stdout
- [x] `task test` runs both `swift test` and the smoke executable

**Verification Commands**:

- `swift build`
- `swift test --filter Command`
- `swift test`
- `swift run AppleGatewaySmokeTests`
- `task test`
- `swiftlint`

## Progress Log

- 2026-07-02: Plan created from approved design docs.
- 2026-07-03: TASK-007 implementation plan revised after Step 3 acceptance
  `comm-000569` for workflow
  `codex-design-and-implement-review-loop-session-346`. Review decision was
  `accepted_no_high_or_mid_findings`; no high or mid findings required
  remediation. Plan traceability now records the issue reference,
  codex-agent references, accepted scope, deliverables, dependencies,
  verification commands, and explicit exclusions for release/signing/notary/
  commit/push work before the later implementation step.
- 2026-07-03: TASK-007 implemented after the Riela workflow's Step 3 design
  review accepted the command-frame design. The later Riela implementation-plan
  step stalled and was terminated; implementation continued locally against the
  accepted Riela design/review artifacts. Added global `--config` and
  `--pretty` parsing in the shared core command frame, JSON stdout envelopes
  for selected-command config failures, `AppleGatewaySmokeTests`, and smoke
  wiring in `task test`. Verification passed with the Xcode Swift toolchain:
  `swift build`, `swift test --filter Command`, `swift run
  AppleGatewaySmokeTests`, `swift test`, `task test`, `swiftlint`, and the
  no-config GraphQL CLI smoke command for `{ permissions { calendars } }`.
- 2026-07-03: Phase 0 closeout routed through Riela session
  `codex-design-and-implement-review-loop-session-350`; manager routing
  selected issue-resolution, but the intake backend stalled with stale
  timestamps and the workflow process was terminated. Local closeout continued
  against the design docs and implementation plan: moved command-frame files
  under `Sources/AppleGatewayCore/CLI/`, added minimal
  `AppleEventBridge/` and `Domains/*Adapter/` skeleton provider boundaries,
  and marked the phase-level deliverables and status complete pending final
  verification.
- 2026-07-03: TASK-001 implementation plan expanded after Step 3 design
  acceptance for `AppCore`/`AppCLI` rename, `AppleGatewayReaderCLI`,
  shared embedded `Resources/AppleGatewayInfo.plist`, reader bundle-id
  deferral, and required build/otool/test/lint verification.
- 2026-07-03: TASK-001 implemented. Renamed package targets and source/test
  directories to `AppleGatewayCore`, `AppleGatewayCLI`,
  `AppleGatewayReaderCLI`, and `AppleGatewayCoreTests`; added a shared core
  command-line runner, thin full/reader executable entrypoints, and
  `Resources/AppleGatewayInfo.plist`; embedded the shared plist into both
  executables with identical SwiftPM linker settings. Verification passed:
  `swift build`, `otool -s __TEXT __info_plist .build/debug/apple-gateway`,
  `otool -s __TEXT __info_plist .build/debug/apple-gateway-reader`,
  `task test`, and `swiftlint`. The first plain `swift build` attempt used an
  incompatible Nix macOS 11.3 SDK with the Xcode Swift 6.3 toolchain; rerunning
  with Xcode `DEVELOPER_DIR`, `SDKROOT`, `TOOLCHAINS`, and toolchain `PATH`
  succeeded.
- 2026-07-03: TASK-002 implementation plan expanded after Step 3 design
  acceptance. Scope is limited to config loading and `config validate`, with
  explicit parser subset, config path/value precedence, supported env override
  list, tilde expansion, unknown-key rejection, local validation boundaries,
  focused unit-test requirements, and verification commands.
- 2026-07-03: TASK-002 implemented. Added `Sources/AppleGatewayCore/Config/`
  schema, defaults, parser, resolver, env override handling, path expansion,
  validation, and `CONFIG_INVALID` envelope formatting; wired scoped
  `config validate [--config <path>]` routing through `AppleGatewayCommand`;
  added focused config unit tests under `Tests/AppleGatewayCoreTests/Config/`.
  Verification passed with explicit Xcode toolchain environment:
  `swift build`, `swift test --filter Config`, `task test`, and `swiftlint`.
  A plain `swift build` attempt still failed before compilation due to the
  existing Nix macOS 11.3 SDK mismatch with the Xcode Swift 6.3 toolchain.
- 2026-07-03: TASK-003 implementation plan expanded after Step 3 design
  acceptance from communication `comm-000518`. Scope is limited to the
  GraphQL runtime, safe placeholder `permissions` query registration, and
  scoped `graphql` / `schema print` CLI wiring. The plan explicitly excludes
  TASK-004 error-model work, TASK-005 permission probes, TASK-006 file store,
  TASK-007 smoke tests, commits, and pushes.
- 2026-07-03: TASK-003 implemented in workflow mode after Step 5 acceptance
  from communication `comm-000521`. Added the zero-dependency GraphQL runtime
  under `Sources/AppleGatewayCore/GraphQLRuntime/` with lexer/parser location
  errors, AST, schema registry, role-aware validation, variable coercion,
  executor/projection, JSON envelopes, and SDL printing; registered the safe
  non-prompting placeholder `permissions` query; wired scoped `graphql` and
  `schema print` CLI paths; added focused GraphQL runtime and command tests.
  Explicitly deferred TASK-004, TASK-005, TASK-006, and TASK-007. Preserved
  codex-agent reference `comm-000520` residual risks. Verification passed with
  explicit Xcode toolchain environment: `swift build`,
  `swift test --filter GraphQL`, `task test`, and `swiftlint`.
- 2026-07-03: TASK-003 post-integrity coverage hardening added after Riela's
  low-severity findings. Reader SDL is now pinned with an exact snapshot test,
  and command tests cover `graphql --query-file`, `--variables`,
  `--variables-file`, and `--pretty`. Verification passed with explicit Xcode
  toolchain environment: `swift test --filter GraphQL`, `task test`,
  `swiftlint`, `swift build`, plus CLI checks for permissions query execution
  and reader mutation rejection.
- 2026-07-03: TASK-004 implementation plan expanded after Step 3 design
  acceptance from communication `comm-000532`. Scope is limited to the shared
  `AppleGatewayError` model, complete error-code exit mapping, shared JSON
  envelope shape with top-level `extensions.requestId`, existing
  `CONFIG_INVALID` adaptation, existing GraphQL envelope adaptation,
  first-error aggregate exit selection for multi-root partial failures, and
  focused error/envelope tests. The plan explicitly excludes TASK-005
  permissions probes, TASK-006 file store behavior, TASK-007 smoke tests,
  commits, and pushes.
- 2026-07-03: TASK-004 implemented in workflow mode after Step 5 acceptance
  from communication `comm-000535`. Added the shared `AppleGatewayError` /
  `AppleGatewayErrorCode` model and `AppleGatewayJSONEnvelope` formatter;
  adapted config validation and GraphQL runtime envelopes to top-level
  `extensions.requestId`; mapped JSON-producing command exits from the first
  envelope error; preserved GraphQL locations and root `path` for partial
  failures; added focused mapping, envelope, config, GraphQL, and command-exit
  tests. Plain `swift build` still failed before project compilation because
  the shell selected the incompatible Nix macOS 11.3 SDK with Xcode Swift 6.3;
  verification passed with explicit Xcode toolchain environment:
  `swift build`, `swift test --filter Error`, `swift test --filter GraphQL`,
  `task test`, and `swiftlint`.
- 2026-07-03: TASK-005 design and implementation plan accepted through
  Riela session `codex-design-and-implement-review-loop-session-333`
  (`comm-000545` / `comm-000547`). The Riela implementation worker stalled
  during `step6-implement` after creating the initial permissions model and
  was cancelled; implementation then continued locally against the accepted
  Riela design and plan. Added `Sources/AppleGatewayCore/Permissions/`
  models, status/request protocols, live EventKit status/request probes,
  non-prompting Notes automation status via
  `AEDeterminePermissionToAutomateTarget`, read-only Full Disk Access probes,
  Clock Accessibility/automation status, notification-helper unavailable diagnostics,
  shared permission failure formatter, doctor output, `permissions status
  [--json]`, and `permissions request --domain ...`; replaced the GraphQL
  placeholder with the full non-prompting `PermissionsStatus` resolver and
  `PermissionState` enum; added focused permissions, command, and GraphQL
  tests for no-prompt status boundaries, request-domain isolation, disabled
  domains, formatter contract, JSON status output, and full GraphQL field
  coverage. Verification passed with explicit Xcode toolchain environment:
  `swift build`, `swift test --filter Permissions`, `swift test --filter
  GraphQL`, `swift test --filter Command`, `swift test`, `task test`,
  `swiftlint`, plus CLI smokes for `permissions status --json` and the full
  GraphQL `permissions` field query.
- 2026-07-03: TASK-006 design clarification was started through Riela
  session `codex-design-and-implement-review-loop-session-343`
  (`comm-000559`). The design-doc update produced the accepted TASK-006
  file-store contract for `agdk1` HMAC-SHA256 download keys, strict
  traversal rejection, managed cache layout, contained `file download`,
  contained `cache prune`, and SQLite snapshot sidecar copying. The Riela
  session stalled during `step2-design-self-review` and was cancelled;
  implementation continued locally against the Riela-updated design docs.
  Added `Sources/AppleGatewayCore/FileStore/` with key payload models,
  CryptoKit-backed key codec, path-safety helpers, download materialization,
  prune, snapshot-copy helper, and materializer protocol seams; wired
  `file download --key ... [--output-dir ...]` and `cache prune [--all]`
  through `AppleGatewayCommand`; added focused tests for forged-key
  `INVALID_DOWNLOAD_KEY`, traversal rejection, cache-root and explicit
  output containment, prune root refusal, symlink non-following behavior,
  key-material preservation/removal semantics, snapshot sidecar copying, and
  command envelopes. Verification passed with explicit Xcode toolchain
  environment: `swift build`, `swift test --filter FileStore`, `swift test
  --filter Command`, `swift test`, `task test`, and `swiftlint`.
- 2026-07-03: TASK-005 implementation plan expanded after Step 3 design
  acceptance from communication `comm-000545`. Scope is limited to
  non-prompting permission status probes, isolated prompt-capable request
  paths, GraphQL `PermissionsStatus` resolver integration, shared permission
  failure-message formatting, and focused tests. The plan explicitly excludes
  TASK-006 file store, TASK-007 smoke frame, Phase 4 notification helper
  creation/distribution, commits, pushes, signing, notarization, uploads, and
  manual/external release gates.
