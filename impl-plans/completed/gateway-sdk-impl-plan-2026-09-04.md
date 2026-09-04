# Implementation plan: AppleGatewaySDK facade on GatewaySDKKit (2026-09-04)

Brief (contract): `design-docs/briefs/gateway-sdk-2026-09-04.md`
Design (pinned decisions): `design-docs/gateway-sdk-design-2026-09-04.md`
One feature, one work package. Branch `feat/gateway-sdk`; commit per task; never push.
Never touch `/Users/taco/gits/tacogips/apple-gateway` or modify
`/Users/taco/gits/tacogips/gateway-sdk-kit` (read-only path dependency).

Every build/test command runs through an arm64 shell:

```
arch -arm64 /bin/zsh -lc 'cd /Users/taco/gits/tacogips/apple-gateway-worktrees/gateway-sdk && <cmd>'
```

Full gate: `swift build && swift test && swift run AppleGatewaySmokeTests && swiftlint`
(baseline is green with 0 lint violations; keep it that way after every task).

## Accepted-design traceability

The accepted design is the source of truth. Tasks below preserve its intentional
divergences from the generic kit: `calendarReminders` remains one catalog domain, and
catalog SDL strips only a defaulted argument/input field's top-level non-null while
runtime requiredness remains `isNonNull && defaultValue == nil`.

| Reference behavior | Implementation tasks |
| --- | --- |
| `GatewaySDK.swift`: protocol facade, named invocation, schema, and search defaults | Tasks 2, 4, 5 |
| `GatewayEnvelope.swift`: CLI-output parsing and failure-envelope semantics | Tasks 4, 5 |
| `GatewayDocumentBuilder.swift`: operation documents, variables, and selections | Tasks 4, 5 |
| `Command.swift`: public injection seams, config resolution, GraphQL output, and CLI compatibility | Tasks 3, 4, 5 |
| `Validator.swift`: defaulted requiredness and reader mutation rejection | Tasks 2, 4 |
| `ErrorEnvelope.swift`: established Apple error codes, request IDs, and exit codes | Tasks 4, 5 |

## Deliverables and dependency order

| Task | Deliverable | Depends on | Parallelizable |
| --- | --- | --- | --- |
| 1 | Kit dependency plus registry export seams | Accepted design | No |
| 2 | Role-aware catalog exporter and parity tests | Task 1 | No |
| 3 | Shared GraphQL service composition with unchanged CLI behavior | Task 1 | No |
| 4 | Public `AppleGatewaySDK` facade and SDK tests | Tasks 2 and 3 | No |
| 5 | `schema search` and `graphql operation` CLI subcommands and tests | Tasks 2 and 3; reuse Task 4 conversion seam | No |
| 6 | README, accepted design, and active plan documentation | Tasks 4 and 5 | No |
| 7 | Recorded full verification and clean committed handoff | Tasks 1 through 6 | No |

No implementation tasks are designated for parallel execution. Although some new
files have disjoint write scopes, the public types, conversion helper, command routing,
and shared test gate form a dependency chain; implement sequentially to avoid drift and
merge churn.

## Progress log expectations

Maintain a dated checklist in this active plan while implementation runs. For every
task, record status (`pending`, `in_progress`, `complete`, or `blocked`), changed files,
the exact verification command and result, resulting commit hash, and any design-aligned
deviation or residual risk. Never mark a task complete until its scoped gate passes.
After Task 7, move this file to `impl-plans/completed/` in the final documentation
commit if repository workflow permits; otherwise record why it remains active.

Implementation status (2026-09-04):

