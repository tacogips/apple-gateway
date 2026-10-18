import Foundation
import Testing
@testable import AppleGatewayCore

private let writeLookupTemplates: [NotesJXATemplate] = [.createNoteAttachment, .replaceNoteBody, .deleteNote, .moveNote]

@Test func noteWriteLookupDoesNotEnumerateLibraryAndMarksImmediatelyBeforeMutation() throws {
  for template in writeLookupTemplates {
    let result = try executeWriteLookup(template, mode: "success")
    #expect(result["failed"] as? Bool == false)
    #expect(result["lookups"] as? Int == 1)
    #expect(result["markers"] as? Int == 1)
    #expect(result["writes"] as? Int == 1)
  }
}

@Test func noteWriteLookupRejectsMissingLockedWrongIdentityAndUnownedContainersBeforeDispatch() throws {
  for template in writeLookupTemplates {
    for mode in ["missing", "locked", "wrongNote", "cycle", "denied", "timeout"] {
      let result = try executeWriteLookup(template, mode: mode)
      #expect(result["failed"] as? Bool == true)
      #expect(result["markers"] as? Int == 0)
      #expect(result["writes"] as? Int == 0)
    }
  }
  for mode in ["wrongFolder", "foreignFolder"] {
    let result = try executeWriteLookup(.moveNote, mode: mode)
    #expect(result["failed"] as? Bool == true)
    #expect(result["markers"] as? Int == 0)
    #expect(result["writes"] as? Int == 0)
  }
}

@Test func noteWriteLookupKeepsDispatchMarkerAfterUncertainMutationFailure() throws {
  for template in writeLookupTemplates {
    let result = try executeWriteLookup(template, mode: "afterWriteTimeout")
    #expect(result["failed"] as? Bool == true)
    #expect(result["markers"] as? Int == 1)
    #expect(result["writes"] as? Int == 1)
    #expect(!template.permitsTimeoutRetry)
  }
}

private func executeWriteLookup(_ template: NotesJXATemplate, mode: String) throws -> [String: Any] {
  let source = template.source.replacingOccurrences(of: "Application('Notes')", with: "mockApplication()")
    .replacingOccurrences(of: "function run(argv)", with: "function templateRun(argv)")
    .replacingOccurrences(of: "Path(input.filePath)", with: "input.filePath")
  let wrapper = """
  function run(argv) {
    mode = JSON.parse(argv[0]).mode;
    let failed = false;
    try { templateRun(argv); } catch (error) { failed = true; }
    return JSON.stringify({failed: failed, lookups: lookups, markers: markers, writes: writes});
  }
  """
  let input: [String: String] = ["mode": mode, "noteId": "last-of-50000", "accountId": "account",
    "folderId": "target", "filePath": "/fixture/image.png", "bodyHtml": "replacement"]
  let arguments = try #require(String(data: JSONEncoder().encode(input), encoding: .utf8))
  let data = try AppleEventBridge(timeoutSeconds: 5, maxTimeoutRetries: 0).runJXA(
    script: writeLookupFixture + "\n" + source + "\n" + wrapper, argumentsJSON: arguments)
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let writeLookupFixture = """
let mode = '', lookups = 0, markers = 0, writes = 0;
function appleGatewayWillWrite() { markers++; }
const account = {id: () => 'account'};
const foreign = {id: () => 'foreign'};
const folder = {id: () => 'nested', container: () => mode === 'cycle' ? folder : account};
const target = {id: () => mode === 'wrongFolder' ? 'wrong' : 'target',
  container: () => mode === 'foreignFolder' ? foreign : account};
function mutate() {
  if (markers !== 1) { throw new Error('Mutation before dispatch marker'); }
  writes++;
  if (mode === 'afterWriteTimeout') { throw {errorNumber: -1712}; }
}
const note = {id: () => mode === 'wrongNote' ? 'wrong' : 'last-of-50000',
  passwordProtected: () => mode === 'locked', container: () => folder,
  delete: () => mutate(), move: options => {
    if (options.to !== target) { throw new Error('Wrong move target'); }
    mutate();
  }};
Object.defineProperty(note, 'body', {set: value => {
  if (value !== 'replacement') { throw new Error('Wrong replacement body'); }
  mutate();
}});
function mockApplication() {
  const accounts = () => { throw new Error('Global account enumeration forbidden'); };
  accounts.id = () => ['account', 'foreign'];
  const notes = () => { throw new Error('Materializing 50000 notes forbidden'); };
  notes.byId = id => {
    lookups++;
    if (id !== 'last-of-50000') { throw new Error('Wrong lookup ID'); }
    if (mode === 'missing') { throw {errorNumber: -1728}; }
    if (mode === 'denied') { throw {errorNumber: -1743}; }
    if (mode === 'timeout') { throw {errorNumber: -1712}; }
    return note;
  };
  const folders = () => { throw new Error('Folder enumeration forbidden'); };
  folders.byId = id => target;
  return {accounts: accounts, notes: notes, folders: folders, make: command => {
    if (command.new !== 'attachment' || command.at !== note || command.withData !== '/fixture/image.png') {
      throw new Error('Wrong native attachment command');
    }
    mutate();
    return {id: () => 'attachment-created'};
  }};
}
"""
