# apple-gateway

macOS CLI and GraphQL bridge for Apple apps, including Calendar, Reminders,
Notes, Mail, notifications, and Clock alarms.

## Development

```bash
nix develop
task build
task test
swift run apple-gateway --help
```

The package uses Swift Package Manager with:

- Library target: `AppleGatewayCore`
- Executable targets: `AppleGatewayCLI`, `AppleGatewayReaderCLI`, and
  `AppleGatewayNotifier`
- Installed executables: `apple-gateway`, `apple-gateway-reader`, and the
  packaged `AppleGatewayNotifier.app` helper

## Homebrew Formula

Build local formula archives:

```bash
task build:homebrew -- darwin-arm64 darwin-x64
```

Render a formula after both platform archives exist:

```bash
task homebrew:formula -- 0.1.0
```

Render directly into the default sibling tap checkout:

```bash
task homebrew:tap-formula -- 0.1.0
```

Install from the tap after the formula is published:

```bash
brew tap tacogips/tap
brew install apple-gateway
```

## Homebrew Cask

The Cask workflow builds signed, notarized, and stapled macOS DMG artifacts.
Apple signing credentials must stay local and must not be committed.

Check the build plan:

```bash
task build:homebrew-cask -- --dry-run darwin-arm64 darwin-x64
```

Build with local signing credentials:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  task build:homebrew-cask -- darwin-arm64 darwin-x64
```

Render a Cask:

```bash
task homebrew:cask -- 0.1.0
```

For a tagged release, build, upload, and render the tap Cask:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  task release:homebrew-cask-local -- v0.1.0
```

See `packaging/homebrew/README.md` and `.agents/skills/` for release workflows.

## macOS Permissions and Setup

Run the signed Cask build for stable TCC identities across updates:

```bash
brew tap tacogips/tap
brew install --cask apple-gateway
```

Formula installs are supported for interactive terminal use, but Calendar,
Reminders, and Notes prompts attach to the responsible terminal app. Launchd
and background use should use the signed Cask.

Check current permission state:

```bash
apple-gateway permissions status
apple-gateway permissions status --json
```

Request prompt-capable permissions:

```bash
apple-gateway permissions request --domain calendar
apple-gateway permissions request --domain reminders
apple-gateway permissions request --domain notes
apple-gateway permissions request --domain notifications
```

Full Disk Access is manual. Enable the responsible terminal app, or the signed
`apple-gateway` app identity for background use, in System Settings > Privacy &
Security > Full Disk Access. The CLI also prints this deep link in permission
diagnostics:

```text
x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles
```

Notifications are posted through `AppleGatewayNotifier.app`, installed under
Homebrew `libexec` by the formula and cask packages. The first notification
request may prompt for notification authorization.

Clock alarms require the Shortcuts bridge package installed from
`packaging/shortcuts`. The default shortcuts are:

- `apple-gateway-get-alarms`
- `apple-gateway-create-alarm`
- `apple-gateway-toggle-alarm`
- `apple-gateway-update-alarm` on macOS 26+
- `apple-gateway-delete-alarm` on macOS 26+

Install or import the shortcuts in Shortcuts.app, keep their names aligned with
`clock_alarms.shortcut_prefix`, then verify with the non-mutating checker:

```bash
scripts/live-clock-alarms-check.sh
```

The detailed source build sheet is `packaging/shortcuts/SOURCE.md`. After the
shortcuts are installed, validate the read-only JSON contract with:

```bash
scripts/live-clock-alarms-check.sh --read-only
```

The permissions doctor also checks the exact expected bridge shortcut names for
the configured `clock_alarms.shortcut_prefix`. With the default prefix, it
expects `apple-gateway-get-alarms`, `apple-gateway-create-alarm`,
`apple-gateway-toggle-alarm`, plus `apple-gateway-update-alarm` and
`apple-gateway-delete-alarm` on macOS 26+. The JSON output includes
missing-shortcut detail; a different shortcut that only shares the prefix is not
sufficient.

```bash
apple-gateway permissions status --json
```
