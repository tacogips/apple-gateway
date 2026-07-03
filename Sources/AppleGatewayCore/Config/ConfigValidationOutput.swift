import Foundation

public enum ConfigValidationJSON {
  public static func successData(_ resolved: ResolvedAppleGatewayConfig, pretty: Bool = false) throws -> Data {
    try AppleGatewayJSONEnvelope.successData(resolved, pretty: pretty)
  }

  public static func errorData(
    _ error: AppleGatewayConfigError,
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> Data {
    try AppleGatewayJSONEnvelope.errorData(error.appleGatewayError, requestId: requestId, pretty: pretty)
  }

  public static func errorResponse(
    _ error: AppleGatewayConfigError,
    requestId: String = UUID().uuidString,
    pretty: Bool = false
  ) throws -> AppleGatewayJSONResponse {
    try AppleGatewayJSONEnvelope.response(
      data: Optional<String>.none,
      errors: [error.appleGatewayError],
      requestId: requestId,
      pretty: pretty
    )
  }
}
