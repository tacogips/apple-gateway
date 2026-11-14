import Foundation

public protocol NotesWriting: Sendable {
  func createNote(_ request: NotesCreateRequest) throws -> String
  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String
  func deleteNote(noteId: String) throws -> DeleteResult
  func moveNote(_ request: NotesMoveRequest) throws -> String
}
