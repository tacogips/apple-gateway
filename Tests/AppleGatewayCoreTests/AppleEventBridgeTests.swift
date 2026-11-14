import Foundation
import Testing
@testable import AppleGatewayCore

@Test func appleEventBridgeRunsJXAWithJSONArguments() throws {
  let fixture = try StubOsascriptFixture(mode: "success")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  let data = try bridge.runJXA(script: "return JSON.stringify({ok: true})", argumentsJSON: #"{"name":"Notes"}"#)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

  #expect(object["ok"] as? Bool == true)
  #expect(try fixture.capturedArguments() == [
    "-l",
    "JavaScript",
    "-e",
    "return JSON.stringify({ok: true})",
    #"{"name":"Notes"}"#
  ])
}

@Test func appleEventBridgeRetriesAppleEventTimeoutThenFails() throws {
  let fixture = try StubOsascriptFixture(mode: "timeout-always")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
    Issue.record("Expected timeout")
  } catch AppleEventBridgeError.timeout(let message) {
    #expect(message.contains("-1712"))
    #expect(try fixture.invocationCount() == 2)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func appleEventBridgeRetriesAppleEventTimeoutThenSucceeds() throws {
  let fixture = try StubOsascriptFixture(mode: "timeout-once")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  let data = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

  #expect(object["retried"] as? Bool == true)
  #expect(try fixture.invocationCount() == 2)
}

@Test func appleEventBridgeClassifiesPermissionDeniedStderr() throws {
  let fixture = try StubOsascriptFixture(mode: "denied")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
    Issue.record("Expected automationDenied")
  } catch AppleEventBridgeError.automationDenied(let message) {
    #expect(message.contains("-1743"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func appleEventBridgeClassifiesConnectionInvalidStderrAsAppUnavailable() throws {
  let fixture = try StubOsascriptFixture(mode: "connection-invalid")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
    Issue.record("Expected appUnavailable")
  } catch AppleEventBridgeError.appUnavailable(let message) {
    #expect(message.contains("-609"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func appleEventBridgeRejectsGarbageOutput() throws {
  let fixture = try StubOsascriptFixture(mode: "garbage")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
    Issue.record("Expected scriptFailure")
  } catch AppleEventBridgeError.scriptFailure(let message) {
    #expect(message.contains("non-JSON"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test func appleEventBridgeDrainsLargeOutputWithoutPipeDeadlock() throws {
  let fixture = try StubOsascriptFixture(mode: "large-output")
  let bridge = AppleEventBridge(
    osascriptPath: fixture.executablePath,
    timeoutSeconds: 5,
    environment: fixture.environment,
    maxTimeoutRetries: 0
  )

  let data = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let value = try #require(object["value"] as? String)

  #expect(value.count == 200_000)
}

@Test func appleEventBridgeUsesPrivateCaptureFilesAndCleansThemUp() throws {
  let fixture = try StubOsascriptFixture(mode: "capture-permissions")
  let bridge = AppleEventBridge(
    osascriptPath: fixture.executablePath,
    environment: fixture.environment,
    temporaryDirectory: fixture.root
  )

  let data = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

  #expect(object["stdoutMode"] == "600")
  #expect(object["stderrMode"] == "600")
  #expect(try fixture.captureDirectories().isEmpty)
}

@Test func appleEventBridgeHardStopsProcessThatIgnoresTermination() throws {
  let fixture = try StubOsascriptFixture(mode: "ignore-term")
  let bridge = AppleEventBridge(
    osascriptPath: fixture.executablePath,
    timeoutSeconds: 0.05,
    environment: fixture.environment,
    maxTimeoutRetries: 0,
    terminationGraceSeconds: 0.05,
    temporaryDirectory: fixture.root
  )
  let startedAt = Date()

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: #"{"ok":true}"#)
    Issue.record("Expected hard timeout")
  } catch AppleEventBridgeError.timeout {
    #expect(Date().timeIntervalSince(startedAt) < 2)
    #expect(try fixture.captureDirectories().isEmpty)
  }
}

@Test func liveNotesSummaryArgumentsHonorBatchSize() throws {
  let fixture = try StubOsascriptFixture(mode: "summary-array-max-two")
  let adapter = LiveNotesAppleEventAdapter(bridge: AppleEventBridge(
    osascriptPath: fixture.executablePath,
    environment: fixture.environment
  ))

  let notes = try adapter.noteMetadataSummaries(
    noteIds: ["note-1", "note-2", "note-3", "note-4", "note-5"],
    batchSize: 2
  )

  #expect(notes.isEmpty)
  #expect(try fixture.invocationCount() == 3)
}

