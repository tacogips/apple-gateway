# Calendar and Reminders Design (EventKit)

## Status

Draft

## Mechanism

Direct EventKit (`EKEventStore`) from the CLI process. One store instance
per process, created lazily on first calendar/reminders resolver call.
AppleScript to Calendar.app/Reminders.app is rejected as a mechanism
(minutes-slow on real stores; requires GUI apps). See
`design-docs/references/macos-platform-research-2026-07.md` section 1.

EventKit sees all sources synced by `calaccessd`: iCloud, Exchange, Google,
CalDAV, local, subscribed, and birthdays. Both events and reminders come
from the same framework; both adapters share an `EventKitSession` helper
that owns store creation, access requests (`requestFullAccessToEvents` /
`requestFullAccessToReminders` on macOS 14+, semaphore-bridged), and
DateComponents/DateTime conversion.

## Production Adapter Boundary

Production GraphQL execution must use live `EKEventStore`-backed adapters by
default for both calendar and reminders reads and writes. The CLI wiring owns
this default; tests, smoke flows, and any non-live harnesses keep passing
explicit fake or unavailable services through the existing injection seams.

The live adapter boundary is:

- `CalendarProviding` and `CalendarWriting` are implemented by a calendar
  EventKit adapter backed by the process-local `EventKitSession`.
- `RemindersProviding` and `RemindersWriting` are implemented by a reminders
  EventKit adapter backed by the same process-local `EventKitSession`.
- The GraphQL runtime and domain services depend only on those protocols and
  must not construct `EKEventStore` directly.
- `UnavailableCalendarReminderProvider` remains valid only for explicit
  injected paths where EventKit should not be touched, such as negative tests or
  platform-unavailable builds; it is not the production CLI default on macOS
  when EventKit is importable.

Live adapters perform authorization checks at the EventKit boundary before each
operation that needs calendar or reminder access. Reader-role write rejection
remains enforced in the GraphQL schema/runtime before write services are called,
so wiring live writers must not weaken role isolation.

## GraphQL Types

```graphql
enum CalendarEntityType { EVENT, REMINDER }

type Calendar {
  id: ID!                      # EKCalendar.calendarIdentifier
  title: String!
  entityType: CalendarEntityType!
  sourceTitle: String!         # EKSource title, e.g. "iCloud"
  sourceType: String!          # local | caldav | exchange | subscribed | birthdays
  colorHex: String
  allowsModifications: Boolean!
  isSubscribed: Boolean!
  isDefault: Boolean!          # default calendar for new items of its entity type
}

enum EventStatus { NONE, CONFIRMED, TENTATIVE, CANCELED }
enum EventAvailability { NOT_SUPPORTED, BUSY, FREE, TENTATIVE, UNAVAILABLE }
enum AttendeeStatus { UNKNOWN, PENDING, ACCEPTED, DECLINED, TENTATIVE, DELEGATED, COMPLETED, IN_PROCESS }
enum RecurrenceFrequency { DAILY, WEEKLY, MONTHLY, YEARLY }
enum RecurrenceSpan { THIS_EVENT, FUTURE_EVENTS }

type EventParticipant {
  name: String
  email: String
  isCurrentUser: Boolean!
  status: AttendeeStatus!
}

"EventKit alarm attached to an event or reminder"
type Alarm {
  relativeOffsetSeconds: Int   # negative = before start/due
  absoluteDate: DateTime       # exactly one of the two is non-null
}

type RecurrenceRule {
  frequency: RecurrenceFrequency!
  interval: Int!
  daysOfWeek: [Int!]           # 1=Sunday ... 7=Saturday
  daysOfMonth: [Int!]
  monthsOfYear: [Int!]
  weeksOfYear: [Int!]
  daysOfYear: [Int!]
  setPositions: [Int!]
  endDate: DateTime
  occurrenceCount: Int
}

type CalendarEvent {
  id: ID!                      # EKEvent.eventIdentifier
  calendarId: ID!
  title: String!
  notes: String
  location: String
  url: String
  isAllDay: Boolean!
  startDate: DateTime!
  endDate: DateTime!
  timeZone: String             # IANA identifier
  status: EventStatus!
  availability: EventAvailability!
  organizer: EventParticipant
  attendees: [EventParticipant!]!
  alarms: [Alarm!]!
  recurrenceRules: [RecurrenceRule!]!
  isRecurring: Boolean!
  occurrenceDate: DateTime     # identifies the instance for recurring events
  isDetached: Boolean!
  creationDate: DateTime
  lastModifiedDate: DateTime
}

type Reminder {
  id: ID!                      # EKReminder.calendarItemIdentifier
  listId: ID!                  # owning Calendar (entityType REMINDER)
  title: String!
  notes: String
  url: String
  priority: Int!               # 0 none, 1 high, 5 medium, 9 low
  isCompleted: Boolean!
  completionDate: DateTime
  startDate: DateTime
  dueDate: DateTime
  dueDateHasTime: Boolean!     # false when due date is date-only
  alarms: [Alarm!]!
  recurrenceRules: [RecurrenceRule!]!
  creationDate: DateTime
  lastModifiedDate: DateTime
}
```

## Search Inputs and Connections

