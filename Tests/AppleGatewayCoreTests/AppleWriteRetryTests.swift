import Foundation
import Testing
@testable import AppleGatewayCore

@Test func writeRetryUsesBoundedBackoffAndCountsRetriesAfterInitialAttempt() throws {
  var delays: [TimeInterval] = []
  var calls = 0
  let retry = AppleWriteRetry(policy: .init(initialWaitSeconds: 20, maxRetries: 5), sleep: { delays.append($0) })
  let result = try retry.run {
    calls += 1
    if calls <= 5 {
      throw AppleWriteAttemptFailure(error: .init(code: .appleEventTimeout, message: "preflight"), definitelyNotDispatched: true, transient: true)
    }
    return "created-once"
  }
  #expect(result == "created-once")
  #expect(calls == 6)
  #expect(delays == [20, 40, 60, 60, 60])
}

@Test func writeRetryNeverRepeatsAmbiguousOrTerminalWrites() throws {
  for failure in [
    AppleWriteAttemptFailure(error: .init(code: .appleEventTimeout, message: "after dispatch"), definitelyNotDispatched: false, transient: true),
    AppleWriteAttemptFailure(error: .init(code: .automationDenied, message: "denied"), definitelyNotDispatched: true, transient: false)
  ] {
    var calls = 0
    let retry = AppleWriteRetry(sleep: { _ in Issue.record("Unexpected sleep") })
    do {
      try retry.run { calls += 1; throw failure }
      Issue.record("Expected failure")
    } catch let error as AppleGatewayError {
      #expect(error.details?["writeAttempts"] == "1")
      #expect(error.details?["retrySafe"] == "false")
      #expect(error.details?["writeOutcome"] == (failure.definitelyNotDispatched ? "notDispatched" : "unknown"))
    }
    #expect(calls == 1)
  }
}

@Test func writeRetryDoesNotInferSafetyFromErrorCodeOrProviderDetails() throws {
  var calls = 0
  let retry = AppleWriteRetry(sleep: { _ in Issue.record("Unexpected sleep") })
  do {
    try retry.run {
      calls += 1
      throw AppleGatewayError(code: .appleEventTimeout, message: "transient", details: ["retrySafe": "true", "writeOutcome": "notDispatched"])
    }
  } catch let error as AppleGatewayError {
    #expect(error.details?["writeOutcome"] == "unknown")
    #expect(error.details?["retrySafe"] == "false")
  }
  #expect(calls == 1)
}

@Test func writeRetryZeroDisablesAndExhaustionReportsAttempts() throws {
  for maximum in [0, 3] {
    var calls = 0
    var waits = 0
    do {
      try AppleWriteRetry(policy: .init(maxRetries: maximum), sleep: { _ in waits += 1 }).run {
        calls += 1
        throw AppleWriteAttemptFailure(error: .init(code: .appleEventTimeout, message: "preflight"), definitelyNotDispatched: true, transient: true)
      }
    } catch let error as AppleGatewayError {
      #expect(error.details?["writeAttempts"] == String(maximum + 1))
      #expect(error.details?["writeOutcome"] == "notDispatched")
    }
    #expect(calls == maximum + 1)
    #expect(waits == maximum)
  }
}

@Test func writeRetryReadbackNeverReplaysConfirmedWrite() throws {
  var writes = 0
  var reads = 0
  let retry = AppleWriteRetry(sleep: { _ in })
  let id = try retry.run { writes += 1; return "stable-id" }
  let value = try retry.readback(id: id) {
    reads += 1
    if reads < 3 { throw AppleEventBridgeError.timeout(message: "read only") }
    return id
  }
  #expect(value == id)
  #expect(writes == 1)
  #expect(reads == 3)
  do {
    _ = try retry.readback(id: id) { throw AppleEventBridgeError.timeout(message: "read only") }
  } catch let error as AppleGatewayError {
    #expect(error.details?["writeOutcome"] == "confirmed")
    #expect(error.details?["resourceId"] == id)
    #expect(error.details?["readbackAttempts"] == "4")
  }
  #expect(writes == 1)
}

