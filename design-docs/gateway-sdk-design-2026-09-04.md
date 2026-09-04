# Design: `AppleGatewaySDK` facade on `GatewaySDKKit` (2026-09-04)

Brief: `design-docs/briefs/gateway-sdk-2026-09-04.md` (one feature). Master design:
`/Users/taco/gits/tacogips/riela/docs/briefs/gateway-sdk-2026-09-04.md` sections 2 and
3.3. Kit (read-only): `/Users/taco/gits/tacogips/gateway-sdk-kit`, product
`GatewaySDKKit`, package name `gateway-sdk-kit`, macOS 14, Swift 6.

## 0. Reference and workflow boundaries

- `/Users/taco/gits/tacogips/gateway-sdk-kit` is the authoritative local SDK-kit
  reference and is read-only for this work. `/Users/taco/gits/tacogips/apple-gateway`
  is also read-only; all changes remain in this `feat/gateway-sdk` worktree.
- This is a Codex-only Swift package workflow. No Cursor CLI behavior was supplied, so
  Cursor adapter work and Cursor-specific behavior mapping are not applicable.
- The exporter intentionally adapts two local runtime facts instead of copying the
  master design literally: the single `calendarReminders` module remains one catalog
  domain, and defaulted top-level non-null input types are made nullable in catalog SDL
  while their runtime requiredness is preserved as specified in section 2.2.

## 1. Package dependency

`Package.swift` gains:

```swift
// The operator switches this path dependency to a URL pin when the kit is published.
.package(path: "../../gateway-sdk-kit")
```

and target `AppleGatewayCore` gains `.product(name: "GatewaySDKKit", package: "gateway-sdk-kit")`.
No other manifest changes; all executables inherit it transitively.

## 2. Catalog exporter — `Sources/AppleGatewayCore/SDK/AppleSchemaCatalogExporter.swift`

Public entry point (extension on the kit type):

```swift
extension GatewaySchemaCatalog {
  public static func apple(role: AppleGatewayRole) -> GatewaySchemaCatalog
}
```

### 2.1 Domain-tagged module source (anti-drift seam)

`SchemaRegistry.swift` gains an internal domain-tagged module list, and
`bootstrap(role:)` is rewritten on top of it so the exporter and the runtime cannot
disagree about module set or order:

```swift
struct GraphQLDomainModule {
  let domain: String
  let module: GraphQLSchemaModule
}

extension GraphQLSchemaRegistry {
  static var domainModules: [GraphQLDomainModule] {
    [
      GraphQLDomainModule(domain: "permissions", module: .permissions),
      GraphQLDomainModule(domain: "calendarReminders", module: .calendarReminders),
      GraphQLDomainModule(domain: "notes", module: .notes),
      GraphQLDomainModule(domain: "mail", module: .mail),
      GraphQLDomainModule(domain: "notifications", module: .notifications),
      GraphQLDomainModule(domain: "clockAlarms", module: .clockAlarms),
      GraphQLDomainModule(domain: "phoneCalls", module: .phoneCalls)
    ]
  }
}
// bootstrap(role:) = GraphQLSchemaRegistry(modules: domainModules.map(\.module), role: role)
```

The property must remain computed: every access creates a fresh module graph, avoiding
Swift 6 shared static state containing the runtime's non-`Sendable` resolver closures.
The exporter iterates `domainModules`, tagging every root field with its domain. Reader
role applies the registry's exact rule: mutation fields are dropped (`SchemaRegistry.swift:84`).

### 2.2 Mapping rules

- `GraphQLTypeReference` -> `GatewayTypeRef`: `.named`/`.list`/`.nonNull` 1:1.
- `GraphQLNamedTypeKind` -> `GatewayNamedType.Kind`: `scalar`->`.scalar`,
  `object([GraphQLFieldDefinition])`->`.object([GatewayField])` (with arguments),
  `enumType`->`.enumeration`, `inputObject`->`.inputObject([GatewayArgument])`.