```graphql
input EventSearchInput {
  calendarIds: [ID!]
  startDate: DateTime!    # required: EventKit event predicates need a range
  endDate: DateTime!      # range wider than 4 years is split into chunks internally
  query: String           # case-insensitive substring on title/notes/location
  first: Int              # default limits.default_page_size, capped at max_page_size
  after: String
}

input ReminderSearchInput {
  listIds: [ID!]
  status: ReminderStatusFilter = ALL   # ALL | INCOMPLETE | COMPLETED
  dueAfter: DateTime
  dueBefore: DateTime
  query: String
  first: Int
  after: String
}

enum ReminderStatusFilter { ALL, INCOMPLETE, COMPLETED }

type EventConnection {
  edges: [EventEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}
type EventEdge { cursor: String!, node: CalendarEvent! }

type ReminderConnection {
  edges: [ReminderEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}
type ReminderEdge { cursor: String!, node: Reminder! }
```

Pagination is offset-cursor based (opaque base64 cursor over the sorted,
filtered in-memory result), matching the base project's connection shape.
Sorting: events by `startDate` ascending; reminders by due date ascending
with no-due-date items last. Unsupported filter combinations fail with
`INVALID_ARGUMENT` rather than being ignored (mail-gateway review Q7).

## Mutations

```graphql
input CreateCalendarInput { title: String!, sourceTitle: String, colorHex: String }
input CreateReminderListInput { title: String!, sourceTitle: String, colorHex: String }

input AlarmInput {
  relativeOffsetSeconds: Int
  absoluteDate: DateTime      # exactly one must be set
}

input RecurrenceRuleInput {
  frequency: RecurrenceFrequency!
  interval: Int = 1
  daysOfWeek: [Int!]
  daysOfMonth: [Int!]
  monthsOfYear: [Int!]
  setPositions: [Int!]
  endDate: DateTime
  occurrenceCount: Int        # at most one of endDate/occurrenceCount
}

input CreateEventInput {
  calendarId: ID              # default event calendar when omitted
  title: String!
  startDate: DateTime!
  endDate: DateTime!
  isAllDay: Boolean = false
  notes: String
  location: String
  url: String
  timeZone: String
  availability: EventAvailability
  alarms: [AlarmInput!]
  recurrenceRules: [RecurrenceRuleInput!]
}

input UpdateEventInput {
  eventId: ID!
  occurrenceDate: DateTime          # required to address one instance of a series
  span: RecurrenceSpan = THIS_EVENT
  # every field below: null/omitted = leave unchanged
  title: String
  startDate: DateTime
  endDate: DateTime
  isAllDay: Boolean
  notes: String
  location: String
  url: String
  timeZone: String
  availability: EventAvailability
  calendarId: ID                    # move between calendars
  alarms: [AlarmInput!]             # full replacement when present
  recurrenceRules: [RecurrenceRuleInput!]  # full replacement when present
}

input CreateReminderInput {
  listId: ID                  # default reminder list when omitted
  title: String!
  notes: String
  url: String
  priority: Int
  startDate: DateTime
  dueDate: DateTime
  dueDateHasTime: Boolean = true
  alarms: [AlarmInput!]
  recurrenceRules: [RecurrenceRuleInput!]
}

input UpdateReminderInput {
  reminderId: ID!
  title: String
  notes: String
  url: String
  priority: Int
  startDate: DateTime
  dueDate: DateTime
  dueDateHasTime: Boolean
  listId: ID
  alarms: [AlarmInput!]
  recurrenceRules: [RecurrenceRuleInput!]
}
```

Semantics:

- `alarms` / `recurrenceRules` on update are full-replacement, never merge.
  `setEventAlarms` / `setReminderAlarms` are convenience mutations with the
  same replacement semantics for alarm-only edits.
- Writes to calendars with `allowsModifications == false` fail with
  `CALENDAR_READ_ONLY` before touching the store.
- Attendee modification is not supported (EventKit cannot add attendees on
  macOS); `attendees` is read-only and documented as such.
- Recurring events: `deleteEvent`/`updateEvent` honor `span`; addressing a
  specific occurrence requires `occurrenceDate` because
  `event(for identifier:)` returns the earliest instance otherwise.
- All saves use `span`-aware `save(_:span:commit:)` with immediate commit.

## EventKit Notes and Edge Cases

- Access requests use the macOS 14 full-access APIs; a `.writeOnly` status
  (from a legacy grant) is surfaced as `WRITE_ONLY_ACCESS`, not treated as
  usable.
- Production adapters use one `EKEventStore` per process through
  `EventKitSession`; store objects are mapped to domain values immediately and
  are never cached or returned across the protocol boundary.
- `EKEventStore` predicates limit event enumeration to 4-year windows; the
  adapter chunks longer requested ranges transparently.
- All-day events: `isAllDay` drives date-only serialization (the DateTime
  scalar still carries a timestamp; `dueDateHasTime`-style flags carry the
  distinction for reminders).
- `fetchReminders(matching:)` is completion-handler based; bridged
  synchronously like all other callbacks.
- Store objects (`EKEvent`, `EKCalendar`) are not `Sendable`; adapters
  convert to value-type domain models (`Codable` structs) at the boundary
  and never let EventKit objects escape (mail-gateway review Q8 analog).

## Testing

- `CalendarProviding`/`RemindersProviding` fakes drive resolver and
  connection tests.
- Adapter mapping tests must be deterministic and must not touch real user
  calendar or reminder data. They use fakes or mapper seams to cover calendar,
  event, reminder, alarm, recurrence, identifier, timezone, all-day, and
  date-only due-date semantics.
- Smoke tests use injectable fake providers/writers by default. Manual live
  smoke is opt-in and must target scratch "apple-gateway-test" calendars/lists.
- Date conversion, recurrence mapping (`EKRecurrenceRule` to/from domain
  model), and alarm mapping get direct unit tests.
- A manual live checklist (create/update/delete event and reminder on a
  scratch calendar) is documented in the phase plan; not run in CI.
