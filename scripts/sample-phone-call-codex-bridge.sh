#!/usr/bin/env bash
set -euo pipefail

apple_gateway_bin="${APPLE_GATEWAY_BIN:-apple-gateway}"
codex_bin="${CODEX_BIN:-codex}"
config_path="${APPLE_GATEWAY_CONFIG:-}"
stt_model="${OPENAI_STT_MODEL:-gpt-4o-mini-transcribe}"
tts_model="${OPENAI_TTS_MODEL:-tts-1}"
tts_voice="${OPENAI_TTS_VOICE:-alloy}"
codex_workdir="${CODEX_WORKDIR:-$(pwd)}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required by this sample bridge." >&2
  exit 1
fi

for command_name in "$apple_gateway_bin" "$codex_bin" curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

bridge_parent="${TMPDIR:-/tmp}"
bridge_parent="${bridge_parent%/}"
bridge_dir="$(mktemp -d "$bridge_parent/apple-gateway-codex-bridge.XXXXXX")"
history_file="$bridge_dir/history.txt"
response_file="$bridge_dir/codex-response.txt"
tts_file="$bridge_dir/codex-response.wav"
touch "$history_file"

gateway() {
  if [[ -n "$config_path" ]]; then
    "$apple_gateway_bin" --config "$config_path" "$@"
  else
    "$apple_gateway_bin" "$@"
  fi
}

stop_listener() {
  gateway graphql \
    --query 'mutation { stopPhoneCallListening { success } }' \
    >/dev/null 2>&1 || true
  if [[ "$bridge_dir" == "$bridge_parent"/apple-gateway-codex-bridge.* ]]; then
    find "$bridge_dir" -depth -delete
  fi
}
trap stop_listener EXIT INT TERM

gateway graphql \
  --query 'mutation {
    startPhoneCallListening(input: { chunkDurationSeconds: 5 }) {
      success isListening deviceName warning
    }
  }' \
  --pretty

last_sequence=0
echo "Codex phone-call sample bridge is listening. Press Ctrl-C to stop."

while true; do
  variables="$(jq -cn --argjson after "$last_sequence" '{after: $after}')"
  event_response="$(
    # shellcheck disable=SC2016
    gateway graphql \
      --query 'query($after: Int) {
        phoneCallAudioInputEvents(afterSequence: $after) {
          sequence filePath createdAt durationSeconds interruptedPlayback
        }
      }' \
      --variables "$variables"
  )"

  while IFS= read -r event; do
    sequence="$(jq -r '.sequence' <<<"$event")"
    audio_file="$(jq -r '.filePath' <<<"$event")"
    last_sequence="$sequence"

    if [[ ! -f "$audio_file" ]]; then
      echo "Skipping missing audio chunk: $audio_file" >&2
      continue
    fi

    transcript_response="$(
      curl --silent --show-error --fail-with-body \
        https://api.openai.com/v1/audio/transcriptions \
        --header "Authorization: Bearer $OPENAI_API_KEY" \
        --form "model=$stt_model" \
        --form "file=@$audio_file"
    )"
    user_text="$(jq -r '.text // empty' <<<"$transcript_response")"
    if [[ -z "$user_text" ]]; then
      continue
    fi

    printf 'User: %s\n' "$user_text" >>"$history_file"
    prompt="$(
      printf '%s\n\n%s\n' \
        "You are answering a live phone call. Reply in concise spoken plain text without Markdown. Use the conversation transcript below and answer the latest user message." \
        "$(<"$history_file")"
    )"
    "$codex_bin" exec \
      --ephemeral \
      --sandbox read-only \
      --skip-git-repo-check \
      --cd "$codex_workdir" \
      --output-last-message "$response_file" \
      "$prompt" \
      >/dev/null

    agent_text="$(<"$response_file")"
    printf 'Agent: %s\n' "$agent_text" >>"$history_file"
    speech_request="$(
      jq -cn \
        --arg model "$tts_model" \
        --arg voice "$tts_voice" \
        --arg input "$agent_text" \
        '{model: $model, voice: $voice, input: $input, response_format: "wav"}'
    )"
    curl --silent --show-error --fail-with-body \
      https://api.openai.com/v1/audio/speech \
      --header "Authorization: Bearer $OPENAI_API_KEY" \
      --header "Content-Type: application/json" \
      --data "$speech_request" \
      --output "$tts_file"

    play_variables="$(jq -cn --arg filePath "$tts_file" '{input: {filePath: $filePath}}')"
    # shellcheck disable=SC2016
    gateway graphql \
      --query 'mutation($input: PlayPhoneCallAudioInput!) {
        playAudioToPhoneCall(input: $input) { success isPlaying warning }
      }' \
      --variables "$play_variables" \
      >/dev/null
  done < <(jq -c '.data.phoneCallAudioInputEvents[]?' <<<"$event_response")

  sleep 1
done
