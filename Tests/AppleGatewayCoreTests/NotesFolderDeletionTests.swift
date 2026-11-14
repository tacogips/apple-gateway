import Foundation
import Testing
@testable import AppleGatewayCore

@Test func folderDeleteTemplateScopesIdentityAndDeletesNativeSubtreeOnlyWithConsent() throws {
  let template = NotesJXATemplate.deleteNoteFolder.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
  let fixture = """
  let markers = 0, deletions = 0;
  function appleGatewayWillWrite() { markers++; }
  function mockApplication() {
    const options = JSON.parse(currentArguments);
    const account = {id: () => options.foreign ? 'other' : 'account'};
    function ancestor(depth) {
      return {id: () => 'ancestor-' + depth, container: () => depth < 65 ? ancestor(depth + 1) : account};
    }
    const folder = {
      id: () => options.mismatch ? 'wrong' : 'folder',
      container: () => options.cycle ? folder : options.deep ? ancestor(0) : options.nested ? {id: () => 'parent', container: () => account} : account,
      notes: () => options.notes ? [{}] : [],
      folders: () => options.children ? [{}] : [],
      delete: () => {
        if (markers !== 1) throw new Error('Wrong write marker ordering');
        deletions++;
        if (options.afterDispatchFailure) throw new Error('Synthetic uncertain outcome');
      }
    };
    const accounts = () => [account]; accounts.id = () => ['account', 'other'];
    return {accounts: accounts, folders: {byId: id => {
      if (options.missing) throw new Error('Missing folder');
      return folder;
    }}};
  }
  let currentArguments;
  """
  let wrapper = """
  const originalRun = run;
  run = function(argv) {
    currentArguments = argv[0];
    try {
      const value = JSON.parse(originalRun(argv));
      return JSON.stringify({success: value.success, deletions: deletions, markers: markers});
    } catch (error) {
      return JSON.stringify({success: false, deletions: deletions, markers: markers});
    }
  };
  """
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  let cases: [([String: Any], Bool)] = [
    ([:], true), (["notes": true], false), (["children": true], false),
    (["notes": true, "children": true, "allowNonEmpty": true], true),
    (["foreign": true, "allowNonEmpty": true], false), (["mismatch": true], false),
    (["missing": true], false), (["accountId": "missing"], false), (["folderId": ""], false),
    (["nested": true], true), (["cycle": true], false), (["deep": true], false),
    (["afterDispatchFailure": true], false)
  ]
  for (options, succeeds) in cases {
    let values = ["accountId": "account", "folderId": "folder", "allowNonEmpty": false] as [String: Any]
    let merged = values.merging(options) { _, new in new }
    let arguments = try #require(String(data: JSONSerialization.data(withJSONObject: merged), encoding: .utf8))
    let output = try bridge.runJXA(script: fixture + "\n" + template + "\n" + wrapper, argumentsJSON: arguments)
    let result = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    #expect(result["success"] as? Bool == succeeds)
    let dispatched = succeeds || options["afterDispatchFailure"] as? Bool == true
    #expect(result["deletions"] as? Int == (dispatched ? 1 : 0))
    #expect(result["markers"] as? Int == (dispatched ? 1 : 0))
  }
  #expect(!NotesJXATemplate.deleteNoteFolder.permitsTimeoutRetry)
  #expect(!template.contains("emptyTrash"))
  #expect(!template.contains("purge"))
}
