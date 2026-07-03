import Foundation

public enum NotesServiceFactory {
  public static func liveServices() -> NotesServices {
    let adapter = LiveNotesAppleEventAdapter()
    return NotesServices(
      readService: NotesReadService(provider: adapter),
      writeService: NotesWriteService(provider: adapter, writer: adapter)
    )
  }

  public static func liveReadService() -> NotesReadService {
    liveServices().readService
  }

  public static func liveWriteService() -> NotesWriteService {
    liveServices().writeService
  }

  public static func unavailableReadService() -> NotesReadService {
    NotesReadService(provider: UnavailableNotesProvider())
  }

  public static func unavailableWriteService() -> NotesWriteService {
    let provider = UnavailableNotesProvider()
    return NotesWriteService(provider: provider, writer: provider)
  }
}

public struct NotesServices: Sendable {
  public var readService: NotesReadService
  public var writeService: NotesWriteService

  public init(readService: NotesReadService, writeService: NotesWriteService) {
    self.readService = readService
    self.writeService = writeService
  }
}

public struct UnavailableNotesProvider: NotesProviding, NotesWriting {
  public init() {}

  public func accounts() throws -> [NoteAccount] {
    throw unavailable("Notes provider is unavailable")
  }

  public func folders(accountId: String?) throws -> [NoteFolder] {
    throw unavailable("Notes provider is unavailable")
  }

  public func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String] {
    throw unavailable("Notes provider is unavailable")
  }

  public func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note] {
    throw unavailable("Notes provider is unavailable")
  }

  public func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String] {
    throw unavailable("Notes provider is unavailable")
  }

  public func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String] {
    throw unavailable("Notes provider is unavailable")
  }

  public func noteMetadata(noteId: String) throws -> NoteLookupResult {
    throw unavailable("Notes provider is unavailable")
  }

  public func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult {
    throw unavailable("Notes provider is unavailable")
  }

  public func createNote(_ request: NotesCreateRequest) throws -> String {
    throw unavailable("Notes writer is unavailable")
  }

  public func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String {
    throw unavailable("Notes writer is unavailable")
  }

  public func deleteNote(noteId: String) throws -> DeleteResult {
    throw unavailable("Notes writer is unavailable")
  }

  public func moveNote(_ request: NotesMoveRequest) throws -> String {
    throw unavailable("Notes writer is unavailable")
  }

  private func unavailable(_ message: String) -> AppleGatewayError {
    AppleGatewayError(code: .domainDisabled, message: message)
  }
}
