# Apple Mail Updates

**Status**: Complete
**Design Reference**: `design-docs/specs/design-apple-mail-updates.md`

## Purpose

Add lightweight Mail message state changes to the full `apple-gateway`
executable without weakening the reader role or writing Mail's local database.

## Deliverables

- [x] Mail write service with stable target preflight
- [x] Mail.app JXA update adapter
- [x] Full-schema GraphQL mutations
- [x] Reader mutation isolation
- [x] Mail Automation permission status and request
- [x] Unit tests and documentation

## Progress Log

- 2026-07-24: Implemented read/unread, flag/unflag, move, and delete.