| Task | Status | Evidence |
| --- | --- | --- |
| 1 | complete | `Package.swift`; `SchemaRegistry.swift`; arm64 `swift build` passed. |
| 2 | complete | `SDK/AppleSchemaCatalogExporter.swift`; structural SDL parity now asserts forbidden builtin scalars against scalar definitions; validation, requiredness, and role tests passed in the final arm64 full gate. |
| 3 | complete | `GraphQLServiceComposition.swift`; CLI raw GraphQL routes through shared composition; full gate passed. |
| 4 | complete | `SDK/AppleGatewaySDK.swift`; SDK acceptance tests use isolated HOME and missing-config paths; calendar, events, reminder, Notes, reader, parity, config, and limit-error tests passed in the final arm64 full gate. |
| 5 | complete | `CLI/CommandSDKSubcommands.swift`; CLI subcommand tests use isolated HOME and missing-config paths; search, operation parity, selection, unknown-operation, config, and help tests passed in the final arm64 full gate. |
| 6 | complete | `README.md`, accepted design, and this plan updated. |
| 7 | complete | Final arm64 full gate passed: build, 266 tests (one operator-owned live integration test skipped), smoke tests, and SwiftLint (0 violations). |

## Implementation record (2026-09-04)

- Changed: `Package.swift`, `README.md`, `Sources/AppleGatewayCore/CLI/Command.swift`,
  `Sources/AppleGatewayCore/CLI/CommandSDKSubcommands.swift`,
  `Sources/AppleGatewayCore/GraphQLRuntime/SchemaRegistry.swift`,
  `Sources/AppleGatewayCore/GraphQLRuntime/GraphQLServiceComposition.swift`,
  `Sources/AppleGatewayCore/SDK/AppleSchemaCatalogExporter.swift`,
  `Sources/AppleGatewayCore/SDK/AppleGatewaySDK.swift`, and focused SDK tests.
- Initial verification passed:
  `arch -arm64 /bin/zsh -lc 'swift build && swift test && swift run AppleGatewaySmokeTests && swiftlint'`.
  Swift test reported 261 passing tests (one operator-owned live integration test skipped);
  smoke tests passed; SwiftLint reported 0 violations. A self-review then required expanded
  exporter, SDK, CLI, and documentation coverage. A subsequent self-review corrected
  SDL result-requiredness parity, the configured Notes maximum-page-size error, builtin
  scalar assertions, and isolated test homes. The final arm64 gate passed with 266 tests
  (one operator-owned live integration test skipped), smoke tests, and 0 SwiftLint
  violations.
- Design-aligned residual risk: the local `GatewaySDKKit` dependency remains read-only
  until its URL-pinned publication. SDK tests cover the public permission route, role
  boundaries, config envelopes, catalog export, search, and built operation flow. The
  corrective coverage also exercises calendar, Notes, and mutation injection seams.
- Resulting commit: final handoff commit; its exact hash is recorded in workflow output.

## Task 1 — Dependency + registry seams

Files: `Package.swift`, `Sources/AppleGatewayCore/GraphQLRuntime/SchemaRegistry.swift`.

1. `Package.swift`: add
   ```swift
   // The operator switches this path dependency to a URL pin when the kit is published.
   .package(path: "../../gateway-sdk-kit")
   ```
   under `dependencies:`, and `.product(name: "GatewaySDKKit", package: "gateway-sdk-kit")`
   to the `AppleGatewayCore` target's dependencies.
2. `SchemaRegistry.swift`:
   - Add `var description: String?` (default `nil`, placed after `arguments`) to
     `GraphQLFieldDefinition`. Do NOT change its custom `==` and do not edit any module
     call site.
   - Add a tiny internal `GraphQLDomainModule { domain, module }` and a computed
     `static var domainModules: [GraphQLDomainModule]` with exactly `permissions,
     calendarReminders, notes, mail, notifications, clockAlarms, phoneCalls` in that
     order. Do not use a stored `static let`: `GraphQLSchemaModule` contains
     non-`Sendable` resolver closures, and Swift 6 strict concurrency rejects that
     shared state. Rewrite `bootstrap(role:)` as
     `GraphQLSchemaRegistry(modules: domainModules.map(\.module), role: role)`.

Verify: full gate green (behaviour unchanged). Commit:
`feat: add GatewaySDKKit dependency and schema registry export seams`.

## Task 2 — Catalog exporter

File (new): `Sources/AppleGatewayCore/SDK/AppleSchemaCatalogExporter.swift` (~260 lines).

Public API exactly:

