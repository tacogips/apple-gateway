import Foundation
import Testing
@testable import AppleGatewayCore

@Test func clockAlarmAdapterListsThroughStubShortcuts() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "list")
  let adapter = fixture.adapter()

  let alarms = try adapter.clockAlarms()

  #expect(alarms == [
    ClockAlarm(label: "Wake", time: "07:30", isEnabled: true, repeatDays: [.monday])
  ])
}

@Test func clockAlarmAdapterReportsMissingShortcut() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "missing")
  let adapter = fixture.adapter()

  do {
    _ = try adapter.createClockAlarm(CreateClockAlarmInput(time: "08:00", label: "Missing"))
    Issue.record("Expected missing shortcut")
  } catch let error as AppleGatewayError {
    #expect(error.code == .shortcutNotInstalled)
    #expect(error.details?["shortcut"] == "apple-gateway-create-alarm")
    #expect(error.details?["installGuide"] == "packaging/shortcuts/README.md")
  }
}

@Test func clockAlarmAdapterRejectsGarbageShortcutOutput() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "garbage")
  let adapter = fixture.adapter()

  do {
    _ = try adapter.clockAlarms()
    Issue.record("Expected invalid JSON")
  } catch let error as AppleGatewayError {
    #expect(error.code == .unexpectedError)
    #expect(error.message.contains("invalid JSON"))
  }
}

@Test func clockAlarmAdapterMapsNonzeroShortcutExit() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "nonzero")
  let adapter = fixture.adapter()

  do {
    _ = try adapter.clockAlarms()
    Issue.record("Expected nonzero shortcuts failure")
  } catch let error as AppleGatewayError {
    #expect(error.code == .shortcutActionUnsupported)
    #expect(error.details?["status"] == "42")
  }
}

@Test func clockAlarmAdapterRejectsAmbiguousLabelsBeforeMutation() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "ambiguous")
  let adapter = fixture.adapter()

  do {
    _ = try adapter.toggleClockAlarm(ToggleClockAlarmInput(label: "Wake", enabled: false))
    Issue.record("Expected ambiguous label")
  } catch let error as AppleGatewayError {
    #expect(error.code == .invalidArgument)
    #expect(error.message.contains("ambiguous"))
  }

  let log = try fixture.invocations()
  #expect(!log.contains("apple-gateway-toggle-alarm"))
}

@Test func clockAlarmAdapterTogglesAndVerifiesByRelisting() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "toggle")
  let adapter = fixture.adapter()

  let result = try adapter.toggleClockAlarm(ToggleClockAlarmInput(label: "Wake", enabled: false))

  #expect(result.success == true)
  #expect(result.alarm == ClockAlarm(label: "Wake", time: "07:30", isEnabled: false, repeatDays: [.monday]))
  #expect(result.warning == nil)
  let input = try fixture.lastInputPayload()
  #expect(input["contractVersion"] as? Int == 1)
  #expect((input["payload"] as? [String: Any])?["label"] as? String == "Wake")
  #expect((input["payload"] as? [String: Any])?["enabled"] as? Bool == false)
}

@Test func clockAlarmAdapterReturnsWarningWhenVerificationCannotConfirmMutation() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "inconclusive")
  let adapter = fixture.adapter()

  let result = try adapter.createClockAlarm(CreateClockAlarmInput(time: "08:00", label: "Focus"))

  #expect(result.success == true)
  #expect(result.alarm == nil)
  #expect(result.warning?.contains("could not be confirmed") == true)
}

@Test func clockAlarmAdapterGatesUpdateAndDeleteBeforeMacOS26() throws {
  let fixture = try ClockAlarmShortcutFixture(mode: "list")
  let adapter = fixture.adapter(osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 0))

  do {
    _ = try adapter.updateClockAlarm(UpdateClockAlarmInput(label: "Wake", time: "08:00"))
    Issue.record("Expected OS gate")
  } catch let error as AppleGatewayError {
    #expect(error.code == .unsupportedOSVersion)
  }

  do {
    _ = try adapter.deleteClockAlarm(DeleteClockAlarmInput(label: "Wake"))
    Issue.record("Expected OS gate")
  } catch let error as AppleGatewayError {
    #expect(error.code == .unsupportedOSVersion)
  }
}

private struct ClockAlarmShortcutFixture {
  let root: URL
  let executable: URL
  let invocationLog: URL
  let inputCapture: URL
  let state: URL
  let mode: String

