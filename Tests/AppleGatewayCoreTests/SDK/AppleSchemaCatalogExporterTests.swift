import GatewaySDKKit
import Testing
@testable import AppleGatewayCore

@Test func appleCatalogsValidateAndRespectRoleBoundaries() {
  let full = GatewaySchemaCatalog.apple(role: .full)
  let reader = GatewaySchemaCatalog.apple(role: .reader)

  #expect(full.validate().isEmpty)
  #expect(reader.validate().isEmpty)
  #expect(full.operation(named: "createReminder")?.kind == .mutation)
  #expect(full.operation(named: "createReminder")?.domain == "calendarReminders")
  #expect(full.operation(named: "deleteEvent")?.isDestructive == true)
  #expect(full.operation(named: "dismissNotifications")?.isDestructive == true)
  #expect(reader.operations(of: .mutation).isEmpty)
  #expect(reader.operation(named: "calendars")?.tier == "reader")
  #expect(full.types.contains { $0.name == "DateTime" })
  #expect(!full.types.contains { $0.name == "String" })
}

@Test func appleCatalogMatchesRuntimeRootFields() {
  for role in [AppleGatewayRole.full, .reader] {
    let schema = GraphQLRuntime.schema(role: role)
    let catalog = GatewaySchemaCatalog.apple(role: role)
    for operation in catalog.operations {
      #expect(schema.contains("  \(operation.name)(" ) || schema.contains("  \(operation.name):"))
    }
    #expect(schema.contains("scalar DateTime"))
    #expect(!catalog.sdl().contains("scalar String"))
  }
}
