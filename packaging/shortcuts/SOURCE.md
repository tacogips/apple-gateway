# Clock Alarm Bridge Shortcut Source

This file is the build sheet for the five bridge shortcuts. The exported
`.shortcut` files still need to be created in Shortcuts.app and added next to
this document because the local `shortcuts` CLI cannot author, import, or
export shortcuts.

Observed local CLI capability on 2026-07-03:

- `shortcuts run`
- `shortcuts list`
- `shortcuts view`
- `shortcuts sign`

No `create`, `import`, or `export` subcommand is available.

## Shared Rules

- Prefix all shortcut names with `apple-gateway` unless
  `clock_alarms.shortcut_prefix` is changed.
- Read mutation input from the Shortcut input file as JSON.
- Write `apple-gateway-get-alarms` output as JSON matching
  `contractVersion: 1`.
- Mutation shortcuts may return no output; the CLI verifies mutations by
  running `apple-gateway-get-alarms` again.
- Address alarms by label. If Shortcuts exposes multiple matches for the same
  label, leave ambiguity handling to the CLI adapter.

## apple-gateway-get-alarms

Availability: macOS 13+.

Shortcut actions:

1. Get all alarms from Clock.
2. For each alarm, produce a dictionary with:
   - `id`: stable identifier if Shortcuts exposes one; otherwise omit it.
   - `label`: alarm name.
   - `time`: local 24-hour `HH:mm`.
   - `isEnabled`: boolean enabled state.
   - `repeatDays`: array of uppercase weekday names.
3. Wrap the array in:

```json
{
  "contractVersion": 1,
  "alarms": []
}
```

4. Provide that dictionary as the shortcut result so `shortcuts run
   apple-gateway-get-alarms --output-path <file>` writes JSON.

## apple-gateway-create-alarm

Availability: macOS 13+.

Input payload:

```json
{
  "contractVersion": 1,
  "payload": {
    "time": "07:30",
    "label": "Wake up",
    "repeatDays": ["MONDAY"]
  }
}
```

Shortcut actions:

1. Read the Shortcut input JSON.
2. Validate `contractVersion` is `1`.
3. Read `payload.time`, optional `payload.label`, and optional
   `payload.repeatDays`.
4. Use the Clock Create Alarm action with those values.

## apple-gateway-toggle-alarm

Availability: macOS 13+.

Input payload:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Wake up",
    "enabled": false
  }
}
```

Shortcut actions:

1. Read the Shortcut input JSON.
2. Validate `contractVersion` is `1`.
3. Find alarms whose name equals `payload.label`.
4. Toggle or set the enabled state according to `payload.enabled`.

If Shortcuts only exposes a toggle action and no explicit enabled setter, the
shortcut should compare the current enabled state first and only toggle when it
differs from `payload.enabled`. If `payload.enabled` is absent, perform a plain
toggle.

## apple-gateway-update-alarm

Availability: macOS 26+.

Input payload:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Wake up",
    "time": "07:45",
    "newLabel": "Morning",
    "repeatDays": ["MONDAY", "FRIDAY"]
  }
}
```

Shortcut actions:

1. Read the Shortcut input JSON.
2. Validate `contractVersion` is `1`.
3. Find alarms whose name equals `payload.label`.
4. Use the Clock Update Alarm action, setting only the fields present in the
   payload.

## apple-gateway-delete-alarm

Availability: macOS 26+.

Input payload:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Morning"
  }
}
```

Shortcut actions:

1. Read the Shortcut input JSON.
2. Validate `contractVersion` is `1`.
3. Find alarms whose name equals `payload.label`.
4. Use the Clock Delete Alarms action.

## Export

After creating each shortcut in Shortcuts.app:

1. Export the shortcut from Shortcuts.app into this directory.
2. Keep the file name equal to the shortcut name plus `.shortcut`.
3. Sign exported files when needed:

```bash
shortcuts sign --mode anyone \
  --input packaging/shortcuts/apple-gateway-get-alarms.shortcut \
  --output packaging/shortcuts/apple-gateway-get-alarms.shortcut
```

4. Run:

```bash
scripts/live-clock-alarms-check.sh --read-only
```

5. Run the scratch mutation check only after confirming the read-only check
   returns parseable JSON:

```bash
scripts/live-clock-alarms-check.sh --execute
```
