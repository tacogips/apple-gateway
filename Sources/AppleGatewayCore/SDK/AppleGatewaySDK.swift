import Foundation
import GatewaySDKKit

/// Public Swift façade over apple-gateway's internal GraphQL runtime.
public struct AppleGatewaySDK: GatewaySDK {
  public let provider = "apple-gateway"
  public let tier: String
  public let catalog: GatewaySchemaCatalog

  private let role: AppleGatewayRole
  private let permissionsProvider: (any PermissionsProviding)?
  private let calendarReadService: CalendarReadService?
  private let calendarWriteService: CalendarWriteService?
  private let notesReadService: NotesReadService?
  private let notesWriteService: NotesWriteService?
  private let mailReadService: MailReadService?
  private let mailWriteService: MailWriteService?
  private let notificationsService: (any NotificationsProviding)?
  private let clockAlarmsService: (any ClockAlarmsProviding)?
  private let phoneCallsService: (any PhoneCallsProviding)?

  public init(
    role: AppleGatewayRole = .full,
    permissionsProvider: (any PermissionsProviding)? = nil,
    responsibleProcessDetector: any ResponsibleProcessDetecting = DefaultResponsibleProcessDetector(),
    fileMaterializer: (any FileStoreMaterializing)? = nil,
    calendarReadService: CalendarReadService? = nil,
    calendarWriteService: CalendarWriteService? = nil,
    notesReadService: NotesReadService? = nil,
    notesWriteService: NotesWriteService? = nil,
    mailReadService: MailReadService? = nil,
    mailWriteService: MailWriteService? = nil,
    notificationsService: (any NotificationsProviding)? = nil,
    clockAlarmsService: (any ClockAlarmsProviding)? = nil,
    phoneCallsService: (any PhoneCallsProviding)? = nil
  ) {
    self.role = role
    tier = role == .full ? "full" : "reader"
    catalog = .apple(role: role)
    self.permissionsProvider = permissionsProvider
    self.calendarReadService = calendarReadService
    self.calendarWriteService = calendarWriteService
    self.notesReadService = notesReadService
    self.notesWriteService = notesWriteService
    self.mailReadService = mailReadService
    self.mailWriteService = mailWriteService
    self.notificationsService = notificationsService
    self.clockAlarmsService = clockAlarmsService
    self.phoneCallsService = phoneCallsService
    _ = responsibleProcessDetector
    _ = fileMaterializer
  }

  public func execute(
    document: String,
    variables: [String: GatewayJSONValue],
    environment: [String: String]
  ) async -> GatewayEnvelope {
    guard environment["HOME"]?.isEmpty == false else {
      return configEnvelope(.environment(
        name: "HOME",
        message: "A non-empty HOME is required for SDK execution"
      ))
    }
    let config: AppleGatewayConfig
    do {
      config = try AppleGatewayConfigResolver().resolve(
        cliConfigPath: nil,
        environment: environment
      ).config
    } catch let error as AppleGatewayConfigError {
      return configEnvelope(error)
    } catch {
      return errorEnvelope(AppleGatewayError(code: .unexpectedError, message: String(describing: error)))
    }

    let runtimeVariables: [String: GraphQLValue]
    do {
      runtimeVariables = try GraphQLValue.gatewayVariables(variables)
    } catch let error as GraphQLRuntimeError {
      return errorEnvelope(AppleGatewayError(code: .invalidArgument, message: error.message))
    } catch {
      return errorEnvelope(AppleGatewayError(code: .invalidArgument, message: String(describing: error)))
    }

    let response = serviceComposition(config: config, environment: environment).executeResponse(
      query: document,
      variables: runtimeVariables,
      config: config,
      pretty: false
    )
    return GatewayEnvelope(
      parsingCLIOutput: String(bytes: response.data, encoding: .utf8) ?? "",
      exitCode: response.exitCode
    )
  }

  private func serviceComposition(
    config: AppleGatewayConfig,
    environment: [String: String]
  ) -> GraphQLServiceComposition {
    let calendarServices = calendarReadService == nil || calendarWriteService == nil
      ? CalendarReminderServiceFactory.liveServices()
      : nil
    let notesServices = notesReadService == nil || notesWriteService == nil
      ? NotesServiceFactory.liveServices(config: config, environment: environment)
      : nil
    return GraphQLServiceComposition(
      role: role,
      environment: environment,
      isEnvironmentIsolated: true,
      permissionsProvider: permissionsProvider ?? LivePermissionsProvider(
        environment: environment,
        includeDarwinUserDirectory: false
      ),
      calendarReadService: calendarReadService
        ?? calendarServices?.readService
        ?? CalendarReminderServiceFactory.liveReadService(),
      calendarWriteService: calendarWriteService
        ?? calendarServices?.writeService
        ?? CalendarReminderServiceFactory.liveWriteService(),
      notesReadService: notesReadService
        ?? notesServices?.readService
        ?? NotesServiceFactory.liveReadService(config: config, environment: environment),
      notesWriteService: notesWriteService
        ?? notesServices?.writeService
        ?? NotesServiceFactory.liveWriteService(config: config, environment: environment),
      mailReadService: mailReadService,
      mailWriteService: mailWriteService,
      notificationsService: notificationsService,
      clockAlarmsService: clockAlarmsService,
      phoneCallsService: phoneCallsService
    )
  }

  private func configEnvelope(_ error: AppleGatewayConfigError) -> GatewayEnvelope {
    do {
      let response = try ConfigValidationJSON.errorResponse(error, pretty: false)
      return GatewayEnvelope(
        parsingCLIOutput: String(bytes: response.data, encoding: .utf8) ?? "",
        exitCode: response.exitCode
      )
    } catch {
      return errorEnvelope(AppleGatewayError(code: .unexpectedError, message: String(describing: error)))
    }
  }

  private func errorEnvelope(_ error: AppleGatewayError) -> GatewayEnvelope {
    do {
      let response = try AppleGatewayJSONEnvelope.response(
        data: Optional<GraphQLValue>.none,
        errors: [error]
      )
      return GatewayEnvelope(
        parsingCLIOutput: String(bytes: response.data, encoding: .utf8) ?? "",
        exitCode: response.exitCode
      )
    } catch {
      return GatewayEnvelope.failure(error, exitCode: 1)
    }
  }
}
