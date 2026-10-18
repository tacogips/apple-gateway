# Notes read representations and folder parents

- Expose note(noteId:, bodyKind: NoteBodyKind = PLAINTEXT), forwarding to the existing NotesReadService body-kind implementation.
- Preserve default/plaintext reads; test requested HTML, invalid enum, provider calls and oversized HTML file descriptors.
- Fix issue #7: listFolders reads each folder container ID and emits null only for the account container. Verify nested, duplicate-name and account-filter behavior by executing the actual JXA template against fixtures.
- Run Swift tests/smoke/lint, publish Apple gateway patch 0.1.9 with the existing macOS formula archive matrix, then integrate into Riela after frozen 0.2.7 packaging completes.

The installed Notes scripting dictionary defines folder.container as account or folder. No folder creation or other CRUD surface is added.

Notes implementation verified with 277 Swift tests and CLI smoke tests passing, SwiftLint zero violations. Issue #8 tracks HTML body-kind selection, issue #7 tracks folder hierarchy. Formula packaging must also preserve both existing CLI products and the notifier app; the generic checked-in scripts currently omit them and retain template repository metadata. Fix and verify this release-blocking packaging path before tagging.

Released v0.1.9 at 8e3558e with four public assets. Both architecture archives verified checksums, both CLI versions and notifier bundle. Packaging scripts corrected under issue9 to preserve all products. 277 Swift tests and CLI smoke passed; lint zero violations. Homebrew strict audit/fetch/upgrade/test passed. Tap53f7a77 metadata workflow39113536267 succeeded; public main and immutable e258d8a version/source checksum verified.
