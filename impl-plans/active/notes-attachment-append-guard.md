# Prevent unsafe Notes attachment append

Issue: https://github.com/tacogips/apple-gateway/issues/13

A controlled native fixture proved one imported PNG becomes two generic attachments after HTML APPEND. Reject APPEND when metadata contains native attachments before any body read/write. Keep text-only append and explicit REPLACE; document caller ownership and restoration. Test no writer invocation and no body hydration, then full tests/smoke/lint and both architecture release0.1.12.

Final gates:288 tests and smoke passed; zero lint violations in141 files.
