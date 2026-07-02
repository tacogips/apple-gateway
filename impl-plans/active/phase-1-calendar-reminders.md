# Phase 1: Calendar, Reminders, and EventKit Alarms

**Status**: In Progress (blocked on Phase 0)
**Design Reference**: `design-docs/specs/design-calendar-reminders.md`

## Purpose

Deliver the first real domain: full EventKit-backed CRUD for calendars,
events, reminder lists, and reminders, including complete `EKAlarm`
control and recurrence rules.

## Deliverables

- [ ] `Domains/CalendarKitAdapter/` and `Domains/RemindersAdapter/` with a
      shared `EventKitSession`
- [ ] Schema modules registering all Query/Mutation fields from the domain
      spec (calendars, events, event, reminderLists, reminders, reminder;
      create/update/delete for calendars, events, reminder lists,
      reminders; setEventAlarms, setReminderAlarms, setReminderCompleted)
- [ ] Domain value models (`Codable`, `Sendable`) and EventKit mapping
- [ ] Fake providers + resolver tests; manual live checklist

## Tasks

### TASK-001: EventKitSession

**Parallelizable**: No

Store lifecycle, macOS 14 full-access requests bridged with semaphores,
authorization mapping (`.fullAccess`/`.writeOnly`/`.denied`/`.notDetermined`
to `PermissionState` and error codes), DateTime scalar conversion
(ISO 8601 with timezone), DateComponents handling for date-only values.

**Completion Criteria**:

- [ ] `.writeOnly` surfaces as `WRITE_ONLY_ACCESS`, never used for reads
- [ ] `.notDetermined` fails with `PERMISSION_NOT_DETERMINED` (no implicit
      prompt), per resolved Decision 7
- [ ] Date conversion unit tests: timezone offsets, all-day, date-only due

### TASK-002: Read side (calendars, events, reminders)

**Parallelizable**: Yes (after TASK-001)

Predicate-based event enumeration with 4-year window chunking, reminder
fetch with status/date filters, substring `query` filtering, offset-cursor
connections, sort orders from the spec, recurrence/alarm/participant
mapping to domain models.

**Completion Criteria**:

- [ ] `events` requires start/end; ranges over 4 years chunk transparently
      (verified with a fake provider capturing predicate windows)
- [ ] Unsupported filter combinations fail `INVALID_ARGUMENT`
- [ ] Connection tests: pagination stability, totalCount, endCursor

### TASK-003: Write side (mutations)

**Parallelizable**: Yes (after TASK-001)

Create/update/delete for events and reminders, calendar and reminder-list
creation/deletion, alarm and recurrence full-replacement semantics,
`RecurrenceSpan` handling with `occurrenceDate` addressing, read-only
calendar guard.

**Completion Criteria**:

- [ ] Update with omitted fields leaves them unchanged (fake-provider
      assertion on the save payload)
- [ ] `alarms`/`recurrenceRules` present means replace-all
- [ ] `CALENDAR_READ_ONLY` raised before any save on subscribed calendars
- [ ] Span semantics unit-tested for delete/update of series instances

### TASK-004: Schema module registration and smoke flows

**Parallelizable**: No (integrates 002-003)

Register the calendar and reminders schema modules; extend smoke tests
with full CLI flows over fakes (create event with alarm, search, update
span, complete reminder); update `schema print` snapshot.

**Completion Criteria**:

- [ ] Reader binary serves all reads, rejects all writes for this domain
- [ ] SDL snapshot updated and reviewed against the domain spec

### TASK-005: Manual live verification checklist

**Parallelizable**: No (after TASK-004)

Documented manual run against a scratch "apple-gateway-test" calendar and
reminder list: create/read/update/delete each entity, alarm set/replace,
recurring event span edits, permission prompt behavior from Terminal and
iTerm2. Record results in this plan's Progress Log.

**Completion Criteria**:

- [ ] Checklist executed on macOS 14 and on the newest available macOS
- [ ] Findings fed back into specs or filed as user-qa questions

## Progress Log

- 2026-07-02: Plan created from approved design docs.
