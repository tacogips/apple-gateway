import Foundation

public protocol NotesProviding: Sendable {
  func accounts() throws -> [NoteAccount]
  func folders(accountId: String?) throws -> [NoteFolder]
  func noteIds(accountId: String?, folderId: String?, batchSize: Int) throws -> [String]
  func noteMetadata(noteIds: [String], batchSize: Int) throws -> [Note]
  func bodySearchNoteIds(input: NotesBodySearchInput, batchSize: Int) throws -> [String]
  func searchSnippets(noteIds: [String], query: String?, batchSize: Int) throws -> [String: String]
  func noteMetadata(noteId: String) throws -> NoteLookupResult
  func noteBody(noteId: String, kind: NoteBodyKind) throws -> NoteBodyLookupResult
}
