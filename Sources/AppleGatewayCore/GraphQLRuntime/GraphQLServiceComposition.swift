import Foundation

/// The common runtime context used by both the CLI and the public SDK façade.
struct GraphQLServiceComposition: Sendable {
  let role: AppleGatewayRole
  let environment: [String: String]
  let permissionsProvider: any PermissionsProviding
  let calendarReadService: CalendarReadService
  let calendarWriteService: CalendarWriteService
  let notesReadService: NotesReadService
  let notesWriteService: NotesWriteService
  let mailReadService: MailReadService?
  let mailWriteService: MailWriteService?
  let notificationsService: (any NotificationsProviding)?
  let clockAlarmsService: (any ClockAlarmsProviding)?
  let phoneCallsService: (any PhoneCallsProviding)?

  func executeResponse(
    query: String,
    variables: [String: GraphQLValue],
    config: AppleGatewayConfig,
    pretty: Bool
  ) -> AppleGatewayJSONResponse {
    GraphQLRuntime.executeResponse(
      query: query,
      variables: variables,
      role: role,
      config: config,
      permissionsProvider: permissionsProvider,
      calendarReadService: calendarReadService,
      calendarWriteService: calendarWriteService,
      notesReadService: notesReadService,
      notesWriteService: notesWriteService,
      mailReadService: mailReadService ?? MailServiceFactory.liveReadService(config: config, environment: environment),
      mailWriteService: mailWriteService ?? MailServiceFactory.liveWriteService(config: config, environment: environment),
      notificationsService: notificationsService ?? NotificationsServiceFactory.liveService(config: config, environment: environment),
      clockAlarmsService: clockAlarmsService ?? ClockAlarmsServiceFactory.liveService(config: config, environment: environment),
      phoneCallsService: phoneCallsService ?? PhoneCallsServiceFactory.liveService(config: config, environment: environment),
      pretty: pretty
    )
  }
}
