# macOS Platform Access Research (2026-07)

Research snapshot backing the mechanism choices in `design-docs/specs/`.
Scope: macOS 14 Sonoma through macOS 26 Tahoe, unsandboxed Homebrew-distributed
CLI, Developer ID signing available.

## 1. Calendar and Reminders

- EventKit (`EKEventStore`) works from a bare CLI binary; no `.app` bundle is
  required for TCC authorization. Proven by shipping tools:
  [reminders-cli](https://github.com/keith/reminders-cli),
  [ekctl](https://github.com/schappim/ekctl), icalBuddy.
- TCC attributes the grant to the "responsible process", which for an
  interactive shell is the terminal application, not the CLI binary
  ([Qt blog on responsible process](https://www.qt.io/blog/the-curious-case-of-the-responsible-process),
  [Eclectic Light TCC explainer](https://eclecticlight.co/2025/11/08/explainer-permissions-privacy-and-tcc/)).
  Terminal hosts without calendar/reminder usage keys in their own Info.plist
  are silently denied without a prompt (observed with Warp, codex CLI,
  claude-code issue trackers).
- Embedding an Info.plist into the executable via the
  `-sectcreate __TEXT __info_plist` linker flag gives the CLI its own TCC
  identity and usage strings; recommended by Apple DTS for CLI tools
  ([forums thread 111100](https://developer.apple.com/forums/thread/111100),
  [polpiella.dev guide](https://www.polpiella.dev/info-plist-swift-cli/)).
- macOS 14 API changes
  ([TN3153](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos)):
  use `requestFullAccessToEvents` / `requestFullAccessToReminders` with
  `NSCalendarsFullAccessUsageDescription` /
  `NSRemindersFullAccessUsageDescription`. The legacy `requestAccess(to:)`
  now yields write-only access, which cannot read or delete.
- TCC grants key on the codesign designated requirement: Developer ID gives a
  stable identity across updates; ad-hoc signatures degrade to per-build
  cdhash ([forums thread 730043](https://developer.apple.com/forums/thread/730043)).
- AppleScript to Calendar.app/Reminders.app is functionally complete but
  disqualifyingly slow on large stores (single reminder creation observed at
  ~80 s; calendar sweeps take minutes) and requires the GUI apps to run.

## 2. Clock App Alarms

- Clock.app has no scripting dictionary (`sdef` returns error -192 on Tahoe)
  and no public API. AlarmKit (WWDC25) is iOS 26 / Mac Catalyst only, not
  linkable from a plain macOS CLI
  ([AlarmKit docs](https://developer.apple.com/documentation/AlarmKit)).
- The only supported automation path is Shortcuts: macOS 13+ ships
  Create Alarm, Toggle Alarm, Get All Alarms, Start Timer actions; macOS 26
  Tahoe adds Update Alarm, Delete Alarms, Dismiss/Snooze Alarm
  ([AppleInsider Ventura Clock](https://appleinsider.com/inside/macos-ventura/tips/how-to-use-the-clock-app-in-macos-ventura),
  [macmost Tahoe Shortcuts](https://macmost.com/an-introduction-to-shortcuts-automation-in-macos-tahoe.html)).
  `shortcuts run <name>` invokes them from a CLI
  ([Apple support](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)),
  but shortcuts cannot be authored programmatically; the user must install
  them once.
- Alarm storage: `~/Library/Preferences/com.apple.mobiletimerd.plist` on
  macOS 13-15; migrated to Core Data SQLite at
  `~/Library/Group Containers/group.com.apple.mobiletimerd/local.sqlite` on
  Tahoe ([Eclectic Light](https://eclecticlight.co/2025/11/14/how-the-clock-hoards-timers-until-it-breaks/)).
  Read-only inspection is feasible; writing is unsafe (daemon in-memory
  state, cfprefsd caching, schema drift).
- EventKit alarms (`EKAlarm` on events and reminders) are the fully
  API-supported alternative. On macOS 26.2+, a reminder flagged Urgent fires
  a must-dismiss alarm
  ([TidBITS on 26.2](https://tidbits.com/2025/12/12/os-26-2-adds-reminder-alarms-edge-light-podcast-chapters-and-enhanced-safety-alerts/)).

## 3. Apple Notes

- AppleScript dictionary: accounts, nested folders, notes with read-write
  `body` (HTML subset), read-only `plaintext`, `id`, dates,
  `password protected`; commands `make new note`, `delete`, `move`
  ([macosxautomation notes guide](https://www.macosxautomation.com/applescript/notes/04.html)).
  HTML round-trip is lossy: tags and checklists are dropped; CSS stripped.
  Locked notes are invisible. Attachments cannot be created; export is flaky.
- Per-note property access costs one Apple Event round trip; batch fetch
  (`get {id, name, modification date} of every note`) is mandatory at scale.
  macnotesapp was rewritten around batched ScriptingBridge calls for this
  reason ([macnotesapp](https://github.com/RhetTbull/macnotesapp)).
- macOS 26 Tahoe has a live AppleScript -1712 timeout regression affecting
  Notes/Mail/Finder scripting; chunking, explicit timeouts, and retry are
  required ([mjtsai](https://mjtsai.com/blog/2025/09/17/tahoe-applescript-timeouts/)).
- Direct store: `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`,
  bodies gzipped protobuf in `ZICNOTEDATA.ZDATA`
  ([swiftforensics](http://www.swiftforensics.com/2018/02/reading-notes-database-on-macos.html)).
  Reference parsers track schemas through macOS 26
  ([apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser)).
  Read-only in practice; writing risks CloudKit sync corruption. Requires
  Full Disk Access.

## 4. Apple Mail

- Mail.app AppleScript remains complete through Tahoe but is disqualifyingly
  slow (~44 s for 1,200 messages vs ~30 ms via SQLite,
  [benchmark](https://dev.to/whoffagents/how-to-read-apple-mail-without-applescript-its-1000x-faster-cji)),
  needs Mail running, and hits the Tahoe -1712 hang.
- On-disk layout: `~/Library/Mail/V10/` from Ventura through Tahoe (probe
  V11 then V10 then V9 at startup). `.emlx` files are a byte-count line, raw
  RFC 822, and a trailing XML plist with flags; large attachments become
  `.partial.emlx` plus an `Attachments/` directory needing reassembly
  ([emlx format](http://mike.laiosa.org/2009/03/01/emlx.html),
  [partial-emlx-converter](https://github.com/qqilihq/partial-emlx-converter)).
- `V10/MailData/Envelope Index` is SQLite (`messages`, `subjects`,
  `addresses`, `mailboxes`, `summaries`; Cocoa epoch dates, offset
  978307200). Open read-only/immutable: Mail holds a WAL write lock and
  writing forces a full reindex
  ([DFIR writeup](https://forge-work.com/dfir/knowledge/artifacts/macos-mail-envelope-index)).
- `~/Library/Mail` requires Full Disk Access. FDA has no prompt API; only a
  manual grant in System Settings (deep link:
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).
- Prior art: [apple-mail-mcp](https://github.com/imdinu/apple-mail-mcp)
  (Envelope Index + emlx + FTS5, millisecond queries on 73k messages),
  [mikez/emlx](https://github.com/mikez/emlx).

## 5. Notifications

- `UNUserNotificationCenter` from a non-bundled binary crashes
  (`bundleProxyForCurrentProcess is nil`) through Tahoe; the embedded
  `__info_plist` trick does not fix it
  ([forums thread 724249](https://developer.apple.com/forums/thread/724249)).
  A real on-disk `.app` is required.
- Helper-app prior art: [alerter](https://github.com/vjeantet/alerter)
  (actively maintained Swift rewrite, signed and notarized, reply text and
  action buttons); terminal-notifier is stalled since 2017. Homebrew can
  install a `.app` inside the Cellar and exec its inner binary.
- `osascript 'display notification'` supports title/subtitle/sound only, no
  actions, and can be silently dropped when the host terminal lacks
  notification permission.
- Delivered-notification database moved in Sequoia: through Sonoma it is
  `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`; on
  Sequoia 15 and Tahoe 26 it is
  `~/Library/Group Containers/group.com.apple.usernoted/db2/db` and is
  TCC-protected, requiring Full Disk Access
  ([9to5mac](https://9to5mac.com/2024/09/01/security-bite-apple-addresses-privacy-concerns-around-notification-center-database-in-macos-sequoia/)).
  Schema: `record` table with `app_id`, NSKeyedArchiver binary-plist `data`
  BLOBs, `delivered_date` as CFAbsoluteTime
  ([schema writeup](https://github.com/75033us/blog/blob/main/2022-02-02-macos-monterey-notification-database-schema.md)).
- No supported API reads other apps' notifications;
  `getDeliveredNotifications` returns only the caller's.
- Clearing: own notifications via
  `removeDeliveredNotifications(withIdentifiers:)` in the helper app.
  System-wide clearing exists only as Accessibility UI scripting of the
  NotificationCenter process, which breaks on most major releases and is
  version-branched ([clear-all gist](https://gist.github.com/lancethomps/a5ac103f334b171f70ce2ff983220b4f)).
  Deleting rows from the live database races `usernoted` and is unsafe.

## Cross-Cutting Facts

1. Interactive TCC prompts attribute to the terminal application; behavior
   varies by which app launched the CLI. Denials from permission-key-less
   hosts are silent.
2. Full Disk Access can never be requested programmatically.
3. Developer ID signing gives stable TCC identity across updates; ad-hoc
   does not survive rebuilds.
4. macOS 26 Tahoe ships an AppleScript -1712 timeout regression affecting
   Mail, Notes, and Finder scripting: chunk work, set explicit timeouts,
   retry.
