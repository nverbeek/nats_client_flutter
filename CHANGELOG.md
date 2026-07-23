# 1.0.17

## New Features

- **JetStream consumer Pause/Resume**: Consumer Detail now has a Pause action (prompting for how long) and a Resume action, suspending message delivery/pulls without deleting the consumer; a "Paused until" indicator shows the current state
- **Filtered/targeted stream Purge**: Purge now supports an optional subject filter, plus a choice of purging everything, keeping only the newest N messages, or purging up to a given sequence number — instead of only all-or-nothing

## Maintenance & Dependencies

- Upgraded `dart_nats` to 1.4.0, adopting the consumer pause/resume and filtered/keep/sequence-bounded purge APIs it added; Object Store's new streaming upload/download APIs were deliberately not adopted this release (see ROADMAP.md)
- Worked around a `dart_nats` parsing gap where a paused consumer's pause-expiry timestamp wasn't read correctly off the server's response

# 1.0.16

## New Features

- **Post-reconnect auto-recovery**: the JetStream Browse/Tail, Key-Value, Object Store, and Services dashboards now automatically retry out of a stuck error state once the connection recovers from a drop, instead of requiring a manual Refresh
- **JetStream Stream Edit**: streams can now be edited after creation, not just at creation time — storage/retention/discard policy, size/count limits, and the allow-rollup/deny-delete/deny-purge flags are all exposed in the same dialog used to create a stream
- **JetStream stream Subjects redesigned as chips**: a stream's subject list (previously one unbounded comma-joined line — some streams have 600+) now wraps as chips, collapsed to the first 12 with a "+N more" toggle and a one-click copy button
- **Hex/Binary payload view**: Message Detail now has a Text/Hex toggle for the payload, automatically defaulting to Hex whenever a payload isn't valid UTF-8
- **KV Bucket Info + richer Consumer Detail**: a new Bucket Info dialog surfaces TTL/replicas/history depth for Key-Value buckets, and JetStream Consumer Detail now shows ack-wait, max-deliver, and max-ack-pending
- **Quick-Subscribe from a message row**: "Subscribe to This Subject" in a row's menu adds an exact-subject subscription with one click, alongside whatever wildcard subscription originally delivered it
- **Right-click context menus**: right-clicking a row (Live Messages, JetStream Browse/Tail, or KV keys) now opens the same action menu as its overflow button, anchored at the click point; every message row menu also gained a "Copy Subject" action alongside "Copy"
- **Per-message timestamps**: an opt-in "Show Message Timestamps" setting adds a thin 12-hour/millisecond timestamp to each message row, plus a "Received" time in Message Detail
- **Max Messages Kept setting**: caps how many messages the app buffers in memory (default 10,000, 0 = unlimited), trimming the oldest once the buffer would exceed the limit

## Bug Fixes

- Typing in the Filter/Find field (or any other text field) no longer triggers message-row keyboard shortcuts — previously, typing a stray "r" while a message was selected could actually re-publish (Replay) it
- Fixed an occasional wrong-row selection when a new message arrived during the ~300ms window used to distinguish a single click from a double-click
- Fixed a possible startup crash from window-resize/move events firing before preferences finished loading, and from an unrecognized saved authentication method
- Fixed the post-reconnect recovery signal never actually firing, due to an incorrect assumption about the connection's status-transition sequence
- Entering an invalid regex in the Filter/Find field no longer crashes the list — the error is now surfaced inline instead
- Publishing while the client's reconnect buffer is full now surfaces a clear error instead of silently dropping the message
- Fixed a crash when a JetStream API error response omits its usual description field
- Fixed a Key-Value watch subscription leak on repeated bucket selection; a broken watch now surfaces an error/Retry instead of silently going stale
- Fixed Stream Edit silently wiping a stream's sub-day Max Age or resetting a KV bucket's direct-get setting when saved without touching those fields
- Added NATS name/subject validation to the stream, consumer, and KV-key creation dialogs, catching invalid input before it reaches the server
- Fixed Object Store Download reporting a false "Downloaded" success when the save-file dialog was cancelled; Upload/Download now confirm before a large transfer or before silently overwriting an existing object
- Fixed KV/Object Store dialogs crashing if a confirmation dialog (e.g. Delete) was left open across a disconnect
- Status bar text now truncates instead of overflowing on a narrow window

