# Phase 2 Apple Notes Live Checklist

Use this checklist for TASK-005 after Notes schema registration and fake-backed
smoke tests pass. Run only against scratch Notes data. Do not use personal or
production notes.

## Environment

- [ ] macOS version recorded:
- [ ] `apple-gateway --version` recorded:
- [ ] Terminal or host process recorded:
- [ ] Test config path recorded, if not default:
- [ ] `limits.apple_event_batch_size` recorded:
- [ ] `limits.apple_event_timeout_seconds` recorded:

## Automation Prompt

- [ ] Revoke or start from a clean Notes Automation permission state when safe.
- [ ] Run a minimal read query:

```bash
swift run apple-gateway graphql --query '{ noteAccounts { id name isDefault } }'
```

- [ ] Record whether the first-run Automation prompt appeared before the
      command completed:
- [ ] If prompted, grant access and rerun the command. Record whether it
      succeeds:
- [ ] If denied, record the error code and stderr/stdout behavior:

## Scratch Data Flow

- [ ] Create or select a scratch Notes folder. Folder id:
- [ ] Create a scratch note:

```bash
swift run apple-gateway graphql --query 'mutation($in: CreateNoteInput!) {
  createNote(input: $in) { id name bodyHtml modificationDate }
}' --variables '{"in":{"folderId":"<scratch-folder-id>","title":"Apple Gateway Scratch","bodyText":"Initial body"}}'
```

- [ ] Created note id recorded:
- [ ] Search/list finds only expected scratch data:

```bash
swift run apple-gateway graphql --query 'query($in: NoteSearchInput!) {
  notes(input: $in) { totalCount edges { node { id name snippet } } }
}' --variables '{"in":{"folderId":"<scratch-folder-id>","query":"Apple Gateway Scratch","first":10}}'
```

- [ ] Append or update body:

```bash
swift run apple-gateway graphql --query 'mutation($in: UpdateNoteBodyInput!) {
  updateNoteBody(input: $in) { id name bodyHtml modificationDate }
}' --variables '{"in":{"noteId":"<note-id>","mode":"APPEND","bodyHtml":"<div>Appended body</div>"}}'
```

- [ ] Move the note to a second scratch folder:

```bash
swift run apple-gateway graphql --query 'mutation($noteId: ID!, $folderId: ID!) {
  moveNote(noteId: $noteId, folderId: $folderId) { id folderId name }
}' --variables '{"noteId":"<note-id>","folderId":"<second-scratch-folder-id>"}'
```

- [ ] Delete the note and confirm it is removed from normal search results:

```bash
swift run apple-gateway graphql --query 'mutation($noteId: ID!) {
  deleteNote(noteId: $noteId) { success }
}' --variables '{"noteId":"<note-id>"}'
```

## Reader Behavior

- [ ] Reader serves Notes read queries:

```bash
swift run apple-gateway-reader graphql --query '{ noteAccounts { id name } }'
```

- [ ] Reader rejects Notes mutations with `WRITE_DISABLED_IN_READER` before
      resolver dispatch:

```bash
swift run apple-gateway-reader graphql --query 'mutation {
  createNote(input: { title: "Blocked", bodyText: "No" }) { id }
}'
```

## macOS 26 Tahoe Timeout And Chunking

- [ ] On macOS 26, run a list/search query that requires enough scratch notes
      to observe chunking by `limits.apple_event_batch_size`.
- [ ] Record observed chunk size:
- [ ] Record whether any `-1712` or timeout occurred:
- [ ] If timeout occurred, record whether the one retry recovered or failed
      with the bridge timeout classification instead of hanging:

## Cleanup

- [ ] Remove scratch notes and scratch folders.
- [ ] Record any remaining manual cleanup needed:
