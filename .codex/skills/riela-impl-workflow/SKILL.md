---
name: riela-impl-workflow
description: Run or document the apple-gateway Riela design-and-implementation review loop for full issue-resolution work, including accepted design, implementation plans, implementation, adversarial review, documentation refresh, verification, plan archival, and final commit handoff.
---

# Riela Implementation Workflow

Use the current repository state and runtime communications as authoritative.
Treat one `workflowMode: "issue-resolution"` execution as one accepted work
package unless the workflow explicitly fans out.

## Workflow Contract

- Run the documentation refresh only after Step 7 accepts the implementation.
- Do not reopen accepted design or implementation scope during documentation
  refresh. Align user-facing docs with shipped behavior and accepted evidence.
- Review `README.md`, this skill, directly affected repository-facing skills,
  the accepted design, the active or completed implementation plan, and the
  current diff before commit generation.
- Archive a fully completed plan under `impl-plans/completed/`, update links to
  its completed path, and preserve permission-gated live checks as residual
  risks rather than unchecked implementation tasks.
- Preserve workflow mode, workflow execution id, issue and communication
  references, codex-agent references, file paths, findings, review decisions,
  exact verification commands, results, gaps, and residual risks in handoffs.
- Return machine-readable JSON when the runtime requests it.

## Accepted Phase 2 Apple Notes Work Package

Workflow execution
`codex-design-and-implement-review-loop-session-655` resolved the Notes list
hydration findings in `issue-resolution` mode. The Step 7 decision is
`accepted_adversarial_review`. Issue references are `comm-001899`,
`comm-001903`, `comm-001913`, `comm-001917`, `comm-001922`, `comm-001923`,
`comm-001925`, `comm-001927`, `comm-001932`, `comm-001937`, and `comm-001939`.
No codex-agent references were supplied.

The accepted user-facing behavior is:

- Notes list queries discover candidates, filter, sort, resolve cursors, and
  paginate using lightweight metadata before reading shared state or
  attachment metadata.
- Only selected page ids receive detailed hydration, bounded by
  `limits.apple_event_batch_size`; empty pages perform no detail request.
- A selected note's sharing-property or attachment-access failure falls back
  to `isShared: false` or an empty attachment list without aborting hydration
  for other selected notes.
- Missing, locked, moved, renamed, or otherwise stale page metadata remains a
  request-level error. Automation denial, timeout, and Notes.app unavailable
  errors also remain request-level errors.
- The GraphQL schema, cursor format, body and attachment export behavior,
  mutation behavior, other domains, and live-checklist scope are unchanged.

The accepted design is
`design-docs/specs/design-apple-notes.md`. The completed plan is
`impl-plans/completed/phase-2-apple-notes.md`. The mandatory user-facing
summary is in `README.md` under macOS permissions and setup.

## Accepted Verification

Record the accepted scoped verification as 98 passing tests and SwiftLint with
zero violations across 129 files. The initial test failure was environment-only
and was corrected with the repository-prescribed Xcode exports. Use these
commands when reconciling the final documentation and plan state:

```bash
nix develop -c bash -lc 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault; export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH; swift test --filter "AppleEventBridge|Mail|Notes|Permissions|Usernoted"'
swiftlint
test ! -e impl-plans/active/phase-2-apple-notes.md
test -f impl-plans/completed/phase-2-apple-notes.md
rg -n '^[-*] \[ \]' impl-plans/completed/phase-2-apple-notes.md
rg -n 'impl-plans/active/phase-2-apple-notes\.md|impl-plans/completed/phase-2-apple-notes\.md' design-docs README.md impl-plans
git --no-pager diff --check
git status --short -- README.md .codex/skills/riela-impl-workflow design-docs impl-plans
```

Browser E2E is not applicable: this SwiftPM repository has no browser-facing
surface, package manifest, browser E2E script, Playwright/Cypress configuration,
or web E2E suite.

Keep these residual risks explicit:

- Live Notes verification depends on macOS TCC permissions and Notes scripting
  behavior.
- Exceptional cleanup failures may retain mode-0600 capture files inside a
  mode-0700 temporary directory.
