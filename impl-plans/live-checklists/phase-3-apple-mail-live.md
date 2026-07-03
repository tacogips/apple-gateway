# Phase 3 Apple Mail Live Checklist

Use this checklist for TASK-004 after Mail schema registration, fake-backed
smoke tests, fixture Envelope Index tests, parser/materializer tests, and
file-download tests pass. Run only from an interactive macOS session owned by
the operator. Do not run this checklist from non-interactive automation.

Do not request or change Full Disk Access unless the operator explicitly opts
into the live run. Do not log real Mail message content, secret values, private
mailbox names beyond the minimum needed to identify a count check, or local
private Mail paths. Record only redacted counts, command outcomes, generated
gateway ids, and follow-up notes.

## Environment

- [ ] macOS version and build recorded:
- [ ] `apple-gateway --version` recorded:
- [ ] Terminal or host process recorded:
- [ ] Test config path recorded, if not default:
- [ ] `mail.mail_root` configured value recorded as present or absent only:
- [ ] If `mail.mail_root` is present, confirm it points at the intended Mail
      version root without recording the absolute path:
- [ ] Scratch output directory recorded as a non-private test directory:
- [ ] Operator confirmed that selected messages are scratch-safe or explicitly
      approved for inspection:

## Full Disk Access Readiness

- [ ] Current Full Disk Access state for the terminal or host process recorded:
- [ ] If not granted, run only non-mutating readiness commands that do not
      require live Mail data, then stop:
- [ ] If the operator opts in, grant Full Disk Access manually in System
      Settings for the recorded host process:
- [ ] Record whether a restart of the host process was required:
- [ ] Record any `FULL_DISK_ACCESS_REQUIRED` error code and remediation text:

Never automate the Full Disk Access grant. Never request access during a
non-interactive run.

## Non-Mutating Readiness Checks

Run schema and permission/readiness checks before reading the live Mail store.
These commands must not mutate Mail data.

```bash
scripts/live-mail-check.sh
swift run apple-gateway permissions status --json
swift run apple-gateway schema print --role full
swift run apple-gateway schema print --role reader
```

- [ ] Full schema exposes exact Query root fields
      `mailAccounts: [MailAccount!]!`,
      `mailboxes(accountId: ID): [Mailbox!]!`,
      `mailMessages(input: MailSearchInput!): MailMessageConnection!`, and
      `mailMessage(messageId: ID!): MailMessage`:
- [ ] Reader schema exposes exact Query root fields
      `mailAccounts: [MailAccount!]!`,
      `mailboxes(accountId: ID): [Mailbox!]!`,
      `mailMessages(input: MailSearchInput!): MailMessageConnection!`, and
      `mailMessage(messageId: ID!): MailMessage`:
- [ ] No Mail Mutation root field name/signature appears in full schema:
- [ ] Reader schema omits `type Mutation` or rejects mutations before resolver
      dispatch:
- [ ] Any readiness error recorded without private paths or message content:
- [ ] Dry-run script output recorded without private paths or message
      content:

## Mail.app Count Comparison

Use Mail.app only for manual visual counts and selection. Do not record message
subjects, bodies, sender addresses, recipient addresses, or local paths.

After Full Disk Access is granted manually and the operator accepts live Mail
metadata reads, the helper can run the limited read-only queries:

```bash
scripts/live-mail-check.sh --read-only \
  --account-id '<optional-account-id>' \
  --mailbox-id '<optional-mailbox-id>'
```

- [ ] Mail.app is open with the same account set the operator wants to test:
- [ ] Representative account label recorded in redacted form:
- [ ] Mail.app account count observed:
- [ ] `mailAccounts` count recorded:

```bash
swift run apple-gateway graphql --query '{
  mailAccounts { id name kind }
}'
```

- [ ] Account count matches Mail.app or difference is explained:
- [ ] Representative mailbox label recorded in redacted form:
- [ ] Mail.app mailbox message count observed:
- [ ] `mailboxes(accountId:)` returns the expected mailbox:

```bash
swift run apple-gateway graphql --query 'query($accountId: ID) {
  mailboxes(accountId: $accountId) { id accountId name totalCount unreadCount }
}' --variables '{"accountId":"<account-id-or-null>"}'
```

