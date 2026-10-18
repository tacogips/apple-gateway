# Native Notes attachment import

Issue: https://github.com/tacogips/apple-gateway/issues/10

Expose createNoteAttachment(input:{noteId,filePath}):NoteAttachment using Notes native make attachment with data file, which copies bytes into Notes storage. Accept explicit absolute readable regular files, preserve existing note body/attachments, and return matching attachment readback with existing best-effort download key. Reader role remains mutation-free. Add protocol default failure to preserve custom writer compatibility.

Verify service validation and provider dispatch, GraphQL schema/role/input mapping, mock JXA exact command and missing/locked guards, and actual disposable fixture export/hash through parent. Run full tests/smoke/lint and both macOS release archives before0.1.10 publication; integrate released revision into Riela0.2.8.
