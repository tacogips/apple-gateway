import Foundation
import Testing
@testable import AppleGatewayCore

@Test func errorCodeExitMappingMatchesPrimarySpec() {
  let expected: [AppleGatewayErrorCode: Int] = [
    .invalidArgument: 5,
    .graphQLParseError: 5,
    .graphQLValidationError: 5,
    .writeDisabledInReader: 5,
    .permissionDenied: 4,
    .permissionNotDetermined: 4,
    .writeOnlyAccess: 4,
    .fullDiskAccessRequired: 4,
    .automationDenied: 4,
    .domainDisabled: 5,
    .calendarNotFound: 5,
    .eventNotFound: 5,
    .reminderNotFound: 5,
    .calendarReadOnly: 5,
    .noteNotFound: 5,
    .noteLocked: 5,
    .noteFolderNotFound: 5,
    .mailboxNotFound: 5,
    .messageNotFound: 5,
    .mailStoreNotFound: 5,
    .shortcutNotInstalled: 6,
    .shortcutActionUnsupported: 6,
    .notifierHelperMissing: 6,
    .notificationDBUnavailable: 6,
    .appleEventTimeout: 6,
    .invalidDownloadKey: 5,
    .fileOperationFailed: 6,
    .configInvalid: 3,
    .unsupportedOSVersion: 6,
    .unexpectedError: 1
  ]

  #expect(Set(AppleGatewayErrorCode.allCases) == Set(expected.keys))
  for code in AppleGatewayErrorCode.allCases {
    #expect(code.exitCode == expected[code])
  }
}

@Test func successEnvelopeIncludesDataAndTopLevelRequestId() throws {
  let data = try AppleGatewayJSONEnvelope.successData(
    ["status": "ok"],
    requestId: "request-success"
  )
  let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let payload = try #require(envelope["data"] as? [String: Any])
  let extensions = try #require(envelope["extensions"] as? [String: Any])

  #expect(payload["status"] as? String == "ok")
  #expect(envelope["errors"] == nil)
  #expect(extensions["requestId"] as? String == "request-success")
}

@Test func singleErrorEnvelopeIncludesCodeExitDetailsAndRequestId() throws {
  let error = AppleGatewayError(
    code: .permissionDenied,
    message: "Calendar access denied for this process",
    details: ["domain": "calendar", "responsibleProcessHint": "iTerm2"]
  )
  let data = try AppleGatewayJSONEnvelope.errorData(error, requestId: "request-error")
  let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let errors = try #require(envelope["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  let errorExtensions = try #require(firstError["extensions"] as? [String: Any])
  let details = try #require(errorExtensions["details"] as? [String: String])
  let envelopeExtensions = try #require(envelope["extensions"] as? [String: Any])

  #expect(envelope["data"] is NSNull)
  #expect(firstError["message"] as? String == "Calendar access denied for this process")
  #expect(errorExtensions["code"] as? String == "PERMISSION_DENIED")
  #expect(errorExtensions["exitCode"] as? Int == 4)
  #expect(details["domain"] == "calendar")
  #expect(envelopeExtensions["requestId"] as? String == "request-error")
}