- Named types whose name is in `GatewaySchemaCatalog.builtinScalars`
  (`ID,String,Int,Float,Boolean,JSON`) are **not** exported; this mirrors the runtime
  SDL printer, which skips built-in scalars (`SDLPrinter.swift:82-84`). `DateTime` is
  the only custom scalar and is exported.
- **Defaulted non-null rule** (load-bearing): the kit's `validate()` rejects any
  argument/input field with `isRequired || type.isRequired` that carries a
  `defaultValue` (`GatewayCatalogValidation.swift:103`), while the runtime models many
  optional-with-default arguments as non-null + default (e.g.
  `span: RecurrenceSpan! = THIS_EVENT`, `interval: Int! = 1`;
  `CalendarRemindersSchemaModule.swift:133-214,337,354`). Runtime requiredness is
  `type.isNonNull && defaultValue == nil` (`Validator.swift:91`). The exporter therefore
  maps every argument, object-field argument, and input-object field as:
  - `isRequired = type.isNonNull && defaultValue == nil`
  - exported `GatewayTypeRef` = the runtime type **with the top-level non-null stripped
    when a default value exists**, otherwise 1:1
  - `defaultValue` = converted default (see 2.3), kept only when the type is not
    required after stripping (always true by construction)

  Documents built from the stripped spelling stay valid against the runtime: the
  validator's variable-flow check compares types modulo top-level non-null
  (`Validator.swift:168-180`), and the builder only declares supplied variables.
- `GatewayOperation`: `kind` query/mutation; `tier` = lowest tier that may run it —
  `"reader"` for queries, `"full"` for mutations (kit doc: "lowest tier",
  `GatewayCatalogModel.swift:191`); `result` = mapped field type; `domain` = the
  contributing module's domain; `isDestructive` = name has prefix `delete` or `dismiss`
  (covers deleteCalendar/deleteEvent/deleteReminder/deleteNote/deleteMailMessage/
  deleteClockAlarm/dismissNotifications/dismissAllGatewayNotifications);
  `summary` = the field's new `description` if set, else the field name.
- Catalog root: `provider = "apple-gateway"`, `tier = "full"|"reader"` per role.

### 2.3 Default-value conversion

`GraphQLValue` -> `GatewayJSONValue`: int/float/string/bool/null/list/object 1:1,
`enumCase(x)` -> `.string(x)` (JSON has no enum), `variable` never occurs in schema
defaults (assert via conversion error -> omit default). Internal helper in the exporter
file.

### 2.4 `description` on `GraphQLFieldDefinition`

Add `var description: String? = nil` to `GraphQLFieldDefinition`
(`SchemaRegistry.swift:15`). The custom `==` (name/type/arguments) is left unchanged.
No module call sites change ("where cheap": summaries fall back to field names now;
descriptions can be added incrementally later).

## 3. Facade — `Sources/AppleGatewayCore/SDK/AppleGatewaySDK.swift`

