import Foundation

public struct MailReadService: Sendable {
  private let provider: any MailProviding

  public init(provider: any MailProviding) {
    self.provider = provider
  }

  public func accounts() throws -> [MailAccount] {
    try provider.accounts()
  }

  public func mailboxes(accountId: String? = nil) throws -> [Mailbox] {
    try provider.mailboxes(accountId: accountId)
  }

  public func messages(input: MailSearchInput) throws -> MailMessageConnection {
    try provider.messages(input: input)
  }

  public func message(messageId: String) throws -> MailMessage? {
    try provider.message(messageId: messageId)
  }
}

public enum MailServiceFactory {
  public static func liveServices(
    config: AppleGatewayConfig = .defaultValue,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MailServices {
    let provider = LiveMailEnvelopeIndexProvider(config: config, environment: environment)
    return MailServices(
      readService: MailReadService(provider: provider),
      writeService: MailWriteService(
        provider: provider,
        writer: LiveMailAppleEventWriter(
          bridge: AppleEventBridge(
            timeoutSeconds: TimeInterval(config.limits.appleEventTimeoutSeconds),
            environment: environment
          )
        )
      )
    )
  }

  public static func liveReadService(
    config: AppleGatewayConfig = .defaultValue,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MailReadService {
    liveServices(config: config, environment: environment).readService
  }

  public static func liveWriteService(
    config: AppleGatewayConfig = .defaultValue,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MailWriteService {
    liveServices(config: config, environment: environment).writeService
  }

  public static func unavailableReadService() -> MailReadService {
    MailReadService(provider: UnavailableMailProvider())
  }

  public static func unavailableWriteService() -> MailWriteService {
    let provider = UnavailableMailProvider()
    return MailWriteService(provider: provider, writer: UnavailableMailWriter())
  }
}

public struct MailServices: Sendable {
  public var readService: MailReadService
  public var writeService: MailWriteService

  public init(readService: MailReadService, writeService: MailWriteService) {
    self.readService = readService
    self.writeService = writeService
  }
}

public struct UnavailableMailProvider: MailProviding {
  public init() {}

  public func accounts() throws -> [MailAccount] {
    throw unavailable()
  }

  public func mailboxes(accountId: String?) throws -> [Mailbox] {
    throw unavailable()
  }

  public func messages(input: MailSearchInput) throws -> MailMessageConnection {
    throw unavailable()
  }

  public func message(messageId: String) throws -> MailMessage? {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Mail provider is unavailable")
  }
}

public struct UnavailableMailWriter: MailWriting {
  public init() {}

  public func setRead(target: MailMessageTarget, isRead: Bool) throws {
    throw unavailable()
  }

  public func setFlagged(target: MailMessageTarget, isFlagged: Bool) throws {
    throw unavailable()
  }

  public func move(target: MailMessageTarget, destination: MailboxTarget) throws {
    throw unavailable()
  }

  public func delete(target: MailMessageTarget) throws {
    throw unavailable()
  }

  private func unavailable() -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: "Mail writer is unavailable")
  }
}

struct LiveMailEnvelopeIndexProvider: MailProviding {
  var config: AppleGatewayConfig
  var environment: [String: String]

  func accounts() throws -> [MailAccount] {
    try withQueryService { try $0.accounts() }
  }

  func mailboxes(accountId: String?) throws -> [Mailbox] {
    try withQueryService { try $0.mailboxes(accountId: accountId) }
  }

  func messages(input: MailSearchInput) throws -> MailMessageConnection {
    try withQueryService { try $0.messages(input: input) }
  }

  func message(messageId: String) throws -> MailMessage? {
    try withQueryService { try $0.message(messageId: messageId) }
  }

  private func withQueryService<T>(_ operation: (MailEnvelopeIndexQueryService) throws -> T) throws -> T {
    let homeDirectory = URL(
      fileURLWithPath: environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory(),
      isDirectory: true
    )
    let resolver = MailRootResolver(homeDirectory: homeDirectory)
    let paths = try resolver.resolve(config: config)
    let database = try MailEnvelopeIndexStore(
      config: config,
      environment: environment
    ).openDatabase(config: config)
    defer {
      database.close()
    }
    let fileStore = FileStore(cacheRoot: config.storage.cacheDir.expandingTildeInMailReadServicePath(homeDirectory: homeDirectory))
    let fileResolver = FileSystemMailMessageFileResolver(mailRoot: paths.root, fileStore: fileStore)
    let service = MailEnvelopeIndexQueryService(
      database: database,
      accountsPlistURL: paths.root
        .appendingPathComponent("MailData", isDirectory: true)
        .appendingPathComponent("Accounts.plist"),
      limits: config.limits,
      fileResolver: fileResolver
    )
    return try operation(service)
  }
}

protocol MailMessageFileResolving: Sendable {
  func files(messageRowId: Int64) throws -> MailMessageFileSet
}

struct EmptyMailMessageFileResolver: MailMessageFileResolving {
  func files(messageRowId: Int64) throws -> MailMessageFileSet {
    MailMessageFileSet()
  }
}

struct FileSystemMailMessageFileResolver: MailMessageFileResolving {
  var mailRoot: URL
  var fileStore: FileStore

  func files(messageRowId: Int64) throws -> MailMessageFileSet {
    guard let emlx = findEMLX(messageRowId: messageRowId) else {
      return MailMessageFileSet()
    }
    return try MailMessageFileFactory(fileStore: fileStore).files(emlxPath: emlx.path)
  }

  private func findEMLX(messageRowId: Int64) -> URL? {
    let names = ["\(messageRowId).emlx", "\(messageRowId).partial.emlx"]
    guard
      let enumerator = FileManager.default.enumerator(
        at: mailRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      return nil
    }
    for case let url as URL in enumerator where names.contains(url.lastPathComponent) {
      return url
    }
    return nil
  }
}

private extension String {
  func expandingTildeInMailReadServicePath(homeDirectory: URL) -> String {
    guard self == "~" || hasPrefix("~/") else {
      return self
    }
    return homeDirectory.appendingPathComponent(String(dropFirst(2))).path
  }
}