```swift
import GatewaySDKKit

extension GatewaySchemaCatalog {
  public static func apple(role: AppleGatewayRole) -> GatewaySchemaCatalog
}
```

Rules (design section 2; all internal helpers live in this file):

- Iterate `GraphQLSchemaRegistry.domainModules` in order. For role `.reader`, skip
  every module's `mutationFields` (the registry's rule, SchemaRegistry.swift:84).
- Root field -> `GatewayOperation(name:, kind: .query/.mutation, tier:, arguments:,
  result:, summary:, isDestructive:, domain:)` where:
  - `tier`: `"reader"` for queries, `"full"` for mutations (lowest tier that may run it).
  - `domain`: the module's domain string.
  - `isDestructive`: `name.hasPrefix("delete") || name.hasPrefix("dismiss")`.
  - `summary`: `field.description ?? field.name`.
  - `result`: mapped type ref.
- Type mapping: `GraphQLTypeReference` -> `GatewayTypeRef` 1:1
  (`.named`/`.list`/`.nonNull`).
- **Defaulted-non-null rule** for every operation argument, object-field argument, and
  input-object field: let `hasDefault = defaultValue != nil`;
  `isRequired = type.isNonNull && !hasDefault`; exported type = top-level `.nonNull`
  stripped iff `hasDefault`, else 1:1; `defaultValue` = converted default.
  Rationale: kit `validate()` rejects required+default
  (GatewayCatalogValidation.swift:103); the runtime validator accepts variables modulo
  top-level non-null (Validator.swift:168-180).
- Default conversion `GraphQLValue -> GatewayJSONValue`: int/float/string/bool/null/
  list/object 1:1, `.enumCase(x)` -> `.string(x)`; `.variable` cannot occur — if it
  ever does, omit the default.
- Named types: export every registry type except names in
  `GatewaySchemaCatalog.builtinScalars` (`ID,String,Int,Float,Boolean,JSON`).
  `scalar`->`.scalar`, `object`->`.object([GatewayField])` (field arguments mapped with
  the same defaulted-non-null rule), `enumType`->`.enumeration`,
  `inputObject`->`.inputObject([GatewayArgument])`. Deduplicate by name across modules
  the way the registry does (later module wins via dictionary; preserve deterministic
  order: registry iteration sorted by name is fine because catalog.sdl() sorts groups
  by name anyway — but keep a stable order to make tests deterministic).
- Catalog root: `provider: "apple-gateway"`, `tier: role == .full ? "full" : "reader"`.

Tests (new): `Tests/AppleGatewayCoreTests/SDK/AppleSchemaCatalogExporterTests.swift`
(swift-testing, `@testable import AppleGatewayCore`, `import GatewaySDKKit`):

- `catalog.validate() == []` for `.full` and `.reader` (print problems on failure).
- Parity, both roles, both directions, between `GraphQLRuntime.schema(role:)` and
  `GatewaySchemaCatalog.apple(role:).sdl()`. Implement a small test-side SDL splitter
  in this file: split each SDL text into definitions (`type X { ... }`,
  `input X { ... }`, `enum X { ... }`, `scalar X`), ignore description block strings
  (`"""..."""` lines), and reduce to comparable structures:
  - map rootTypeName -> set of field signatures, where each signature is
    `(name, [(argName, argTypeStrippedOfTopLevelBang)], resultType)`;
  - map typeName -> (kind, set of field/value signatures with argument types
    stripped of one trailing `!` at top level only).
  Assert the reduced structures are equal both ways (compare full equality of the two
  maps). Also assert `"scalar DateTime"` appears in both and `ID`/`String` blocks in
  neither.
- Model-level requiredness parity: for every root field argument in
  `GraphQLSchemaRegistry.bootstrap(role:)`, find the catalog operation argument and
  assert `isRequired == (runtimeType.isNonNull && runtimeDefault == nil)` and that the
  exported type spelling equals the runtime spelling with top-level non-null stripped
  iff a default exists.
- Spot checks: `createReminder` (kind mutation, tier "full", domain
  "calendarReminders"); `calendars` and `events` tier "reader"; `deleteEvent` and
  `dismissNotifications` `isDestructive == true`; `createReminder.isDestructive == false`;
  reader catalog `operations(of: .mutation).isEmpty`.

