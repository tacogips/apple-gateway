# Notes attachment accessor patch 0.1.8

## Cause and fix

Live Notes JXA attachment properties allow direct invocation (`attachment.id()`),
but `attachment.id.call(attachment)` throws `Can't convert types`. The generic
accessor swallowed that failure and dropped otherwise valid attachment IDs.
Invoke function properties through `object[propertyName]()` instead, preserving
the existing unavailable-property fallbacks and bridge-error propagation.

## Verification

- A regression fixture whose callable properties reject `Function.call` failed
  before the fix and passed afterward.
- Xcode `mise run test`: 273 tests and CLI smoke tests passed.
- `mise run lint`: zero violations.
- Read-only live verification of the user-selected note returned two attachment
  download keys; both embedded HEIC images were materialized separately to avoid
  colliding filenames. No note content or attachment identifiers are included
  in this document. The note was not modified.

## Release scope

Patch version 0.1.8 uses the existing macOS Formula release channel with arm64
and x86_64 archives. Archives must preserve both CLI executables and the notifier
bundle expected by the current tap. This patch does not fix Konjac CloudKit sync.
