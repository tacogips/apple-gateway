# Issue 2: Unified Recurring Master-ID Lookup

**Status**: Accepted
**Issue**: https://github.com/tacogips/apple-gateway/issues/2
**Feature ID**: `issue-2-recurring-master-lookup`
**Workflow Mode**: `issue-resolution`
**Last Reviewed**: 2026-07-23

## Problem

`Query.event` can resolve an EventKit recurring master identifier through
`EKEventStore.event(withIdentifier:)`, but dated mutation preflight and write
lookup enumerate occurrences and compare each occurrence's
`eventIdentifier` directly with the caller-supplied master identifier.
Detached occurrences can change the identifiers returned during enumeration,
so a valid master ID is rejected as `EVENT_NOT_FOUND`.

The lookup paths must agree on the resolved series identity while preserving
the requested occurrence and `EKSpan`. In particular, a missing dated
occurrence must never cause `THIS_EVENT` or `FUTURE_EVENTS` to operate on the
master as a substitute target.

## Scope

This design covers recurring event lookup for:

- `CalendarProviding.event(eventId:occurrenceDate:)`;
- `LiveEventKitCalendarReminderAdapter.updateEvent`;
- `LiveEventKitCalendarReminderAdapter.deleteEvent`; and
- `CalendarWriteService` mutation preflight.

It does not change the GraphQL schema, recurrence creation or mapping, reminder
behavior, unrelated Apple domains, release metadata, or EventKit's save/remove
span mapping.

## Existing Behavior

When `occurrenceDate` is present,
`LiveEventKitCalendarReminderAdapter.event(eventId:occurrenceDate:)` searches
events in a two-day window across every calendar and accepts only an exact raw
`event.eventIdentifier == eventId` match. Its private mutation lookup performs
the same search and then falls back to `store.event(withIdentifier:)`.

This creates three defects:

1. detached occurrence identifiers can differ from the original master ID;
2. enumeration is unnecessarily global instead of scoped to the resolved
   master's calendar; and
3. a mutation miss can select the master despite a caller-supplied occurrence
   date, risking the wrong recurrence anchor.

## Design Decisions

### 1. Resolve the master before enumerating occurrences

Lookup starts with `store.event(withIdentifier: eventId)`. If no master or
resolved event exists, lookup returns not found without global occurrence
enumeration.

The resolved event supplies:

- the owning `EKCalendar`;
- `eventIdentifier`;
- `calendarItemIdentifier`;
- `calendarItemExternalIdentifier`, which EventKit documents as shared by all
  occurrences of a recurring event; and
- the requested identifier as a compatibility alias.

These non-empty identifiers form three typed identity sets: event identifiers,
calendar-item identifiers, and external identifiers. Matching never compares
values across identifier categories.

### 2. Scope occurrence enumeration to the resolved calendar

For a dated lookup, first build the existing two-day predicate around
`occurrenceDate`, but pass `[resolved.calendar]` rather than `nil`. A unique
local-identifier match can return immediately. A unique external-identifier
match can also return immediately after
`calendarItems(withExternalIdentifier:)` confirms that the external identity
maps to only one event series in the resolved calendar. This direct duplicate
check avoids enumerating years of unrelated occurrences for the common path.

If the narrow search has no match, search outward in calendar-month chunks,
alternating before and after the requested occurrence date. The fallback
retains the two-year bound in each direction but never materializes the full
four-year range in one synchronous EventKit query. Search execution is capped
at 49 total windows and 10,000 cumulative candidates. Exceeding either cap
fails before any save or removal rather than allowing an unbounded lookup to
block every operation sharing the adapter lock.

Select an event only when:

- its occurrence date equals the requested date using the existing exact-date
  contract; and
- its `eventIdentifier` matches an accepted event identifier, its
  `calendarItemIdentifier` matches an accepted calendar-item identifier, or
  its `calendarItemExternalIdentifier` matches an accepted external
  identifier.

Identity comparison is isolated in an internal pure helper so detached-ID
cases can be covered without a live EventKit store. Local identity matches take
precedence. External identity is a fallback only when exactly one eligible
candidate matches and the direct series lookup is unique. Multiple local or
external candidates, or multiple series returned for the external identifier,
are ambiguous and fail closed as not found; enumeration order never chooses a
destructive target.

### 3. Separate lookup context from the mutation target

The resolved master is lookup context and a valid result only when no
`occurrenceDate` was requested.

For a dated query or mutation:

- return/use the matching occurrence when found;
- return not found when no exact occurrence is found; and
- never substitute the master as the write target.

This rule preserves occurrence-specific behavior for both `THIS_EVENT` and
`FUTURE_EVENTS`. The existing `EventKitCalendarReminderMapper.ekSpan` mapping
remains unchanged, and the requested occurrence is passed to the writer
unchanged.