Verify: full gate. Commit: `feat: export the apple-gateway schema catalog for GatewaySDKKit`.

## Task 3 — Shared execution composition

Files: new `Sources/AppleGatewayCore/GraphQLRuntime/GraphQLServiceComposition.swift`
(~120 lines); edit `Sources/AppleGatewayCore/CLI/Command.swift`.

1. Internal struct:
   ```swift
   struct GraphQLServiceComposition: Sendable {
     let role: AppleGatewayRole
     let permissionsProvider: any PermissionsProviding
     // ... the same concrete calendar/Notes services AppleGatewayCommand already
     // holds, plus optional mail/notifications/clock/phone overrides; store exactly
     // what executeResponse needs
     func executeResponse(
       query: String,
       variables: [String: GraphQLValue],
       config: AppleGatewayConfig,
       pretty: Bool
     ) -> AppleGatewayJSONResponse
   }
   ```
   Body = the exact call currently at Command.swift:318-334: pass stored services,
   with `mailReadService ?? MailServiceFactory.liveReadService(config:)`,
   `mailWriteService ?? MailServiceFactory.liveWriteService(config:)`,
   `notificationsService ?? NotificationsServiceFactory.liveService(config:)`,
   `clockAlarmsService ?? ClockAlarmsServiceFactory.liveService(config:)`,
   `phoneCallsService ?? PhoneCallsServiceFactory.liveService(config:)`.
2. `AppleGatewayCommand` gains an internal computed property `serviceComposition:
   GraphQLServiceComposition` built from its stored seams; `runGraphQLCommand` replaces
   the direct `GraphQLRuntime.executeResponse` call with
   `serviceComposition.executeResponse(query:variables:config:pretty:)`. No other change
   to that function; output must stay byte-identical.

Verify: full gate (CommandTests + smoke pin behaviour). Commit:
`refactor: extract shared GraphQL service composition for CLI and SDK`.

## Task 4 — AppleGatewaySDK facade

File (new): `Sources/AppleGatewayCore/SDK/AppleGatewaySDK.swift` (~160 lines).

```swift
import GatewaySDKKit

public struct AppleGatewaySDK: GatewaySDK {
  public let provider = "apple-gateway"
  public let tier: String
  public let catalog: GatewaySchemaCatalog
  public init(
    role: AppleGatewayRole = .full,
    permissionsProvider: any PermissionsProviding = LivePermissionsProvider(),
    responsibleProcessDetector: any ResponsibleProcessDetecting = DefaultResponsibleProcessDetector(),
    fileMaterializer: (any FileStoreMaterializing)? = nil,
    calendarReadService: CalendarReadService? = nil,
    calendarWriteService: CalendarWriteService? = nil,
    notesReadService: NotesReadService? = nil,
    notesWriteService: NotesWriteService? = nil,
    mailReadService: MailReadService? = nil,
    mailWriteService: MailWriteService? = nil,
    notificationsService: (any NotificationsProviding)? = nil,
    clockAlarmsService: (any ClockAlarmsProviding)? = nil,
    phoneCallsService: (any PhoneCallsProviding)? = nil
  )
  public func execute(
    document: String,
    variables: [String: GatewayJSONValue],
    environment: [String: String]
  ) async -> GatewayEnvelope
}
```

Init: store `role` privately, `tier = role == .full ? "full" : "reader"`,
`catalog = .apple(role: role)`, and retain the optional calendar/Notes injections.
Do not resolve default Notes services in init because `execute` has not received its
environment. The GraphQL path does not use `responsibleProcessDetector` or
`fileMaterializer`; accept them for exact public initializer parity without using them.

After config resolution, a private `serviceComposition(config:)` creates missing
calendar services through `CalendarReminderServiceFactory.liveServices()`. If either
Notes side is missing, it calls `NotesServiceFactory.liveServices(config:)` exactly
once for that execution, preserves either injected side, and fills only missing sides
from the live pair. It then builds `GraphQLServiceComposition`; mail, notifications,
clock alarms, and phone calls keep their config-aware lazy fallbacks there. Never use
unavailable services as defaults and never observe `ProcessInfo.processInfo.environment`.

