import Foundation
import Testing
@testable import AppleGatewayCore

@Test func folderTemplateCreatesAtExactAccountOrParentAndRejectsForeignParent() throws {
  let template = NotesJXATemplate.createNoteFolder.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
  let fixture = """
  let destination = '';
  function collection(values, id) {
    const result = () => values;
    result.push = folder => { destination = id; };
    return result;
  }
  function mockApplication() {
    const parent = {id: () => 'parent', folders: collection([], 'parent')};
    const account = {id: () => 'account', folders: collection([parent], 'account')};
    return {
      accounts: () => [account],
      Folder: properties => ({id: () => destination + ':' + properties.name})
    };
  }
  """
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  for parent in [nil, "parent"] as [String?] {
    let input = CreateNoteFolderInput(accountId: "account", parentFolderId: parent, name: "quoted\"name")
    let arguments = try #require(String(data: JSONEncoder().encode(input), encoding: .utf8))
    let output = try bridge.runJXA(script: fixture + "\n" + template, argumentsJSON: arguments)
    let result = try #require(JSONSerialization.jsonObject(with: output) as? [String: String])
    #expect(result["folderId"] == "\(parent ?? "account"):quoted\"name")
  }
  #expect(throws: (any Error).self) {
    try bridge.runJXA(script: fixture + "\n" + template, argumentsJSON: #"{"accountId":"account","parentFolderId":"foreign","name":"x"}"#)
  }
}
