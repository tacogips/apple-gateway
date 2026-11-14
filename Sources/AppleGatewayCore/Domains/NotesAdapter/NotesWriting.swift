import Foundation

public protocol NotesWriting: Sendable {
  func createNoteFolder(_ input: CreateNoteFolderInput) throws -> String
  func createNoteAttachment(_ input: CreateNoteAttachmentInput) throws -> String
  func createNote(_ request: NotesCreateRequest) throws -> String
  func replaceNoteBody(_ request: NotesBodyWriteRequest) throws -> String
  func deleteNote(noteId: String) throws -> DeleteResult
  func moveNote(_ request: NotesMoveRequest) throws -> String
}

public extension NotesWriting {
  func createNoteFolder(_ input: CreateNoteFolderInput) throws -> String {
    throw AppleGatewayError(code: .domainDisabled, message: "Notes folder creation is unavailable for this writer")
  }

  func createNoteAttachment(_ input: CreateNoteAttachmentInput) throws -> String {
    throw AppleGatewayError(code: .domainDisabled, message: "Notes attachment import is unavailable for this writer")
  }
}
