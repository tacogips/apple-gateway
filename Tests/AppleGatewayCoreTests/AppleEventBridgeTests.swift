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
    garbage)
      printf 'not json\\n'
      ;;
    *)
      printf 'unknown stub mode: %s\\n' "$mode" >&2
      exit 2
      ;;
  esac
  """
}
