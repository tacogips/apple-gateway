# Issue 2: Unified Recurring Master-ID Lookup

**Status**: Implementation complete with documented process-evidence gap
**Issue**: https://github.com/tacogips/apple-gateway/issues/2
**Feature ID**: `issue-2-recurring-master-lookup`
**Workflow Mode**: `issue-resolution`
**Design Reference**: `design-docs/issue-2-recurring-master-lookup.md`
**Last Reviewed**: 2026-07-23

## Purpose

Make recurring-event queries and mutations resolve a caller-supplied master ID
through the same master-first, calendar-scoped occurrence lookup. Detached
occurrences must remain addressable without allowing a dated `THIS_EVENT` or
`FUTURE_EVENTS` mutation to fall back to the series master.

## Scope and Constraints

- Preserve the public GraphQL schema and error codes.
- Preserve `EventKitCalendarReminderMapper.ekSpan` behavior.
- Do not change recurrence input decoding or recurrence-rule mapping in this
  feature branch; those belong to issue #1.
- Do not modify Notes, Clock, Notifications, Mail, release, or version files.
- Do not commit or push.

## Deliverables

- [x] One shared master-first EventKit event resolver used by public reads and
      adapter writes.
- [x] A production-linked pure occurrence target selector covering series
      identity, calendar identity, exact occurrence date, and dated-miss
      behavior.
- [x] Typed local/external identity matching with local preference and
      fail-closed ambiguity handling.
- [x] Calendar-scoped occurrence enumeration using resolved local and external
      master identities.
- [x] Month-sized outward fallback searches for detached occurrences moved
      outside the narrow two-day predicate, bounded by 49 windows and 10,000
      cumulative candidates.
- [x] Direct external-series duplicate detection so a unique narrow external
      match does not trigger fallback enumeration.
- [x] Safe dated-miss behavior that returns `EVENT_NOT_FOUND` rather than
      selecting the master as a write target.
- [x] Service preflight and request forwarding aligned with the adapter lookup.
- [x] Deterministic unit coverage for detached identifiers and span forwarding.
- [x] An environment-gated scratch-calendar integration test that is skipped
      unless explicitly enabled and verifies retained/removed occurrence
      boundaries, unrelated-event isolation, and cleanup success.
- [x] Narrow and full Swift test suites passing.

## Dependencies and Task Order

`TASK-001` mechanically extracts the current production condition into a
testable seam and establishes failing regression tests without fixing its
behavior. `TASK-002` implements the identity matcher and resolver. `TASK-003`
aligns service behavior and completes service tests. `TASK-004` verifies the
bounded change. Tasks are intentionally sequential because each later task
depends on evidence or behavior from the previous task.

## Tasks

### TASK-001: Add failing detached-series regression tests

**Parallelizable**: No

**Files**:

- `Tests/AppleGatewayCoreTests/CalendarReminders/CalendarWriteServiceTests.swift`
- `Sources/AppleGatewayCore/Domains/CalendarKitAdapter/LiveEventKitCalendarReminderAdapter.swift`
  for a mechanical, behavior-preserving selector extraction.
- A focused selector test file under
  `Tests/AppleGatewayCoreTests/CalendarReminders/` for the extracted pure
  occurrence target selector.

**Changes**:

1. Mechanically extract the current dated-occurrence selection behavior into an
   internal pure selector called by the production adapter's public occurrence
   path. It accepts resolved master identities, resolved calendar ID, requested
   occurrence date, and bounded candidates represented by identifiers,
   calendar ID, and occurrence date. It returns a selected candidate or no
   dated target. Preserve the current raw-ID/global-calendar behavior in this
   extraction so detached-identity and wrong-calendar tests fail before the
   fix; the existing public dated-miss `nil` behavior remains unchanged.
2. Confirm existing tests remain green after the behavior-preserving
   extraction.
3. Add these exact production-selector regression tests:
   - `detachedMasterIdMatchesResolvedSeriesIdentity`;
   - `detachedMasterIdRejectsDifferentCalendar`;
   - `detachedMasterIdRejectsDifferentSeries`;
   - `detachedMasterIdRejectsNonExactOccurrenceDate`; and
   - `detachedMasterIdDatedMissDoesNotUseMaster`.
