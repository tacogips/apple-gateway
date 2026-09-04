import GatewaySDKKit
import Testing
@testable import AppleGatewayCore

@Test func sdkInvokesCatalogOperationAndExecutesRawDocument() async {
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let invoked = await sdk.invoke(GatewayOperationRequest(operation: "permissions"))
  #expect(invoked.errors.isEmpty)
  #expect(invoked.rawOutput.contains("\"permissions\""))

  let raw = await sdk.execute(
    document: "{ permissions { calendars } }",
    variables: [:],
    environment: ["HOME": "/tmp"]
  )
  #expect(raw.errors.isEmpty)
  #expect(raw.rawOutput.contains("\"calendars\":\"GRANTED\""))
}

@Test func readerSDKRejectsRawMutation() async {
  let sdk = AppleGatewaySDK(role: .reader, permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.execute(
    document: "mutation { createReminder(input: { title: \"x\" }) { id } }",
    variables: [:],
    environment: ["HOME": "/tmp"]
  )
  #expect(envelope.exitCode == 5)
  #expect(envelope.errors.first?.code == "WRITE_DISABLED_IN_READER")
  #expect(envelope.errors.first?.message == "Mutations are disabled in reader mode")
}

@Test func readerSDKNamedMutationFailsBeforeRuntimeExecution() async {
  let sdk = AppleGatewaySDK(role: .reader, permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.invoke(GatewayOperationRequest(operation: "createReminder"))
  #expect(envelope.exitCode == 2)
  #expect(envelope.errors.first?.message == "unknown operation 'createReminder'")
  #expect(envelope.rawOutput.isEmpty)
}

@Test func sdkConfigFailureMatchesCLIEnvelopeShape() async {
  let environment = [
    "HOME": "/tmp",
    "APPLE_GATEWAY_CONFIG": "/tmp/apple-gateway-sdk-missing-config.toml"
  ]
  let sdk = AppleGatewaySDK(permissionsProvider: SDKPermissionsProvider())
  let envelope = await sdk.execute(
    document: "{ permissions { calendars } }",
    variables: [:],
    environment: environment
  )
  let cli = try? AppleGatewayCommand(
    arguments: ["graphql", "--query", "{ permissions { calendars } }"],
    environment: environment,
    permissionsProvider: SDKPermissionsProvider()
  ).runResult()
  #expect(envelope.exitCode == cli?.exitCode)
  #expect(envelope.errors.first?.code == "CONFIG_INVALID")
  #expect(cli?.output.contains("CONFIG_INVALID") == true)
}

private struct SDKPermissionsProvider: PermissionsProviding {
  func status(config: AppleGatewayConfig) -> PermissionsStatus {
    PermissionsStatus(
      calendars: PermissionFieldStatus(state: .granted),
      reminders: PermissionFieldStatus(state: .granted),
      notesAutomation: PermissionFieldStatus(state: .granted),
      mailAutomation: PermissionFieldStatus(state: .granted),
      mailFullDiskAccess: PermissionFieldStatus(state: .granted),
      notificationsHelper: PermissionFieldStatus(state: .granted),
      notificationDbFullDiskAccess: PermissionFieldStatus(state: .granted),
      clockAutomation: PermissionFieldStatus(state: .granted),
      phoneContacts: PermissionFieldStatus(state: .granted),
      phoneAutomation: PermissionFieldStatus(state: .granted)
    )
  }

  func request(domain: PermissionRequestDomain, config: AppleGatewayConfig) -> PermissionRequestResult {
    PermissionRequestResult(domain: domain, status: PermissionFieldStatus(state: .granted))
  }
}