- [ ] Mailbox `totalCount` and `unreadCount` match Mail.app for the selected
      mailbox or differences are explained:
- [ ] `mailMessages` count for the selected account/mailbox recorded:

```bash
swift run apple-gateway graphql --query 'query($input: MailSearchInput!) {
  mailMessages(input: $input) {
    totalCount
    edges {
      cursor
      node {
        id
        mailboxId
        dateReceived
        isRead
        isFlagged
        hasAttachments
        files {
          bodyText { kind filename byteSize downloadKey }
          bodyHtml { kind filename byteSize downloadKey }
          rawSource { kind filename byteSize downloadKey }
          attachments { kind filename mimeType byteSize downloadKey }
        }
      }
    }
  }
}' --variables '{"input":{"accountId":"<account-id>","mailboxId":"<mailbox-id>","first":10}}'
```

- [ ] First page ordering matches Mail.app newest-first expectation:
- [ ] No private message content was copied into notes or logs:

## Body Download Check

Use a scratch-safe or operator-selected message whose body may be inspected.
Record only the gateway message id, file kind, output filename, byte count, and
pass/fail result.

- [ ] Selected message id recorded:
- [ ] Selected body file kind recorded (`BODY_TEXT`, `BODY_HTML`, or
      `RAW_SOURCE`):
- [ ] Download key recorded only if it is a generated gateway key and contains
      no local private path:

```bash
swift run apple-gateway file download \
  --key '<body-download-key>' \
  --output-root '<scratch-output-directory>'
```

- [ ] Download completed:
- [ ] Output path stays inside the scratch output directory:
- [ ] Output byte count recorded:
- [ ] Body content was inspected only by the operator and not pasted into this
      log:
- [ ] Evicted or missing body case, if encountered, failed with the documented
      `MESSAGE_NOT_FOUND` details:

## Attachment Download Check

Use a scratch-safe or operator-selected message with an attachment that may be
downloaded. Record only generated gateway ids, attachment filename if
non-sensitive, byte count, and pass/fail result.

- [ ] Selected message id recorded:
- [ ] Attachment file kind is `ATTACHMENT`:
- [ ] Attachment filename recorded only if non-sensitive, otherwise redacted:
- [ ] Download key recorded only if it is a generated gateway key and contains
      no local private path:

```bash
swift run apple-gateway file download \
  --key '<attachment-download-key>' \
  --output-root '<scratch-output-directory>'
```

- [ ] Download completed:
- [ ] Output path stays inside the scratch output directory:
- [ ] Output byte count recorded:
- [ ] Attachment content was not pasted into this log:
- [ ] Missing attachment case, if encountered, failed with the documented
      `MESSAGE_NOT_FOUND` details:

## Reader Behavior

- [ ] Reader serves Mail read queries:

```bash
swift run apple-gateway-reader graphql --query '{
  mailAccounts { id name kind }
}'
```

- [ ] Reader rejects mutation operations with `WRITE_DISABLED_IN_READER`
      before resolver dispatch:

```bash
swift run apple-gateway-reader graphql --query 'mutation {
  createNote(input: { title: "Blocked", bodyText: "No" }) { id }
}'
```

- [ ] Confirm the rejection is owned by the reader runtime, not by Mail
      resolver code:

## System Privacy Constraints

- [ ] Live Mail access was read-only:
- [ ] No Mail data was modified, moved, deleted, flagged, or marked read:
- [ ] No live `Envelope Index` path was opened writable:
- [ ] No local private Mail path was recorded:
- [ ] No real message subject, body, sender, recipient, or attachment content
      was recorded:
- [ ] Any screenshots or terminal logs were redacted before attaching to
      follow-up work:

## Cleanup And Follow-Up

- [ ] Remove downloaded body and attachment files from the scratch output
      directory, unless retained intentionally for a redacted follow-up:
- [ ] Confirm no scratch output remains in private Mail directories:
- [ ] Remove any temporary test config containing machine-local paths:
- [ ] Record live checklist result in
      `impl-plans/active/phase-3-apple-mail.md`:
- [ ] Record skipped steps with concrete reason:
- [ ] File or link follow-up design/user-qa items for unresolved schema drift,
      count mismatch, FDA, reader, body, attachment, or privacy behavior:
