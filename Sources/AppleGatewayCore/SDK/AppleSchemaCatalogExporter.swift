import GatewaySDKKit

extension GatewaySchemaCatalog {
  /// Exports the runtime schema without making the runtime itself public.
  public static func apple(role: AppleGatewayRole) -> GatewaySchemaCatalog {
    var operations: [GatewayOperation] = []
    var definitions: [String: GraphQLNamedTypeDefinition] = [:]

    for domainModule in GraphQLSchemaRegistry.domainModules {
      for definition in domainModule.module.types {
        definitions[definition.name] = definition
      }
      operations += domainModule.module.queryFields.map {
        GatewayOperation(
          name: $0.name,
          kind: .query,
          tier: "reader",
          arguments: $0.arguments.map(GatewayArgument.init),
          result: GatewayTypeRef($0.type),
          summary: $0.description ?? $0.name,
          isDestructive: isDestructive($0.name),
          domain: domainModule.domain
        )
      }
      if role == .full {
        operations += domainModule.module.mutationFields.map {
          GatewayOperation(
            name: $0.name,
            kind: .mutation,
            tier: "full",
            arguments: $0.arguments.map(GatewayArgument.init),
            result: GatewayTypeRef($0.type),
            summary: $0.description ?? $0.name,
            isDestructive: isDestructive($0.name),
            domain: domainModule.domain
          )
        }
      }
    }

    let types = definitions.keys.sorted().compactMap { name -> GatewayNamedType? in
      guard let definition = definitions[name], !builtinScalars.contains(name) else {
        return nil
      }
      return GatewayNamedType(definition)
    }
    return GatewaySchemaCatalog(
      provider: "apple-gateway",
      tier: role == .full ? "full" : "reader",
      operations: operations,
      types: types
    )
  }
}

extension GatewayTypeRef {
  init(_ reference: GraphQLTypeReference) {
    switch reference {
    case .named(let name): self = .named(name)
    case .list(let inner): self = .list(GatewayTypeRef(inner))
    case .nonNull(let inner): self = .nonNull(GatewayTypeRef(inner))
    }
  }
}

private extension GatewayArgument {
  init(_ definition: GraphQLArgumentDefinition) {
    let hasDefault = definition.defaultValue != nil
    let type = GatewayTypeRef(definition.type)
    self.init(
      name: definition.name,
      type: hasDefault ? type.unwrappingNonNull : type,
      isRequired: definition.type.isNonNull && !hasDefault,
      defaultValue: definition.defaultValue.flatMap(GatewayJSONValue.init),
      description: nil
    )
  }

  init(_ definition: GraphQLInputFieldDefinition) {
    let hasDefault = definition.defaultValue != nil
    let type = GatewayTypeRef(definition.type)
    self.init(
      name: definition.name,
      type: hasDefault ? type.unwrappingNonNull : type,
      isRequired: definition.type.isNonNull && !hasDefault,
      defaultValue: definition.defaultValue.flatMap(GatewayJSONValue.init),
      description: nil
    )
  }
}

private extension GatewayField {
  init(_ definition: GraphQLFieldDefinition) {
    self.init(
      name: definition.name,
      type: GatewayTypeRef(definition.type),
      arguments: definition.arguments.map(GatewayArgument.init),
      description: definition.description
    )
  }
}

private extension GatewayNamedType {
  init(_ definition: GraphQLNamedTypeDefinition) {
    let kind: Kind
    switch definition.kind {
    case .scalar:
      kind = .scalar
    case .object(let fields):
      kind = .object(fields.map(GatewayField.init))
    case .enumType(let values):
      kind = .enumeration(values)
    case .inputObject(let fields):
      kind = .inputObject(fields.map(GatewayArgument.init))
    }
    self.init(name: definition.name, kind: kind)
  }
}

private extension GatewayJSONValue {
  init?(_ value: GraphQLValue) {
    switch value {
    case .int(let number): self = .int(number)
    case .float(let number): self = .double(number)
    case .string(let text), .enumCase(let text): self = .string(text)
    case .bool(let flag): self = .bool(flag)
    case .null: self = .null
    case .list(let values): self = .array(values.compactMap(GatewayJSONValue.init))
    case .object(let values):
      var converted: [String: GatewayJSONValue] = [:]
      for (key, item) in values {
        guard let item = GatewayJSONValue(item) else { return nil }
        converted[key] = item
      }
      self = .object(converted)
    case .variable:
      return nil
    }
  }
}

extension GraphQLValue {
  static func gatewayVariables(
    _ variables: [String: GatewayJSONValue]
  ) throws -> [String: GraphQLValue] {
    try variables.mapValues { try GraphQLValue.fromJSONObject($0.anyValue) }
  }
}

private func isDestructive(_ name: String) -> Bool {
  name.hasPrefix("delete") || name.hasPrefix("dismiss")
}
