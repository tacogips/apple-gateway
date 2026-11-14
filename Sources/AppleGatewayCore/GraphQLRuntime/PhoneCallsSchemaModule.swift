import Foundation

extension GraphQLSchemaModule {
  static var phoneCalls: GraphQLSchemaModule {
    GraphQLSchemaModule(
      types: PhoneCallsSchema.types,
      queryFields: PhoneCallsSchema.queryFields,
      mutationFields: PhoneCallsSchema.mutationFields
    )
  }
}

private enum PhoneCallsSchema {
  static var types: [GraphQLNamedTypeDefinition] {
    [
      enumType("PhoneCallState", PhoneCallState.allCases.map(\.rawValue)),
      object("PhoneCallStatus", fields: [
        field("state", nonNull(named("PhoneCallState"))),
        field("callerName", string()),
        field("callerNumber", string()),
        field("application", string()),
        field("warning", string())
      ]),
      object("PhoneCallActionResult", fields: [
        field("success", nonNull(named("Boolean"))),
        field("state", nonNull(named("PhoneCallState"))),
        field("targetName", string()),
        field("application", string()),
        field("warning", string())
      ]),
      object("PhoneCallAudioResult", fields: [
        field("success", nonNull(named("Boolean"))),
        field("isPlaying", nonNull(named("Boolean"))),
        field("filePath", string()),
        field("deviceName", string()),
        field("warning", string())
      ]),
      object("PhoneCallAudioConfiguration", fields: [
        field("playbackDeviceUID", string()),
        field("captureDeviceUID", string()),
        field("cacheDirectory", nonNull(string()))
      ]),
      object("PhoneCallListeningStatus", fields: [
        field("success", nonNull(named("Boolean"))),
        field("isListening", nonNull(named("Boolean"))),
        field("deviceName", string()),
        field("chunkDurationSeconds", named("Int")),
        field("warning", string())
      ]),
      object("PhoneCallAudioInputEvent", fields: [
        field("sequence", nonNull(named("Int"))),
        field("filePath", nonNull(string())),
        field("createdAt", nonNull(string())),
        field("durationSeconds", nonNull(named("Int"))),
        field("interruptedPlayback", nonNull(named("Boolean")))
      ]),
      input("PlacePhoneCallInput", fields: [
        inputField("phoneNumber", string()),
        inputField("contactName", string()),
        inputField("phoneLabel", string()),
        inputField("autoConfirm", named("Boolean"), defaultValue: .bool(false))
      ]),
      input("PlayPhoneCallAudioInput", fields: [
        inputField("filePath", nonNull(string()))
      ]),
      input("StartPhoneCallListeningInput", fields: [
        inputField("chunkDurationSeconds", named("Int"), defaultValue: .int(5))
      ])
    ]
  }