@Test func appleEventBridgeKeepsUserPayloadOutOfScriptSource() throws {
  let fixture = try StubOsascriptFixture(mode: "success")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)
  let script = "const input = JSON.parse(arguments[0]); JSON.stringify(input);"
  let payload = #"{"query":"\"quoted\" and backslash \\ payload"}"#

  _ = try bridge.runJXA(script: script, argumentsJSON: payload)
  let arguments = try fixture.capturedArguments()

  #expect(arguments[3] == script)
  #expect(arguments[4] == payload)
  #expect(!arguments[3].contains(#"\"quoted\""#))
  #expect(arguments[4].contains(#"\\"#))
}

@Test func appleEventBridgeRejectsInvalidArgumentsJSONBeforeLaunch() throws {
  let fixture = try StubOsascriptFixture(mode: "success")
  let bridge = AppleEventBridge(osascriptPath: fixture.executablePath, environment: fixture.environment)

  do {
    _ = try bridge.runJXA(script: "static script", argumentsJSON: "{")
    Issue.record("Expected invalid arguments JSON")
  } catch AppleEventBridgeError.invalidArgumentsJSON {
    #expect(try fixture.invocationCount() == 0)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private struct StubOsascriptFixture {
  let root: URL
  let executablePath: String
  let capturePath: String
  let countPath: String
  let environment: [String: String]

  init(mode: String) throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-gateway-osascript-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let executable = root.appendingPathComponent("osascript-stub")
    capturePath = root.appendingPathComponent("argv.txt").path
    countPath = root.appendingPathComponent("count.txt").path
    executablePath = executable.path
    try Self.stubSource.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    environment = [
      "APPLE_GATEWAY_STUB_MODE": mode,
      "APPLE_GATEWAY_STUB_CAPTURE": capturePath,
      "APPLE_GATEWAY_STUB_COUNT": countPath,
      "PATH": "/usr/bin:/bin"
    ]
  }

  func capturedArguments() throws -> [String] {
    let contents = try String(contentsOfFile: capturePath, encoding: .utf8)
    return contents.split(separator: "\n").map(String.init)
  }

  func invocationCount() throws -> Int {
    guard FileManager.default.fileExists(atPath: countPath) else {
      return 0
    }
    let contents = try String(contentsOfFile: countPath, encoding: .utf8)
    return Int(contents.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
  }

  func captureDirectories() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("apple-gateway-osascript-") }
  }

  private static let stubSource = """
  #!/usr/bin/env bash
  set -euo pipefail
  mode="${APPLE_GATEWAY_STUB_MODE:-success}"
  capture="${APPLE_GATEWAY_STUB_CAPTURE:?}"
  count_file="${APPLE_GATEWAY_STUB_COUNT:?}"
  count=0
  if [[ -f "$count_file" ]]; then
    count="$(cat "$count_file")"
  fi
  count=$((count + 1))
  printf '%s\\n' "$count" > "$count_file"
  printf '%s\\n' "$@" > "$capture"

  case "$mode" in
    success)
      printf '{"ok":true}\\n'
      ;;
    timeout-always)
      printf 'execution error: AppleEvent timed out. (-1712)\\n' >&2
      exit 1
      ;;
    timeout-once)
      if [[ "$count" -eq 1 ]]; then
        printf 'execution error: AppleEvent timed out. (-1712)\\n' >&2
        exit 1
      fi
      printf '{"retried":true}\\n'
      ;;
    denied)
      printf 'execution error: Not authorized to send Apple events. (-1743)\\n' >&2
      exit 1
      ;;
    connection-invalid)
      printf 'execution error: Connection is invalid. (-609)\\n' >&2
      exit 1
      ;;
    garbage)
      printf 'not json\\n'
      ;;
    large-output)
      /usr/bin/awk 'BEGIN {
        printf "{\\\"value\\\":\\\""
        for (i = 0; i < 200000; i += 1) {
          printf "x"
        }
        printf "\\\"}\\n"
      }'
      ;;
    capture-permissions)
      stdout_path="$(/usr/sbin/lsof -a -p "$$" -d 1 -Fn | /usr/bin/sed -n 's/^n//p')"
      stderr_path="$(/usr/sbin/lsof -a -p "$$" -d 2 -Fn | /usr/bin/sed -n 's/^n//p')"
      stdout_mode="$(/usr/bin/stat -f '%Lp' "$stdout_path")"
      stderr_mode="$(/usr/bin/stat -f '%Lp' "$stderr_path")"
      printf '{"stdoutMode":"%s","stderrMode":"%s"}\\n' "$stdout_mode" "$stderr_mode"
      ;;
    ignore-term)
      trap '' TERM
      while true; do
        :
      done
      ;;
    summary-array-max-two)
      note_count="$(printf '%s' "${5:-}" | /usr/bin/grep -o 'note-' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
      if [[ "$note_count" -gt 2 ]]; then
        printf 'summary batch contained %s note ids\\n' "$note_count" >&2
        exit 2
      fi
      printf '[]\\n'
      ;;
    *)
      printf 'unknown stub mode: %s\\n' "$mode" >&2
      exit 2
      ;;
  esac
  """
}