The "master fallback" is therefore limited to undated lookup and to obtaining
series identity/calendar context. It is not a dated mutation fallback.

### 4. Share one resolution algorithm

The public provider lookup and the adapter's private mutation lookup use one
internal resolver with an explicit target policy:

| Request | Resolver result |
| --- | --- |
| Valid ID, no occurrence date | Resolved EventKit event/master |
| Valid master ID, exact occurrence found | Matching occurrence |
| Valid master ID, dated occurrence missing | Not found |
| Unknown ID | Not found |

The public path maps a found `EKEvent` to `CalendarEvent`. The mutation path
converts a missing result to the existing `AppleGatewayError.eventNotFound`.

### 5. Keep service preflight and write addressing identical

`CalendarWriteService.existingEvent` continues to call
`CalendarProviding.event` with both the original ID and occurrence date. Its
fake-provider tests must model detached-series resolution rather than raw ID
equality. The service must forward the original master ID, occurrence date, and
span unchanged in `CalendarEventSaveRequest` or
`CalendarEventDeleteRequest`.

This keeps writability checks tied to the calendar of the same occurrence that
the writer will target.

## Error Semantics

- Unknown master ID: `EVENT_NOT_FOUND`.
- Known master ID but no exact occurrence at the requested date:
  `EVENT_NOT_FOUND`.
- Search window or cumulative candidate cap exceeded: `UNEXPECTED_ERROR` with
  the internal limits in error details; no write is attempted.
- Read-only owning calendar: existing `CALENDAR_READ_ONLY`.
- EventKit authorization and save/remove failures: unchanged.

No new public error code or GraphQL field is introduced.

## Verification Design

Automated tests must cover:

1. pure identity matching where the caller's master ID, event identifier, and
   calendar-item identifier differ from the enumerated occurrence, leaving
   only the shared `calendarItemExternalIdentifier` to match the series;
2. unique local-identity preference, typed-category isolation, and rejection
   of ambiguous external-identity matches;
3. rejection of an occurrence from another calendar or another series;
4. rejection of a non-exact occurrence date;
5. resolver-level coverage proving a unique narrow external match does not
   invoke fallback search;
6. resolver-level coverage proving a detached moved occurrence is found in the
   first applicable bounded fallback window;
7. direct external-series ambiguity plus window- and candidate-limit rejection;
8. service update/delete preflight in a detached-series fake-provider scenario;
9. `THIS_EVENT` and `FUTURE_EVENTS` forwarding the original occurrence date and
   span; and
10. no fallback to a master target after a dated occurrence miss.

Run the narrow calendar/reminder tests first, then the full Swift package test
suite. An environment-gated integration test may create and remove only a
uniquely named scratch calendar when
`APPLE_GATEWAY_RUN_LIVE_EVENTKIT_TESTS=1`; default test runs skip it without
touching EventKit data. When enabled, it retains a pre-cutoff occurrence,
removes the cutoff and later occurrences, preserves an unrelated same-calendar
control event, and reports cleanup failure instead of suppressing it.

## Acceptance Criteria

- Query and mutation lookup share resolved series identity rules.
- Occurrence enumeration is restricted to the resolved master's calendar.
- A unique narrow external-identity match does not trigger a multi-year scan.
- A master ID can address an exact occurrence after sibling occurrences have
  been detached.
- Ambiguous identity matches fail closed instead of using EventKit enumeration
  order.
- A detached occurrence moved outside the narrow two-day window remains
  addressable through bounded month-sized fallback windows.
- Fallback lookup is capped by window and candidate counts and fails before a
  destructive write when either resource limit is exceeded.
- `THIS_EVENT` and `FUTURE_EVENTS` retain the caller's exact occurrence target
  and existing `EKSpan` mapping.
- A dated lookup miss cannot mutate the whole series through master fallback.
- Unit tests and the full Swift test suite pass.

## Risks

- EventKit identifier behavior can vary by backing account and macOS release.
  Comparing both local identifier forms, the documented recurring-series
  external identifier, and the input ID reduces, but cannot eliminate,
  platform-specific risk.
- Exact `Date` equality is retained to avoid broadening this issue. If EventKit
  normalizes occurrence timestamps for some calendars, tolerance or component
  matching requires a separate design.
- Month-sized queries limit each synchronous EventKit materialization, but a
  backing store can still make one bounded query slow. Candidate and window
  caps prevent repeated unbounded work but cannot impose a deadline inside
  EventKit's synchronous API.
- The fallback horizon remains intentionally bounded. A detached occurrence
  moved more than two years from its original occurrence date remains outside
  lookup.
- The opt-in live integration test requires explicit calendar permission and
  is skipped by default to prevent implicit user-data mutation.