4. Run the five named tests and record their pre-fix failures against the
   selector used by the production adapter.
5. Extend `WriteCalendarProvider` so it can record requested `(eventId,
   occurrenceDate)` values and model a master ID resolving to a detached
   occurrence with a different returned ID.
6. Add `detachedMasterIdUpdateAndDeletePreserveSpan` using the original master
   ID and an exact
   occurrence date.
7. Cover both `.thisEvent` and `.futureEvents`.
8. Assert that preflight succeeds, the original master ID is forwarded, and
   occurrence date/span are unchanged.
9. Add a service dated-miss case proving the writer is not called.

**Completion Criteria**:

- [ ] The detached-identity selector test fails against the behavior-preserving
      raw-ID extraction before the source fix, and the failure output is
      recorded; safety cases pass or fail according to the extracted behavior
      and remain mandatory regression coverage.
- [x] The selector tests exercise code called by the production adapter rather
      than a fake-only implementation.
- [x] Tests require matching when local identifiers differ and only the
      documented recurring-series `calendarItemExternalIdentifier` intersects.
- [x] Tests deterministically reject a different calendar, a different series,
      and a non-exact occurrence date.
- [x] Tests distinguish successful exact occurrence resolution from unsafe
      master fallback.
- [x] No live EventKit calendar is required.

### TASK-002: Implement shared master-first adapter resolution

**Parallelizable**: No

**Files**:

- `Sources/AppleGatewayCore/Domains/CalendarKitAdapter/LiveEventKitCalendarReminderAdapter.swift`

**Changes**:

1. Replace the split public/private occurrence paths with one internal resolver.
2. Resolve `store.event(withIdentifier: eventId)` before occurrence
   enumeration.
3. Build the accepted non-empty identity set from the input ID plus the
   resolved event's `eventIdentifier`, `calendarItemIdentifier`, and
   `calendarItemExternalIdentifier`.
   Keep these as separate identifier categories.
4. Build the narrow occurrence predicate with `[resolved.calendar]`.
5. Route target selection through the production-linked pure selector.
   Select only an occurrence from the resolved calendar, with the exact
   requested `occurrenceDate`, and a same-category identifier intersecting the
   resolved identity set. Prefer a unique local match and fail closed on
   ambiguity.
6. Use `calendarItems(withExternalIdentifier:)` to confirm whether an external
   identity maps to one or multiple event series in the resolved calendar.
7. Return a unique narrow external match immediately when the direct series
   lookup is unique.
8. If the narrow search misses, search outward in calendar-month chunks, up to
   two years in each direction, with explicit window and cumulative-candidate
   limits.
9. Return the resolved event directly only for an undated lookup.
10. Return `nil` for a dated miss or ambiguous target; mutation callers translate this to the
   existing `EVENT_NOT_FOUND`.
11. Return an explicit internal error before writing when a search resource
    limit is exceeded.
12. Keep access checks, locking, mapper calls, and save/remove `EKSpan` mapping
   unchanged.

**Completion Criteria**:

- [x] `event(eventId:occurrenceDate:)`, `updateEvent`, and `deleteEvent` use the
      same resolver.
- [x] Occurrence predicates are scoped to the resolved event's calendar.
- [x] Matching accepts resolved local EventKit identifiers and the documented
      recurring-series external identifier rather than only the raw caller ID.
- [x] Identifier categories are not cross-compared, unique local matches take
      precedence, and ambiguous external fallback fails closed.
- [x] Unique narrow external matches return without multi-year enumeration.
- [x] Detached events moved beyond the narrow two-day window are searched in
      bounded month-sized fallback windows.
- [x] Window and cumulative-candidate limits fail before any destructive write.
- [x] A supplied occurrence date can never yield the master as a substitute
      mutation target.
- [x] The adapter file remains below the repository's 1000-line limit.

### TASK-003: Align service preflight and forwarding

**Parallelizable**: No

**Files**:

- `Sources/AppleGatewayCore/Domains/CalendarRemindersWriteService.swift`, only
  if production behavior requires an alignment change.
