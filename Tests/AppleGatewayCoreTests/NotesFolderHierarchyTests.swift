import Foundation
import Testing
@testable import AppleGatewayCore

@Test func folderTemplateReportsActualContainerIDsAndPreservesAccountScope() throws {
  let template = NotesJXATemplate.listFolders.source
    .replacingOccurrences(of: "Application('Notes')", with: "mockApplication('Notes')")
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  let all = try JSONDecoder().decode([NoteFolder].self, from: bridge.runJXA(
    script: notesFolderHierarchyFixture + "\n" + template, argumentsJSON: "{}"
  ))
  let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
  #expect(all.count == 4)
  #expect(byID["root"]?.parentFolderId == nil)
  #expect(byID["child"]?.parentFolderId == "root")
  #expect(byID["grandchild"]?.parentFolderId == "child")
  #expect(byID["other-root"]?.parentFolderId == nil)
  #expect(byID["child"]?.noteCount == 2)
  #expect(byID["grandchild"]?.accountId == "account-a")

  let scoped = try JSONDecoder().decode([NoteFolder].self, from: bridge.runJXA(
    script: notesFolderHierarchyFixture + "\n" + template, argumentsJSON: #"{"accountId":"account-b"}"#
  ))
  #expect(scoped.map(\.id) == ["other-root"])
}

@Test func folderTemplateDoesNotHideContainerPermissionFailures() throws {
  let template = NotesJXATemplate.listFolders.source
    .replacingOccurrences(of: "Application('Notes')", with: "mockApplication('Notes')")
  let fixture = notesFolderHierarchyFixture.replacingOccurrences(
    of: "container: () => parent,", with: "container: () => { throw { errorNumber: -1743, message: 'Not authorized to send Apple events' }; },"
  )
  let bridge = AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0)
  do {
    _ = try bridge.runJXA(script: fixture + "\n" + template, argumentsJSON: "{}")
    Issue.record("Expected container permission error")
  } catch AppleEventBridgeError.automationDenied {
    // Bridge-level failure remains visible to callers.
  }
}

private let notesFolderHierarchyFixture = """
function mockApplication() {
  const accountA = { id: () => 'account-a' };
  const accountB = { id: () => 'account-b' };
  function folder(id, parent, count) {
    return {
      id: () => id,
      name: () => 'Same name',
      container: () => parent,
      notes: () => Array(count).fill({})
    };
  }
  const root = folder('root', accountA, 1);
  const child = folder('child', root, 2);
  const grandchild = folder('grandchild', child, 0);
  accountA.folders = () => [root, child, grandchild];
  accountB.folders = () => [folder('other-root', accountB, 3)];
  return { accounts: () => [accountA, accountB] };
}
"""
