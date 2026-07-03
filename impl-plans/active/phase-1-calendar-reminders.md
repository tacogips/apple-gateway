# Phase 1: Calendar, Reminders, and EventKit Alarms

**Status**: Implementation complete; live manual verification remains
permission-gated
**Design Reference**: `design-docs/specs/design-calendar-reminders.md`

## Purpose

Deliver the first real domain: full EventKit-backed CRUD for calendars,
events, reminder lists, and reminders, including complete `EKAlarm`
control and recurrence rules.

## Deliverables

- [x] `Domains/CalendarKitAdapter/` and `Domains/RemindersAdapter/` with a
      shared `EventKitSession`
- [x] Schema modules registering all Query/Mutation fields from the domain
      spec (calendars, events, event, reminderLists, reminders, reminder;
      create/update/delete for calendars, events, reminder lists,
      reminders; setEventAlarms, setReminderAlarms, setReminderCompleted)
- [x] Domain value models (`Codable`, `Sendable`) and EventKit mapping
- [x] Fake providers + resolver tests; manual live checklist artifact and safe
      dry-run helper
- [x] Permission-gated live scratch helper that refuses `--execute` before
      mutation unless Calendar and Reminders permissions are both `GRANTED`

Live checklist execution remains open under TASK-005 until Calendar and
Reminders permissions are granted on the target host.

## Tasks

### TASK-001: EventKitSession

**Parallelizable**: No

Store lifecycle, macOS 14 full-access requests bridged with semaphores,
authorization mapping (`.fullAccess`/`.writeOnly`/`.denied`/`.notDetermined`
to `PermissionState` and error codes), DateTime scalar conversion
(ISO 8601 with timezone), DateComponents handling for date-only values.

**Completion Criteria**:

- [x] `.writeOnly` surfaces as `WRITE_ONLY_ACCESS`, never used for reads
- [x] `.notDetermined` fails with `PERMISSION_NOT_DETERMINED` (no implicit
      prompt), per resolved Decision 7
- [x] Date conversion unit tests: timezone offsets, all-day, date-only due

### TASK-002: Read side (calendars, events, reminders)

**Parallelizable**: Yes (after TASK-001)

Predicate-based event enumeration with 4-year window chunking, reminder
fetch with status/date filters, substring `query` filtering, offset-cursor
connections, sort orders from the spec, recurrence/alarm/participant
mapping to domain models.

**Completion Criteria**:

- [x] `events` requires start/end; ranges over 4 years chunk transparently
      (verified with a fake provider capturing predicate windows)
- [x] Unsupported filter combinations fail `INVALID_ARGUMENT`
- [x] Connection tests: pagination stability, totalCount, endCursor

### TASK-003: Write side (mutations)

**Parallelizable**: Yes (after TASK-001)

Create/update/delete for events and reminders, calendar and reminder-list
creation/deletion, alarm and recurrence full-replacement semantics,
`RecurrenceSpan` handling with `occurrenceDate` addressing, read-only
calendar guard.

**Completion Criteria**:

- [x] Update with omitted fields leaves them unchanged (fake-provider
      assertion on the save payload)
- [x] `alarms`/`recurrenceRules` present means replace-all
- [x] `CALENDAR_READ_ONLY` raised before any save on subscribed calendars
- [x] Span semantics unit-tested for delete/update of series instances

### TASK-004: Schema module registration and smoke flows

**Parallelizable**: No (integrates 002-003)

Register the calendar and reminders schema modules; extend smoke tests
with full CLI flows over fakes (create event with alarm, search, update
span, complete reminder); update `schema print` snapshot.

**Completion Criteria**:

- [x] Reader binary serves all reads, rejects all writes for this domain
- [x] SDL snapshot updated and reviewed against the domain spec

### TASK-004A: Live EventKit production adapters

**Parallelizable**: No (after TASK-004)

Replace the production GraphQL CLI calendar/reminders defaults with live
`EKEventStore`-backed adapters while preserving fake injection for tests and
smoke flows. Implement both calendar and reminders read/write protocol adapters
behind `CalendarProviding`, `CalendarWriting`, `RemindersProviding`, and
`RemindersWriting`; keep GraphQL/domain services protocol-only; add
deterministic mapper coverage through fakes or adapter seams without touching
real user stores.

**Completion Criteria**:

- [x] Production `apple-gateway graphql` defaults use live EventKit adapters on
      macOS when EventKit is importable, not unavailable calendar/reminder
      services