- `Tests/AppleGatewayCoreTests/CalendarReminders/CalendarWriteServiceTests.swift`

**Changes**:

1. Confirm `CalendarWriteService.existingEvent` passes the original master ID
   and occurrence date together to `CalendarProviding`.
2. Retain the resolved occurrence's calendar for writability checks.
3. Forward the original master ID, exact occurrence date, and caller-selected
   span without rewriting them.
4. Change service production code only if the tests expose divergent
   preflight/write addressing; do not add a second independent lookup.

**Completion Criteria**:

- [x] Detached-series update and delete preflight succeeds for writable
      calendars.
- [x] Read-only-calendar enforcement remains before writer invocation.
- [x] `.thisEvent` and `.futureEvents` request fields are preserved exactly.
- [x] Dated not-found behavior prevents writer invocation.

### TASK-004: Verify and review the bounded implementation

**Parallelizable**: No

**Commands**:

```bash
swift test --filter detachedMasterId
swift test
swiftlint
git diff --check
git rev-parse HEAD
git status --short
git diff --stat
```

Record `git rev-parse HEAD` before `TASK-001` and again after verification;
the two values must be identical. Confirm the filtered test output reports all
fourteen `detachedMasterId...` tests and a nonzero executed count.
If `swiftlint` is unavailable, record that fact and rely on the repository's
available lint task rather than installing new tooling.

Compile the opt-in live check without enabling it:

```bash
swift test --filter liveEventKitRecurringMasterScratchCalendarRoundTrip
```

Only with explicit permission to mutate an isolated scratch calendar, run:

```bash
APPLE_GATEWAY_RUN_LIVE_EVENTKIT_TESTS=1 \
  swift test --filter liveEventKitRecurringMasterScratchCalendarRoundTrip
```

**Completion Criteria**:

- [x] Narrow regression tests pass.
- [x] Filtered output proves all fourteen named regression tests executed.
- [x] Full `swift test` passes.
- [x] SwiftLint passes when available.
- [x] Diff checks show only issue #2 source, tests, and its two documentation
      files.
- [x] `VERSION` and unrelated domains are unchanged.
- [x] Baseline and final `git rev-parse HEAD` values match, proving no commit
      was created.

## Verification Matrix

| Requirement | Evidence |
| --- | --- |
| Master resolved before enumeration | Adapter resolver unit/source review |
| Enumeration scoped to master calendar | Production target-selector wrong-calendar test plus predicate source review |
| Resolved identifiers match detached occurrence | External-identifier-only production selector test plus service fake tests |
| Ambiguous target cannot be deleted | Typed selector ambiguity and cross-category tests |
| Unique narrow external match avoids broad search | Production resolver query-sequence test |
| Moved detached occurrence remains discoverable | Production resolver bounded-fallback test |
| Dense lookup work is capped | Production resolver candidate-limit test |
| Exact occurrence date required | Production selector non-exact-date test |
| Query/write lookup consistency | Shared resolver call-site tests/source review |
| `THIS_EVENT` safe targeting | Exact occurrence and dated-miss tests |
| `FUTURE_EVENTS` safe targeting | Exact occurrence/span forwarding tests |
| No unrelated regression | Full `swift test` and scope diff |

## Progress Log

- 2026-07-23: Plan created from the accepted feature-local design.
- 2026-07-23: Self-review completed; task dependencies, bounded files,
  completion criteria, progress tracking, and verification commands confirmed.
- 2026-07-23: Independent review found two mid-severity plan-only gaps:
  production adapter coverage and mandatory calendar/date rejection tests.
  Plan revised to require a production-linked selector, named failing-first
  cases, nonzero narrow-test evidence, and baseline/final HEAD comparison.
- 2026-07-23: Added the production-linked
  `EventOccurrenceTargetSelector` and a shared master-first resolver in
  `Sources/AppleGatewayCore/Domains/CalendarKitAdapter/LiveEventKitCalendarReminderAdapter.swift`.
  Public reads and writes now resolve the EventKit event first, enumerate only
  its calendar, match the input and resolved EventKit identities, require the
  exact occurrence date, and return no target for a dated miss.
