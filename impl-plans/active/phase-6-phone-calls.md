# Phase 6: Phone Calls

## Scope

- Add a phone-call GraphQL domain for status, placement, answer, decline, and
  end operations.
- Resolve saved contacts through Contacts with ambiguity checks.
- Route outgoing calls with `tel:`.
- Constrain best-effort Accessibility controls to Phone, FaceTime, and
  call-related Notification Center UI.
- Add Contacts and Accessibility permission reporting/request support.
- Preserve reader-mode mutation exclusion.
- Route local audio files through a configured virtual Core Audio device with
  explicit play/stop mutations and microphone restoration.
- Capture caller audio from a separately configured Core Audio input into
  provider-neutral WAV events, with local voice activity detection and
  playback interruption.
- Keep STT, LLM orchestration, and TTS outside apple-gateway; provide an
  optional Codex/OpenAI sample bridge for integration verification.
- Document the public-API and UI-automation reliability boundary.

## Verification

- Unit-test target validation, number normalization, contact delegation, and
  call-control delegation.
- GraphQL-test schema role separation and every operation.
- Run SwiftLint, `swift test`, `swift run AppleGatewaySmokeTests`, and
  `swift build`.

## Follow-up Boundary

Incoming-call auto-answer policy is intentionally not part of this phase. The
audio listener starts only through an explicit mutation and does not choose or
accept calls.
