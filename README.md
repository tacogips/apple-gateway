# apple-gateway

macOS CLI and GraphQL bridge for Apple apps, including Calendar, Reminders,
Notes, Mail, notifications, Clock alarms, and iPhone cellular calls routed
through Phone or FaceTime.

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
apple-gateway permissions request --domain mail
apple-gateway permissions request --domain notifications
apple-gateway permissions request --domain phone-calls
```

Full Disk Access is manual. Enable the responsible terminal app, or the signed
`apple-gateway` app identity for background use, in System Settings > Privacy &
Security > Full Disk Access. The CLI also prints this deep link in permission
diagnostics:

```text
x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles
```

Mail queries remain read-only at the local database layer. The full
`apple-gateway` executable can mark messages read or flagged, move them, and
delete them through Mail.app automation; `apple-gateway-reader` exposes no
mutations. Inspect the exact mutation names and inputs with:

```bash
apple-gateway schema print
```

Notifications are posted through `AppleGatewayNotifier.app`, installed under
Homebrew `libexec` by the formula and cask packages. The first notification
request may prompt for notification authorization.

Clock alarms are controlled directly through Clock.app accessibility
automation. No Shortcuts assets or setup are required. Grant the terminal or
installed `apple-gateway` identity access under System Settings > Privacy &
Security > Accessibility and Automation, or request the permissions from the
CLI:

```bash
apple-gateway permissions request --domain clock-alarms
```

Run a non-mutating live check, or exercise the complete create/toggle/update/
delete flow with an automatically cleaned-up scratch alarm:

```bash
scripts/live-clock-alarms-check.sh
scripts/live-clock-alarms-check.sh --execute
```

Phone calls use Apple's existing iPhone Cellular Calls setup. Outgoing calls
are handed to Phone/FaceTime with a `tel:` URL; macOS may still show a
confirmation. Calling by saved contact name uses Contacts, while answering,
declining, and ending use explicitly best-effort Accessibility automation:

```bash
apple-gateway graphql --query 'mutation {
  placePhoneCall(input: {
    contactName: "Example Person"
    phoneLabel: "mobile"
    autoConfirm: true
  }) {
    success state targetName warning
  }
}'

apple-gateway graphql --query 'mutation {
  answerPhoneCall { success state application warning }
}'
```

Audio files can be routed into an active call through a user-installed virtual
audio device such as BlackHole 2ch. Phone or FaceTime must be configured to use
the system microphone:

```bash
# Darwin only; BlackHole 2ch is the recommended default.
nix run .#install-virtual-audio-driver -- blackhole-2ch
```

The allowlisted Homebrew casks are `blackhole-2ch`, `blackhole-16ch`,
`blackhole-64ch`, `vb-cable`, and `loopback`. For example:

```bash
nix run .#install-virtual-audio-driver -- vb-cable
nix run .#install-virtual-audio-driver -- loopback
```

`nix run .#install-blackhole` remains a compatibility shortcut for BlackHole
2ch. Entering `nix develop` only checks for a compatible driver and prints the
generic command when one is missing; it never installs or modifies host audio
drivers automatically.

```toml
[phone_calls]
# Optional when exactly one BlackHole/Loopback/VB-Cable device is installed.
virtual_audio_device_uid = "BlackHole2ch_UID"
# Required for caller-audio capture. Route Phone/FaceTime output into this device.
capture_audio_device_uid = "LoopbackCapture_UID"
```

```bash
apple-gateway graphql --query 'mutation {
  playAudioToPhoneCall(input: { filePath: "/absolute/path/prompt.wav" }) {
    success isPlaying filePath deviceName warning
  }
}'

apple-gateway graphql --query 'mutation {
  stopPhoneCallAudio { success isPlaying }
}'
```

Caller audio can be captured as provider-neutral WAV events in five-second
windows. The listener performs local voice activity detection. When caller
speech starts while gateway audio is playing, it stops that playback
immediately; the completed window then appears in `phoneCallAudioInputEvents`:
Notify callers and obtain any consent required for call recording or
transcription in the relevant jurisdiction.

```bash
apple-gateway graphql --query 'mutation {
  startPhoneCallListening(input: { chunkDurationSeconds: 5 }) {
    success isListening deviceName warning
  }
}'

apple-gateway graphql --query '{
  phoneCallAudioInputEvents(afterSequence: 0) {
    sequence filePath createdAt durationSeconds interruptedPlayback
  }
}'
```

apple-gateway does not transcribe audio or call an LLM. Riela, Codex, or another
consumer owns polling, STT, reasoning, and TTS. A standalone integration sample
is available at `scripts/sample-phone-call-codex-bridge.sh`; it uses OpenAI STT
and TTS plus `codex exec` without introducing those dependencies into the
gateway:

```bash
OPENAI_API_KEY=... scripts/sample-phone-call-codex-bridge.sh
```

See `design-docs/specs/design-phone-calls.md` for setup, reliability limits,
raw-number use, status checks, and the Codex integration boundary.

```bash
apple-gateway permissions status --json
```