- 2026-07-23: Added five selector tests in
  `Tests/AppleGatewayCoreTests/CalendarReminders/EventOccurrenceTargetSelectorTests.swift`
  plus the service-level
  `detachedMasterIdUpdateAndDeletePreserveSpan` test in
  `Tests/AppleGatewayCoreTests/CalendarReminders/CalendarWriteServiceTests.swift`.
  The service test covers update, `THIS_EVENT`, `FUTURE_EVENTS`, original-ID
  forwarding, exact occurrence-date forwarding, and writer suppression on a
  dated miss. The initial implementation did not require a service change;
  self-review later added explicit master-ID forwarding as recorded below.
- 2026-07-23: `swift test --filter detachedMasterId` executed all six named
  tests and passed. `swift test` passed 197 tests and `task test` passed the
  same suite plus `AppleGatewaySmokeTests`.
- 2026-07-23: Final `swiftlint` passed with zero violations,
  `git diff --check` and explicit documentation whitespace checks passed, and
  the adapter remains 385 lines. The final HEAD
  `1f0c97cc3d4461ee71810cceedbd5c96a66806bd` matches the recorded baseline;
  no commit or push occurred and no unrelated domain or `VERSION` file changed.
- 2026-07-23: Self-review found that update preflight resolved a detached
  payload ID and `CalendarEventSaveRequest` did not separately preserve the
  caller's master ID. Added explicit `eventId` addressing to the save request,
  passed `UpdateEventInput.eventId` from the service, used it in the live
  adapter resolver, and retained the detached event ID only in the update
  payload.
- 2026-07-23: Self-review also corrected overstated failing-first evidence.
  The production selector seam and its fixed behavior were introduced in the
  same implementation pass, so no behavior-preserving pre-fix selector output
  was captured. The unsupported process-evidence criterion above is reopened;
  post-fix selector and service behavior remain covered.
