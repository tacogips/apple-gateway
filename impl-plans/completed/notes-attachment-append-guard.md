# Prevent unsafe Notes attachment append

Issue: https://github.com/tacogips/apple-gateway/issues/13

A controlled native fixture proved one imported PNG becomes two generic attachments after HTML APPEND. Reject APPEND when metadata contains native attachments before any body read/write. Keep text-only append and explicit REPLACE; document caller ownership and restoration. Test no writer invocation and no body hydration, then full tests/smoke/lint and both architecture release0.1.12.

Final gates:288 tests and smoke passed; zero lint violations in141 files.

Completed v0.1.12 at97dccf0be085e8567fef341b6719edaac84f9d93, four public assets verified. Both architectures/full+reader versions/checksums/notifier verified. Tap4519a4f audit/fetch/upgrade/test passed; metadata workflow39118665031 succeeded, immutable615be803 and public main version/hash verified after CDN refresh.

Caller actual Riela0.2.9/Apple0.1.12 probe on a disposable PNG note rejected APPEND; plaintext, exact attachment IDs and exported99-byte PNG SHA256 all remained unchanged. Caller also proved text-only explicit REPLACE plus native import restores actual exported bytes.