- [x] Tests and smoke paths can still inject fakes or unavailable services and
      do not access real calendar/reminders data
- [x] EventKit mapping tests cover identifiers, timezone/all-day handling,
      date-only reminder due dates, alarms, recurrence, and read-only calendar
      semantics through deterministic seams
- [x] Reader binary/schema/runtime still rejects calendar/reminder mutations
      before writer calls
- [x] Verification passes with `swift build`, targeted and broad `swift test`,
      `swift run AppleGatewaySmokeTests`, and `swiftlint`

### TASK-005: Manual live verification checklist

**Parallelizable**: No (after TASK-004A)

Documented manual run against a scratch "apple-gateway-test" calendar and
reminder list: create/read/update/delete each entity, alarm set/replace,
recurring event span edits, permission prompt behavior from Terminal and
iTerm2. Record results in this plan's Progress Log. Use
`impl-plans/live-checklists/phase-1-calendar-reminders-live.md` and
`scripts/live-calendar-reminders-check.sh` for the safe opt-in run.

**Completion Criteria**:

- [ ] Checklist executed on macOS 14 and on the newest available macOS
- [ ] Findings fed back into specs or filed as user-qa questions

## Progress Log

- 2026-07-02: Plan created from approved design docs.
- 2026-07-03: Phase 0 foundation plan marked complete after verified
  closeout, so Phase 1 is no longer blocked on Phase 0.
- 2026-07-03: TASK-001 routed through Riela session
  `codex-design-and-implement-review-loop-session-351`; manager routing
  selected issue-resolution, but issue intake stalled with stale timestamps
  and the workflow process was terminated. Local implementation continued
  against `design-calendar-reminders.md` and this plan. Added
  `EventKitSession`, `LiveEventKitStoreAccess`, explicit read-access error
  mapping for `.writeOnly` and `.notDetermined`, semaphore-bridged
  full-access request helpers, and pure `EventKitDateTime` conversion helpers.
  Verification passed with the Xcode Swift toolchain: `swift test --filter
  EventKitSession`, `swift build`, `task test`, and `swiftlint`.
- 2026-07-03: TASK-002 routed through Riela session
  `codex-design-and-implement-review-loop-session-353`; manager routing
  selected issue-resolution, but issue intake immediately emitted the known
  stale silence warning and the workflow process was terminated. Local
  implementation continued against `design-calendar-reminders.md` and this
  plan. Added Calendar/Reminder read-side value models, provider protocol
  methods, `CalendarReadService`, 4-year event range chunking, query/status/date
  filtering, offset cursor connections, and fake-backed tests. Verification
  passed with the Xcode Swift toolchain: `swift test --filter
  CalendarReadService`, `swift build`, `task test`, and `swiftlint`.
- 2026-07-03: TASK-003 routed through Riela session
  `codex-design-and-implement-review-loop-session-354`; manager routing
  selected issue-resolution, but issue intake stalled with stale timestamps
  and the workflow process was terminated. Local implementation continued
  against `design-calendar-reminders.md` and this plan. Added write input
  models, `CalendarWriting`/`RemindersWriting` protocol methods,
  `CalendarWriteService`, omitted-field update preservation,
  alarm/recurrence full-replacement semantics, read-only calendar guards before
  writer calls, and recurrence span pass-through for event update/delete.
  Verification passed with the Xcode Swift toolchain: `swift test --filter
  CalendarWriteService`, `swift build`, `task test`, and `swiftlint`.
- 2026-07-03: TASK-004 routed through Riela session
  `codex-design-and-implement-review-loop-session-356`; manager routing
  selected issue-resolution, but issue intake stalled with stale timestamps
  and the workflow process was terminated. Local implementation continued
  against `design-calendar-reminders.md` and this plan. Registered the
  calendar/reminders GraphQL module in bootstrap schema, added `ID` and
  `DateTime` scalar coercion, exposed read/write service injection through
  the runtime and CLI, added unavailable default services for non-live paths,
  and extended fake-backed GraphQL and smoke coverage for create event with
  alarm, event search, update event span, complete reminder, reader schema
  reads, and reader mutation rejection. Verification passed with the Xcode
  Swift toolchain: `swift build`, `swift test --filter GraphQLRuntime`,
  `swift run AppleGatewaySmokeTests`, `task test`, and `swiftlint`.
