# Correct Recurrence Decoding, Validation, and EventKit Persistence

**Status**: Implementation complete with documented process-evidence gap
**Feature ID**: `issue-1-recurrence-input`
**Workflow Mode**: `issue-resolution`
**Issue**: https://github.com/tacogips/apple-gateway/issues/1
**Design Reference**: `design-docs/issue-1-recurrence-input.md`

## Purpose

Implement the accepted issue #1 design so JSON recurrence integers remain
integers, variables and inline literals decode identically, EventKit receives
`nil` for unused recurrence components, and invalid weekdays fail explicitly.
The work preserves the public GraphQL schema and remains unit-testable without
accessing a live calendar.

## Dependencies and Constraints

- The accepted design at
  `design-docs/issue-1-recurrence-input.md` is authoritative.
- Existing SwiftPM target boundaries remain unchanged.
- `GraphQLVariableResolver`, the bootstrap calendar schema, and
  `EventKitCalendarReminderMapper` provide the required implementation seams.
- Tests use Swift Testing with `@testable import AppleGatewayCore`.
- The package targets macOS 14 or newer and may use Foundation/Core Foundation
  boolean type identity and EventKit recurrence APIs.
- Do not change issue #2 lookup behavior, the public GraphQL schema, unrelated
  domains, `VERSION`, release artifacts, or package topology.
- Leave all changes uncommitted and unpushed.

## Deliverables

- [x] `Tests/AppleGatewayCoreTests/GraphQLRuntime/GraphQLRuntimeTests.swift`
      contains failing-first JSON scalar classification and variables/inline
      recurrence parity tests.
- [x] `Tests/AppleGatewayCoreTests/CalendarReminders/EventKitCalendarReminderMapperTests.swift`
      contains failing-first initializer-shape, round-trip, and invalid-weekday
      tests.
- [x] `Sources/AppleGatewayCore/GraphQLRuntime/VariableResolver.swift`
      distinguishes CFBoolean values from numeric `NSNumber` values without
      weakening scalar coercion.
- [x] `Sources/AppleGatewayCore/Domains/EventKitCalendarReminderMapper.swift`
      passes `nil` for empty recurrence components and rejects weekdays outside
      `1...7`.
- [x] Targeted tests, `task test`, SwiftLint, whitespace checks, and scope
      checks pass.

## Tasks

### TASK-001: Add failing-first GraphQL runtime regression tests

**Parallelizable**: No

Update
`Tests/AppleGatewayCoreTests/GraphQLRuntime/GraphQLRuntimeTests.swift`.

1. Add `jsonObjectConversionDistinguishesBooleansFromZeroAndOne`:
   - decode a JSON object containing `true`, `false`, `0`, and `1` with
     `JSONSerialization`;
   - convert its values with `GraphQLValue.fromJSONObject`;
   - assert booleans are `.bool` and both numbers are `.int`;
   - coerce the values against Boolean and Int variable definitions to prove
     the classifications remain valid at the resolver boundary.
2. Add `createEventRecurrenceVariablesMatchInlineLiteral`:
   - use a variables mutation with `$input: CreateEventInput!`;
   - construct variables from `JSONSerialization`, including `frequency:
     "WEEKLY"`, `interval: 1`, `daysOfWeek: [3, 4]`, and an ISO-8601
     `endDate`;
   - run `fromJSONObject`, bootstrap-schema validation,
     `coerceJSONVariables`, `resolveArguments`, and
     `createEventInputValue`;
   - parse and validate an equivalent inline mutation and decode it through
     `resolveArguments` and `createEventInputValue`;
   - assert the two recurrence arrays are equal and explicitly assert weekly
     frequency, interval 1, weekdays `[3, 4]`, and the parsed end date.
3. Run the two tests before implementation and record that they fail for the
   expected numeric-to-Boolean classification defect. Do not weaken assertions
   to accommodate the current behavior.

**Completion Criteria**:

- [x] Test data originates from `JSONSerialization`, not hand-built
      `GraphQLValue` values alone.
- [x] True booleans and numeric `0`/`1` have independent assertions.
- [x] Both GraphQL input paths exercise parser/validator/resolver boundaries
      and compare decoded domain recurrence values.
- [ ] The pre-fix failure is captured in the progress log.

### TASK-002: Add failing-first EventKit mapper regression tests

**Parallelizable**: Yes, after the test naming and shared fixture approach in
TASK-001 are settled

Update
`Tests/AppleGatewayCoreTests/CalendarReminders/EventKitCalendarReminderMapperTests.swift`.

1. Add `weeklyRecurrenceRuleMappingUsesNilForUnusedComponents` using a weekly,
   interval-one rule with weekdays `[3, 4]` and a fixed end date.
