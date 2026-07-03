import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notificationProtocolRoundTripsPostRequestAndResponse() throws {
  let request = NotificationHelperRequest(
    operation: .post,
    id: "fixture-id",
    title: "Build finished",
    subtitle: "apple-gateway",
    body: "The build completed.",
    sound: "default",
    actions: ["Open", "Dismiss"],
    allowReply: true,
    waitSeconds: 30
  )

  let requestData = try NotificationHelperProtocol.encodeRequest(request)
  let decodedRequest = try NotificationHelperProtocol.decodeRequest(from: requestData)

  #expect(decodedRequest == request)

  let response = NotificationHelperResponse.success(NotificationHelperResult(
    posted: NotificationHelperPosted(
      id: "fixture-id",
      delivered: true,
      activation: NotificationHelperActivation(kind: .action, actionLabel: "Open")
    )
  ))
  let responseData = try NotificationHelperProtocol.encodeResponse(response)
  let decodedResponse = try NotificationHelperProtocol.decodeResponse(from: responseData)

  #expect(decodedResponse == response)
}

@Test func notificationProtocolRoundTripsListDismissDismissAllAndSettings() throws {
  let requests = [
    NotificationHelperRequest(operation: .list),
    NotificationHelperRequest(operation: .dismiss, ids: ["one", "two"]),
    NotificationHelperRequest(operation: .dismissAll),
    NotificationHelperRequest(operation: .settings)
  ]

  for request in requests {
    let data = try NotificationHelperProtocol.encodeRequest(request)
    #expect(try NotificationHelperProtocol.decodeRequest(from: data) == request)
  }

  let listResponse = NotificationHelperResponse.success(NotificationHelperResult(
    notifications: [
      NotificationHelperDeliveredNotification(
        id: "one",
        appBundleId: "me.tacogips.apple-gateway.notifier",
        title: "Title",
        deliveredAt: "2026-07-03T00:00:00Z"
      )
    ]
  ))
  let dismissResponse = NotificationHelperResponse.success(NotificationHelperResult(dismissedCount: 2))
  let settingsResponse = NotificationHelperResponse.success(NotificationHelperResult(
    settings: NotificationHelperSettings(
      authorizationStatus: "authorized",
      alertSetting: "enabled",
      soundSetting: "enabled"
    )
  ))

  #expect(try NotificationHelperProtocol.decodeResponse(from: NotificationHelperProtocol.encodeResponse(listResponse)) == listResponse)
  #expect(try NotificationHelperProtocol.decodeResponse(from: NotificationHelperProtocol.encodeResponse(dismissResponse)) == dismissResponse)
  #expect(try NotificationHelperProtocol.decodeResponse(from: NotificationHelperProtocol.encodeResponse(settingsResponse)) == settingsResponse)
}

@Test func notificationProtocolRejectsMismatchedProtocolVersionWithDedicatedError() throws {
  let data = Data(#"{"operation":"settings","protocolVersion":999}"#.utf8)

  switch NotificationHelperProtocol.decodeRequestResult(from: data) {
  case .success:
    Issue.record("Expected protocol version mismatch")
  case .failure(let response):
    #expect(response.ok == false)
    #expect(response.error?.code == .protocolVersionMismatch)
    #expect(response.error?.details?["supportedProtocolVersion"] == "1")
    #expect(response.error?.details?["receivedProtocolVersion"] == "999")
  }
}

@Test func notificationProtocolRejectsMalformedRequestBeforeDispatch() {
  let cases: [(Data, NotificationHelperErrorCode)] = [
    (Data("{".utf8), .malformedRequest),
    (Data(#"{"operation":"settings"}"#.utf8), .malformedRequest),
    (Data(#"{"operation":"settings","protocolVersion":"1"}"#.utf8), .malformedRequest)
  ]

  for (data, code) in cases {
    switch NotificationHelperProtocol.decodeRequestResult(from: data) {
    case .success:
      Issue.record("Expected malformed request")
    case .failure(let response):
      #expect(response.ok == false)
      #expect(response.error?.code == code)
    }
  }
}

@Test func notificationProtocolRejectsUnknownOperationAndInvalidPayloads() {
  let cases: [(String, NotificationHelperErrorCode)] = [
    (#"{"operation":"missing","protocolVersion":1}"#, .invalidArgument),
    (#"{"operation":"post","protocolVersion":1,"title":""}"#, .invalidArgument),
    (#"{"operation":"post","protocolVersion":1,"title":"Title","actions":[""]}"#, .invalidArgument),
    (#"{"operation":"post","protocolVersion":1,"title":"Title","waitSeconds":0}"#, .invalidArgument),
    (#"{"operation":"dismiss","protocolVersion":1,"ids":[]}"#, .invalidArgument),
    (#"{"operation":"list","protocolVersion":1,"title":"not meaningful"}"#, .invalidArgument)
  ]

  for (json, code) in cases {
    switch NotificationHelperProtocol.decodeRequestResult(from: Data(json.utf8)) {
    case .success:
      Issue.record("Expected invalid payload for \(json)")
    case .failure(let response):
      #expect(response.ok == false)
      #expect(response.error?.code == code)
    }
  }
}
