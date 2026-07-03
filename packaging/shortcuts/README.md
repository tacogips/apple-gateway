# Apple Gateway Clock Alarm Shortcuts

Apple Gateway drives Clock.app alarms through user-installed Shortcuts because
macOS does not expose a public Clock alarm API. Install these bridge shortcuts
with the configured prefix, which defaults to `apple-gateway`:

- `apple-gateway-get-alarms`
- `apple-gateway-create-alarm`
- `apple-gateway-toggle-alarm`
- `apple-gateway-update-alarm` (macOS 26+)
- `apple-gateway-delete-alarm` (macOS 26+)

The repository reserves this directory for the exported `.shortcut` files.
Export them from Shortcuts.app after creating or updating the bridge actions.
Shortcuts cannot be installed programmatically by the CLI. The source build
sheet is `SOURCE.md`, and `manifest.json` records the expected bridge shortcut
names and validation commands.

The local `shortcuts` CLI on this development machine advertises only `run`,
`list`, `view`, and `sign`; it has no `create`, `import`, or `export`
subcommand. Do not treat `SOURCE.md` or `manifest.json` as substitutes for the
real exported `.shortcut` files.

## Verification

Check whether the bridge shortcuts are installed without running them:

```bash
scripts/live-clock-alarms-check.sh
```

Run the get shortcut and validate parseable JSON without mutating alarms:

```bash
scripts/live-clock-alarms-check.sh --read-only
```

Run the scratch mutation flow only after reviewing the checklist and accepting
that it will create a temporary Clock alarm:

```bash
scripts/live-clock-alarms-check.sh --execute
```

## JSON Contract

Contract version: `1`.

`apple-gateway-get-alarms` writes this JSON object to its output path:

```json
{
  "contractVersion": 1,
  "alarms": [
    {
      "id": "optional-stable-id",
      "label": "Wake up",
      "time": "07:30",
      "isEnabled": true,
      "repeatDays": ["MONDAY", "TUESDAY"]
    }
  ]
}
```

Fields:

- `contractVersion`: integer contract version. The current value is `1`.
- `alarms`: array of Clock alarms returned by Shortcuts.
- `id`: optional stable identifier when Shortcuts or the OS exposes one.
- `label`: alarm name. Mutations address alarms by this field.
- `time`: local 24-hour `HH:mm` alarm time.
- `isEnabled`: whether the alarm is enabled.
- `repeatDays`: zero or more weekday enum values: `MONDAY`, `TUESDAY`,
  `WEDNESDAY`, `THURSDAY`, `FRIDAY`, `SATURDAY`, `SUNDAY`.

Mutation shortcuts receive a JSON file containing `contractVersion` and
`payload`.

Create alarm:

```json
{
  "contractVersion": 1,
  "payload": {
    "time": "07:30",
    "label": "Wake up",
    "repeatDays": ["MONDAY", "TUESDAY"]
  }
}
```

Toggle alarm:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Wake up",
    "enabled": false
  }
}
```

Update alarm on macOS 26+:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Wake up",
    "time": "07:45",
    "newLabel": "Morning",
    "repeatDays": ["MONDAY", "WEDNESDAY", "FRIDAY"]
  }
}
```

Delete alarm on macOS 26+:

```json
{
  "contractVersion": 1,
  "payload": {
    "label": "Morning"
  }
}
```

Mutation shortcuts may ignore stdout. Apple Gateway verifies mutations by
running the get shortcut again and comparing the alarm list. If verification is
inconclusive, GraphQL returns a successful result with `warning` populated.