2. Assert the produced `EKRecurrenceRule` has:
   - frequency `.weekly`;
   - interval `1`;
   - weekday raw values `[3, 4]`;
   - the exact recurrence end date;
   - `nil` for `daysOfTheMonth`, `monthsOfTheYear`, `weeksOfTheYear`,
     `daysOfTheYear`, and `setPositions`;
   - no loss when mapped back to `RecurrenceRule`.
3. Add `recurrenceRuleMappingRejectsInvalidWeekdays`, covering at least `0`
   and `8`, and assert `AppleGatewayError.code == .invalidArgument`.
4. Run both tests before implementation and record their expected failures:
   unused collections are not `nil`, and invalid weekdays fall back to Sunday.

**Completion Criteria**:

- [x] Tests inspect `EKRecurrenceRule` properties without saving or fetching a
      real EventKit object.
- [x] All unused component collections are covered; `daysOfTheWeek` is
      non-empty for the target rule and is asserted separately.
- [x] Reverse mapping proves the domain rule remains unchanged.
- [x] Invalid lower and upper weekday boundaries fail explicitly.
- [ ] The pre-fix failures are captured in the progress log.

### TASK-003: Correct JSON boolean and number classification

**Parallelizable**: No, after TASK-001

Update
`Sources/AppleGatewayCore/GraphQLRuntime/VariableResolver.swift`.

1. Import Core Foundation if required by the chosen API.
2. In `GraphQLValue.fromJSONObject`, identify an `NSNumber` as Boolean only
   when its Core Foundation type ID equals `CFBooleanGetTypeID()`.
3. Perform that identity check before numeric Swift casts. Preserve the
   existing Int, Double, string, list, object, null, and unsupported-value
   behavior.
4. Keep scalar coercion strict; do not add Int-to-Boolean or Boolean-to-Int
   coercions.
5. Run the TASK-001 tests and relevant existing variable resolver tests.

**Completion Criteria**:

- [x] JSON `true` and `false` become `.bool`.
- [x] JSON numeric `0` and `1` become `.int`.
- [x] Non-integral numbers still become `.float`, and existing integral-Double
      behavior remains intact.
- [x] Unsupported values still return `GRAPHQL_VALIDATION_ERROR`.
- [x] Variables recurrence decoding passes without schema changes.

### TASK-004: Correct EventKit recurrence construction and validation

**Parallelizable**: No, after TASK-002

Update
`Sources/AppleGatewayCore/Domains/EventKitCalendarReminderMapper.swift`.

1. Validate every `daysOfWeek` value is within `1...7` before constructing
   `EKRecurrenceDayOfWeek`.
2. Throw `AppleGatewayError(code: .invalidArgument, ...)` for an invalid value;
   include the rejected value in a stable, non-sensitive message or details.
3. Remove the `.sunday` fallback and make weekday mapping preserve only valid
   raw values.
4. For each EventKit recurrence component, pass `nil` when the corresponding
   domain list is empty:
   - `daysOfTheWeek`;
   - `daysOfTheMonth`;
   - `monthsOfTheYear`;
   - `weeksOfTheYear`;
   - `daysOfTheYear`;
   - `setPositions`.
5. Preserve existing frequency, interval, end-date, occurrence-count, and
   reverse-mapping behavior.
6. Run the TASK-002 tests and the existing mapper tests.

**Completion Criteria**:

- [x] The target weekly rule retains frequency, interval, weekdays, and end
      date.
- [x] All six unused EventKit component arguments use `nil`.
- [x] Non-empty component arrays retain their existing value mappings.
- [x] Weekdays `0` and `8` throw `.invalidArgument`.
- [x] Existing interval and recurrence-end validations still pass.

### TASK-005: Full verification and scope closeout

**Parallelizable**: No, after TASK-003 and TASK-004

Run the following commands from the repository root:

```bash
swift test --filter jsonObjectConversionDistinguishesBooleansFromZeroAndOne
swift test --filter createEventRecurrenceVariablesMatchInlineLiteral
swift test --filter weeklyRecurrenceRuleMappingUsesNilForUnusedComponents
swift test --filter recurrenceRuleMappingRejectsInvalidWeekdays
task test
swiftlint
git diff --check
if rg -n '[[:blank:]]+$' design-docs/issue-1-recurrence-input.md impl-plans/issue-1-recurrence-input.md; then exit 1; fi
git status --short
git diff --stat
```

If the default shell exposes the known Nix SDK/Apple toolchain mismatch, run
SwiftLint or tests through the repository's `nix develop` shell with the Xcode
`DEVELOPER_DIR`, `SDKROOT`, `TOOLCHAINS`, and toolchain `PATH` prescribed by
`.codex/skills/swift-coding-agent/SKILL.md`; record the exact fallback command
used.

