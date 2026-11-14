# Phone Call Bridge Design

## Goal

Allow the full `apple-gateway` executable, and therefore an explicitly
authorized Codex workflow, to hand a telephone call to the Mac's Phone or
FaceTime app and to operate visible incoming/in-call controls.

The cellular leg remains owned by Apple's iPhone Cellular Calls feature.
`apple-gateway` never talks to a carrier, implements a softphone, or accesses
the iPhone radio directly.

## Platform Boundary

The implementation deliberately separates supported APIs from UI automation:

| Capability | Mechanism | Reliability |
| --- | --- | --- |
| Resolve a saved contact | Contacts framework | Supported |
| Hand a number to Phone/FaceTime | `tel:` URL via `NSWorkspace` | Supported; macOS may require visible confirmation |
| Inspect incoming/active controls | Accessibility API | Best effort |
| Answer, decline, or end | Accessibility `AXPress` on a semantically matched control | Best effort |

Apple does not publish a macOS API that lets a third-party CLI accept or end
an iPhone Cellular Calls session. The GraphQL result therefore includes a
`warning` field, and the implementation does not claim that an Accessibility
action is a stable call-control contract.

Accessibility matching is constrained to Phone, FaceTime, and call-related
Notification Center content. It uses known accessibility identifiers first
and exact English/Japanese visible labels second. It never clicks a positional
button or an arbitrary first button.

## Permissions

Calling a raw number only needs macOS to accept the `tel:` URL. Calling by
contact name requires Contacts permission. Status inspection and
answer/decline/end require Accessibility permission.

```bash
apple-gateway permissions request --domain phone-calls
apple-gateway permissions status
```

The request path asks for Contacts and Accessibility. Status reports the two
parts separately as `phoneContacts` and `phoneAutomation`. GraphQL status
queries never prompt.

The iPhone and Mac must already satisfy Apple's iPhone Cellular Calls setup:
the same Apple Account, Wi-Fi enabled, Calls from iPhone enabled, and an active
iPhone cellular plan. On systems with the Phone app, `tel:` is handled there;
older supported macOS versions may route it to FaceTime.

## GraphQL API

The reader executable exposes status only. The full executable additionally
exposes mutations:

```graphql
query {
  phoneCallStatus {
    state
    callerName
    callerNumber
    application
    warning
  }
}

mutation {
  placePhoneCall(input: {
    contactName: "Example Person"
    phoneLabel: "mobile"
    autoConfirm: true
  }) {
    success
    state
    targetName
    application
    warning
  }
}

mutation {
  answerPhoneCall {
    success
    state
    application
    warning
  }
}
```

`placePhoneCall` accepts exactly one of `contactName` or `phoneNumber`.
`phoneLabel` is used only with a contact. If a contact has multiple numbers,
the caller must select an unambiguous label. Ambiguous contact names and
labels fail without dialing. `autoConfirm` defaults to `false`; when set to
`true`, the gateway waits briefly for an exact outgoing Call control in Phone
or FaceTime and presses it through Accessibility. If no matching control
appears, the result warning states that the call may already be dialing or may
still need manual confirmation.

Additional call-control mutations are `declinePhoneCall` and
`endPhoneCall`.

## Virtual Audio File Playback

`playAudioToPhoneCall` streams a local audio file to a virtual Core Audio
device. `stopPhoneCallAudio` terminates the player and restores the microphone:

```graphql
mutation {
  playAudioToPhoneCall(input: { filePath: "/absolute/path/prompt.wav" }) {
    success
    isPlaying
    filePath
    deviceName
    warning
  }
}

mutation {
  stopPhoneCallAudio {
    success
    isPlaying
  }
}
```

The virtual audio driver is not bundled or installed automatically by
apple-gateway. The implementation detects BlackHole, Loopback, and VB-Cable
devices. If more than one candidate exists, configure the exact Core Audio UID:

```bash
# Explicit Darwin setup; BlackHole 2ch is the recommended default.
nix run .#install-virtual-audio-driver -- blackhole-2ch
```

The allowlisted Homebrew casks are `blackhole-2ch`, `blackhole-16ch`,
`blackhole-64ch`, `vb-cable`, and `loopback`. The compatibility command
`nix run .#install-blackhole` installs BlackHole 2ch. The default development
shell performs only a read-only availability check and prints the generic
installer command when no compatible driver is found.

```toml
[phone_calls]
virtual_audio_device_uid = "BlackHole2ch_UID"
```

Playback uses a detached internal helper so it continues after the GraphQL CLI
request exits. The helper sends decoded audio directly to the selected Core
Audio output device, while the gateway changes the macOS default input to the
same loopback device. It does not change the default speaker output.

Phone or FaceTime must use the system microphone rather than a pinned physical
microphone. The prior default input device is stored under
`storage.cache_dir/phone-audio/session.json` and restored when playback ends or
`stopPhoneCallAudio` runs. A crash or forced machine shutdown can leave the
virtual device selected; in that case, select the desired microphone again in
System Settings.

Supported file formats are those decoded by `AVAudioFile`, such as common WAV,
AIFF, CAF, and compatible compressed formats. Only one file can play at a time.
The gateway does not mix the file with the physical microphone.

## Caller Audio Input and Barge-In

Caller audio capture is provider-neutral. Configure a distinct Core Audio input
device that receives Phone or FaceTime output:

```toml
[phone_calls]
virtual_audio_device_uid = "BlackHole2ch_UID"
capture_audio_device_uid = "LoopbackCapture_UID"
```

Loopback can create an application-specific device whose source is FaceTime or
Phone while continuing to monitor the audio through speakers. With BlackHole or
VB-Cable, create the equivalent system routing or multi-output arrangement.
The transmit and capture devices should be separate to avoid feeding agent
speech back into caller-speech detection.

`startPhoneCallListening` launches a detached AVAudioEngine input listener. It
splits the configured device input into 1–30 second WAV windows, with five
seconds as the intended polling interval. Windows without speech are deleted.
Windows containing speech are retained under
`storage.cache_dir/phone-listener/chunks` and announced through
`phoneCallAudioInputEvents(afterSequence:)`. Starting a new listening session
clears the prior session's event log and chunk files.

Voice activity detection runs on each audio buffer rather than waiting for a
window to finish. When speech crosses the local threshold, an active
`playAudioToPhoneCall` helper is terminated and the previous system microphone
is restored. The event's `interruptedPlayback` field records whether this
barge-in occurred. This makes interruption responsive even though STT and agent
processing happen after a bounded audio window completes.

The gateway does not perform STT, invoke Codex, retain an LLM conversation, or
generate TTS. It exposes local WAV paths and call/audio controls so Riela or
another orchestrator can supply those policies and providers.

The orchestrator is responsible for caller disclosure, consent, retention, and
deletion policies required for recording or transcription.

## Codex Sample Bridge

`scripts/sample-phone-call-codex-bridge.sh` is an optional end-to-end sample,
not part of the gateway runtime. It:

1. Starts five-second caller-audio capture.
2. Polls `phoneCallAudioInputEvents`.
3. Sends each WAV event to the OpenAI transcription endpoint.
4. Sends the transcript and conversation history to `codex exec`.
5. Generates a WAV response through OpenAI TTS.
6. Calls `playAudioToPhoneCall`.

The sample requires `OPENAI_API_KEY`, `curl`, `jq`, Codex authentication, and an
already active call. It never auto-answers or chooses a callee. A Riela
integration can replace the sample while preserving the same GraphQL boundary.