```swift
public struct AppleGatewaySDK: GatewaySDK {
  public let provider = "apple-gateway"
  public let tier: String                  // "full" | "reader"
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

Same defaulted seams as `AppleGatewayCommand.init` (`Command.swift:30-46`); lint-safe
because SwiftLint does not count defaulted parameters. `role` is stored internally;
`tier` is its string form. `catalog = .apple(role:)` computed once in init. The struct is
`Sendable` (same stored seam types as the already-`Sendable` `AppleGatewayCommand`).
`invoke`, `schemaSDL`, `searchSchema` come from the kit's protocol extension; apple has
no command-kind operations, so the argv path is unused.

### 3.1 Shared execution composition (anti-drift helper)

New internal struct, `Sources/AppleGatewayCore/GraphQLRuntime/GraphQLServiceComposition.swift`:

```swift
struct GraphQLServiceComposition: Sendable {
  // Role, permissions, concrete calendar/Notes services, and optional
  // config-dependent service overrides used by executeResponse.
  func executeResponse(
    query: String,
    variables: [String: GraphQLValue],
    config: AppleGatewayConfig,
    pretty: Bool
  ) -> AppleGatewayJSONResponse
}
```

Its body is the exact final composition `runGraphQLCommand` performs today
(`Command.swift:318-334`): call `GraphQLRuntime.executeResponse` with concrete
calendar/Notes services and live-factory fallbacks for
mail/notifications/clockAlarms/phoneCalls built from `config`.
`AppleGatewayCommand` gains an internal `serviceComposition` property using the
services it already resolved during command initialization, and `runGraphQLCommand`
delegates to it without changing CLI behavior.

`AppleGatewaySDK` does **not** hold a preconstructed composition. It stores the optional
calendar/Notes service injections from its initializer. After each `execute` resolves
that call's `environment` into `AppleGatewayConfig`, an internal
`serviceComposition(config:)` resolves missing services and returns a concrete
composition:

- missing calendar services come from `CalendarReminderServiceFactory.liveServices()`;
- if either Notes service is missing, call `NotesServiceFactory.liveServices(config:)`
  once for that execution, retain any injected side, and fill only the missing side
  from the returned pair; and
- mail, notifications, clock alarms, and phone calls retain their existing lazy
  config-aware fallbacks inside `GraphQLServiceComposition.executeResponse`.

This defers Notes cache-root and limit selection until the per-call environment is
known, preserves injected fakes, and observes no ambient environment. The accepted
`responsibleProcessDetector` and `fileMaterializer` initializer parameters remain for
API parity but are not used by the GraphQL execution path. `GraphQLRuntime` stays
internal.

### 3.2 `execute` data flow

1. Resolve config exactly as the CLI does with no `--config` flag:
   `AppleGatewayConfigResolver().resolve(cliConfigPath: nil, environment: environment)`.
   The passed `environment` is the only environment observed (protocol contract).
   On `AppleGatewayConfigError` -> the same JSON envelope `configErrorResult` prints,
   wrapped per step 4.
2. Convert variables: `GatewayJSONValue.anyValue` -> `GraphQLValue.fromJSONObject`
   (the CLI's own coercion path, `Command.swift:426`). On failure -> the same
   `invalidArgument` envelope the CLI prints for bad variables.
3. Build `serviceComposition(config:)` from the stored injections and the resolved
   config, then call `executeResponse(query:variables:config:pretty:false)`.
4. Map `AppleGatewayJSONResponse { data, exitCode }` ->
   `GatewayEnvelope(parsingCLIOutput: String(decoding: data, as: UTF8.self), exitCode:)`.
   The kit parser understands the `{data, errors, extensions:{requestId}}` shape the
   runtime prints, so `data`/`errors`/`requestId` populate and `rawOutput` is exactly
   the JSON the CLI would print with the CLI's exit code — the brief's contract.

Tier safety: reader facades build the reader registry (mutations dropped), the reader
catalog contains no mutations, and raw `execute` still hits the validator's
`writeDisabledInReader` rule (`Validator.swift:9-14`). The SDK cannot widen a tier.

## 4. CLI — new file `Sources/AppleGatewayCore/CLI/CommandSDKSubcommands.swift`

Extension on `AppleGatewayCommand` (Command.swift is 803 lines; the 1000-line rule
forbids growing it much). `runResult()` dispatch changes are minimal: `schema` routing
accepts `search`, `graphql` routing accepts a leading `operation` word before flag
parsing. `schema print` and `graphql --query/--query-file` behaviour and output are
untouched.

### 4.1 `schema search`

`schema search <regex> [--role full|reader] [--kinds q1,q2,...] [--include-referenced-types] [--limit N]`

- `--role` defaults to the binary's role, mirroring `schema print` (metadata only, no
  tier widening). `--kinds` takes comma-separated `GatewayDefinitionKind` raw values
  (`query,mutation,command,object,inputObject,enumeration,scalar`); unknown value ->
  `Error.invalidUsage`. `--limit` must parse as positive Int.
- Builds `GatewaySchemaCatalog.apple(role:)`, runs
  `GatewaySchemaSearch(catalog:).search(pattern, options:)`.
- Output: JSON array of the kit's `Codable` `Match` values via `JSONEncoder` with
  `sortedKeys` (+ `prettyPrinted` when the global `--pretty` frame flag is set).
- Invalid regex (kit throw) -> `Error.invalidUsage("Invalid search pattern: ...")`,
  consistent with other argument errors.

### 4.2 `graphql operation`

`graphql operation <name> [--variables <json>|--variables-file <path>] [--select a.b,c]`

Synchronous flow (no async bridge inside `run()`):

1. Parse variables JSON into `[String: GatewayJSONValue]` (via
   `GatewayJSONValue.parse`, requiring a top-level object; errors -> the same
   `invalidArgument` JSON envelope shape `loadVariables` produces).
2. Selection: `--select` -> `.fields(value.split(separator: ","))`; absent -> `.default`.
3. `GatewayDocumentBuilder(catalog: .apple(role: self.role)).build(request)`.
   Builder errors (unknown operation, bad selection path, missing required variable,
   type mismatch) -> JSON error envelope via `AppleGatewayJSONEnvelope.response` with
   `AppleGatewayError(code: .invalidArgument, message: ...)` and its standard exit code.
4. Convert `built.variables` -> `GraphQLValue` (same path as 3.2 step 2), resolve config
   from the frame as `runGraphQLCommand` does, execute through `serviceComposition`,
   print the response JSON with the response exit code — byte-compatible with what
   `graphql --query <built.document>` would print.

Usage text (`Command.swift:131 usage`) gains both subcommands for both role variants.

## 5. Tests — `Tests/AppleGatewayCoreTests/SDK/`

New directory; swift-testing like the rest of the suite; fakes reused from existing
domain tests / new small fakes alongside.

1. `AppleSchemaCatalogExporterTests.swift`
   - `catalog.validate() == []` for `.full` and `.reader`.
   - Parity, both roles and both directions, between `GraphQLRuntime.schema(role:)`
     (via `@testable`) and `catalog.sdl()`: a small test-side SDL splitter reduces each
     output to comparable definition sets — root-type field signatures and named-type
     blocks. Normalization applied before comparing: argument types compare with the
     top-level `!` stripped (the exporter's defaulted-non-null rule makes this the only
     spelling difference; the runtime printer never prints defaults). Assert equal sets
     of: root field names per root type, per-field argument name lists,
     stripped argument type spellings, result types, named type names, and per-type
     field/value lists.
   - Model-level requiredness parity: for every registry root-field argument,
     the catalog argument's `isRequired == (type.isNonNull && defaultValue == nil)` and
     the type spelling is stripped iff a default exists.
   - Spot checks: `createReminder` tier `"full"` domain `"calendarReminders"`;
     `calendars`/`events` tier `"reader"`; `deleteEvent` and `dismissNotifications`
     `isDestructive`; reader catalog has zero mutations; `DateTime` exported, `ID`
     not.
2. `AppleGatewaySDKTests.swift` (fakes injected through the init seams)
   - `invoke` `calendars`: document contains no variable declarations; fake calendar
     read service received the expected call; envelope data present.
   - `invoke` `events` with `variables: ["input": ...]`: built document declares
     `$input`; fake received the coerced search input.
   - `invoke` `createReminder` (mutation, input object) via fake write service.
   - one `notes` query via fake notes read service.
   - reader-role SDK named invocation of `createReminder` -> GatewaySDKKit
     `unknownOperation(name: "createReminder")` builder-failure envelope because the
     reader catalog omits mutations; assert exit code 2, message
     `unknown operation 'createReminder'`, nil error code, and empty raw output. Raw
     `execute` of a handwritten mutation reaches the apple-gateway validator instead;
     assert message `Mutations are disabled in reader mode`, code
     `WRITE_DISABLED_IN_READER`, and exit code 5.
   - passthrough: run `sdk.execute(document:variables:)` and `AppleGatewayCommand`
     `graphql --query --variables` with the same document, variables, environment, and
     fakes. Assert equal exit codes and byte-for-byte output after replacing each
     independently generated `extensions.requestId` value with one fixed sentinel;
     also assert both original request IDs are nonempty.
   - config failures: point `APPLE_GATEWAY_CONFIG` at the same missing explicit path
     for SDK and CLI, then assert matching `CONFIG_INVALID` code, exit code, and
     request-ID-normalized bytes.
   - config-sensitive default Notes services: with no injected Notes service, pass
     `APPLE_GATEWAY_LIMITS_DEFAULT_PAGE_SIZE=1` and
     `APPLE_GATEWAY_LIMITS_MAX_PAGE_SIZE=1`, then execute a `notes(input: { first: 2 })`
     document through SDK and CLI. Both must return the same limit error and
     request-ID-normalized bytes. This proves the SDK constructs Notes services from
     the current call's resolved environment rather than SDK initialization state.
3. `CommandSDKSubcommandTests.swift`
   - `schema search` returns JSON matches (name filter, `--kinds`, `--limit`,
     `--role reader` excludes mutations), invalid kind/regex -> usage errors.
   - `graphql operation calendars` with fakes prints the same envelope as the
     equivalent `graphql --query`; `--select` narrows the selection; unknown operation
     -> invalidArgument envelope.
   - existing `CommandTests` (usage, graphql, schema print) unchanged and green.

Smoke tests: unchanged; `swift run AppleGatewaySmokeTests` must stay green.

## 6. README

New "Client SDK (AppleGatewaySDK)" section: dependency snippet, Swift example
(catalog -> `searchSchema` -> `invoke` with variables; raw `execute`), tier semantics,
and docs for `schema search` / `graphql operation` with example output. Existing
sections untouched.

## 7. Edge cases

- Empty variables map: builder declares nothing; runtime applies its own defaults.
- Nullable variable omitted: never declared (kit contract), so no explicit-null issue.
- Enum default values export as strings; documents never inject catalog defaults.
- Builder/`--select` errors: envelope (SDK: kit `failure` exit 2; CLI: invalidArgument
  envelope) — never a crash, never a thrown error out of `invoke`.
- Reader binary + `graphql operation <mutation>`: builder fails (operation absent from
  reader catalog) -> invalidArgument envelope; raw document path still blocked by the
  validator. Tier enforcement stays in the registry/validator.
- `--pretty` affects only local JSON printing, mirroring existing frame handling.
- Config resolution failure inside `execute` returns the CLI's config-error envelope
  rather than throwing.
- Response request IDs are intentionally generated per execution. Byte-compatibility
  tests compare the original JSON bytes after replacing only the two dynamic request-ID
  values with one sentinel; all other whitespace, key ordering, data, errors, and exit
  codes must match exactly.

## 8. File budget / lint

New files stay well under 1000 lines: exporter ~260, facade ~160, CLI extension ~280,
composition ~120, tests ~3 x 250. `Command.swift` shrinks slightly (composition moves
out). Baseline SwiftLint = 0 violations must be preserved; defaulted init parameters
are exempt from `function_parameter_count`.

## 9. Rollout / compatibility

Additive only: no existing public API, CLI output, tier rule, domain adapter,
permissions, packaging, or notarization change. riela migrates its passthrough and
schema add-ons to the facade later, against exactly these names. Path dependency is
flagged for a URL pin by the manifest comment. Commits land per deliverable on
`feat/gateway-sdk`; no push, no tags.

## 10. Verification

`arch -arm64 /bin/zsh -lc 'cd /Users/taco/gits/tacogips/apple-gateway-worktrees/gateway-sdk && swift build && swift test && swift run AppleGatewaySmokeTests && swiftlint'`