`execute` (design 3.2):
1. `AppleGatewayConfigResolver().resolve(cliConfigPath: nil, environment: environment)`;
   on `AppleGatewayConfigError`, produce the same JSON the CLI's `configErrorResult`
   prints (reuse the internal envelope API) and return
   `GatewayEnvelope(parsingCLIOutput: thatJSON, exitCode: itsExitCode)`.
2. Variables: `try GraphQLValue.fromJSONObject(value.anyValue)` per entry; on
   `GraphQLRuntimeError`, build the CLI's invalidArgument envelope (same shape as
   Command.swift:299-309) and return it parsed as above.
3. `serviceComposition(config: config).executeResponse(query: document, variables:,
   config:, pretty: false)`.
4. `return GatewayEnvelope(parsingCLIOutput: String(decoding: response.data, as: UTF8.self), exitCode: response.exitCode)`.

Tests (new): `Tests/AppleGatewayCoreTests/SDK/AppleGatewaySDKTests.swift`. Reuse or
add small fakes (pattern: existing fakes in Tests/AppleGatewayCoreTests domain tests /
`StaticPermissionsProvider`). Cover exactly the brief's list:

- `invoke(GatewayOperationRequest(operation: "calendars"))` with a recording fake
  `CalendarReadService`: envelope has data, no errors; fake recorded the call. Build
  the document separately via `GatewayDocumentBuilder` to assert it declares no
  variables (no `(` after `query Calendars`? assert `!built.document.contains("$")`).
