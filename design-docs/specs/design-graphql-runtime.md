# GraphQL Runtime Design

## Status

Draft

## Purpose

Define the zero-dependency GraphQL execution engine inside
`AppleGatewayCore`. The base project (mail-gateway) executes GraphQL via
substring scanning; its 2026-07 implementation review flagged that approach
as its most critical weakness (write-blocking by string scan, variables
parsed then discarded, arguments extracted ad hoc). apple-gateway keeps the
zero-dependency policy but replaces scanning with a small, real parser.

## Decision

Hand-rolled lexer + recursive-descent parser + code-defined schema registry
+ tree-walking executor. No Graphiti/GraphQLSwift (they pull in
swift-nio and violate the zero-dependency policy inherited from the base
project).

## Supported Language Subset

Executable documents only, deliberately narrowed:

- One operation per document (`query`, `mutation`, optional operation name).
- Named fields with arguments and nested selection sets.
- Field aliases.
- Variables: declarations with types and default values; `$var` references
  in argument positions. Values arrive via `--variables` /
  `--variables-file` as a JSON object.
- Literal values: Int, Float, String (with escapes), Boolean, null, enum,
  list, input object.
- `#` comments.

Rejected with `GRAPHQL_VALIDATION_ERROR` (explicitly, not silently):
fragments and fragment spreads, directives, subscriptions, multiple
operations per document. This matches the base project's rejection of
fragments/multi-root but enforces it on the AST instead of by scanning.

## Components

```
GraphQLRuntime/
  Lexer.swift          tokens: name, int, float, string, punctuator
  Parser.swift         document -> Operation AST (throws with line/column)
  AST.swift            Operation, Field, Argument, Value, TypeRef
  SchemaRegistry.swift code-defined types, fields, args, enums, inputs
  Validator.swift      unknown field/arg/type, required args, value coercion
  VariableResolver.swift  substitute + coerce variables into argument values
  Executor.swift       resolve root field -> domain service -> project result
  SDLPrinter.swift     render the registry as SDL for `schema print`
  Projection.swift     shape [String: Any] results by the selection set
```

### Schema Registry

The schema is defined in Swift code, one `SchemaModule` per domain:

```swift
struct SchemaModule {
  let types: [GQLType]
  let queryFields: [GQLFieldDefinition]
  let mutationFields: [GQLFieldDefinition]
}

let schema = SchemaRegistry(modules: [
  permissionsModule, calendarModule, remindersModule,
  clockAlarmsModule, notesModule, mailModule, notificationsModule
], role: role) // role .reader drops all mutationFields and the Mutation type
```

Each `GQLFieldDefinition` carries its argument definitions, result type
reference, and a resolver closure
`(ResolvedArguments, ExecutionContext) throws -> GQLValue`.
`ExecutionContext` holds the config, the domain adapter set, and the file
store. Because the registry is data, the SDL printer and the validator
share one source of truth: `schema print` output can never drift from
execution behavior.

### Execution Flow

```
query string + variables JSON
  -> Lexer -> Parser -> Operation AST
  -> Validator (against role-specific registry)
  -> VariableResolver (coerce into ResolvedArguments)
  -> Executor: for each root field, invoke resolver
  -> Projection: prune resolver output to the requested selection set
  -> envelope { "data": ... } or { "data": null, "errors": [...] }
```

Multiple root fields in one operation are allowed and resolved
sequentially in document order (unlike the base project's single-root
restriction; the AST makes this free). Errors follow GraphQL spec shape:
a failing root field yields `null` for that field plus an `errors` entry;
the process exit code is the highest-severity mapped exit code.

### Reader Enforcement

`apple-gateway-reader` constructs the registry with `role: .reader`. The
Mutation type does not exist in that registry, so `mutation { ... }`
documents fail validation with `WRITE_DISABLED_IN_READER` before any
resolver runs. There is no string matching anywhere in enforcement.

## CLI Contract

```bash
apple-gateway graphql --query <string> | --query-file <path>
                      [--variables <json> | --variables-file <path>]
                      [--pretty]
apple-gateway schema print [--role full|reader]
```

- Exactly one of `--query` / `--query-file`.
- At most one of `--variables` / `--variables-file`; must decode to a JSON
  object.
- Output: JSON envelope on stdout; `--pretty` adds sorted-key formatting.

## Testing

- Lexer/parser golden tests including error positions.
- Validator tests: unknown fields, missing required args, enum coercion,
  nested input objects, list coercion, variable type mismatches.
- Reader-role tests: every mutation field rejected; commented-out mutation
  text inside string literals or `#` comments does not trigger rejection
  (regression tests ported conceptually from mail-gateway's adversarial
  scanner tests).
- Projection tests: only requested fields returned, aliases honored.
- SDL printer snapshot test pinned to the checked-in schema document.
