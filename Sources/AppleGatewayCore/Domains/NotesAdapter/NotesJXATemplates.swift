import Foundation

public enum NotesJXATemplate: String, CaseIterable, Sendable {
  case listAccounts
  case listFolders
  case listNoteMetadataWindow
  case fetchNoteMetadataBatch
  case searchNoteIdsByPlaintext
  case fetchSearchSnippetsBatch
  case probeNoteVisibility
  case fetchNoteBody
  case exportAttachment
  case createNote
  case replaceNoteBody
  case deleteNote
  case moveNote

  public var source: String {
    switch self {
    case .listAccounts:
      return Self.listAccountsSource
    case .listFolders:
      return Self.listFoldersSource
    case .listNoteMetadataWindow:
      return Self.listNoteMetadataWindowSource
    case .fetchNoteMetadataBatch:
      return Self.fetchNoteMetadataBatchSource
    case .searchNoteIdsByPlaintext:
      return Self.searchNoteIdsByPlaintextSource
    case .fetchSearchSnippetsBatch:
      return Self.fetchSearchSnippetsBatchSource
    case .probeNoteVisibility:
      return Self.probeNoteVisibilitySource
    case .fetchNoteBody:
      return Self.fetchNoteBodySource
    case .exportAttachment:
      return Self.exportAttachmentSource
    case .createNote:
      return Self.createNoteSource
    case .replaceNoteBody:
      return Self.replaceNoteBodySource
    case .deleteNote:
      return Self.deleteNoteSource
    case .moveNote:
      return Self.moveNoteSource
    }
  }