## Maintenance & Dependencies

- Upgraded `dart_nats` to 1.2.3, and moved Ack/Nak/Term to the new `ackSync()`/`nakSync()`/`termSync()` methods, which confirm the server actually received them
- The upstream `dart_nats` repo moved to `dart-nats/dart-nats`
- KV key-list loading now batches requests instead of firing them all at once, and JetStream Browse's filter updates incrementally instead of rescanning the whole list on every batch
- Full repo-wide `dart format` pass and documentation updates (`AGENTS.md`/`README.md`)
- Added unit/widget/integration test coverage for every feature and fix above, including live-server verification

# 1.0.15

## New Features

- **NATS Micro-services (Services API) discovery**: new opt-in "Services" tab (off by default) discovers any NATS microservices (ADR-32) advertising themselves on the network and shows their ping/info/stats — per service and per instance, refreshing live as instances start and stop
- **Multi-select on the Live Messages list**: Shift+Click and Ctrl+Click (plus Ctrl+Shift+Up/Down) select multiple messages at once; Ctrl+C or the row menu's "Copy Selected (N)" copies them all as plain text (`subject: payload`, one line per message). The status bar shows a running "Selected: N" count while anything is selected
- **Export & Replay captured messages to/from file**: export a selection or your entire capture to an NDJSON file (with a warning past 20,000 messages), then replay a previously exported file back onto a connected server with configurable per-message and per-repeat pacing, a live "will send N messages" preview, and a cancelable in-app progress banner
- **Message Detail headers now render as a table**: keys and values are laid out in a proper two-column grid instead of one flattened text block, with a dedicated copy button (matching the existing Payload copy button) for grabbing the raw `key: value` text
- **Paused banner**: pausing the Live Messages or JetStream Browse Messages list now shows a clear banner above the list, in addition to the existing toolbar button, so it's obvious at a glance that new messages are being buffered rather than lost

## Bug Fixes

- JetStream Browse Messages now displays single-line by default, matching the main Live Messages list, instead of always showing up to 5 lines per message
- Cleaned up extra spacing near the JetStream Clear/Pause buttons

## Maintenance & Dependencies

- `dart_nats` is temporarily pinned to a fork branch carrying the new client-side service-discovery API, pending that PR merging upstream and a new tagged release
- Updated GitHub Actions workflow dependencies and the Flutter version used for CI builds
- Added unit/widget/integration test coverage for every feature above, including live-server verification (service discovery against a real hosted microservice, multi-select/copy interactions, header table rendering, and export/replay round-tripping byte-for-byte)

# 1.0.14

## New Features

- **Subscription Manager & per-subscription color indicators**: the old comma-delimited Subjects field is now a chip row — add/remove individual subscriptions live (no reconnect needed), each tagged with a color-coded indicator on its Live Messages rows so you can tell at a glance which subscription delivered a message. An overflow "+N more" chip opens a full manager dialog for editing beyond what fits inline
- **Queue group subscriptions**: each subscription can now optionally join a queue group, splitting delivery across every app/client sharing that group instead of every member receiving everything
- New "Show Subscription Colors" toggle in Settings (on by default) if you'd rather not see the color indicators
- **Message headers on send**: the Send dialog now has a Headers section for attaching custom key/value headers to outgoing messages, matching the header support already present on the receive side. Replay and Edit & Send now also preserve the original message's headers
- **JetStream Account Info panel**: a new info button on the JetStream and Key-Value dashboards opens a read-only summary of account memory/storage usage vs. limits, stream/consumer counts, and API stats
- **Connection host/port history**: the Host field is now an autocomplete dropdown offering your last 10 successfully-connected targets, filtering as you type; picking one fills in scheme/host/port together, with per-entry delete and a "Clear history" action
- **Material 3 refresh**: adopted OS dynamic color (Material You) where the platform supports it, and moved primary/icon-only actions (Connect, Send, Browse Messages, Upload, Put Value, Pause/Resume, and more) to the current Material 3 emphasis widgets (`FilledButton`/`IconButton.filled`/`.filledTonal`/`.outlined`) in place of the older `ElevatedButton` styling

