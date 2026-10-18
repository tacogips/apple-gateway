# apple-gateway

macOS CLI and GraphQL bridge for Apple apps, including Calendar, Reminders,
Notes, Mail, notifications, Clock alarms, and iPhone cellular calls routed
through Phone or FaceTime.

## Development

```bash
mise install
mise run build
mise run test
swift run apple-gateway --help
```

The package uses Swift Package Manager with:

- Library target: `AppleGatewayCore`
- Executable targets: `AppleGatewayCLI`, `AppleGatewayReaderCLI`, and
  `AppleGatewayNotifier`
- Installed executables: `apple-gateway`, `apple-gateway-reader`, and the
  packaged `AppleGatewayNotifier.app` helper

## Client SDK (AppleGatewaySDK)

`AppleGatewayCore` exposes `AppleGatewaySDK`, a Swift façade backed by the
same GraphQL runtime as the CLI. The package pins the public `GatewaySDKKit`
release.

```swift
dependencies: [
  .package(url: "https://github.com/tacogips/gateway-sdk-kit.git", exact: "0.1.0")
]
// Target dependency: .product(name: "GatewaySDKKit", package: "gateway-sdk-kit")
```

```swift
import AppleGatewayCore
import GatewaySDKKit

let sdk = AppleGatewaySDK()
let catalog = sdk.catalog
let matches = try sdk.searchSchema("reminder")
let events = await sdk.invoke(
  GatewayOperationRequest(operation: "events", variables: ["input": .object([
    "startDate": .string("2026-01-01T00:00:00Z"),
    "endDate": .string("2026-01-01T01:00:00Z")
  ])]),
  environment: ["HOME": "/tmp"]
)
let raw = await sdk.execute(
  document: "{ permissions { calendars } }",
  variables: [:],
  environment: ["HOME": "/tmp"]
)
```

The reader-tier façade (`AppleGatewaySDK(role: .reader)`) cannot build named
mutations, and the runtime also rejects raw mutations. `execute` observes only
the environment dictionary supplied to it.

The CLI can search the same catalog or build an operation document without
interpolating GraphQL strings:

```bash
apple-gateway schema search reminder --kinds query,mutation --limit 10
apple-gateway graphql operation events --variables '{"input":{"startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-01T01:00:00Z","first":10}}'
apple-gateway graphql operation permissions --select calendars,reminders
```

`schema search reminder --limit 1` returns the exact-name catalog definition as
JSON, including match provenance and SDL:

```json
[{"kind":"query","matchedOn":["name","argument:reminderId","summary"],"name":"reminder","sdl":"type Query {\n  \"\"\"\n  reminder\n  \"\"\"\n  reminder(reminderId: ID!): Reminder\n}","tier":"reader"}]
```

## Homebrew Formula

Build local formula archives:

```bash
mise run build:homebrew -- darwin-arm64 darwin-x64
```

Render a formula after both platform archives exist:

```bash
mise run homebrew:formula -- 0.1.0
```

Render directly into the default sibling tap checkout:

```bash
mise run homebrew:tap-formula -- 0.1.0
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
mise run build:homebrew-cask -- --dry-run darwin-arm64 darwin-x64
```

Build with local signing credentials:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  mise run build:homebrew-cask -- darwin-arm64 darwin-x64
```

Render a Cask:

```bash
mise run homebrew:cask -- 0.1.0
```

For a tagged release, build, upload, and render the tap Cask:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  mise run release:homebrew-cask-local -- v0.1.0
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

Notes list queries filter, sort, and paginate lightweight metadata before
requesting shared state and attachment metadata from Notes.app. Only notes on
the selected page receive this detailed hydration, and an empty page performs
no detail request. If Notes.app cannot expose sharing or attachments for one
selected note, that note falls back to `isShared: false` or an empty attachment
list without discarding details for other notes. Automation denial, timeout,
application-unavailable, and stale page metadata remain request-level errors.

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
mise run install-virtual-audio-driver -- blackhole-2ch
```

The allowlisted Homebrew casks are `blackhole-2ch`, `blackhole-16ch`,
`blackhole-64ch`, `vb-cable`, and `loopback`. For example:

```bash
mise run install-virtual-audio-driver -- vb-cable
mise run install-virtual-audio-driver -- loopback
```

`mise run install-blackhole` remains a compatibility shortcut for BlackHole
2ch. Running `mise install` only provisions tools; the driver task checks for a compatible driver and prints the
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

### Notes body representations

The `note` query defaults to `bodyKind: PLAINTEXT`. Request `bodyKind: HTML` to read Notes HTML, including headings and lists:

```graphql
{
  note(noteId: "note-id", bodyKind: HTML) {
    id bodyHtml bodyFile { downloadKey kind byteSize }
  }
}
```

Only the requested representation is fetched. Large bodies return a `bodyFile` descriptor with the matching `HTML` or `PLAINTEXT` kind instead of an inline body. `noteFolders.parentFolderId` identifies the containing folder; top-level folders have a null parent.

### Import a Notes attachment

The full gateway supports `createNoteAttachment(input: {noteId, filePath}) { id name contentIdentifier downloadKey }`. The native Notes command copies source bytes into Notes storage and appends an attachment without replacing the note body. Supply an explicit canonical absolute path to a readable regular file, from 1 byte through 64 MiB, with no symlink components. The attachment keeps the source filename. Reader mode rejects this mutation.

The returned download key uses the existing best-effort attachment export path. Verify exported bytes when archival integrity matters. The mutation is not idempotent: callers must persist the returned attachment ID and reconcile existing attachments before retrying after uncertain completion. An HTML `file://` image source is not a substitute for native import.

### Notes folder creation and uncertain writes

The full gateway supports `createNoteFolder(input: {accountId, parentFolderId, name}) { id name accountId parentFolderId }`. Omit `parentFolderId` for an account root. Account IDs are explicit; a parent must belong to that account. Names are normalized to NFC and must be a single nonempty name without separators, control characters, surrounding whitespace, or more than 255 UTF-8 bytes. A unique existing name under the exact parent is returned; ambiguous matches fail. Newly created folder identity is verified by readback. This reuse check is not an atomic concurrency lock.

Notes, Mail and Clock mutations are never automatically repeated after an Apple Event timeout: the application may already have completed the write. Reconcile the current state before retrying an uncertain mutation. Read operations retain the configured timeout retry policy.

`updateNoteBody(mode: APPEND)` rejects notes with native attachments before reading or rewriting their body. Notes-exported image HTML can duplicate or degrade native attachments when assigned back, so it is not a durable attachment-preserving representation. Text-only APPEND is supported. REPLACE explicitly replaces the complete body; applications that own that body must retain validated source bytes and restore attachments through `createNoteAttachment`, then verify exported bytes. Attachment IDs and names may change after a body replacement.