  private static let listAccountsSource = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    return JSON.stringify(app.accounts().map((account, index) => ({
      id: String(account.id()),
      name: String(account.name()),
      isDefault: index === 0
    })));
  }
  """

  private static let listFoldersSource = """
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
        output.push({
          id: String(folder.id()),
          accountId: accountId,
          name: String(folder.name()),
          parentFolderId: null,
          noteCount: folder.notes().length
        });
      });
    });
    return JSON.stringify(output);
  }
  """

  private static let listNoteMetadataWindowSource = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    const start = input.offset || 0;
    const limit = input.limit || 200;
    const noteIds = [];
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
        folder.notes().forEach(note => {
          if (note.passwordProtected && note.passwordProtected()) {
            return;
          }
          if (seen < start) {
            seen += 1;
            return;
          }
          if (noteIds.length >= limit) {
            hasMore = true;
            return;
          }
          noteIds.push(String(note.id()));
          seen += 1;
        });
      });
    });
    return JSON.stringify({ noteIds: noteIds, hasMore: hasMore });
  }
  """

  private static let noteMetadataHelpersSource = """
  function normalizedNotesValue(value) {
    try {
      if (value === null || value === undefined) {
        return null;
      }
      const text = String(value).trim();
      const sentinel = text.toLowerCase();
      if (!text || sentinel === 'missing value' || sentinel === 'null' || sentinel === 'undefined') {
        return null;
      }
      return text;
    } catch (error) {
      return null;
    }
  }

  function guardedNotesProperty(object, propertyName) {
    try {
      const property = object[propertyName];
      if (property === null || property === undefined) {
        return null;
      }
      return typeof property === 'function' ? property.call(object) : property;
    } catch (error) {
      return null;
    }
  }

  function notesAttachmentMetadata(note) {
    let attachments;
    try {
      attachments = note.attachments();
    } catch (error) {
      return [];
    }
    const output = [];
    attachments.forEach(attachment => {
      try {
        const id = normalizedNotesValue(guardedNotesProperty(attachment, 'id'));
        if (!id) {
          return;
        }
        const name = normalizedNotesValue(guardedNotesProperty(attachment, 'name'))
          || normalizedNotesValue(guardedNotesProperty(attachment, 'fileName'))
          || 'Untitled Attachment';
        const contentIdentifier = normalizedNotesValue(
          guardedNotesProperty(attachment, 'contentIdentifier')
        );
        output.push({ id: id, name: name, contentIdentifier: contentIdentifier, downloadKey: null });
      } catch (error) {
        // A malformed attachment must not hide other attachment metadata.
      }
    });
    return output;
  }

  function notesSharedState(note) {
    const shared = guardedNotesProperty(note, 'shared');
    if (typeof shared === 'boolean') {
      return shared;
    }
    const isShared = guardedNotesProperty(note, 'isShared');
    return typeof isShared === 'boolean' ? isShared : false;
  }
  """

  private static let fetchNoteMetadataBatchSource = noteMetadataHelpersSource + "\n\n" + """
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
            isShared: notesSharedState(note),
            creationDate: note.creationDate().toISOString(),
            modificationDate: note.modificationDate().toISOString(),
            attachments: notesAttachmentMetadata(note)
          });
        });
      });
    });
    return JSON.stringify(notes);
  }
  """

  private static let searchNoteIdsByPlaintextSource = """
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
  """

  private static let fetchSearchSnippetsBatchSource = """
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
  """

  private static let probeNoteVisibilitySource = noteMetadataHelpersSource + "\n\n" + """
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
              isShared: notesSharedState(note),
              creationDate: note.creationDate().toISOString(),
              modificationDate: note.modificationDate().toISOString(),
              attachments: notesAttachmentMetadata(note)
            }
          });
        }
      }
    }
    return JSON.stringify({ status: lockedCandidate ? 'locked' : 'missing', note: null });
  }
  """

  private static let fetchNoteBodySource = noteMetadataHelpersSource + "\n\n" + """
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
              isShared: notesSharedState(note),
              creationDate: note.creationDate().toISOString(),
              modificationDate: note.modificationDate().toISOString(),
              attachments: notesAttachmentMetadata(note)
            }
          });
        }
      }
    }
    return JSON.stringify({ status: 'missing', note: null, kind: input.kind, body: '' });
  }
  """

  private static let exportAttachmentSource = noteMetadataHelpersSource + "\n\n" + """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    for (const account of app.accounts()) {
      for (const folder of account.folders()) {
        for (const note of folder.notes()) {
          if (String(note.id()) !== input.noteId) {
            continue;
          }
          let attachments;
          try {
            attachments = note.attachments();
          } catch (error) {
            if (error && (error.number === -1743 || error.number === -1712)) {
              throw error;
            }
            return JSON.stringify({ status: 'unavailable', path: null });
          }
          for (const attachment of attachments) {
            const attachmentId = normalizedNotesValue(guardedNotesProperty(attachment, 'id'));
            if (attachmentId !== input.attachmentId) {
              continue;
            }
            try {
              app.save(attachment, { in: Path(input.destinationPath) });
              return JSON.stringify({ status: 'exported', path: input.destinationPath });
            } catch (error) {
              if (error && (error.number === -1743 || error.number === -1712)) {
                throw error;
              }
              return JSON.stringify({ status: 'unavailable', path: null });
            }
          }
          return JSON.stringify({ status: 'attachmentMissing', path: null });
        }
      }
    }
    return JSON.stringify({ status: 'noteMissing', path: null });
  }
  """

  private static let createNoteSource = """
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

  private static let replaceNoteBodySource = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    for (const account of app.accounts()) {
      for (const folder of account.folders()) {
        for (const note of folder.notes()) {
          if (String(note.id()) !== input.noteId) {
            continue;
          }
          if (note.passwordProtected && note.passwordProtected()) {
            throw new Error('Note is password protected');
          }
          note.body = input.bodyHtml;
          return JSON.stringify({ noteId: String(note.id()) });
        }
      }
    }
    throw new Error('Note not found');
  }
  """

  private static let deleteNoteSource = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    for (const account of app.accounts()) {
      for (const folder of account.folders()) {
        for (const note of folder.notes()) {
          if (String(note.id()) !== input.noteId) {
            continue;
          }
          if (note.passwordProtected && note.passwordProtected()) {
            throw new Error('Note is password protected');
          }
          note.delete();
          return JSON.stringify({ success: true });
        }
      }
    }
    throw new Error('Note not found');
  }
  """

  private static let moveNoteSource = """
  function run(argv) {
    const input = JSON.parse(argv[0]);
    const app = Application('Notes');
    let targetFolder = null;
    for (const account of app.accounts()) {
      if (String(account.id()) !== input.accountId) {
        continue;
      }
      for (const folder of account.folders()) {
        if (String(folder.id()) === input.folderId) {
          targetFolder = folder;
          break;
        }
      }
    }
    if (!targetFolder) {
      throw new Error('Notes folder not found');
    }
    for (const account of app.accounts()) {
      for (const folder of account.folders()) {
        for (const note of folder.notes()) {
          if (String(note.id()) !== input.noteId) {
            continue;
          }
          if (note.passwordProtected && note.passwordProtected()) {
            throw new Error('Note is password protected');
          }
          note.move({ to: targetFolder });
          return JSON.stringify({ noteId: input.noteId });
        }
      }
    }
    throw new Error('Note not found');
  }
  """
}