- 2026-07-23: Post-revision verification used
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer;
  export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk;
  export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault;
  export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH`.
  `swift test --skip-build --filter detachedMasterId` passed all six named
  tests, and `swiftlint` passed with zero violations. `task test` emitted a
  complete pass for 197 tests plus `AppleGatewaySmokeTests: passed`; the
  command wrapper reached its 60-second limit only after those successful
  results were emitted.
- 2026-07-23: Step 7 review found that the identity set omitted
  `calendarItemExternalIdentifier`, the EventKit identifier documented as
  shared by every occurrence of a recurring event. Added that identifier to
  both resolved and candidate identity sets through the shared production
  helper. Strengthened `detachedMasterIdMatchesResolvedSeriesIdentity` so the
  master and occurrence local identifiers differ and only the external
  identifier intersects. Updated the accepted design and this plan to record
  the corrected identity contract.
- 2026-07-23: Post-Step-7 verification used the explicit Xcode environment
  above. `swift test --filter detachedMasterId` rebuilt the affected targets
  and passed all six named tests. `task test` reported all 197 Swift tests and
  `AppleGatewaySmokeTests: passed`; the command wrapper timed out only after
  both successful results were emitted. `swiftlint` passed with zero
  violations. `git diff --check`, the explicit four-document whitespace
  check, baseline/final HEAD equality, the `VERSION` check, and the unrelated
  Notes/Clock/Notifications/Mail scope check all passed. The final worktree
  contains only the intended source, test, design, and plan paths and remains
  uncommitted.
- 2026-07-23: Adversarial Step 7 review found two mid-severity production
  targeting gaps: untyped first-match selection could choose an ambiguous
  external-identifier candidate, and the two-day predicate could omit a
  detached occurrence moved farther from its original date. Replaced the
  flattened identity set with typed event, calendar-item, and external
  identity sets; unique local matches take precedence, and ambiguous fallback
  fails closed. Added a calendar-scoped four-year fallback window for external
  matches and narrow misses.
- 2026-07-23: Added four adversarial `detachedMasterId...` regressions for
  local preference, external ambiguity, identifier-category isolation, and
  expanded moved-occurrence coverage. Added
  `Tests/AppleGatewayCoreTests/CalendarReminders/LiveEventKitRecurringMasterIntegrationTests.swift`,
  which compiles in normal verification but touches a uniquely named scratch
  calendar only when `APPLE_GATEWAY_RUN_LIVE_EVENTKIT_TESTS=1`.
- 2026-07-23: Post-adversarial focused compilation and test execution used the
  explicit Xcode environment. All ten `detachedMasterId...` tests passed. The
  opt-in live test compiled and was skipped because the enabling environment
  variable was not set; no Calendar data was changed.
- 2026-07-23: Final post-adversarial verification used the same explicit Xcode
  environment. `task test` reported 202 Swift tests passed, one opt-in live
  test skipped, and `AppleGatewaySmokeTests: passed`; the command wrapper
  reached its timeout only after both successful results were emitted.
  `swiftlint` passed with zero violations. `git diff --check`, the explicit
  four-document whitespace check, baseline/final HEAD equality, adapter
  1000-line enforcement, `VERSION`, unrelated-domain, and worktree-scope checks
  all passed. Changes remain uncommitted and unpushed.
- 2026-07-23: Step 6 self-review found that the opt-in destructive check
  asserted only `DeleteResult.success` and silently ignored scratch-calendar
  cleanup errors. Strengthened it with post-delete readback proving the
  pre-cutoff occurrence and an unrelated same-calendar control event remain,
  while cutoff and later target occurrences are absent. Cleanup failures now
  record a test issue with the scratch calendar identifier.
- 2026-07-23: Post-self-review verification compiled the strengthened opt-in
  test and confirmed it remains skipped without the enabling environment
  variable. All ten `detachedMasterId...` tests passed, `task test` reported
  202 Swift tests plus `AppleGatewaySmokeTests: passed`, and `swiftlint`
  reported zero violations. Diff, documentation whitespace, HEAD equality,
  unrelated-domain, and worktree-scope checks passed; no commit or Calendar
  mutation occurred.
- 2026-07-23: The next adversarial review found that a unique narrow external
  match still triggered one synchronous four-year `events(matching:)` query
  while the adapter lock was held. It also found that moved-occurrence
  coverage tested only window arithmetic rather than the production resolver
  query sequence.
- 2026-07-23: Replaced the monolithic fallback with the production-linked
  `EventOccurrenceResolver`. A direct
  `calendarItems(withExternalIdentifier:)` series-uniqueness check lets unique
  narrow external matches return immediately. Narrow misses search outward in
  month-sized windows with a 49-window and 10,000-candidate ceiling; limit
  exhaustion raises an internal error before any save or removal.
- 2026-07-23: Replaced the planner-only moved-occurrence check with resolver
  tests proving immediate narrow return, bounded fallback query ordering,
  direct external-series ambiguity rejection, and both candidate and window
  limits. `swift test --filter detachedMasterId` rebuilt the affected targets
  and passed all fourteen named tests.
- 2026-07-23: The first post-revision `task test` run exposed two unrelated
  notification-helper timeout flakes under parallel load. Both tests passed
  immediately in isolation, and a full rerun passed all 206 Swift tests plus
  `AppleGatewaySmokeTests`; the opt-in live EventKit test remained skipped and
  no Calendar data was changed.
- 2026-07-23: Final verification passed `swiftlint` with zero violations,
  `git diff --check`, the explicit four-document whitespace check, baseline
  HEAD equality, the 1000-line adapter limit at 627 lines, and the
  VERSION/unrelated-domain scope check. The worktree contains only intended
  source, test, design, and implementation-plan paths and remains uncommitted
  and unpushed.

## Residual Risks

- Protocol fakes cannot reproduce every account-specific EventKit identifier
  transition. The isolated live check remains opt-in and has not been executed
  without explicit permission.
- Exact occurrence-date equality remains unchanged.
- The fallback horizon is bounded to two years in each direction from the
  original occurrence date; moves beyond that bound remain unaddressable by
  master ID.
- A single month-sized EventKit predicate remains synchronous. Candidate and
  window limits bound repeated work but cannot cancel one slow framework call.