@Test func writeRetryConfigDefaultsBoundsAndEnvironment() throws {
  let resolver = AppleGatewayConfigResolver()
  let environment = ["HOME": "/nonexistent-apple-gateway-write-retry-test"]
  #expect(try resolver.resolve(environment: environment).config.writeRetry == .init(initialWaitSeconds: 2, maxRetries: 3))
  var overrides = environment
  overrides["APPLE_GATEWAY_WRITE_RETRY_INITIAL_WAIT_SECONDS"] = "60"
  overrides["APPLE_GATEWAY_WRITE_RETRY_MAX_RETRIES"] = "0"
  #expect(try resolver.resolve(environment: overrides).config.writeRetry == .init(initialWaitSeconds: 60, maxRetries: 0))
  for (key, value) in [
    ("INITIAL_WAIT_SECONDS", "0"), ("INITIAL_WAIT_SECONDS", "61"),
    ("MAX_RETRIES", "-1"), ("MAX_RETRIES", "6"), ("MAX_RETRIES", "1.5")
  ] {
    var invalid = environment
    invalid["APPLE_GATEWAY_WRITE_RETRY_" + key] = value
    #expect(throws: AppleGatewayConfigError.self) { try resolver.resolve(environment: invalid) }
  }
}

@Test func writeRetryOldConfigDecodesWithDefaults() throws {
  let encoded = try JSONEncoder().encode(AppleGatewayConfig.defaultValue)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object.removeValue(forKey: "write_retry")
  let decoded = try JSONDecoder().decode(AppleGatewayConfig.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(decoded.writeRetry == .defaultValue)
}

@Test func writeJXAEnvelopeTracksPreflightAndDispatchedFailuresWithoutAppleApps() throws {
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  for started in [false, true] {
    let script = """
    function run(argv) {
      \(started ? "appleGatewayWillWrite();" : "")
      const failure = new Error('fixture timeout'); failure.errorNumber = -1712; throw failure;
    }
    """
    // Execute only fixture JavaScript: no Application, ObjC or provider calls.
    let data = try bridge.runJXA(script: AppleWriteJXA.source(script, tracksDispatch: true), argumentsJSON: "{}")
    do {
      try AppleWriteJXA.validate(data)
      Issue.record("Expected controlled failure")
    } catch let failure as AppleWriteAttemptFailure {
      #expect(failure.definitelyNotDispatched == !started)
      #expect(failure.transient)
    }
  }
}

@Test func writeBridgeRetriesOnlyControlledPreDispatchFailure() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let executable = root.appendingPathComponent("fixture")
  let countFile = root.appendingPathComponent("count")
  let source = #"""
  #!/bin/sh
  count=0
  if [ -f "$COUNT_FILE" ]; then count=$(cat "$COUNT_FILE"); fi
  count=$((count + 1))
  printf '%s' "$count" > "$COUNT_FILE"
  if [ "$MODE" = raw ]; then
    printf 'execution error: timed out (-1712)' >&2
    exit 1
  fi
  if [ "$MODE" = unknown ]; then
    printf '{"_appleGatewayWriteFailure":{"started":true,"number":-1712,"message":"fixture"}}'
  elif [ "$count" -eq 1 ]; then
    printf '{"_appleGatewayWriteFailure":{"started":false,"number":-600,"message":"fixture"}}'
  else
    printf '{"noteId":"created-once"}'
  fi
  """#
  try source.write(to: executable, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
  for mode in ["preflight", "unknown", "raw"] {
    try? FileManager.default.removeItem(at: countFile)
    var delays: [TimeInterval] = []
    let bridge = AppleEventBridge(osascriptPath: executable.path, environment: ["COUNT_FILE": countFile.path, "MODE": mode, "PATH": "/usr/bin:/bin"])
    do {
      let data = try bridge.runWriteJXA(script: "function run(argv) {}", argumentsJSON: "{}", tracksDispatch: true,
                                     retry: AppleWriteRetry(sleep: { delays.append($0) }))
      #expect(mode == "preflight")
      #expect(String(data: data, encoding: .utf8) == #"{"noteId":"created-once"}"#)
    } catch let error as AppleGatewayError {
      #expect(mode != "preflight")
      #expect(error.details?["writeOutcome"] == "unknown")
    }
    #expect(try String(contentsOf: countFile, encoding: .utf8) == (mode == "preflight" ? "2" : "1"))
    #expect(delays == (mode == "preflight" ? [2] : []))
  }
}

@Test func writeRetryCancellationDuringWaitPreventsAnotherDispatch() throws {
  var cancelled = false
  var calls = 0
  let retry = AppleWriteRetry(sleep: { _ in cancelled = true }, isCancelled: { cancelled })
  do {
    try retry.run {
      calls += 1
      throw AppleWriteAttemptFailure(error: .init(code: .appleEventTimeout, message: "preflight"), definitelyNotDispatched: true, transient: true)
    }
    Issue.record("Expected cancellation")
  } catch let error as AppleGatewayError {
    #expect(error.details?["writeAttempts"] == "1")
    #expect(error.details?["writeOutcome"] == "notDispatched")
  }
  #expect(calls == 1)
}

@Test func writeRetryLaunchEvidenceExcludesPermanentErrors() {
  for (code, transient) in [(POSIXErrorCode.EAGAIN, true), (.ENOMEM, true), (.ENOENT, false), (.EACCES, false)] {
    let failure = AppleWriteRetry.launchFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(code.rawValue)), message: "fixture")
    #expect(failure.definitelyNotDispatched)
    #expect(failure.transient == transient)
  }
}

@Test func writeRetryDoesNotReplayEarlierGraphQLAliasesAndScopesConfig() throws {
  var resolverCalls: [String] = []
  var attempts = 0
  var policies: [AppleWriteRetryPolicy] = []
  let first = GraphQLFieldDefinition(name: "first", type: .named("String"), arguments: []) { _, _ in
    resolverCalls.append("first")
    policies.append(AppleWriteRetryContext.policy)
    return .string("created-first")
  }
  let second = GraphQLFieldDefinition(name: "second", type: .named("String"), arguments: []) { _, _ in
    resolverCalls.append("second")
    policies.append(AppleWriteRetryContext.policy)
    return try AppleWriteRetry(sleep: { _ in }).run {
      attempts += 1
      if attempts == 1 {
        throw AppleWriteAttemptFailure(error: .init(code: .appleEventTimeout, message: "preflight"), definitelyNotDispatched: true, transient: true)
      }
      return .string("created-second")
    }
  }
  let module = GraphQLSchemaModule(types: [.init(name: "String", kind: .scalar)], queryFields: [], mutationFields: [first, second])
  let configured = AppleWriteRetryPolicy(initialWaitSeconds: 7, maxRetries: 1)
  let data = GraphQLRuntime.execute(query: "mutation { a: first b: second }", variables: [:], role: .full,
                                    config: .init(writeRetry: configured), schema: .init(modules: [module], role: .full))
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let results = try #require(object["data"] as? [String: String])
  #expect(results == ["a": "created-first", "b": "created-second"])
  #expect(resolverCalls == ["first", "second"])
  #expect(attempts == 2)
  #expect(policies == [configured, configured])
  #expect(AppleWriteRetryContext.policy == .defaultValue)
}

@Test func writeRetryExpiredDeadlinePreventsDispatchAndCannotBeExtendedByNestedScope() throws {
  var calls = 0
  try AppleWriteExecutionContext.withDeadline(.distantPast) {
    try AppleWriteExecutionContext.withDeadline(.distantFuture) {
      do {
        try AppleWriteRetry(sleep: { _ in Issue.record("Unexpected sleep") }).run { calls += 1 }
        Issue.record("Expected deadline failure")
      } catch let error as AppleGatewayError {
        #expect(error.details?["writeAttempts"] == "0")
        #expect(error.details?["writeOutcome"] == "notDispatched")
      }
    }
  }
  #expect(calls == 0)
  #expect(AppleWriteExecutionContext.deadline == nil)
}