  init(mode: String) throws {
    self.mode = mode
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-clock-alarm-tests")
      .appendingPathComponent(UUID().uuidString)
    executable = root.appendingPathComponent("shortcuts")
    invocationLog = root.appendingPathComponent("invocations.log")
    inputCapture = root.appendingPathComponent("last-input.json")
    state = root.appendingPathComponent("state")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "0".write(to: state, atomically: true, encoding: .utf8)
    try Self.stubSource.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
  }

  func adapter(
    osVersion: OperatingSystemVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
  ) -> LiveClockAlarmsAdapter {
    LiveClockAlarmsAdapter(
      config: .defaultValue,
      executor: SubprocessClockAlarmShortcutExecutor(
        shortcutsPath: executable.path,
        timeoutSeconds: 2,
        environment: [
          "APPLE_GATEWAY_CLOCK_STUB_MODE": mode,
          "APPLE_GATEWAY_CLOCK_STUB_LOG": invocationLog.path,
          "APPLE_GATEWAY_CLOCK_STUB_CAPTURE": inputCapture.path,
          "APPLE_GATEWAY_CLOCK_STUB_STATE": state.path,
          "PATH": "/usr/bin:/bin"
        ]
      ),
      osVersion: osVersion
    )
  }

  func invocations() throws -> String {
    guard FileManager.default.fileExists(atPath: invocationLog.path) else {
      return ""
    }
    return try String(contentsOf: invocationLog, encoding: .utf8)
  }

  func lastInputPayload() throws -> [String: Any] {
    let data = try Data(contentsOf: inputCapture)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private static let stubSource = """
  #!/usr/bin/env bash
  set -euo pipefail
  mode="${APPLE_GATEWAY_CLOCK_STUB_MODE:?}"
  log="${APPLE_GATEWAY_CLOCK_STUB_LOG:?}"
  capture="${APPLE_GATEWAY_CLOCK_STUB_CAPTURE:?}"
  state="${APPLE_GATEWAY_CLOCK_STUB_STATE:?}"
  printf '%s\\n' "$*" >> "$log"

  if [[ "${1:-}" == "list" ]]; then
    case "$mode" in
      missing)
        printf '%s\\n' "apple-gateway-get-alarms"
        ;;
      *)
        printf '%s\\n' "apple-gateway-get-alarms"
        printf '%s\\n' "apple-gateway-create-alarm"
        printf '%s\\n' "apple-gateway-toggle-alarm"
        printf '%s\\n' "apple-gateway-update-alarm"
        printf '%s\\n' "apple-gateway-delete-alarm"
        ;;
    esac
    exit 0
  fi

  shortcut="${2:-}"
  output=""
  input=""
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-path)
        output="$2"
        shift 2
        ;;
      --input-path)
        input="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -n "$input" ]]; then
    cp "$input" "$capture"
  fi

  if [[ "$mode" == "nonzero" ]]; then
    printf '%s\\n' "forced failure" >&2
    exit 42
  fi

  if [[ "$shortcut" == "apple-gateway-toggle-alarm" ]]; then
    printf '%s' "1" > "$state"
    exit 0
  fi

  if [[ "$shortcut" == "apple-gateway-create-alarm" ]]; then
    printf '%s' "1" > "$state"
    exit 0
  fi

  if [[ "$shortcut" != "apple-gateway-get-alarms" ]]; then
    exit 0
  fi

  case "$mode" in
    garbage)
      printf '%s' "not-json" > "$output"
      ;;
    ambiguous)
      printf '%s\\n' '{"contractVersion":1,"alarms":[{"label":"Wake","time":"07:30","isEnabled":true,"repeatDays":[]},{"label":"Wake","time":"08:00","isEnabled":false,"repeatDays":[]}]}' > "$output"
      ;;
    toggle)
      if [[ "$(cat "$state")" == "0" ]]; then
        printf '%s\\n' '{"contractVersion":1,"alarms":[{"label":"Wake","time":"07:30","isEnabled":true,"repeatDays":["MONDAY"]}]}' > "$output"
      else
        printf '%s\\n' '{"contractVersion":1,"alarms":[{"label":"Wake","time":"07:30","isEnabled":false,"repeatDays":["MONDAY"]}]}' > "$output"
      fi
      ;;
    inconclusive)
      printf '%s\\n' '{"contractVersion":1,"alarms":[]}' > "$output"
      ;;
    *)
      printf '%s\\n' '{"contractVersion":1,"alarms":[{"label":"Wake","time":"07:30","isEnabled":true,"repeatDays":["MONDAY"]}]}' > "$output"
      ;;
  esac
  """
}
