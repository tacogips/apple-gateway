import Foundation
import Testing
@testable import AppleGatewayCore

@Test func singleNoteLookupDoesNotEnumerateLargeLibraryOrReadUnrequestedAttachments() throws {
  for template in [NotesJXATemplate.fetchNoteBody, .probeNoteVisibility, .exportAttachment] {
    let source = template.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
      .replacingOccurrences(of: "function run(argv)", with: "function templateRun(argv)")
    let wrapper = """
    function run(argv) {
      const output = JSON.parse(templateRun(argv));
      if (byIdCalls !== 1 || bodyCalls > 1) { throw new Error('Unbounded lookup'); }
      if (output.note && (output.note.accountId !== 'account' || output.note.folderId !== 'nested')) {
        throw new Error('Wrong note location');
      }
      return JSON.stringify(output);
    }
    """
    let data = try AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0).runJXA(
      script: (template == .fetchNoteBody
        ? singleLookupFixture.replacingOccurrences(of: "attachments: () => []", with: "attachments: () => { throw new Error('Unrequested attachment read'); }")
        : singleLookupFixture) + "\n" + source + "\n" + wrapper,
      argumentsJSON: #"{"noteId":"last-of-50000","kind":"PLAINTEXT","includeAttachments":false,"attachmentId":"missing","destinationPath":"/unused"}"#
    )
    let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(result["status"] as? String == (template == .exportAttachment ? "attachmentMissing" : "found"))
  }
}

@Test func directNoteLookupReturnsLockedWithoutReadingBodyOrAttachments() throws {
  let fixture = singleLookupFixture
    .replacingOccurrences(of: "passwordProtected: () => false", with: "passwordProtected: () => true")
    .replacingOccurrences(of: "bodyCalls++; return 'Target body';", with: "throw new Error('Locked body accessed');")
    .replacingOccurrences(of: "attachments: () => []", with: "attachments: () => { throw new Error('Locked attachment accessed'); }")
  for template in [NotesJXATemplate.fetchNoteBody, .probeNoteVisibility] {
    let source = template.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
    let data = try AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0).runJXA(
      script: fixture + "\n" + source, argumentsJSON: #"{"noteId":"last-of-50000","kind":"PLAINTEXT"}"#
    )
    #expect((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String == "locked")
  }
}

@Test func directNoteLookupOnlyTreatsMissingObjectAsMissingAndBoundsContainerTraversal() throws {
  let source = NotesJXATemplate.fetchNoteBody.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
  for number in [-1728, -1719] {
    let fixture = singleLookupFixture.replacingOccurrences(
      of: "byIdCalls++; return note;", with: "byIdCalls++; throw {errorNumber: \(number)};"
    )
    let data = try AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0).runJXA(
      script: fixture + "\n" + source, argumentsJSON: #"{"noteId":"last-of-50000","kind":"PLAINTEXT"}"#
    )
    #expect((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String == "missing")
  }
  for replacement in [
    "byIdCalls++; throw {errorNumber: -1743};",
    "byIdCalls++; note.id = () => 'wrong'; return note;",
    "byIdCalls++; folder.container = () => folder; return note;"
  ] {
    let fixture = singleLookupFixture.replacingOccurrences(of: "byIdCalls++; return note;", with: replacement)
    #expect(throws: (any Error).self) {
      try AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0).runJXA(
        script: fixture + "\n" + source, argumentsJSON: #"{"noteId":"last-of-50000","kind":"PLAINTEXT"}"#
      )
    }
  }
}

private let singleLookupFixture = """
let byIdCalls = 0;
let bodyCalls = 0;
const account = {id: () => 'account'};
const folder = {id: () => 'nested', container: () => account};
const note = {
  id: () => 'last-of-50000', container: () => folder,
  name: () => 'Target', passwordProtected: () => false, shared: () => false,
  creationDate: () => new Date('2026-10-18T00:00:00Z'),
  modificationDate: () => new Date('2026-10-18T00:00:00Z'),
  plaintext: () => { bodyCalls++; return 'Target body'; },
  attachments: () => []
};
function mockApplication() {
  const accounts = function() { throw new Error('Do not enumerate accounts/folders'); };
  accounts.id = () => ['account'];
  const notes = function() { throw new Error('Do not materialize 50000 notes'); };
  notes.byId = id => { byIdCalls++; return note; };
  return {accounts: accounts, notes: notes};
}
"""
