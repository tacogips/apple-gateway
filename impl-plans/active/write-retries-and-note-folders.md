# Write timeout behavior and Notes folder creation

Issue11 tracks automatic retry of uncertain non-idempotent Notes writes. Preserve existing public bridge signature and read retries; use explicit no-retry policy for all Notes mutations, Mail writes and Clock UI mutations. Test adapters with a fake osascript that records a call then reports timeout, proving no second write occurs.

Add bounded createNoteFolder(input:{accountId,parentFolderId?,name}):NoteFolder. Validate single folder name, account/parent ownership, return an existing unique exact-parent name match or create once and verify returned identity. No broader folder CRUD. Cover nested/same-name/account boundaries and native JXA command contract.

Run full Swift tests, smoke, lint; release Apple0.1.11 both macOS architectures, tap verification. Riela integration follows frozen0.2.8 completion in0.2.9 with Apple container private exec transport.

Validation: all 287 tests plus smoke passed; SwiftLint reports zero violations in 141 files. The first full run under concurrent optimized release compilation timed out in two existing notifier stub tests (2-second budget); the rerun passed without test or production changes. Retry regressions prove one attempt for each mutation family and retained retries for reads. Folder tests cover actual JXA collection insertion with a mock Notes application, canonical name reuse, explicit ownership and readback mismatch.
