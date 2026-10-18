@testable import AppleGatewayCore

let noteTemplateGoldens: [NotesJXATemplate: String] = [
    .listAccounts: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      return JSON.stringify(app.accounts().map((account, index) => ({
        id: String(account.id()),
        name: String(account.name()),
        isDefault: index === 0
      })));
    }
    """,
    .listFolders: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const accounts = app.accounts();
      const output = [];
      accounts.forEach(account => {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          return;
        }
        account.folders().forEach(folder => {
          const containerId = String(folder.container().id());
          output.push({
            id: String(folder.id()),
            accountId: accountId,
            name: String(folder.name()),
            parentFolderId: containerId === accountId ? null : containerId,
            noteCount: folder.notes().length
          });
        });
      });
      return JSON.stringify(output);
    }
    """,
    .listNoteMetadataWindow: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const start = input.offset || 0;
      const limit = input.limit || 200;
      const noteIds = [];
      let seen = 0;
      for (const account of app.accounts()) {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          continue;
        }
        for (const folder of account.folders()) {
          const folderId = String(folder.id());
          if (input.folderId && input.folderId !== folderId) {
            continue;
          }
          const notes = folder.notes;
          const folderNoteIds = notes.id();
          const protectedValues = notes.passwordProtected();
          for (let index = 0; index < folderNoteIds.length; index += 1) {
            if (protectedValues[index]) {
              continue;
            }
            if (seen < start) {
              seen += 1;
              continue;
            }
            if (noteIds.length >= limit) {
              return JSON.stringify({ noteIds: noteIds, hasMore: true });
            }
            noteIds.push(String(folderNoteIds[index]));
            seen += 1;
          }
        }
      }
      return JSON.stringify({ noteIds: noteIds, hasMore: false });
    }
    """,
    .fetchNoteMetadataBatch: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const wanted = {};
      input.noteIds.forEach(id => { wanted[id] = true; });
      const app = Application('Notes');
      const notes = [];
      app.accounts().forEach(account => {
        const accountId = String(account.id());
        account.folders().forEach(folder => {
          const folderId = String(folder.id());
          folder.notes().forEach(note => {
            const noteId = String(note.id());
            if (!wanted[noteId]) {
              return;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              return;
            }
            notes.push({
              id: noteId,
              accountId: accountId,
              folderId: folderId,
              name: String(note.name()),
              snippet: '',
              plaintext: null,
              bodyHtml: null,
              bodyFile: null,
              isPasswordProtected: false,
              isShared: false,
              creationDate: note.creationDate().toISOString(),
              modificationDate: note.modificationDate().toISOString(),
              attachments: []
            });
          });
        });
      });
      return JSON.stringify(notes);
    }
    """,
    .searchNoteIdsByPlaintext: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      const start = input.offset || 0;
      const limit = input.limit || 200;
      const ids = [];
      let seen = 0;
      let hasMore = false;
      app.accounts().forEach(account => {
        const accountId = String(account.id());
        if (input.accountId && input.accountId !== accountId) {
          return;
        }
        account.folders().forEach(folder => {
          const folderId = String(folder.id());
          if (input.folderId && input.folderId !== folderId) {
            return;
          }
          folder.notes.whose({ plaintext: { _contains: input.query } })().forEach(note => {
            if (note.passwordProtected && note.passwordProtected()) {
              return;
            }
            if (seen < start) {
              seen += 1;
              return;
            }
            if (ids.length >= limit) {
              hasMore = true;
              return;
            }
            ids.push(String(note.id()));
            seen += 1;
          });
        });
      });
      return JSON.stringify({ noteIds: ids, hasMore: hasMore });
    }
    """,
    .fetchSearchSnippetsBatch: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const wanted = {};
      input.noteIds.forEach(id => { wanted[id] = true; });
      const query = (input.query || '').toLowerCase();
      const app = Application('Notes');
      const snippets = {};
      app.accounts().forEach(account => {
        account.folders().forEach(folder => {
          folder.notes().forEach(note => {
            const noteId = String(note.id());
            if (!wanted[noteId] || (note.passwordProtected && note.passwordProtected())) {
              return;
            }
            const body = String(note.plaintext ? note.plaintext() : '');
            const lower = body.toLowerCase();
            const match = query.length > 0 ? lower.indexOf(query) : 0;
            const center = match >= 0 ? match : 0;
            const start = Math.max(0, center - 120);
            snippets[noteId] = body.slice(start, start + 300);
          });
        });
      });
      return JSON.stringify(snippets);
    }
    """,
    .probeNoteVisibility: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      let lockedCandidate = false;
      for (const account of app.accounts()) {
        const accountId = String(account.id());
        for (const folder of account.folders()) {
          const folderId = String(folder.id());
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              lockedCandidate = true;
              continue;
            }
            return JSON.stringify({
              status: 'found',
              note: {
                id: String(note.id()),
                accountId: accountId,
                folderId: folderId,
                name: String(note.name()),
                snippet: '',
                plaintext: null,
                bodyHtml: null,
                bodyFile: null,
                isPasswordProtected: false,
                isShared: false,
                creationDate: note.creationDate().toISOString(),
                modificationDate: note.modificationDate().toISOString(),
                attachments: []
              }
            });
          }
        }
      }
      return JSON.stringify({ status: lockedCandidate ? 'locked' : 'missing', note: null });
    }
    """
    ,
    .fetchNoteBody: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        const accountId = String(account.id());
        for (const folder of account.folders()) {
          const folderId = String(folder.id());
          for (const note of folder.notes()) {
            if (String(note.id()) !== input.noteId) {
              continue;
            }
            if (note.passwordProtected && note.passwordProtected()) {
              return JSON.stringify({ status: 'locked', note: null, kind: input.kind, body: '' });
            }
            const body = input.kind === 'HTML'
              ? String(note.body ? note.body() : '')
              : String(note.plaintext ? note.plaintext() : '');
            return JSON.stringify({
              status: 'found',
              kind: input.kind,
              body: body,
              note: {
                id: String(note.id()),
                accountId: accountId,
                folderId: folderId,
                name: String(note.name()),
                snippet: '',
                plaintext: null,
                bodyHtml: null,
                bodyFile: null,
                isPasswordProtected: false,
                isShared: false,
                creationDate: note.creationDate().toISOString(),
                modificationDate: note.modificationDate().toISOString(),
                attachments: []
              }
            });
          }
        }
      }
      return JSON.stringify({ status: 'missing', note: null, kind: input.kind, body: '' });
    }
    """,
    .createNote: """
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const app = Application('Notes');
      for (const account of app.accounts()) {
        if (String(account.id()) !== input.accountId) {
          continue;
        }
        for (const folder of account.folders()) {
          if (String(folder.id()) !== input.folderId) {
            continue;
          }
          if (typeof appleGatewayWillWrite === 'function') appleGatewayWillWrite();
          const note = app.Note({
            name: input.title,
            body: input.bodyHtml
          });
          folder.notes.push(note);
          return JSON.stringify({ noteId: String(note.id()) });
        }
      }
      throw new Error('Notes folder not found');
    }
    """
]
