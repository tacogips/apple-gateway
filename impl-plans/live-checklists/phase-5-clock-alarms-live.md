# Phase 5 Clock Alarms Live Checklist

Run only against scratch Clock alarms on a local macOS session.

## Environment

- [ ] macOS version recorded.
- [ ] Responsible terminal or installed executable has Accessibility access.
- [ ] Responsible executable has Automation access to System Events.
- [ ] No alarm already uses the selected scratch label.

## Read-only verification

```bash
scripts/live-clock-alarms-check.sh
```

- [ ] Clock.app launched or connected successfully.
- [ ] Alarm list returned without GraphQL errors.

## Mutation verification

```bash
scripts/live-clock-alarms-check.sh --execute
```

- [ ] Scratch alarm was created with Monday and Friday repeats.
- [ ] Scratch alarm was disabled.
- [ ] Time, label, and repeat day were updated while it remained disabled.
- [ ] Updated scratch alarm was deleted.
- [ ] No scratch alarm remains after completion or failure cleanup.