## Bug Fixes

- Removed the now-redundant "Single-line messages" setting, since multi-line display is the only mode the message list actually uses
- Picked up an upstream `dart_nats` fix for JetStream account info misreporting usage/limits as all-zero for standard (non-multi-tenant) accounts

## Maintenance & Dependencies

- Bumped `dart_nats` to `1.1.2` and added an Acknowledgements section to the README crediting the library
- Added `dynamic_color` for OS accent-color support
- Added unit/widget/integration test coverage for every feature above, including live-server verification (queue group message-splitting, subscription color assignment, header round-tripping, account info against a real server, and connection-history recording/dropdown behavior)

# 1.0.13

## New Features

- **Object Store Inspector**: a new tab (toggleable via "Enable Object Store" in Settings, on by default) for browsing and managing JetStream-backed Object Store buckets — files/blobs rather than the small key/value pairs Key-Value Stores handles
- Create and delete buckets (storage type, max size, TTL, replica count)
- Upload any local file via your OS's file picker — large files are chunked automatically
- Download objects via a native save dialog; downloads are verified against the object's SHA-256 digest before being written
- Live search narrows the object list by name
- Object Store has no live-update mechanism (unlike Key-Value Stores), so the list is refreshed on demand rather than updating automatically — a Refresh button covers this
- This feature wraps an `EXPERIMENTAL` API in the underlying NATS client library; that's called out both in the dashboard itself and in the in-app help

## Maintenance & Dependencies

- Added unit/widget test coverage (`ObjectStoreManager`, Create Bucket dialog, dashboard) — Upload/Download are injectable so tests can drive the full flow with a fake file instead of the OS file picker
- Added a real-backend integration test covering the full bucket/object lifecycle, including confirming an externally-written object only appears after Refresh
- Extended the README screenshot tour with a new Object Store screenshot and demo-data seeding
- Settings dialog now scrolls if its content grows past the dialog's fixed height (surfaced by the new Object Store toggle)

# 1.0.12

## New Features

- **Pause/Resume on both message lists**: Freeze Live Messages or a JetStream "Browse Messages" list to read without it scrolling out from under you — incoming messages keep buffering in the background and a badge shows how many are waiting, so nothing's lost
- **Jump to top**: A floating button appears on both message lists once you've scrolled away from the top, jumping straight back to the newest message
- **Filter & Find on JetStream message lists**: The stream/consumer browsing views now have the same Filter and Find controls as Live Messages
- Scroll position now stays stable on both lists during fast message bursts
- **Automatic update checks**: The app checks this repo's GitHub Releases on startup and shows a small dismissible popover if a newer version is available (toggle it off in Settings if you'd rather not be notified)

## Bug Fixes

- Fixed the selected stream's highlight in the JetStream Streams sidebar rendering over unrelated UI (like the connection bar) when scrolling a long stream list
- Fixed message rows with non-UTF-8 payloads (binary or otherwise malformed data) showing a red error box instead of the message content

## Maintenance & Dependencies

- Added integration test coverage for Filter/Find, Pause/Resume, scroll-position stability, and the Ctrl+Enter shortcut on both message lists
- Added unit/integration test coverage for the new automatic update check
- Fixed a test-suite issue where update-check tests were breaking unrelated tests
- Bumped `actions/checkout` in CI to avoid a Node.js deprecation warning
- Updated the automated screenshot capture script to demonstrate Pause/Resume and Jump-to-top in the Messages screenshot

# 1.0.11

## New Features

