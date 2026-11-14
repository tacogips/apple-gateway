import Foundation
import Testing
@testable import AppleGatewayCore

@Test func attachmentTemplateUsesNativeFileDataAndPreservesNoteBody() throws {
  let template = NotesJXATemplate.createNoteAttachment.source
    .replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
    .replacingOccurrences(of: "Path(input.filePath)", with: "mockPath(input.filePath)")
  let fixture = """
  const fixtureNote = {id: () => 'target', passwordProtected: () => false};
  function mockPath(path) { return {filePath: path}; }
  function mockApplication() {
    return {
      accounts: () => [{folders: () => [{notes: () => [{id: () => 'other'}, fixtureNote]}]}],
      make: command => {
        if (command.new !== 'attachment' || command.at !== fixtureNote || command.withData.filePath !== '/fixture/quoted"name.png') {
          throw new Error('Incorrect native attachment command');
        }
        return {id: () => 'attachment-created'};
      }
    };
  }
  """
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  let arguments = try #require(String(data: JSONEncoder().encode(CreateNoteAttachmentInput(noteId: "target", filePath: "/fixture/quoted\"name.png")), encoding: .utf8))
  let output = try bridge.runJXA(script: fixture + "\n" + template, argumentsJSON: arguments)
  let response = try #require(JSONSerialization.jsonObject(with: output) as? [String: String])
  #expect(response["attachmentId"] == "attachment-created")
  for modified in [
    fixture.replacingOccurrences(of: "passwordProtected: () => false", with: "passwordProtected: () => true"),
    fixture.replacingOccurrences(of: "id: () => 'target'", with: "id: () => 'absent'")
  ] {
    #expect(throws: (any Error).self) { try bridge.runJXA(script: modified + "\n" + template, argumentsJSON: arguments) }
  }
}
