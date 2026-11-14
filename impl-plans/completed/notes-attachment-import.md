# Native Notes attachment import

Issue: https://github.com/tacogips/apple-gateway/issues/10

Expose createNoteAttachment(input:{noteId,filePath}):NoteAttachment using Notes native make attachment with data file, which copies bytes into Notes storage. Accept explicit absolute readable regular files, preserve existing note body/attachments, and return matching attachment readback with existing best-effort download key. Reader role remains mutation-free. Add protocol default failure to preserve custom writer compatibility.

Verify service validation and provider dispatch, GraphQL schema/role/input mapping, mock JXA exact command and missing/locked guards, and actual disposable fixture export/hash through parent. Run full tests/smoke/lint and both macOS release archives before0.1.10 publication; integrate released revision into Riela0.2.8.

Caller proved one native import returns one unique attachment ID but Notes metadata repeats that ID. Deduplicate nonempty attachment IDs at metadata, body and hydrated-list outputs while preserving distinct same-filename attachments. Add regression before release.

Released v0.1.10 at35df811d3acb44907f3635b34cc9e9bf601295b9 with four public assets. Final281 tests+CLI smoke and zero lint violations; both architectures checksum/CLI version/native schema/notifier bundle verified. Caller disposable native PNG import/export SHA-256 matched. Tap5eb27dc audit/fetch/upgrade/test passed; metadata workflow39117014023 succeeded and public main/immutable metadata version and formula checksum verified. General bridge timeout retries for non-idempotent writes are recorded separately as issue11; no live duplicate write was observed.
