# Apple Mail Updates Design

## Status

Implemented

## Scope

The full `apple-gateway` GraphQL schema supports four lightweight Mail state
changes:

- mark a message read or unread;
- flag or unflag a message;
- move a message to another mailbox;
- delete a message.

`apple-gateway-reader` remains query-only and rejects every mutation at the
GraphQL runtime boundary. Sending messages and creating drafts are not part
of this surface.

## Safety Boundary

The Envelope Index and `.emlx` retrieval paths remain strictly read-only.
Updates are performed through Mail.app's Apple Event interface using JXA.
User values are JSON encoded and passed as an `osascript` argument; they are
never interpolated into script source.

Each update first resolves the stable `message-N` identifier through the
read provider. It captures the Envelope Index row id, RFC message id, account
display name, and source mailbox path. A move additionally resolves the
destination mailbox before invoking automation. Invalid or missing targets
fail before Mail.app is changed.

The JXA adapter prefers the RFC message id when locating the message and uses
the Mail store row id as a fallback. It scopes lookup to the resolved account
and mailbox path. Destination lookup is similarly scoped.

## GraphQL

The full schema exposes:

```graphql
type MailUpdateResult {
  success: Boolean!
  messageId: ID!
}

type MailMoveResult {
  success: Boolean!
  messageId: ID!
  mailboxId: ID!
}

type Mutation {
  setMailMessageRead(messageId: ID!, isRead: Boolean!): MailUpdateResult!
  setMailMessageFlagged(messageId: ID!, isFlagged: Boolean!): MailUpdateResult!
  moveMailMessage(messageId: ID!, mailboxId: ID!): MailMoveResult!
  deleteMailMessage(messageId: ID!): DeleteResult!
}
```

Mutation results confirm accepted Mail.app automation. They deliberately do
not return a refetched `MailMessage`, because Mail's Envelope Index can update
asynchronously after an Apple Event completes.

## Permissions and Errors

Mail reads require Full Disk Access. Mail updates also require Automation
permission for Mail.app. Permission state appears as `mailAutomation`, and
the prompt-capable request is:

```bash
apple-gateway permissions request --domain mail
```

Automation denial maps to `AUTOMATION_DENIED`; timeout maps to
`APPLE_EVENT_TIMEOUT`; missing runtime targets map to `MESSAGE_NOT_FOUND` or
`MAILBOX_NOT_FOUND`.

## Verification

Unit tests cover stable target resolution, invalid and missing preflight
targets, GraphQL dispatch, role isolation, and script-source payload
separation. Live Mail.app verification remains manual because it changes user
mail state.