- `invoke` `events` with `variables: ["input": .object([...])]`: built document
  declares `$input`; recording fake received the expected `EventSearchInput`
  (assert on the recorded input's fields).
- `invoke` `createReminder` with an input-object variable through a recording fake
  `CalendarWriteService` (role .full).
- one notes query (e.g. `notes` or the actual root field name from
  NotesSchemaModule.swift:92-136) through a fake `NotesReadService`.
- reader-role SDK, named path: `invoke` of `createReminder` fails in
  `GatewayDocumentBuilder` because the reader catalog has no mutation. Assert the
  GatewaySDKKit `unknownOperation(name: "createReminder")` failure envelope has exit
  code 2, message `unknown operation 'createReminder'`, nil error code, and empty raw
  output.
- reader-role SDK, raw path: `execute` a handwritten mutation and assert the existing
  apple-gateway validator envelope has message `Mutations are disabled in reader mode`,
  code `WRITE_DISABLED_IN_READER`, and exit code 5. Do not remap this established error
  to `GRAPHQL_VALIDATION_ERROR`.
- passthrough: same document+variables through `sdk.execute` and through
  `AppleGatewayCommand(arguments: ["graphql", "--query", doc, "--variables", json], ...)`
  with identical fakes and environment. Assert equal exit codes and byte-for-byte
  output after replacing each independently generated `extensions.requestId` with one
  sentinel; assert both original request IDs are nonempty.
- config error parity: point `APPLE_GATEWAY_CONFIG` to the same missing explicit path;
  assert SDK and CLI return `CONFIG_INVALID`, the same exit code, and request-ID-
  normalized byte-identical output.
- config-sensitive default Notes parity: inject no Notes services; set
  `APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE=1` and
  `APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE=1`; execute
  `notes(input: { first: 2 }) { totalCount }` through SDK and CLI and assert the same
  limit error plus request-ID-normalized byte-identical output. The resolver validates
  the configured limit before calling the live provider, so the test is deterministic
  and proves per-execute config-aware Notes construction.

Note test env: always pass an explicit environment to both paths. Use an isolated
temporary `HOME`; use the two limit overrides above for the config-sensitive test and a
missing explicit `APPLE_GATEWAY_CONFIG` path for the config-error test.

Verify: full gate. Commit: `feat: add AppleGatewaySDK facade over the GraphQL runtime`.

## Task 5 — CLI subcommands

Files: new `Sources/AppleGatewayCore/CLI/CommandSDKSubcommands.swift` (~280 lines);
edit `Command.swift` only for dispatch, usage, and the four package-internal helper
access levels listed below. Keep `GlobalCommandFrame` private to `Command.swift`; the
new extension receives only the scalar context it needs, so frame representation and
the command's stored service seams remain encapsulated.

1. Dispatch: in `runSchemaCommand`, accept `search` as first argument and delegate to
   `runSchemaSearchCommand(Array(arguments.dropFirst()), pretty: pretty)` in the new
   file. Change the private `runSchemaCommand` signature to accept `pretty: Bool`, and
   have `runResult` pass `frame.pretty`; the existing `print` branch ignores it and
   remains byte-identical. Keep the
   existing `print` path and its error text unchanged (update the usage-error message
   to mention both subcommands only if tests don't pin the old text — CommandTests
   pins "Usage: apple-gateway schema print [--role full|reader]" only on wrong input;
   check and keep pinned messages identical where asserted). In `runGraphQLCommand`,
   before flag parsing, if the first argument is `operation`, delegate to
   `runGraphQLOperationCommand(Array(arguments.dropFirst()),
   configPath: frame.configPath, pretty: frame.pretty)`. Do not pass
   `GlobalCommandFrame` across the file boundary.
2. Access-control contract in `Command.swift`: change exactly these instance helpers
   from `private` to package-internal by removing the modifier so the same-type
   extension can reuse established behavior: `readOptionValue`, `parseRole`,
   `resolveConfig`, and `configErrorResult`. Do not widen them to `public`, do not move
   `GlobalCommandFrame`, and do not widen any stored service property. Task 3's
   `serviceComposition` property is already planned as internal and is the only service
   composition surface used by the new file.
3. `schema search <regex> [--role full|reader] [--kinds a,b,...]
   [--include-referenced-types] [--limit N]`:
   - parse flags in the existing style (`readOptionValue`, `--flag=value` variants,
     unknown -> `Error.unknownArgument`/`invalidUsage`);
   - kinds: comma-separated `GatewayDefinitionKind` raw values; invalid ->
     `Error.invalidUsage("Unknown schema search kind: ...")`;
   - limit: positive Int or `invalidUsage`;
   - role defaults to `self.role`;
   - run `GatewaySchemaSearch(catalog: .apple(role:)).search(pattern, options:)`;
     kit throw (invalid regex) -> `Error.invalidUsage("Invalid search pattern: <regex>")`;
   - print via `JSONEncoder` with `.sortedKeys` (+ `.prettyPrinted` when the global
     `--pretty` scalar is true). `schema print` must remain byte-identical.
4. `graphql operation <name> [--variables <json>|--variables-file <path>]
   [--select a.b,c]`:
   - parse name (first non-flag arg) + flags in existing style; enforce at-most-one
     variables source (same message style as parseGraphQLArguments);
   - variables: parse text via `GatewayJSONValue.parse`; non-object or invalid JSON ->
     JSON envelope with `AppleGatewayError(code: .invalidArgument, message: "GraphQL
     variables must be valid JSON"/"...decode to a JSON object")` mirroring
     `loadVariables`;
   - selection: `--select v` -> `.fields(v.split(separator: ",").map(String.init))`,
     else `.default`;
   - build via `GatewayDocumentBuilder(catalog: .apple(role: self.role))`; on throw ->
     JSON envelope `AppleGatewayError(code: .invalidArgument, message:
     String(describing: error))` via `AppleGatewayJSONEnvelope.response` with its exit
     code;
   - convert `built.variables` -> `GraphQLValue` (same conversion as the facade — put
     the `[String: GatewayJSONValue] -> [String: GraphQLValue]` helper in ONE internal
     place, e.g. the exporter file or a small extension in the SDK dir, used by both);
   - call the internal `resolveConfig(configPath:)` with the explicit `configPath`
     scalar; on `AppleGatewayConfigError`, call internal
     `configErrorResult(_:pretty:)` with the explicit `pretty` scalar;
   - execute through internal `serviceComposition`, passing `pretty`, and return output
     plus exit code. This is the same config/error/execution path as raw GraphQL without
     exposing the private global frame or private stored services.
5. `usage` string: add both subcommands for full and reader variants next to the
   existing `schema print` / `graphql` lines.

Tests (new): `Tests/AppleGatewayCoreTests/SDK/CommandSDKSubcommandTests.swift`:

- `schema search calendars` returns JSON parseable as an array with a `calendars`
  query match; `--kinds mutation` excludes queries; `--limit 1` caps; `--role reader`
  yields no mutation matches; invalid kind and invalid regex -> `Error.invalidUsage`;
  a global `--pretty` produces pretty JSON while `schema print` stays unchanged.
- `graphql operation calendars` with fakes == output of `graphql --query <same doc>`
  with the same fakes and explicit environment. Extract each original
  `extensions.requestId`, assert both are nonempty, replace only those two JSON string
  values with one sentinel in their respective output, then assert byte-for-byte
  equality; do not normalize key order, whitespace, errors, data, or any other field.
  Also verify a global missing `--config` path returns the same request-ID-normalized
  config-error envelope as raw GraphQL, `--select` narrows (document contains only
  selected fields), and unknown operation returns a JSON envelope with
  `INVALID_ARGUMENT` and a nonzero exit code.
- `--help` output contains `schema search` and `graphql operation`.

Verify: full gate. Commit:
`feat: add schema search and graphql operation CLI subcommands`.

## Task 6 — README + docs commit

- `README.md`: new section "Client SDK (AppleGatewaySDK)" — dependency snippet, Swift
  example (`GatewaySchemaCatalog` via `sdk.catalog`, `searchSchema("reminder")`,
  `invoke(GatewayOperationRequest(operation: "events", variables: [...]))`, raw
  `execute(document:variables:environment:)`), tier semantics ("reader" facade cannot
  build or execute mutations), and CLI docs for `schema search` and
  `graphql operation` with example invocations/output.
- Commit the design doc `design-docs/gateway-sdk-design-2026-09-04.md` and this plan
  `impl-plans/active/gateway-sdk-impl-plan-2026-09-04.md` (already authored) together with the
  README change. Commit: `docs: document the AppleGatewaySDK and new CLI subcommands`.

## Task 7 — Final verification

Run the full gate through arm64 and record output:

```
arch -arm64 /bin/zsh -lc 'cd /Users/taco/gits/tacogips/apple-gateway-worktrees/gateway-sdk && swift build && swift test && swift run AppleGatewaySmokeTests && swiftlint'
```

Check `git status` is clean, all commits on `feat/gateway-sdk`, nothing pushed,
`wc -l` of every touched Swift file < 1000.

## Completion criteria

1. Full gate green; swiftlint 0 violations; smoke tests pass.
2. Deliverable files exist with the brief's exact names/APIs:
   `AppleSchemaCatalogExporter.swift` (`GatewaySchemaCatalog.apple(role:)`),
   `AppleGatewaySDK.swift` (`AppleGatewaySDK: GatewaySDK`), CLI `schema search` +
   `graphql operation`, Package.swift path dependency with URL-pin comment.
3. Exporter parity + validate() tests pass for both roles; every test bullet in the
   brief has a passing test; existing CommandTests/domain/smoke tests unchanged and
   green; `schema print` and `graphql` outputs byte-identical to before.
4. README documents SDK + subcommands; design doc and impl plan committed; all work
   committed on `feat/gateway-sdk`, no push, no tags.

## Guardrails for the implementer

- Do not rename or reshape any public API from the brief; riela is written against it.
- Do not modify the kit; if a kit behaviour surprises you (validate rule, builder
  error), adapt on the apple-gateway side per the design's mapping rules.
- If the parity test fails on an unforeseen spelling difference, fix the exporter or
  the test normalization within the design's rules — never weaken validate()==[].
- Keep `GraphQLRuntime` internal; keep tier enforcement in registry/validator.
- No emojis anywhere; no AI attribution in commit messages.
