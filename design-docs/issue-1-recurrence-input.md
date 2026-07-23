# Correct Recurrence Decoding, Validation, and EventKit Persistence

**Status**: Accepted for implementation
**Feature ID**: `issue-1-recurrence-input`
**Workflow Mode**: `issue-resolution`
**Issue**: https://github.com/tacogips/apple-gateway/issues/1

## Problem

Creating an event with recurrence data can fail or persist the wrong rule
depending on how the GraphQL input is supplied.

1. The variables path converts values returned by `JSONSerialization` through
   `GraphQLValue.fromJSONObject`. Foundation represents JSON booleans and
   numbers with `NSNumber`; Swift bridging can therefore match numeric `0` or
   `1` as `Bool` before the existing `Int` case. Recurrence integer fields such
   as `interval` and `daysOfWeek` then fail GraphQL coercion with
   `Expected scalar Int`.
2. Both variables and inline literals eventually reach
   `EventKitCalendarReminderMapper.makeRecurrenceRule`. It supplies empty
   arrays for every unused `EKRecurrenceRule` component. EventKit can normalize
   that initializer shape to a default daily, interval-one, unbounded rule
   instead of retaining the requested weekly rule, weekdays, and end date.
3. `makeDayOfWeek` silently maps values outside EventKit's `1...7` weekday
   domain to Sunday. Invalid input is therefore accepted with changed meaning.

The fix must make variables and inline literals produce the same
`RecurrenceRule`, preserve that rule when translated to EventKit, and reject
invalid weekdays explicitly.

## Scope

### In scope

- Classify true JSON booleans separately from numeric `NSNumber` values in
  `Sources/AppleGatewayCore/GraphQLRuntime/VariableResolver.swift`.
- Translate empty recurrence component collections to `nil` in
  `Sources/AppleGatewayCore/Domains/EventKitCalendarReminderMapper.swift`.
- Reject every `daysOfWeek` value outside `1...7` with
  `AppleGatewayError(code: .invalidArgument, ...)`.
- Add deterministic runtime and mapper regression tests without reading or
  writing a live EventKit store.

### Out of scope

- Public GraphQL schema changes or field renames.
- New validation ranges for `daysOfMonth`, `monthsOfYear`, `weeksOfYear`,
  `daysOfYear`, or `setPositions`.
- Recurring master-ID lookup and detached-occurrence behavior from issue #2.
- Notes, Clock, Notifications, Mail, release, version, commit, or push work.

## Design

### JSON scalar classification

`GraphQLValue.fromJSONObject` remains the only JSON-to-GraphQL conversion
boundary. It will identify a boolean `NSNumber` by Core Foundation type
identity (`CFGetTypeID(number) == CFBooleanGetTypeID()`) before any Swift
bridging cast to `Bool`. Only that identity is treated as a JSON boolean.

After the boolean identity check, the existing numeric semantics remain:

- integral JSON numbers become `.int`;
- non-integral JSON numbers become `.float`;
- integral `Double` values retain the existing conversion to `.int`;
- strings, arrays, objects, and null recurse or map exactly as today;
- unsupported non-JSON values still raise `GRAPHQL_VALIDATION_ERROR`.

This changes classification, not GraphQL coercion. An integer still cannot
coerce to `Boolean`, and a boolean still cannot coerce to `Int`. The runtime
therefore distinguishes `true`/`false` from `0`/`1` before validating the
declared variable type.

### Variables and inline-literal parity

Both input forms must converge on the existing
`GraphQLVariableResolver.resolveArguments` and
`GraphQLValue.createEventInputValue` behavior:

```text
JSON variables -> fromJSONObject -> coerceJSONVariables
                                           \
inline literal -> Parser -> Validator -------+-> resolveArguments
                                                    -> CreateEventInput
```

No input-form-specific recurrence logic will be added. A weekly rule with
`interval: 1`, `daysOfWeek: [3, 4]`, and an `endDate` must decode to the same
`RecurrenceRule` value through both paths.

### EventKit recurrence construction

`EventKitCalendarReminderMapper.makeRecurrenceRule` will preserve meaningful
collections and omit unused ones:

- a non-empty `daysOfWeek` list maps to `[EKRecurrenceDayOfWeek]`;
- a non-empty numeric component list maps to `[NSNumber]`;
- an empty component list is passed as `nil`, not `[]`, for
  `daysOfTheWeek`, `daysOfTheMonth`, `monthsOfTheYear`, `weeksOfTheYear`,
  `daysOfTheYear`, and `setPositions`;