  static var queryFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "phoneCallStatus",
        type: nonNull(named("PhoneCallStatus")),
        arguments: [],
        resolver: { _, context in
          phoneCallStatusValue(try context.phoneCallsService.phoneCallStatus())
        }
      ),
      GraphQLFieldDefinition(
        name: "phoneCallAudioConfiguration",
        type: nonNull(named("PhoneCallAudioConfiguration")),
        arguments: [],
        resolver: { _, context in
          phoneCallAudioConfigurationValue(
            try context.phoneCallsService.phoneCallAudioConfiguration()
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "phoneCallListeningStatus",
        type: nonNull(named("PhoneCallListeningStatus")),
        arguments: [],
        resolver: { _, context in
          phoneCallListeningStatusValue(try context.phoneCallsService.phoneCallListeningStatus())
        }
      ),
      GraphQLFieldDefinition(
        name: "phoneCallAudioInputEvents",
        type: nonNull(list(nonNull(named("PhoneCallAudioInputEvent")))),
        arguments: [argument("afterSequence", named("Int"), defaultValue: .int(0))],
        resolver: { arguments, context in
          .list(
            try context.phoneCallsService.phoneCallAudioInputEvents(
              afterSequence: arguments["afterSequence"]?.phoneCallsIntValue() ?? 0
            ).map(phoneCallAudioInputEventValue)
          )
        }
      )
    ]
  }

  static var mutationFields: [GraphQLFieldDefinition] {
    [
      GraphQLFieldDefinition(
        name: "placePhoneCall",
        type: nonNull(named("PhoneCallActionResult")),
        arguments: [argument("input", nonNull(named("PlacePhoneCallInput")))],
        resolver: { arguments, context in
          try phoneCallActionResultValue(
            context.phoneCallsService.placePhoneCall(
              arguments.phoneCallsRequired("input").placePhoneCallInputValue()
            )
          )
        }
      ),
      controlMutation(name: "answerPhoneCall") { try $0.answerPhoneCall() },
      controlMutation(name: "declinePhoneCall") { try $0.declinePhoneCall() },
      controlMutation(name: "endPhoneCall") { try $0.endPhoneCall() },
      GraphQLFieldDefinition(
        name: "playAudioToPhoneCall",
        type: nonNull(named("PhoneCallAudioResult")),
        arguments: [argument("input", nonNull(named("PlayPhoneCallAudioInput")))],
        resolver: { arguments, context in
          try phoneCallAudioResultValue(
            context.phoneCallsService.playAudioToPhoneCall(
              arguments.phoneCallsRequired("input").playPhoneCallAudioInputValue()
            )
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "stopPhoneCallAudio",
        type: nonNull(named("PhoneCallAudioResult")),
        arguments: [],
        resolver: { _, context in
          phoneCallAudioResultValue(try context.phoneCallsService.stopPhoneCallAudio())
        }
      ),
      GraphQLFieldDefinition(
        name: "startPhoneCallListening",
        type: nonNull(named("PhoneCallListeningStatus")),
        arguments: [argument("input", nonNull(named("StartPhoneCallListeningInput")))],
        resolver: { arguments, context in
          try phoneCallListeningStatusValue(
            context.phoneCallsService.startPhoneCallListening(
              arguments.phoneCallsRequired("input").startPhoneCallListeningInputValue()
            )
          )
        }
      ),
      GraphQLFieldDefinition(
        name: "stopPhoneCallListening",
        type: nonNull(named("PhoneCallListeningStatus")),
        arguments: [],
        resolver: { _, context in
          phoneCallListeningStatusValue(try context.phoneCallsService.stopPhoneCallListening())
        }
      )
    ]
  }

  private static func controlMutation(
    name: String,
    operation: @escaping (any PhoneCallsProviding) throws -> PhoneCallActionResult
  ) -> GraphQLFieldDefinition {
    GraphQLFieldDefinition(
      name: name,
      type: nonNull(named("PhoneCallActionResult")),
      arguments: [],
      resolver: { _, context in
        phoneCallActionResultValue(try operation(context.phoneCallsService))
      }
    )
  }

  private static func enumType(_ name: String, _ cases: [String]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .enumType(cases))
  }

  private static func object(_ name: String, fields: [GraphQLFieldDefinition]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .object(fields))
  }

  private static func input(_ name: String, fields: [GraphQLInputFieldDefinition]) -> GraphQLNamedTypeDefinition {
    GraphQLNamedTypeDefinition(name: name, kind: .inputObject(fields))
  }

  private static func field(_ name: String, _ type: GraphQLTypeReference) -> GraphQLFieldDefinition {
    GraphQLFieldDefinition(name: name, type: type, arguments: [])
  }

  private static func inputField(
    _ name: String,
    _ type: GraphQLTypeReference,
    defaultValue: GraphQLValue? = nil
  ) -> GraphQLInputFieldDefinition {
    GraphQLInputFieldDefinition(name: name, type: type, defaultValue: defaultValue)
  }

  private static func argument(_ name: String, _ type: GraphQLTypeReference) -> GraphQLArgumentDefinition {
    GraphQLArgumentDefinition(name: name, type: type)
  }

  private static func argument(
    _ name: String,
    _ type: GraphQLTypeReference,
    defaultValue: GraphQLValue?
  ) -> GraphQLArgumentDefinition {
    GraphQLArgumentDefinition(name: name, type: type, defaultValue: defaultValue)
  }
}

private func named(_ name: String) -> GraphQLTypeReference {
  .named(name)
}

private func nonNull(_ reference: GraphQLTypeReference) -> GraphQLTypeReference {
  .nonNull(reference)
}

private func list(_ reference: GraphQLTypeReference) -> GraphQLTypeReference {
  .list(reference)
}

private func string() -> GraphQLTypeReference {
  .named("String")
}

private extension Dictionary where Key == String, Value == GraphQLValue {
  func phoneCallsRequired(_ key: String) throws -> GraphQLValue {
    guard let value = self[key], value != .null else {
      throw AppleGatewayError(code: .invalidArgument, message: "Missing required argument \(key)")
    }
    return value
  }
}

private extension GraphQLValue {
  var phoneCallsNilIfNull: GraphQLValue? {
    self == .null ? nil : self
  }

  func phoneCallsObjectDictionary() throws -> [String: GraphQLValue] {
    guard case .object(let value) = self else {
      throw phoneCallsInvalidValue("Expected input object")
    }
    return value
  }

  func phoneCallsStringValue() throws -> String {
    guard case .string(let value) = self else {
      throw phoneCallsInvalidValue("Expected string")
    }
    return value
  }