Review the final diff against the accepted design and issue #1 contract.
Confirm that no issue #2 adapter/service files, unrelated domain files,
version/release files, commits, or pushes are present.

**Completion Criteria**:

- [x] All four targeted tests pass.
- [x] `task test` passes, including `swift test` and
      `swift run AppleGatewaySmokeTests`.
- [x] `swiftlint`, `git diff --check`, and the explicit untracked-document
      whitespace check pass.
- [x] `git status --short` and `git diff --stat` show only intended issue #1
      source, test, design, and plan files.
- [x] The progress log records exact commands, outcomes, changed files, and
      any residual live EventKit risk.
- [x] Changes remain uncommitted and unpushed.

## Completion Gate

Implementation is complete only when:

- every deliverable and task completion criterion is checked;
- variables and inline literals yield equal decoded recurrence values;
- invalid weekdays return `INVALID_ARGUMENT`;
- the EventKit initializer shape uses `nil` for every unused component;
- targeted and full verification are green; and
- the final scope audit contains no unrelated changes.

An opt-in scratch-calendar save may provide extra integration confidence but
is not required for this bounded deterministic fix and must not be performed
implicitly.

## Progress Log

- 2026-07-23: Plan created from the accepted
  `design-docs/issue-1-recurrence-input.md`. Implementation has not started;
  all deliverables and task criteria remain open.
- 2026-07-23: Plan self-review accepted. Design-plan traceability,
  deliverables, dependencies, completion criteria, progress tracking,
  failing-first order, verification commands, and scope boundaries are
  explicit. No design defects were found.
- 2026-07-23: Independent plan review found one mid-severity plan-only defect:
  `git diff --check` does not inspect the new untracked design and plan files,
  so the whitespace gate did not cover every deliverable. Added an explicit
  `rg`-based trailing-whitespace failure check for both feature-local
  documentation paths.
- 2026-07-23: Independent plan re-review accepted after the plan-only
  correction. No high- or mid-severity findings remain. The review confirmed
  coverage for true booleans versus numeric `0`/`1`, variables/inline parity,
  all six nil-able EventKit collections, both invalid weekday boundaries,
  full-suite verification, and uncommitted scope closeout.
- 2026-07-23: Implemented CFBoolean identity detection in
  `Sources/AppleGatewayCore/GraphQLRuntime/VariableResolver.swift`; numeric
  JSON `0` and `1` now remain integers while JSON booleans remain booleans.
- 2026-07-23: Updated
  `Sources/AppleGatewayCore/Domains/EventKitCalendarReminderMapper.swift` to
  pass `nil` for empty recurrence components and reject weekdays outside
  `1...7` before calling EventKit. The invalid-weekday regression test exposed
  and eliminated an interim EventKit `NSInvalidArgumentException`.
- 2026-07-23: Added JSONSerialization scalar classification, complete
  variables/inline parser-validator-resolver-runtime parity, EventKit
  initializer-shape, round-trip, and invalid-weekday tests in the two declared
  issue #1 test files.
- 2026-07-23: Verification passed under the Xcode toolchain environment
  prescribed by `.codex/skills/swift-coding-agent/SKILL.md`:
  `swift test --filter jsonObjectConversionDistinguishesBooleansFromZeroAndOne`,
  `swift test --filter createEventRecurrenceVariablesMatchInlineLiteral`,
  `swift test --filter weeklyRecurrenceRuleMappingUsesNilForUnusedComponents`,
  `swift test --filter recurrenceRuleMappingRejectsInvalidWeekdays`,
  `swift test` (197 tests), and `task test` (197 tests plus
  `AppleGatewaySmokeTests: passed`). The unqualified first focused test command
  failed before compilation because the active Nix SDK 11.3 did not match the
  Xcode Swift 6.3.3 compiler; the prescribed Xcode SDK override resolved it.
- 2026-07-23: Final `swiftlint` passed with zero violations,
  `git diff --check` passed, the explicit four-document trailing-whitespace
  check passed, and the scope audit found no changes to `VERSION` or the
  Notes, Clock, Notifications, or Mail domains. Baseline and final HEAD are
  both `1f0c97cc3d4461ee71810cceedbd5c96a66806bd`; changes remain uncommitted.
- 2026-07-23: Self-review corrected overstated failing-first evidence. The
  regression tests and source fixes were introduced in the same implementation
  pass, so no pre-fix test output was captured. The two unsupported
  process-evidence criteria above are reopened; all post-fix behavioral and
  verification criteria remain complete.
