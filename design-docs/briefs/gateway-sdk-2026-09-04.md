# Brief: `AppleGatewaySDK` facade on `GatewaySDKKit` (2026-09-04)

Master design: `/Users/taco/gits/tacogips/riela/docs/briefs/gateway-sdk-2026-09-04.md`
(sections 2 and 3.3 are normative). The shared kit is implemented at
`/Users/taco/gits/tacogips/gateway-sdk-kit` (read its `README.md` and
`design-docs/briefs/gateway-sdk-kit-2026-09-04.md` for the exact API). Treat this whole
brief as exactly ONE feature.

## Goal

Give apple-gateway a public client SDK so that a caller (riela's add-on engine, or any
Swift host) can run an operation by name with variables and an optional selection, run
raw GraphQL with variables, print the schema, and regex-search it, without building
GraphQL text by string interpolation and without going through argv.

## Verified seams (2026-09-04, HEAD 3a2320e, v0.1.6)

- `Sources/AppleGatewayCore/CLI/Command.swift:8` `public struct AppleGatewayCommand`;
  init `:30` (`arguments`, `environment`, `role: AppleGatewayRole = .full`, injectable
  service / permission / file-materializer seams); `:73 run() -> String`,
  `:77 runResult() -> AppleGatewayCommandResult { output, exitCode }` (:705).
  `graphql` flags `--query --query-file --variables --variables-file --pretty`
  (`:348-356`, loader `:399`); `schema print [--role full|reader]` (`:113`, `:656-661`).
- `Sources/AppleGatewayCore/GraphQLRuntime/GraphQLRuntime.swift:3` `enum GraphQLRuntime`
  is **internal**: `execute` (:4), `executeResponse` (:42; lex → parse → bootstrap →
  validate → execute :62-79), `schema(role:) -> String` (:105) →
  `SDLPrinter.swift:6 GraphQLSDLPrinter.printSchema()`.
- `GraphQLRuntime/SchemaRegistry.swift`: `GraphQLNamedTypeKind` (scalar / object([GraphQLFieldDefinition]) /
  enumType([String]) / inputObject([GraphQLInputFieldDefinition])), `GraphQLFieldDefinition
  { name, type: GraphQLTypeReference, arguments, resolver }`, `GraphQLArgumentDefinition
  { name, type, defaultValue }`, `GraphQLSchemaModule { types, queryFields, mutationFields }`,
  `GraphQLSchemaRegistry` (:62; `bootstrap(role:)` :87 assembles `[.permissions,
  .calendarReminders, .notes, .mail, .notifications, .clockAlarms, .phoneCalls]`;
  reader role drops mutations at :81), `GraphQLExecutionContext` (:47: config, role,
  permissions provider, the six services, notifications, clock alarms, phone calls).
- Variables already work: `GraphQLRuntime/VariableResolver.swift` (`resolveArguments`
  :7, `coerceJSONVariables` :34, required check :45).
- Root fields per module: `CalendarRemindersSchemaModule.swift:234/:298`,
  `NotesSchemaModule.swift:92/:136`, `MailSchemaModule.swift:102/:146`,
  `NotificationsSchemaModule.swift:72/:90`, `ClockAlarmsSchemaModule.swift:51/:64`,
  `PhoneCallsSchemaModule.swift:72/:115`, permissions `SchemaRegistry.swift:127`.
- No introspection, no `.graphql` resource; `Package.swift` has zero dependencies;
  products: library `AppleGatewayCore`, executables `apple-gateway` (role .full),
  `apple-gateway-reader` (role .reader), `AppleGatewayNotifier`, `AppleGatewaySmokeTests`.
- Tests: swift-testing under `Tests/AppleGatewayCoreTests/` (one
  `*GraphQLRuntimeTests.swift` per domain, `CommandTests.swift`) plus the smoke executable;
  `mise run test` = `swift test` + `swift run AppleGatewaySmokeTests`.
- riela calls `AppleGatewayCommand(arguments:environment:role:...)` from
  `/Users/taco/gits/tacogips/riela/Sources/RielaCLI/ProductionNodeAdapter+AppleGatewaySupport.swift:82-102`
  and builds queries by interpolation; `riela/apple-gateway-graphql` passes documents
  through and `riela/apple-gateway-schema` prints SDL. riela will move the passthrough and
  schema add-ons onto the facade; keep `AppleGatewayCommand` and the CLI behaviour
  unchanged.