- frequency, interval, and recurrence end continue to use the existing
  mappings.

The reverse mapper continues treating `nil` EventKit collections as empty
domain collections, so the public `RecurrenceRule` model and GraphQL schema do
not change.

### Weekday validation and errors

Before constructing `EKRecurrenceDayOfWeek`, the mapper validates every
weekday against EventKit's `1...7` raw-value domain. Any invalid value causes
`makeRecurrenceRule` to throw an `AppleGatewayError` with code
`INVALID_ARGUMENT`; no recurrence rule is returned and there is no Sunday
fallback. Existing checks for a positive interval, mutually exclusive
`endDate`/`occurrenceCount`, and positive occurrence count remain unchanged.

The error is raised before EventKit save. Existing runtime error propagation
surfaces it to a GraphQL mutation caller without changing the schema.

## Behavioral Contract

| Input or mapping case | Required result |
| --- | --- |
| JSON `true` or `false` | `.bool` and valid only for Boolean-compatible fields |
| JSON integer `0` or `1` | `.int`, never `.bool` |
| Variables weekly recurrence | Decodes as weekly, interval 1, weekdays `[3, 4]`, requested end date |
| Equivalent inline recurrence | Produces the identical domain recurrence |
| Empty unused recurrence components | Passed to EventKit as `nil` |
| Weekday below 1 or above 7 | Throws `INVALID_ARGUMENT`; no fallback |

## Test Design

### GraphQL runtime

Add focused coverage under
`Tests/AppleGatewayCoreTests/GraphQLRuntime/GraphQLRuntimeTests.swift`:

- parse JSON with `JSONSerialization`, pass values through
  `GraphQLValue.fromJSONObject`, and prove Boolean values stay `.bool` while
  integer `0` and `1` stay `.int`;
- coerce a variables-based `CreateEventInput` containing the target recurrence
  against the bootstrap schema;
- parse and validate the equivalent inline mutation;
- resolve and decode both arguments, then assert equal `CreateEventInput`
  recurrence rules, including the exact end date.

The test stops at the decoded input boundary and uses no live service.

### EventKit mapper

Extend
`Tests/AppleGatewayCoreTests/CalendarReminders/EventKitCalendarReminderMapperTests.swift`
with a weekly rule containing interval 1, weekdays `[3, 4]`, and an end date.
Assert:

- `EKRecurrenceRule.frequency == .weekly`;
- the interval, weekdays, and recurrence end match;
- all unused component properties are `nil`;
- reverse mapping reconstructs the original domain rule;
- at least the lower and upper invalid weekday boundaries (`0` and `8`) throw
  `AppleGatewayError` with `.invalidArgument`.

The mapper tests instantiate EventKit values without saving to a user store.

## Acceptance Criteria

- Variables-based recurrence integers no longer produce
  `Expected scalar Int`.
- JSON booleans retain Boolean behavior and JSON integers `0`/`1` retain
  integer behavior.
- Variables and inline literals decode the target recurrence identically.
- The EventKit rule remains weekly with weekdays `[3, 4]` and the supplied end
  date, with every unused component represented by `nil`.
- Invalid weekdays fail explicitly with `INVALID_ARGUMENT`.
- Targeted tests, the full Swift test suite, smoke tests, SwiftLint, and
  whitespace validation pass.
- Only the issue #1 runtime, mapper, test, design, and plan files change; no
  version bump, commit, or push occurs.

## Residual Risk

The deterministic tests can verify the initializer arguments and resulting
`EKRecurrenceRule` properties without touching user data. EventKit persistence
normalization after an actual save remains framework-owned behavior and should
be confirmed separately against an opt-in scratch calendar if needed; it is
not a blocker for this bounded unit-tested fix.

## Review Record

- 2026-07-23, design self-review: accepted. Scope, failure modes, public
  compatibility, error semantics, tests, and acceptance criteria match the
  feature contract.
- 2026-07-23, independent design review pass: accepted with no high- or
  mid-severity findings. The review confirmed that issue #2 is excluded, true
  booleans are identified by type identity rather than numeric value, and
  empty-versus-nil handling covers all six EventKit component collections.