  func phoneCallsIntValue() throws -> Int {
    guard case .int(let value) = self else {
      throw phoneCallsInvalidValue("Expected integer")
    }
    return value
  }

  func phoneCallsOptionalString(_ key: String) throws -> String? {
    try phoneCallsObjectDictionary()[key]?.phoneCallsNilIfNull?.phoneCallsStringValue()
  }

  func phoneCallsOptionalBool(_ key: String) throws -> Bool? {
    guard let value = try phoneCallsObjectDictionary()[key]?.phoneCallsNilIfNull else {
      return nil
    }
    guard case .bool(let result) = value else {
      throw phoneCallsInvalidValue("Expected boolean")
    }
    return result
  }

  func placePhoneCallInputValue() throws -> PlacePhoneCallInput {
    PlacePhoneCallInput(
      phoneNumber: try phoneCallsOptionalString("phoneNumber"),
      contactName: try phoneCallsOptionalString("contactName"),
      phoneLabel: try phoneCallsOptionalString("phoneLabel"),
      autoConfirm: try phoneCallsOptionalBool("autoConfirm") ?? false
    )
  }

  func playPhoneCallAudioInputValue() throws -> PlayPhoneCallAudioInput {
    let object = try phoneCallsObjectDictionary()
    guard let filePath = try object["filePath"]?.phoneCallsStringValue() else {
      throw phoneCallsInvalidValue("Missing required field filePath")
    }
    return PlayPhoneCallAudioInput(filePath: filePath)
  }

  func startPhoneCallListeningInputValue() throws -> StartPhoneCallListeningInput {
    let object = try phoneCallsObjectDictionary()
    return StartPhoneCallListeningInput(
      chunkDurationSeconds: try object["chunkDurationSeconds"]?.phoneCallsIntValue() ?? 5
    )
  }

  private func phoneCallsInvalidValue(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .invalidArgument, message: message)
  }
}

private func phoneCallStatusValue(_ status: PhoneCallStatus) -> GraphQLValue {
  .object([
    "state": .enumCase(status.state.rawValue),
    "callerName": status.callerName.map(GraphQLValue.string) ?? .null,
    "callerNumber": status.callerNumber.map(GraphQLValue.string) ?? .null,
    "application": status.application.map(GraphQLValue.string) ?? .null,
    "warning": status.warning.map(GraphQLValue.string) ?? .null
  ])
}

private func phoneCallActionResultValue(_ result: PhoneCallActionResult) -> GraphQLValue {
  .object([
    "success": .bool(result.success),
    "state": .enumCase(result.state.rawValue),
    "targetName": result.targetName.map(GraphQLValue.string) ?? .null,
    "application": result.application.map(GraphQLValue.string) ?? .null,
    "warning": result.warning.map(GraphQLValue.string) ?? .null
  ])
}

private func phoneCallAudioResultValue(_ result: PhoneCallAudioResult) -> GraphQLValue {
  .object([
    "success": .bool(result.success),
    "isPlaying": .bool(result.isPlaying),
    "filePath": result.filePath.map(GraphQLValue.string) ?? .null,
    "deviceName": result.deviceName.map(GraphQLValue.string) ?? .null,
    "warning": result.warning.map(GraphQLValue.string) ?? .null
  ])
}

private func phoneCallAudioConfigurationValue(
  _ configuration: PhoneCallAudioConfiguration
) -> GraphQLValue {
  .object([
    "playbackDeviceUID": configuration.playbackDeviceUID.map(GraphQLValue.string) ?? .null,
    "captureDeviceUID": configuration.captureDeviceUID.map(GraphQLValue.string) ?? .null,
    "cacheDirectory": .string(configuration.cacheDirectory.path)
  ])
}

private func phoneCallListeningStatusValue(_ status: PhoneCallListeningStatus) -> GraphQLValue {
  .object([
    "success": .bool(status.success),
    "isListening": .bool(status.isListening),
    "deviceName": status.deviceName.map(GraphQLValue.string) ?? .null,
    "chunkDurationSeconds": status.chunkDurationSeconds.map(GraphQLValue.int) ?? .null,
    "warning": status.warning.map(GraphQLValue.string) ?? .null
  ])
}

private func phoneCallAudioInputEventValue(_ event: PhoneCallAudioInputEvent) -> GraphQLValue {
  .object([
    "sequence": .int(event.sequence),
    "filePath": .string(event.filePath),
    "createdAt": .string(event.createdAt),
    "durationSeconds": .int(event.durationSeconds),
    "interruptedPlayback": .bool(event.interruptedPlayback)
  ])
}