## Deliverables

1. **Dependency.** `Package.swift`: `.package(url: "https://github.com/tacogips/gateway-sdk-kit.git", exact: "0.1.0")` (this
   worktree is `/Users/taco/gits/tacogips/apple-gateway-worktrees/gateway-sdk`) and
   product `GatewaySDKKit` on `AppleGatewayCore`. One-line comment that the operator
   switches it to a URL pin later.
2. **Catalog export** (`Sources/AppleGatewayCore/SDK/AppleSchemaCatalogExporter.swift`):
   `GatewaySchemaCatalog.apple(role: AppleGatewayRole) -> GatewaySchemaCatalog` built from
   `GraphQLSchemaRegistry.bootstrap(role:)`: `GraphQLTypeReference` → `GatewayTypeRef`
   1:1, `GraphQLNamedTypeKind` → `GatewayNamedType.Kind` 1:1 (object fields with their
   arguments and default values), root fields → `GatewayOperation` (kind query/mutation,
   `tier` = `full` or `reader`, `domain` = the module that contributed the field:
   `permissions`, `calendarReminders`, `notes`, `mail`, `notifications`, `clockAlarms`,
   `phoneCalls`; `isDestructive` = name starts with `delete`/`dismiss`; `summary` from a
   new optional `description` on `GraphQLFieldDefinition` where cheap, else the field
   name). Parity test: root fields and named types of `GraphQLRuntime.schema(role:)` ==
   those of `catalog.sdl()` for both roles; `catalog.validate()` empty for both roles.
3. **Facade** (`Sources/AppleGatewayCore/SDK/AppleGatewaySDK.swift`):
   ```swift
   public struct AppleGatewaySDK: GatewaySDK {
     public let provider = "apple-gateway"
     public let tier: String                  // "full" | "reader"
     public let catalog: GatewaySchemaCatalog
     public init(role: AppleGatewayRole = .full, /* the same injectable seams AppleGatewayCommand takes, all defaulted */)
     public func execute(document:variables:environment:) async -> GatewayEnvelope
   }
   ```
   `execute` composes the same `GraphQLExecutionContext` `AppleGatewayCommand` builds for
   the `graphql` subcommand (extract that composition into an internal shared helper so
   the two cannot drift), converts `GatewayJSONValue` variables to the runtime's JSON
   variables, calls `GraphQLRuntime.executeResponse`, and maps the response to
   `GatewayEnvelope` (`data`, `errors`, `exitCode` consistent with the CLI, `rawOutput` =
   the JSON the CLI would print). `GraphQLRuntime` stays internal.
4. **CLI.** `schema search <regex> [--role full|reader] [--kinds ...]
   [--include-referenced-types] [--limit N]` (JSON matches) and `graphql operation <name>
   [--variables|--variables-file] [--select a.b,c]`; `schema print` and `graphql`
   unchanged; usage text and `README.md` updated with an SDK section (Swift example:
   catalog → search → invoke; raw execute).
5. **Tests**: exporter parity and validate() for both roles; facade `invoke` for
   `calendars`, `events` (with variables), `createReminder` (mutation with input object)
   and one `notes` query through the existing injectable fake services, asserting the
   built document declares variables and the fake service received the expected
   arguments; reader-role SDK invoking a mutation returns a validation-error envelope;
   `execute` passthrough equals `graphql --query` CLI output for the same document and
   variables; `schema search` CLI; smoke tests still green.

## Verification

`arch -arm64 /bin/zsh -lc 'cd /Users/taco/gits/tacogips/apple-gateway-worktrees/gateway-sdk && swift build && swift test && swift run AppleGatewaySmokeTests && swiftlint'`
green. Commit on `feat/gateway-sdk` in this worktree as work lands; do not push.

## Non-goals

No changes to domain adapters, permissions handling, TCC identity, packaging, or
notarization. Do not touch `/Users/taco/gits/tacogips/apple-gateway` (the main checkout).
