# Clock Alarms Design

## Scope

Apple Gateway lists, creates, enables or disables, updates, and deletes alarms
in macOS Clock.app. Timers and stopwatch control are out of scope.

## Automation boundary

Clock.app does not expose an AppleScript dictionary or a public alarm API. The
gateway therefore owns an accessibility-automation adapter implemented with
JXA executed through `/usr/bin/osascript`.

The adapter launches Clock.app, selects its Alarms tab, and uses stable
accessibility identifiers such as `AXMTAAlarmCollectionView`,
`AlarmNameLabel`, and `AlarmEnableSwitch`. Repeat-day checkboxes are addressed
by their ordered positions because localized one-letter labels are not unique.
No Shortcuts.app workflow or packaged `.shortcut` asset is required.

## Permissions

The responsible executable identity needs:

- Accessibility permission to operate Clock.app controls.
- Automation permission for System Events.

`apple-gateway permissions request --domain clock-alarms` requests these
permissions, while `permissions status` and `permissions doctor` report their
state and remediation instructions.

## Addressing and verification

The public GraphQL API addresses alarms by label. Mutations reject missing or
ambiguous labels. After each UI mutation, the adapter re-reads Clock.app and
polls briefly for the expected state so transient accessibility-tree refreshes
do not produce false failures. Updates preserve the alarm's previous enabled
state.

## Testing

- Unit tests inject an automation executor to verify validation, ambiguity,
  mapping, and mutation behavior without operating Clock.app.
- Template tests pin the accessibility anchors and ensure no external bridge is
  invoked.
- `scripts/live-clock-alarms-check.sh` provides a read-only check and an
  opt-in scratch create/toggle/update/delete flow with best-effort cleanup.