- **Expanded Authentication Support**: The Security Settings dialog now supports four authentication methods alongside existing TLS/mTLS — Username/Password, Token, NKey Seed, and decentralized JWT+NKey (`.creds` file)
- Only the fields relevant to your chosen method are shown, and the NKey Seed field has an obscure/reveal toggle like a password field
- Credentials are only remembered on this device if you opt in via "Remember credentials on this device" — otherwise you're prompted for them each launch
- Authentication failures now show a specific "Authentication failed — check your credentials" message instead of a generic connection failure

## Maintenance & Dependencies

- Added unit tests for the new authentication logic (`buildAuthConnectOption`, `isAuthenticationError`) and expanded Security Settings dialog widget test coverage
- Added a real-backend integration test suite verifying a successful connection for all four authentication methods against dedicated fixture servers, running in CI alongside the existing suites on every push
- Documented the new Authentication options in the in-app help and README

# 1.0.10

## New Features

- **JetStream Monitor**: New "JetStream" tab for monitoring streams and consumers — message/byte counts, retention, and ack/redelivery stats at a glance
- **Stream & Consumer Management**: Create, purge, and delete streams; create and delete consumers (push or pull, any ack policy)
- **Stream Message Browsing**: Browse a stream's messages live, or tail a specific consumer and Ack / Nak / Term individual messages
- **JetStream Publishing**: Publish messages with JetStream delivery acknowledgement directly from the existing Send Message dialog
- JetStream is enabled by default and can be turned off in Settings if you don't need it

## Maintenance & Dependencies

- Added a real-backend integration test suite that exercises the app against a live NATS server (core pub/sub, the full JetStream lifecycle, and Live Messages filter/find/keyboard shortcuts), running in CI alongside the existing widget/unit tests on every push
- Automated screenshot generation for the README — screenshots are now captured directly from a live app run instead of by hand, making them easy to keep current
- Migrated remaining deprecated Flutter APIs (`withOpacity` → `withValues`, `DropdownButtonFormField.value` → `initialValue`)

# 1.0.9

## Maintenance & Dependencies

- Improved (simplified) release asset names

# 1.0.8

## New Features

- **Windows ARM64 Support**: Official build of Windows ARM64 has been introduced.

## Maintenance & Dependencies

- Re-aligned to `dart_nats` official branch, latest version.
- Updated to latest flutter & upgraded dependencies

# 1.0.7

## New Features

- New reconnect interval setting
- New keyboard shortcuts
- Double-click to open message detail
- Improved UX for message detail dialog
- Improved snackbar styling

# 1.0.6

## New Features

- **Message Detail Copy**: Added copy button allowing users to copy formatted JSON payloads to clipboard

## Bug Fixes

- Resolved issues with web variant
- Fixed Docker build

## Maintenance & Dependencies

- Upgraded dependencies to latest

# 1.0.5

## New Features

- **Enhanced UI Customization**: Added new view settings to improve user experience
- **Improved List View**: Implemented new list view interactions for better UX
- **New App Icon**: Introduced a completely redesigned, modern app icon

## Bug Fixes

- Resolved deprecation warnings throughout the codebase
- Fixed various debug errors
- Corrected list item display issues

## Maintenance & Dependencies

- **Library Updates**:
  - Replaced discontinued markdown library with a modern alternative
  - Updated multiple dependencies to their latest versions
- **Code Quality**:
  - Refactored dialog code into separate classes for better maintainability

# 1.0.4

## New Features

- Application now remembers it's window size & position

# 1.0.3

## New Features

- Certificates for TLS connections may be specified in the new Security Settings dialog
- Several UI improvements including new color theme
- User may now press Ctrl + Enter to send messages in the Send Message dialog

## Maintenance & Dependencies

- Dependency version upgrades

# 1.0.2

## Bug Fixes

- Connection preferences were not honored properly at startup when making initial connection attempt

# 1.0.1

## New Features

- Application version is now displayed in the help documentation

## Maintenance & Dependencies

- Automated Docker build added
- Automated Docker Hub release on tag push added

# 1.0.0

- Initial release
