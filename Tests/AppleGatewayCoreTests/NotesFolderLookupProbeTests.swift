import Foundation
import Testing
@testable import AppleGatewayCore

@Test func notesExactFolderLookupOptInReadOnlyProbe() throws {
  guard let path = ProcessInfo.processInfo.environment["APPLE_GATEWAY_TEST_FOLDER_LOOKUP_FIXTURE"] else { return }
  let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
  let folderId = try #require(fixture["folder_id"] as? String)
  let helper = NotesJXATemplate.moveNote.source.components(separatedBy: "\n\nfunction run(argv) {")[0]
  let script = helper + "\n\n" + """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    const folder = app.folders.byId(input.folderId);
    const exact = String(folder.id()) === input.folderId;
    const location = notesLocation(app, folder);
    return JSON.stringify({exact: exact, owned: app.accounts.id().map(String).indexOf(location.accountId) !== -1});
  }
  """
  let arguments = try #require(String(data: JSONEncoder().encode(["folderId": folderId]), encoding: .utf8))
  let result = try AppleWriteExecutionContext.withDeadline(Date().addingTimeInterval(15)) {
    try AppleEventBridge(timeoutSeconds: 10, maxTimeoutRetries: 0).runJXA(script: script, argumentsJSON: arguments)
  }
  let proof = try #require(JSONSerialization.jsonObject(with: result) as? [String: Bool])
  #expect(proof["exact"] == true)
  #expect(proof["owned"] == true)
}