- 2026-07-03: Riela session
  `codex-design-and-implement-review-loop-session-359` identified that
  TASK-005 was premature because production GraphQL CLI defaults still used
  unavailable calendar/reminders services. Added TASK-004A as the live
  EventKit adapter prerequisite and updated
  `design-docs/specs/design-calendar-reminders.md` to make production live
  adapter defaults, fake injection seams, deterministic mapper tests, and
  reader-role write rejection explicit.
- 2026-07-03: Completed TASK-004A implementation under Riela session
  `codex-design-and-implement-review-loop-session-359`. Added
  `LiveEventKitCalendarReminderAdapter`, `EventKitCalendarReminderMapper`, a
  live service-pair factory, and production CLI default wiring so GraphQL
  calendar/reminders calls use a live `EKEventStore` adapter unless tests or
  smoke pass explicit fakes. Added deterministic mapper coverage for calendar
  identifiers/default state, timed-event timezone, all-day event assignment,
  date-only reminder due-date components, alarms, recurrence, and invalid alarm
  or recurrence inputs without saving/fetching user data. Existing fake-backed
  GraphQL and smoke tests continue to cover reader write rejection and fake
  injection. Verification passed with the Xcode Swift toolchain:
  `swift build`, `swift test --filter EventKitCalendarReminderMapper`,
  `task test`, and `swiftlint`.
- 2026-07-03: The same Riela session accepted the design review and advanced
  to implementation planning, then the local Riela process was intentionally
  cancelled after local TASK-004A implementation and verification had already
  completed. The persisted Riela session is terminal failed due to
  cancellation, not due to a verification failure.
- 2026-07-03: TASK-005 routed through Riela session
  `codex-design-and-implement-review-loop-session-361`; intake accepted the
  scratch-data-only and non-prompting-readiness constraints, then the workflow
  became silent in design-doc update. Local readiness work continued against
  the plan. Non-prompting `swift run apple-gateway permissions status --json`
  on macOS 26.5.1 (Build 25F80) reported Calendar `NOT_DETERMINED` and
  Reminders `NOT_DETERMINED`, so live mutation was not executed because it
  would require TCC prompting first. Added
  `impl-plans/live-checklists/phase-1-calendar-reminders-live.md` and the
  original `scripts/live-calendar-reminders-check.sh` helper. That initial
  helper behavior treated its default readiness path as a permission guard when
  Calendar and Reminders were both `NOT_DETERMINED`; this was later superseded
  by `codex-simple-work-package-session-421`, where default dry-run succeeds
  without prompting and only `--execute` refuses with exit 4 before mutation
  unless both permissions are already `GRANTED`. Verification at the time:
  `bash -n scripts/live-calendar-reminders-check.sh` and observing the
  permission-gated readiness refusal in the original helper.
- 2026-07-03: The local Riela process for session
  `codex-design-and-implement-review-loop-session-361` was intentionally
  cancelled after intake and local TASK-005 readiness documentation completed.
  The persisted Riela session is terminal failed due to cancellation, not due
  to a checklist or verification failure.
- 2026-07-03: Documentation/status cleanup routed through Riela session
  `codex-simple-work-package-session-395`; the workflow identified stale
  Phase 1 deliverable checkboxes, then the local process was stopped before
  file edits. Updated the top-level status and deliverables to reflect the
  completed EventKit implementation, schema, models, fake tests, and live
  checklist artifact while leaving TASK-005 live execution open because
  Calendar/Reminders permissions are not granted. Verification:
  `git diff --check`, `task build`, and `swift run apple-gateway --help`.
- 2026-07-03: Safer TASK-005 helper update routed through Riela session
  `codex-simple-work-package-session-421`. Updated
  `scripts/live-calendar-reminders-check.sh` so default mode is a successful
  non-prompting dry-run that prints the checklist path, reports Calendar and
  Reminders permission states, verifies full/reader schema readiness, and
  states that no live EventKit query or mutation was performed. Kept live
  scratch verification behind explicit `--execute`, which refuses with exit 4
  before mutation unless Calendar and Reminders permissions are both `GRANTED`.
  Live execution remains permission-gated and was not run in this session.
- 2026-07-03: Schema readiness hardening routed through Riela session
  `codex-simple-work-package-session-432`. Updated
  `scripts/live-calendar-reminders-check.sh` so default dry-run extracts the
  GraphQL `Query` and `Mutation` root blocks before validating exact
  Calendar/Reminders root field exposure. Full and reader schemas must expose
  the exact read root fields, the full schema must expose the exact mutation
  root fields, and the reader schema must not expose those mutation root
  fields. Default dry-run remains non-prompting, non-mutating,
  non-live-querying, and permission-gated live execution was not run.
