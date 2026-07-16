# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap details the development plan, UI architecture, and implementation milestones for expanding the **NATS Client UI** with core advanced NATS ecosystem capabilities: **JetStream (Phase B)**, **Key-Value Stores (Phase A)**, **Expanded Authentication (Phase D)**, and **Update Notifications (Phase E)**.

These features are made possible by our successful migration to the official mainline `dart_nats` package (originally `^1.1.1`; now `^1.2.1`, see Milestone 18).

---

## Progress Overview
- [x] **Milestone 0**: Migrate custom fork to mainline `dart_nats: ^1.1.1` and verify compatibility.
- [x] **Milestone 1**: Design & Implement **Phase B: JetStream Stream & Consumer Monitor** (High Priority). 1a (read-only monitor) and 1b (mutations) complete.
- [x] **Milestone 2**: Design & Implement **Phase A: Key-Value (KV) Store Inspector** (Medium Priority). Implementation, docs, unit/widget tests, and a live-server verification pass (full bucket/key lifecycle, live cross-client updates, and the optimistic-concurrency conflict path) are done.
- [x] **Milestone 3**: Clean up, finalize error handling, write widget/unit tests, and bundle releases. Quality Assurance and Platform Verification are done for Windows, Linux, and Web (including confirming JetStream works over the web target's forced `ws://` scheme).
- [x] **Milestone 4**: Design & Implement **Phase D: Expanded Authentication Support** (username/password, token, NKey, `.creds`) (Medium Priority). Implementation, docs, unit/widget tests, and a live-server verification pass (correct + wrong credentials) are done for all four methods.
- [x] **Milestone 5**: Design & Implement **Phase E: Update Notifications** (Low Priority). Checks GitHub Releases on startup and surfaces a dismissible in-app notice when a newer version is published; opt-out toggle in Settings. Implementation, unit tests, and a live-API verification pass (both the update-available and up-to-date paths) are done.
- [x] **Milestone 6**: Design & Implement **Phase F: Live Message List UX Improvements** (Medium Priority). Filter/Find on the JetStream Browse Messages view (plus tab-aware Ctrl+F/Ctrl+Shift+F), scroll-position-preserving inserts on both message lists (verified correct and performant at thousands-of-messages/large-burst scale), and a Pause/Resume control on both. Implementation and a live-server verification pass are done.
- [x] **Milestone 7**: Design & Implement **Object Store Inspector** (Medium Priority). Implementation, docs, unit/widget tests, and a live-server verification pass (bucket/object lifecycle, chunked upload/download with digest verification, explicit-Refresh-since-there's-no-`watch()`) are done.
- [x] **Milestone 8**: Design & Implement **Message Headers on Send** (Low/Medium Priority). Implementation, unit/widget tests, and a live-server verification pass (published header round-trips back through the app's own loopback subscription and appears in Message Detail) are done.
- [x] **Milestone 9**: Design & Implement **Queue Group Subscriptions** (Medium Priority). Built together with Milestone 11 (see that milestone's note). Implementation, unit/widget tests, and a live-server verification pass (two queue-group members splitting a message burst) are done.
- [x] **Milestone 10**: Design & Implement **JetStream Account Info Panel** (Low Priority). Implementation, unit/widget tests, and a live-server verification pass are done. The pass caught a real bug in vendored `dart_nats-1.1.1`'s `JetStream.accountInfo()` (see Milestone 10's section below) — fetching account info now bypasses it entirely.
- [x] **Milestone 11**: Design & Implement **Subscription Manager & Per-Subscription Color Indicators** (Medium Priority). The Subjects text field is now a chip row (`lib/subject_chips_row.dart`) with a queue-group field baked into each subscription and an overflow "+N more" chip opening a full manager dialog (`lib/subscription_manager_dialog.dart`); Live Messages rows show a per-subscription color dot. Implementation, unit/widget tests, and a live-server verification pass are done.
- [x] **Milestone 12**: Design & Implement **Connection Host/Port History** (Low/Medium Priority). The Host field is now an editable `Autocomplete` dropdown (`lib/connection_history.dart`) offering up to 10 previously-*successfully*-connected targets, filtering as you type; selecting one fills scheme/host/port together, with per-entry delete and a "Clear history" action. Implementation, unit tests, and a widget/live-server test pass are done (two real Flutter framework bugs found and fixed along the way — see the milestone's notes below).
- [ ] **Milestone 13** *(Optional follow-up — may never be picked up)*: Design & Implement **Message Direction Indicator (Incoming vs. Outgoing)** (Low/Medium Priority). Not started.
- [ ] **Milestone 14** *(Optional follow-up — may never be picked up)*: Design & Implement **Request/Reply Correlation Improvements** (Medium Priority). Not started.
- [ ] **Milestone 15** *(Optional follow-up — may never be picked up)*: Investigate & Implement **Code Signing for Windows & macOS Builds** (Low Priority, cost-gated). Not started — research done, decision on which paid/free path pending.
- [x] **Milestone 16**: Apply the Latest Material 3 Standards (Low/Medium Priority). Done ahead of Milestones 12-15, same as Milestones 9-11 before it. OS dynamic color (Material You) via `DynamicColorBuilder`, plus `FilledButton`/`IconButton.filled`/`.filledTonal`/`.outlined` adopted for primary/icon-only actions across the connection bar, bottom toolbar, dashboards, and Security Settings' file pickers.
- [ ] **Milestone 17**: Design & Implement **NATS Server Monitoring Dashboard** (Medium Priority). Not started.
- [x] **Milestone 18**: Design & Implement **NATS Micro-services (Services API) Discovery** (Medium Priority). Client-side discovery (`discoverServices()`/`getServicesInfo()`/`getServicesStats()`) was contributed to a fork of `dart_nats` (`nverbeek/dart-nats`, branch `feature/service-discovery`, PR #44) as the complement to the hosting-side `addService()`/`MicroService` the upstream maintainer landed independently just before this milestone started. PR #44 has since merged upstream and shipped in `chartchuo/dart-nats` **1.2.0** (published to pub.dev as **1.2.1**, 2026-07-16) — `pubspec.yaml` now depends on a normal `dart_nats: ^1.2.1` pub.dev version constraint, no `git:` pin needed. App-side: a new opt-in (default **off**) Services tab, `lib/service_discovery_manager.dart`, `lib/service_discovery_dashboard.dart`. Implementation, unit/widget tests, and a live-server verification pass (a real second `dart_nats` client hosting a fake ADR-32 service, discovered/inspected/stats-checked, then confirmed to vanish from a fresh Discover after it stops) are done.
- [x] **Milestone 19**: Design & Implement **Multi-Select + Clipboard Copy** (Medium Priority). The Live Messages list supports Shift+Click, Ctrl+Click, and Ctrl+Shift+Up/Down for range and disconnected multi-select; Ctrl+C or the row menu's "Copy Selected (N)" copies every selected row as plain text (`subject: payload`, one line per message). The status bar shows a "Selected: N" count while anything is selected. Implementation, tests, and a live-server verification pass are done.
- [ ] **Milestone 20**: Design & Implement **Per-Subscription Message Rate Sparkline** (Low Priority, tentative). Not started — user flagged this one as a "maybe," lowest-confidence of the batch.
- [x] **Milestone 21**: Design & Implement **Message Detail Headers Table + Raw Copy** (Low Priority). The Message Detail dialog's Headers section now renders as a bordered, rounded two-column grid (key | value, one row per header, horizontal dividers, long values wrap instead of overflowing) instead of one flattened text block, with a copy button next to the "Headers" label that copies the same raw `key: value`-per-line text the section used to show. Implementation, tests, and a visual verification pass (light + dark) are done.
- [x] **Milestone 22**: Design & Implement **Export & Replay Captured Messages to/from File** (Low Priority). Bulk **Export** (Selected/All, NDJSON with base64 payloads, warn-and-proceed past 20,000 messages) and **Replay** (file-based bulk publish with message/repeat interval + repeat count pacing, a live preview, and a cancelable `ReplayBanner` that can coexist with `PausedBanner`) added to the Live Messages tab's toolbar and row menu. Implementation, unit/widget tests, and a live-server verification pass (export/replay byte-for-byte round trip, repeat interval honored, Stop halts promptly) are done.
- [ ] **Milestone 23** *(Blocked — not actionable yet)*: Adopt Reconnect-Buffer Overflow Handling (`maxReconnectBuffer`) (Low Priority). Not started — waiting on PR #44 to land upstream and a new `dart_nats` release (likely `1.1.3`).
- [ ] **Milestone 24** *(Blocked — not actionable yet)*: Adopt Heartbeat Ping/Pong for Faster Dead-Connection Detection (Low Priority). Not started — waiting on PR #44 to land upstream and a new `dart_nats` release (likely `1.1.3`).
- [ ] **Milestone 25**: Design & Implement **Quick-Subscribe to Exact Subject from Message Row** (Low/Medium Priority). Not started.

---

## Milestone 0: Mainline Migration (Completed)
- [x] Update `pubspec.yaml` to request `dart_nats: ^1.1.1`.
- [x] Resolve `Consumer` class name collision with `package:provider` inside `lib/main.dart` (resolved via `hide Consumer`).
- [x] Resolve compile-time platform type mismatch for `SecurityContext` (resolved via type cast `as dynamic` on parameters).
- [x] Run static analysis (`flutter analyze`) to guarantee error-free builds.

---

## Milestone 1: Phase B — JetStream Monitor (High Priority)

### Objective
JetStream is the built-in persistence engine for NATS. This module adds a multi-pane management dashboard to list configured streams, inspect consumer status, view real-time streams, publish payloads, and perform operations such as stream purges and consumer creation.

### UI Architecture & Concept
We will introduce a **main navigation/tab bar** or sliding **NavigationRail** to separate the current message stream view from the JetStream/KV dashboards.

```
+---------------------------------------------------------------------------------+
|  NATS Client UI                                                [SETTINGS] [💡]  |
+---------------------------------------------------------------------------------+
|  Tabs: [✉️ Live Messages]  [*️⃣ JetStream Dashboard]  [📁 Key-Value Stores]     |
+---------------------------------------------------------------------------------+
|  Left Pane: Stream List               |  Right Pane: Stream Details / Consumer  |
|  +---------------------------------+  |  Stream: "orders" (2,300 msgs, 4.5 MB)  |
|  | [Stream] orders                 |  |  [Purge Stream]   [Delete Stream]       |
|  | [Stream] telemetry              |  |  -------------------------------------  |
|  | [Stream] notifications          |  |  Consumers:                             |
|  +---------------------------------+  |  - "billing-processor" (Pull, Active)   |
|  | [Add Stream]                    |  |  - "reporting-worker" (Push, Idle)      |
|  +---------------------------------+  |  +------------------------------------+ |
|                                       |  | [Create Consumer]                  | |
|                                       |  +------------------------------------+ |
+---------------------------------------+-----------------------------------------+
| [Status Bar] Total Messages: 2420  |  URL: nats://127.0.0.1:4222  | Connected   |
+---------------------------------------------------------------------------------+
```

### Implementation Checklist

**Milestone 1a — Read-only monitor (Completed):**
- [x] **UI Infrastructure**:
  - [x] Add a `TabController`/`TabBar` to swap between Live Messages and JetStream, kept outside the shared connection bar and status bar since both tabs use the same connection.
  - [x] Keep JetStream logic out of `lib/main.dart` — implemented in `lib/jetstream_manager.dart`, `lib/jetstream_dashboard.dart`, and `lib/jetstream_message_view.dart` instead.
  - [x] Make JetStream an opt-out setting (`Enable JetStream` toggle in Settings, on by default) so the tab and its machinery are fully hidden for users who don't want it.
- [x] **JetStream Backend Core (`lib/jetstream_manager.dart`)**:
  - [x] Thin wrapper around `client.jetStream()` exposing `listStreams()`, `streamInfo()`, `listConsumers()`, `consumerInfo()`, and `checkAvailability()` (via `accountInfo()`).
- [x] **Stream & Consumer Monitor**:
  - [x] Master/detail dashboard listing streams (name, message count, size, storage type) with a detail pane (subjects, retention, byte/message counts, first/last activity).
  - [x] Read-only consumer list per stream (name, push/pull, ack policy, pending/ack-pending/redelivered counts) with a detail dialog.
- [x] **Stream Message Inspection**:
  - [x] "Browse Messages" live tail using an ephemeral, auto-cleaning `OrderedConsumer` (`js.orderedConsumer()`) — no manual consumer setup required just to look at a stream's contents.

**Milestone 1b — Mutations (Completed):**
- [x] Stream management capability:
  - [x] Create a stream dialog (specifying Stream Name, Subjects, maxAge, replicas) — `lib/jetstream_stream_dialog.dart`.
  - [x] Delete a stream (with confirmation).
  - [x] Purge a stream (`JsStream.purge()`, with confirmation).
- [x] Consumer management:
  - [x] Build a **"Create Consumer" dialog** supporting both push (deliver subject) and pull models — `lib/jetstream_consumer_dialog.dart`.
  - [x] Delete a consumer (with confirmation).
- [x] Publish into a stream (`jetStream().publishString()`), by extending `SendMessageDialog` with a "get delivery ack" (JetStream publish) toggle, wired through `sendMessage()` in `lib/main.dart`.
- [x] Enable standard NATS acknowledgment buttons (`Ack`, `Nak`, `Term`) on tailed JetStream payloads: selecting **Tail** on a consumer opens `lib/jetstream_consumer_tail_view.dart`, which binds to that named consumer (honoring its real ack policy, unlike the ephemeral "Browse Messages" ordered consumer) and enables Ack/Nak/Term buttons when its ack policy is `explicit`.

---

## Milestone 2: Phase A — Key-Value (KV) Store Inspector (Medium Priority)

### Objective
Provide a real-time developer GUI for inspecting, updating, and monitoring NATS Key-Value buckets. This eliminates the need to run terminal commands to verify local database states.

### UI Architecture & Concept
A clean multi-column layout. The left column lists active KV buckets, and the right column displays all keys in the selected bucket with their values, revisions, and operations history.

```
+---------------------------------------------------------------------------------+
|  Tabs: [✉️ Live Messages]  [*️⃣ JetStream Dashboard]  [📁 Key-Value Stores]     |
+---------------------------------------------------------------------------------+
|  Left Pane: KV Buckets                |  Right Pane: Keys & Active Payloads     |
|  +---------------------------------+  |  Bucket: "app-config"                   |
|  | [Bucket] app-config             |  |  Search Keys: [_______________________] |
|  | [Bucket] user-features          |  |  +------------------------------------+ |
|  +---------------------------------+  |  | Key: "db.port"                     | |
|  | [Create Bucket]                 |  |  | Value: 5432                        | |
|  +---------------------------------+  |  | Revision: #3 (Put) | [Edit] [Delete| |
|                                       |  | ---------------------------------- | |
|                                       |  | Key: "maintenance-mode"            | |
|                                       |  | Value: false                       | |
|                                       |  +------------------------------------+ |
+---------------------------------------+-----------------------------------------+
```

### What `dart_nats` actually supports (verified against `dart_nats-1.1.1/lib/src/kv.dart` and `jetstream.dart`, not assumed)
- `client.jetStream().keyValue(bucket)` / `KeyValue(client, bucket)` binds to a bucket; `createKeyValue()`/`deleteKeyValue()` create/delete the backing `KV_<bucket>` stream.
- `KeyValue.get(key)` already filters out tombstoned (deleted/purged) entries, returning `null` for them — no extra filtering needed on this app's side.
- `kv.keys()` and `kv.watch()` both work by spinning up a temporary/ephemeral JetStream consumer filtered to `$KV.<bucket>.>` and reading the stream — not a dedicated KV-index API. `watch()` returns `Stream<KeyValueEntry?>` with a `KeyValueOp` (`put`/`delete`/`purge`) per event.
- **Real bug caught only by live-server testing, not by reading the source**: `KeyValueConfig.toStreamConfig()` (used internally by `createKeyValue()`) silently drops both `ttl` and replica count — neither field makes it onto the wire. `KvManager.createBucket()` therefore builds the `StreamConfig` itself (mirroring what that conversion *should* do) rather than going through the package's own bucket-creation helper, so TTL and replicas set in the Create Bucket dialog actually take effect.
- `kv.update(key, value, revision)` is the primitive for optimistic concurrency: it publishes with `PubOpts(expectLastSubjectSeq: revision)`, and the server rejects with a "wrong last sequence" `NatsException` if the key changed since that revision — this is what backs the Edit dialog's conflict detection (distinct from `kv.put()`, a blind overwrite used only for brand-new keys).

### Implementation Checklist
- [x] **Bucket Selection**:
  - [x] Fetch the list of all registered KV buckets using standard management APIs — `KvManager.listBuckets()` lists streams and filters to the `KV_` name prefix (mirrors `JetStreamManager.listStreams()`).
  - [x] Implement a **"Create Bucket"** form (specifying Bucket Name, history depth, TTL, replicas) — `lib/kv_bucket_dialog.dart`.
  - [x] Implement a **"Delete Bucket"** command — trash icon per bucket row, with confirmation.
- [x] **Key-Value Inspection Backend (`lib/kv_manager.dart`)**:
  - [x] Bind selected bucket to `KeyValue` controller using `js.keyValue(bucketName)` (constructed directly as `KeyValue(client, bucket)` — the package's own `keyValue()` helper is `async` only to support an optional `create: true`, unneeded here since bucket creation is a separate explicit step).
  - [x] Fetch key entries using `kv.get(key)`. Tombstone filtering is handled by the package itself (see above) — no extra logic needed.
- [x] **Key Mutation & Concurrency**:
  - [x] Build **"Put Value"** dialog form supporting text/JSON string values — `lib/kv_put_dialog.dart`, shared between create (`kv.putString()`) and edit (`kv.updateString()` with the loaded revision) via an `existingRevision` parameter that also locks the Key field on edit.
  - [x] Implement key deletions (`kv.delete(key)`) and purges (`kv.purge(key)`) — both available from each key row's menu, with confirmation.
  - [x] Add Optimistic Concurrency checks using revisions — edit calls `kv.updateString(key, value, expectedRevision)`; a stale edit surfaces "This key changed since it was loaded — reload and try again." (`describeKvError()`) instead of silently overwriting someone else's change. (Roadmap originally named `kv.getRevision(key)` for this; in practice the revision already carried on the `KeyValueEntry` loaded into the list — from the initial `get()` or a live `watch()` update — is what's passed through, so a separate revision fetch turned out to be unnecessary.)
- [x] **Live Watcher Integration**:
  - [x] Support real-time updates of the key listing pane using stream listeners on `kv.watch()` — after the initial key list loads, `KvDashboard` subscribes to `manager.watch(bucket)` and applies each `put`/`delete`/`purge` event to the in-memory key map, so changes from *any* client (not just this app) appear live with no manual refresh.
- [x] **Tests & live-server verification**: `test/kv_manager_test.dart` (pure `bucketNameFromStream()`/`describeKvError()` logic), `test/kv_bucket_dialog_test.dart`, `test/kv_put_dialog_test.dart`, and `test/kv_dashboard_test.dart` (fake-manager widget tests, mirroring the JetStream dashboard's `FakeJetStreamManager` pattern) cover the UI against fakes. `integration_test/kv_lifecycle_test.dart` runs the full lifecycle against a real JetStream-enabled `nats-server` in one ordered scenario: create bucket → put → a *second, direct* `dart_nats` client's write shows up live via `watch()` with no manual refresh → edit → a stale-edit conflict (opened while a concurrent external write lands) is correctly rejected rather than clobbering it → history → delete key → purge key → delete bucket. Runs in CI automatically (the `test` job loops over every `integration_test/*_test.dart` file); no separate fixture server needed since KV buckets are backed by the same JetStream-enabled server used for the JetStream milestone.

---

## Milestone 3: Clean up, Testing & Release

- [~] **Platform Verification**: all five CI build targets (Windows x64/ARM64, Linux, macOS, Web) compile cleanly. Functional (not just compile) verification of the JetStream tab:
  - [x] **Windows**: manually driven end-to-end (connect, publish, filter/find, message detail, JetStream stream/consumer create) via the `scripts/capture_screenshots.ps1` automation.
  - [x] **Linux**: the full `integration_test/` suite (including the JetStream stream/consumer lifecycle) runs for real under Xvfb in CI on every push — see `.github/workflows/build.yml`'s `test` job.
  - [x] **Web**: confirmed JetStream works over a real WebSocket transport — ran the full create-stream/publish-with-ack/create-consumer/tail/ack/nak/term/delete/purge lifecycle against a `nats-server` with `websocket {}` enabled, forcing the app's `ws://` scheme (the same one the web build is locked to via `kIsWeb`). The server's own audit log confirmed every JetStream API call was tagged `"client_type":"websocket"`. No `kIsWeb` guards needed — JetStream isn't blocked by the websocket scheme boundary. (Caveat: this ran on the desktop target with `ws://` forced, not inside an actual compiled-for-web/Chrome process — `flutter test` doesn't support web for `integration_test`, and standing up a version-matched ChromeDriver for a true in-browser run wasn't pursued. Since JetStream is just NATS pub/sub over whatever transport `dart_nats` gives it, and plain ws:// connectivity is already a shipped, working feature, this is considered sufficient evidence rather than a real gap.)
  - [ ] **macOS**: compiles in CI (`build-macos` job) but has never been functionally exercised — no Mac was available to verify. Remaining gap; needs someone with a Mac to run `flutter run -d macos` (or the `integration_test/` suite) once.
- [x] **Quality Assurance**:
  - [x] Fix any deprecated API alerts (e.g. migrate `withOpacity` instances to `.withValues()`) — none remain; `flutter analyze` is clean project-wide.
  - [x] Add comprehensive unit and widget tests under `test/` verifying the new JetStream layouts (`test/jetstream_dashboard_test.dart`, `test/jetstream_manager_test.dart`, `test/send_message_dialog_test.dart`, plus one file per standalone dialog — see below).
  - [x] Add a real-backend `integration_test/` suite (against an actual JetStream-enabled `nats-server`, not fakes) covering the core pub/sub round trip, Live Messages tab interactions, the full JetStream stream/consumer mutation lifecycle, and the Browse Messages view.
  - [x] **Coverage gap list** (originally audited by hand against every interactive control in `lib/`; ~90 controls found, ~21 touched by either suite at the time). All closed except the one item explicitly deferred:
    - [x] **Message Detail dialog** — `test/message_detail_dialog_test.dart` (close icon/button, copy + "Copied!" animation, no-payload state).
    - [x] **Settings & Security Settings dialogs** — `test/settings_dialog_test.dart`, `test/security_settings_dialog_test.dart`. The three cert-field **Browse** buttons (`file_picker`, opens a native OS dialog) are explicitly **not** tested — not meaningfully testable without a much larger investment; deliberately deferred.
    - [x] **Live Messages tab's daily-use controls** — `integration_test/live_messages_interactions_test.dart` (Filter, Find, Copy/Detail/Replay/Edit & Send/Reply To, and the keyboard shortcuts).
    - [x] **JetStream Browse Messages view** — `integration_test/jetstream_browse_test.dart`.
    - [x] **Nak / Term buttons** — folded into `integration_test/jetstream_lifecycle_test.dart`'s tail scenario alongside Ack.
    - [x] **Form validation & conditional fields** — `test/jetstream_stream_dialog_test.dart`, `test/jetstream_consumer_dialog_test.dart`.
    - [x] **Error/retry paths** — stream-list/consumer-list retry, ephemeral-consumer gating, and the zero-message Browse-disabled state added to `test/jetstream_dashboard_test.dart`.
    - [x] **Keyboard shortcuts** — Ctrl+Enter in `test/send_message_dialog_test.dart`; Ctrl+F/Ctrl+Shift+F/D in `integration_test/live_messages_interactions_test.dart`.
- [x] **Build Pipeline**:
  - [x] Verify that GitHub Actions CI runner ([.github/workflows/build.yml](.github/workflows/build.yml)) packages release bundles successfully for Windows x64/ARM64, Linux, macOS, Web, and Docker.
  - [x] Add a `test` job (real `nats:latest -js` service container + Xvfb) that runs both `test/` and `integration_test/` on every push/PR, and gate every build/release job on it via `needs: test`.

---

## Milestone 4: Phase D — Expanded Authentication Support (Medium Priority)

### Objective
Today the client only supports TLS/mTLS (via the 🔒 Security Settings dialog) or no application-level credentials at all. Beyond the TCP/TLS transport, `dart_nats: ^1.1.1` also implements the standard NATS authentication mechanisms server operators actually configure: username/password, bearer tokens, bare NKey seeds, and decentralized JWT+NKey `.creds` files. This milestone adds first-class UI for all of them, so connecting to a server configured with any of these auth modes doesn't require editing connection strings or reaching for another tool.

### What `dart_nats` actually supports (verified against `dart_nats-1.1.1/lib/src/{client,common}.dart`, not assumed)
- **Username / Password** — `ConnectOption(user: ..., pass: ...)` passed to `client.connect()`.
- **Auth Token** — `ConnectOption(authToken: ...)`.
- **NKey seed** — `client.seed = 'SU...'` set before connecting arms the client to sign the server's nonce challenge (`_sign()` in `client.dart`), **but that alone is not sufficient**: the CONNECT message's `nkey` field (the public key) must also be set via `ConnectOption(nkey: ...)`, or a real server rejects with `authentication error - Nkey ""`. Caught by live-server testing, not by reading the source alone — see the verification note below.
- **Decentralized JWT + NKey (`.creds` file)** — `client.loadCredentialsFile(path)` / `loadCredentials(content)`, the standard format used by NGS/Synadia Cloud and self-hosted operator-mode NATS. This is the modern, recommended auth style for anything beyond a single self-hosted server, and it's a one-call helper — cheap to support.
- **mTLS** — already implemented via the existing Security Settings dialog. When a server is configured with `verify_and_map`, the existing client-certificate UI already doubles as authentication, not just transport encryption, so no new work is needed there.
- **Auth failures on the wire** — the server sends an `-ERR` containing `"Authorization Violation"`/`"Authentication..."`; `dart_nats` already stops retrying and closes the connection when it sees this (`client.dart` around the `-ERR` handler), but `lib/main.dart`'s `natsConnect()` doesn't currently distinguish it from any other connection failure — worth fixing alongside this milestone so a bad password doesn't just say "Failed to connect!".

**Explicitly out of scope**: generating new NKey identities or JWTs (`Nkeys.createUser()` etc. exist in the package, but provisioning credentials is an operator/`nsc` concern, not something this client should do) and OAuth-style browser-redirect flows (NATS has no native equivalent).

### UI Architecture & Concept
Rather than a second toolbar icon, extend the existing **Security Settings** dialog (still opened via the same 🔒 button) with a new "Authentication" section below the current TLS/mTLS fields, separated by a divider. TLS and application-level auth are both really answering "how do I securely connect" from a user's point of view, and this app already groups loosely-related settings into one dialog elsewhere (the main Settings dialog mixes font size, single-line mode, reconnect interval, and the JetStream toggle). An "Authentication Method" dropdown switches between `None` (today's behavior) / `Username & Password` / `Token` / `NKey Seed` / `Credentials File (.creds)`, revealing only the relevant fields for the selected method — the same progressive-disclosure pattern already used for the cert file pickers above it. The dialog becomes scrollable if needed once both sections are present.

Unlike host/port/subjects/TLS cert paths, which are always remembered, the fields introduced here are real secrets. `SharedPreferences` isn't an encrypted OS keychain on every platform this app targets, so these are **opt-in** to persist: an unchecked-by-default "Remember credentials on this device" checkbox, re-entered each launch otherwise.

```
+-------------------------------------------------------------+
|  Security Settings                                     [X]  |
+-------------------------------------------------------------+
|  Trusted Certificate:  [ ca.pem              ] [ Browse... ] |
|  Certificate Chain:    [                     ] [ Browse... ] |
|  Private Key:          [                     ] [ Browse... ] |
|  ------------------------------------------------------------|
|  Authentication                                              |
|  Method: [ Credentials File (.creds)          v ]           |
|                                                               |
|  Credentials File:  [ ngs-user.creds        ] [ Browse... ]  |
|                                                               |
|  [ ] Remember credentials on this device                     |
|      (stored locally, not encrypted)                         |
+-------------------------------------------------------------+
|                                                       [Close] |
+-------------------------------------------------------------+
```

### Implementation Checklist
- [x] **`lib/security_settings_dialog.dart`**: added an "Authentication" section below the existing TLS fields (behind a divider) — method dropdown + conditional fields: username/password text fields, token text field, NKey seed text field with an obscure/reveal toggle (like a password field), and a `.creds` file picker reusing the existing `pickFile()` / `file_picker` pattern already used for the cert pickers (generalized `pickFile()` to take an `allowedExtensions` parameter). No new toolbar button — same 🔒 icon and dialog as today, just with more in it (now scrollable via `SingleChildScrollView`).
- [x] **`lib/main.dart`**: wires the selected method into `natsConnect()` by building the appropriate `ConnectOption` (via `lib/auth_manager.dart`'s `buildAuthConnectOption()`) and/or setting `natsClient.seed` / calling `natsClient.loadCredentials()` before `connect()`.
- [x] **`lib/constants.dart`**: new preference keys for the auth method + its fields, following the existing TLS key-naming convention.
- [x] **Opt-in persistence**: secrets are only written to `SharedPreferences` when "Remember credentials on this device" is checked (`persistAuthSettingsIfRemembered()`/`persistAuthSettings()`); unchecking it wipes any previously-persisted values (`clearPersistedAuthSettings()`) while keeping the in-memory session values. Reuses the existing gzip+base64 encoding already used for the TLS private key field for the `.creds` file contents.
- [x] **Clearer auth-failure feedback**: `natsClient.onError` is now wired up in `natsConnect()`, and `lib/auth_manager.dart`'s `isAuthenticationError()` (mirroring the phrase-matching `dart_nats` itself uses to stop retrying) distinguishes an authorization-violation/authentication close from a generic connection failure, surfacing "Authentication failed — check your credentials" instead of the generic "Failed to connect!".
- [x] Updated `assets/app_help.md` with a new "Authentication" section documenting each method, mirroring the existing "TLS Notes" section.
- [x] Added unit tests for the pure/testable parts (`test/auth_manager_test.dart` covers `buildAuthConnectOption()` and `isAuthenticationError()`) following the same "pure logic vs. network calls" split used in `lib/jetstream_manager.dart` and `test/jetstream_manager_test.dart`; `test/security_settings_dialog_test.dart` was extended with an "Authentication section" group covering the dropdown's conditional fields, the NKey obscure/reveal toggle, the `.creds` file row, and the remember-credentials checkbox.
- [x] **Real-server verification — all four methods**: each was first manually run against a real Docker `nats:latest` server (correct credentials connecting successfully, and wrong credentials correctly triggering `onError`/`isAuthenticationError()` and the "Authentication failed" message), then the "correct credentials connect" case for all four was turned into a permanent, CI-running `integration_test/authentication_test.dart` (see `integration_test/fixtures/auth/` for the committed, non-secret fixture configs/creds, and AGENTS.md's Recipe H to run it locally):
  - **Username/Password**: server with `authorization { user; password; }`.
  - **Token**: server with `authorization { token: "..." }`.
  - **NKey seed**: server with `authorization { users = [{ nkey: "U..." }] }`. This is what caught the real bug noted above (`ConnectOption.nkey` wasn't being set) — `buildAuthConnectOption()` and `natsConnect()` were fixed to derive the public key via `Nkeys.fromSeed(seed).publicKey()` and pass it through, and `test/auth_manager_test.dart` now asserts on it.
  - **Credentials File (`.creds`)**: a throwaway, non-expiring operator/account/user was generated with `nsc` (the official `nats-io/nsc` CLI, downloaded temporarily into the OS scratch dir with the user's explicit go-ahead and deleted afterward; only the generated config/`.creds` fixture files were kept). Worked correctly on the first try, no code changes needed.
  - Because NATS's simple `authorization` block (user/pass, token, bare nkey) and its operator/JWT mode are mutually exclusive server configs, `.github/workflows/build.yml`'s `test` job starts one disposable `nats-server` container per method (as plain steps, not `services:`, since `services:` start before `actions/checkout` — too early to mount these config files) alongside the existing shared JetStream service.
  - Along the way this also surfaced a pre-existing `dart_nats` quirk (not introduced by this milestone, and common to all four methods): when the server's `-ERR Authorization Violation` closes the connection, an internal `Completer` that nothing ever awaits gets `completeError()`'d, which Dart reports as an uncaught zone error. Confirmed harmless for the real app — `runApp()` already runs inside a `runZonedGuarded` zone, which swallows it after logging (verified with standalone `runZonedGuarded` probes against each server config); `flutter test`'s stricter zone is what makes it look fatal there, which is why only the *positive* (correct-credentials) path was automated — see `integration_test/authentication_test.dart`'s doc comment and AGENTS.md's Recipe H for why the negative path is deliberately left as a manual/standalone-probe check instead. Not chased further since fixing it for real would mean changing this app's global reconnect/retry semantics (`retryCount: -1`), a bigger change than this milestone's scope.

---

## Milestone 5: Phase E — Update Notifications (Low Priority)

### Objective
This app only distributes through GitHub Releases — there's no app-store or in-place auto-update mechanism, so a user has no way of knowing a new version exists short of manually checking the repo. This milestone adds a lightweight, opt-out check on startup: on launch, the app asks GitHub's Releases API for this repo's latest published release and, if it's newer than the running build, shows a dismissible in-app notice with a button to the release page. No download/install automation — the user still gets the new build from GitHub themselves, same as today.

### UI Architecture & Concept
On startup (after preferences load), the app calls `GET https://api.github.com/repos/nverbeek/nats_client_flutter/releases/latest` (no auth required; a single request per launch is well within GitHub's anonymous rate limit) and compares its `tag_name` against `PackageInfo.fromPlatform()`'s version, already used elsewhere in the app (e.g. the Help dialog's `%APP_VERSION%`). If newer, a small popover fades/slides in at the top-right of the window, built from a raw `OverlayEntry` rather than a `SnackBar` or `MaterialBanner` — both of those anchor to the bottom or span the full window width, which is a lot of visual weight for a one-line "there's a new version" notice with a single link:

```
+---------------------------------------------------------------------------------+
|  NATS Client UI                                        [SETTINGS] [💡]   +-----+
|                                                                           |🔄 Up|
|                                                                           |date |
|                                                                           |avail|
|                                                                           |able |
|                                                                           |     |
|                                                                           |Vers.|
|                                                                           |1.1.0|
|                                                                           |is   |
|                                                                           |out. |
|                                                                           |     |
|                                                                           |[View|
|                                                                           |Rel.]|
+---------------------------------------------------------------------------------+
```

(In practice it's a compact ~300px rounded card in the corner, not a full column — see the screenshot in the Real-API verification note below.) "View Release" opens the GitHub release page in the system browser via `url_launcher`; the small `X` in its corner dismisses it for the rest of the session (it isn't persisted — the next launch checks again). The check itself is opt-out via a new "Check for Updates" toggle in the existing Settings dialog, alongside "Enable JetStream", on by default.

### Implementation Checklist
- [x] **`lib/update_checker.dart`** (new): pure-logic/network split, following the same pattern as `lib/jetstream_manager.dart` and `lib/auth_manager.dart` — `fetchLatestRelease()` hits the GitHub Releases API (injectable `http.Client` for tests, 5s timeout, fails silently to `null` on any error/malformed response since this is a best-effort convenience check, never something that should interrupt the user) and `isNewerVersion()` does a numeric (not lexicographic) dotted-version comparison so `1.2.10` correctly beats `1.2.9`.
- [x] **`lib/settings_dialog.dart`**: added a "Check for Updates" `Switch` below "Enable JetStream", following the exact same row pattern; `onSave` callback extended with the new bool.
- [x] **`lib/main.dart`**: `checkForUpdates()` runs once after preferences load if the setting is enabled (and again immediately if the user just flipped it on from within Settings, for instant feedback), calling `_showUpdateAvailablePopover()` when `isNewerVersion()` is true. That method inserts a single `OverlayEntry` (tracked in `_updateOverlayEntry` and cleaned up in `dispose()`) holding a `Material` card with a `TweenAnimationBuilder`-driven fade/slide-in, positioned via `Positioned(top: 16, right: 16)` over the whole window.
- [x] **`lib/constants.dart`**: new `prefUpdateCheckEnabled` preference key + `defaultUpdateCheckEnabled = true`.
- [x] Added `http` and `url_launcher` to `pubspec.yaml` (this app's first outbound HTTP dependency beyond the NATS protocol itself).
- [x] **Unit tests**: `test/update_checker_test.dart` covers `isNewerVersion()` (major/minor/patch bumps, equal versions, numeric-vs-lexicographic edge case, build-suffix stripping, missing trailing parts) and `fetchLatestRelease()` against a mocked `http.Client` (`package:http/testing.dart`'s `MockClient` — success, non-200, malformed JSON, missing fields, thrown exception). `test/settings_dialog_test.dart` extended with the new toggle's initial state, tap-to-flip, and its value flowing through `onSave`.
- [x] **Real-API verification**: since this app has no test/staging GitHub repo, verification ran against the real `nverbeek/nats_client_flutter` releases API from a real compiled Windows build (`flutter test <file> -d windows`) — no mocking, via a throwaway `integration_test/` file deleted afterward (not committed — this check is exercised live, not via a fixture server like the JetStream/auth milestones, since GitHub Releases isn't something this project can stand up a disposable instance of). See `AGENTS.md`'s new **Recipe I: Verifying Update Notifications** for the repeatable steps. Three passes:
  - The first pass used a `MaterialBanner`; it worked (appeared with working actions when the local version was set below the real latest tag `v1.0.11`, stayed hidden at version parity) but was replaced after user feedback that a full-width banner was too visually heavy for a one-line notice.
  - After switching to the `OverlayEntry`-based top-right popover, re-verified against the real API again: confirmed the popover renders at `Positioned(top: 16, right: 16)` (not a `SnackBar` or `MaterialBanner`), shows the correct version text and a working "View Release" button, and its dismiss (`X`) button removes it.
  - After a UX nit that the "View Release" button's hover highlight hugged the text with no breathing room, added horizontal padding (compensated with a `Transform.translate` so the visible text stays aligned with the version line above it). Verified programmatically against the live popover: hover/hit width grew by 16px while the rendered text's on-screen position stayed within a pixel of its prior spot.

---

## Milestone 6: Phase F — Live Message List UX Improvements (Medium Priority)

### Objective
Two related list-UX gaps affect both the Live Messages tab (`lib/main.dart`) and the JetStream "Browse Messages" view (`lib/jetstream_message_view.dart`), which share the same newest-message-at-top `ListView.builder` pattern and the `RegexTextHighlight` widget:

1. **JetStream Browse Messages has no Filter/Find.** The Live Messages tab has both (`filterBoxController`/`findBoxController`, Ctrl+F / Ctrl+Shift+F shortcuts), but `JetStreamMessageView` has neither — there's no way to narrow down or highlight matches while tailing a busy stream.
2. **Scrolling is unusable on a busy list.** New messages are inserted at index 0 (newest first). If the user scrolls down to read older messages, each newly arriving message shifts every already-visible row down by one slot, moving the viewport out from under the user. On a fast-moving subject this makes it effectively impossible to click/act on a message before it drifts away.

### Desired Behavior
- If the user has scrolled away from the top, new messages still arrive and get added to the underlying list, but the viewport must not visually move — no jump, no drift.
- If the user is at the top, today's pinned-to-latest behavior is preserved (new messages appear at the top, in view).
- A **Pause** control (next to the existing Delete/Clear button) freezes the on-screen list — no new rows rendered, no scroll movement — while the underlying subscription/consumer keeps running and buffering. Resuming reveals everything that arrived while paused, still without forcibly relocating the user's scroll position.

### Implementation Checklist
- [x] **JetStream Browse Messages — Filter & Find** (Completed):
  - [x] Add Filter and Find fields to `JetStreamMessageView`'s toolbar, mirroring `lib/main.dart`'s pattern; wire Find into the already-present `RegexTextHighlight` (was passed an empty `searchTerm`, now `_currentFind`). Filter narrows `_filteredMessages`; the header count switches from "`N` received" to "`shown` / `received`" once a filter is active; an empty-filtered-list state ("No messages match filter.") is distinguished from the original "Waiting for messages..." empty state. Verified against a real JetStream-enabled server via an extended `integration_test/jetstream_browse_test.dart` (publishes two distinct payloads, exercises Filter narrowing/clearing and Find highlighting/clearing, then re-filters to a single row before the existing Detail/Copy row-menu assertions, which needed disambiguating once a second row existed).
  - [x] Extend the existing Ctrl+F / Ctrl+Shift+F shortcuts to this view. `lib/main.dart`'s global `Focus(onKeyEvent: ...)` is now tab-aware: it first asks `JetStreamDashboardState.focusFilterField()`/`focusFindField()` (new, delegating through a `GlobalKey<JetStreamMessageViewState>` held by `JetStreamDashboard`, which in turn wraps new `FocusNode`s on `JetStreamMessageView`'s own Filter/Find fields) when the JetStream tab is active, falling back to the Live Messages tab's fields when that returns `false` (i.e. not currently browsing) or when the Live Messages tab itself is active. Both State classes were made public (dropped their leading underscore) so `main.dart` and `jetstream_dashboard.dart` can hold typed `GlobalKey`s to them. Verified live: extended `integration_test/jetstream_browse_test.dart` with the same focus-check pattern already used in `live_messages_interactions_test.dart` (tap a field to set a baseline, send the key combo, assert `Focus.of(...).hasFocus` on the other field) and re-ran `live_messages_interactions_test.dart` + `jetstream_lifecycle_test.dart` to confirm no regression on the Live Messages tab's shortcuts or the dashboard's tab-switch behavior.
- [x] **Scroll-position stability (Live Messages tab and JetStream Browse Messages)** (Completed):
  - [x] **Shipped approach — normal (top-anchored) newest-at-top list + a fixed `itemExtent` + exact offset compensation.** `items`/`_messages` stay newest-first and each `ListView.builder` renders them directly (`filteredItems[index]`, index 0 = newest at the top), the plain non-reversed default — so messages fill from the top down, the latest arrives at the top, and a short list sits at the top with empty space below (the original, natural design). Scroll-position stability when messages are prepended above a scrolled-away viewport is handled explicitly in `_insertMessages`: capture the offset before the insert, and in a post-frame callback shift the offset down by the growth in `maxScrollExtent`. That shift is *exact* only because every row is a fixed `_messageRowExtent` tall (`main.dart`: derived from the current font size / single-line setting; `jetstream_message_view.dart`: a constant, since its rows are always font-14 / 5-line) — for a fixed-extent list `maxScrollExtent` is `extent × count`, computed exactly and synchronously, with no lazy estimation. When the user is at the top, no shift is done: the offset stays 0 and the new newest simply appears above. Row banding uses distance-from-the-oldest (`(length - 1 - index) % 2`), which is fixed per message, so stripes don't flip as new messages prepend.
  - [x] **The tradeoff of the fixed extent is uniform row heights** — a short one-line message gets trailing padding rather than sizing to its content (messages were already clipped at 1 or 5 lines, so nothing new is hidden). This was an accepted, deliberate choice: it's the only way to get *exact* stability for a top-anchored newest-at-top list, since the prepended rows are above a scrolled-away viewport and therefore not laid out, so their real heights can't be measured. Guarded against clipping by `integration_test/message_row_extent_test.dart` (a long message at the max font size, 30, at both the single-line and 5-line settings, asserting no render overflow).
  - [x] **Three earlier approaches were tried and discarded before landing on this one** (kept here since the failure modes are worth knowing if this code is touched again):
    1. A `GlobalObjectKey` per row, used to measure a specific "anchor" row's `RenderBox` before/after each insert and nudge the `ScrollController` by the delta. Correct, but every `GlobalKey`-bearing element participates in an app-wide registry that's re-verified every frame — this made scrolling itself janky (even paused/disconnected, since it fires on every scroll frame as rows enter/leave the built range, not just on insert) and made Resume-with-a-large-backlog visibly hang.
    2. Diffing `ScrollPosition.maxScrollExtent` before/after with **variable-height** rows — cheap, but *incorrect* at scale: for a variable-height lazy `ListView.builder`, `maxScrollExtent` is an extrapolated estimate from the built children, and prepending items far from the viewport left it stale even across several frames (confirmed via a widget test at 5,000 items). This is the same mechanism the shipped approach uses — the fix was making the rows fixed-height, which turns that estimate into an exact value and eliminates the staleness entirely.
    3. `reverse: true` + a sliver/data-index mapping. This gave *exact* stability with **zero** compensation code and no fixed height (new messages map to the far sliver end, so rendered rows never move), and shipped for a while — but a reversed list is bottom-anchored, so a short list clings to the bottom of the pane and messages read as growing upward from the bottom, which the user disliked. Reverted in favor of the top-anchored design above, accepting the fixed-height tradeoff to keep the original look.
  - [x] **Performance, given messages can arrive very fast with thousands queued**: `lib/main.dart` and `lib/jetstream_message_view.dart` buffer arrivals in a plain list (O(1) append) and flush at most once per 32ms tick, rather than reacting per message — turning a burst of hundreds of messages into one list mutation instead of hundreds. The fixed `itemExtent` also lets the scrollbar/fling locate any row analytically instead of building off-screen rows to measure them. Verified against a real server via `integration_test/message_list_pause_test.dart`'s burst test (21 filler + 29-message burst via a second, direct `dart_nats` publisher client, not the app's own Send dialog, to simulate a genuinely fast external publisher) — asserting both screen position *and* row stripe color stay fixed on a specific row through the burst.
- [x] **Pause control** (Completed):
  - [x] Added a Pause/Resume `IconButton` (with a live buffered-count `Badge`) next to Delete/Clear on the Live Messages tab, and an equivalent pair (Delete/Clear didn't exist there before) to `JetStreamMessageView`'s header row; the Browse view's connection-status dot also dims to grey while paused.
  - [x] Paused: the subscription/consumer keeps running; arrivals still flow through the same batching buffer but flush into a `pendingMessages`/`_pendingMessages` backlog instead of the visible list — zero rows rendered, zero scroll movement, reusing the exact same flush mechanism as the live (unpaused) path rather than a separate code path.
  - [x] Resume: the backlog is spliced in through the same insert path used for live arrivals (`_insertMessages`), so — same as any other arrival — it doesn't move a scrolled-away viewport, and re-pins to newest if the user was already there, even for a large backlog.
  - [x] Verified against a real server: `integration_test/message_list_pause_test.dart` (Live Messages tab) and the extended `integration_test/jetstream_browse_test.dart` (Browse Messages) both publish a message while paused via a direct `dart_nats` client, confirm it's buffered (badge shows the count, row absent) and not yet visible, then confirm Resume reveals it; the Browse view's new Delete button is also exercised there.
- [ ] **A follow-up "jump to newest" / scrollbar-drag pass was attempted and reverted**: it added a "jump to newest" `FloatingActionButton` and a fix for a scrollbar-thumb-drag-while-pinned bug (`NotificationListener`/`ScrollStartNotification` + `_isProgrammaticJump`/`_pointerDown` guards). In real manual use this made scrolling feel broken/unnatural, so that scroll-position-affecting machinery was reverted rather than carried forward — not worth re-attempting without a fresh look. (The fixed `itemExtent` from that same pass was *not* reverted — it was ultimately adopted as part of the top-anchored redesign above.)
  - [x] **The Pause/Resume button polish from that pass was kept**: the buffered-count `Badge` overlapped the icon closely enough that it was hard to tell Pause from Resume at a glance, and its variable width shifted every other toolbar control as the count changed digits. Replaced with a fixed-width slot containing a `Row` (icon + a separate count pill shown only while paused with a nonzero backlog), on both the Live Messages tab and JetStream Browse Messages. Verified via a new wide-count regression test (`integration_test/message_list_pause_test.dart`, buffers 1,200 messages to reach "1.2k" — a single-digit count never exercised the overflow this was fixing) against a real server.

---

## Also This Session: Connect via Ctrl+Enter

Small, standalone UX addition unrelated to the message list work above: Ctrl+Enter (Cmd+Enter on Mac) now fires Connect while focus is in the Host, Port, or Subjects field and the client is currently disconnected — no more reaching for the mouse after typing connection details. Implemented as a `Shortcuts`/`Actions` pair (`_ConnectIntent` + `_withConnectShortcut()` in `lib/main.dart`) wrapping each of those three fields individually, mirroring the same pattern `SendMessageDialog` already uses for its own Ctrl+Enter-to-send shortcut; the action no-ops if already connected/connecting, matching the existing Connect button's `enabled` condition. Verified against a real server via `integration_test/connect_shortcut_test.dart` (one case per field, starting the app disconnected and confirming the status reaches "Connected" via the shortcut alone).

---

## Milestone 7: Object Store Inspector (Medium Priority)

### Objective
`dart_nats: ^1.1.1` ships a full JetStream-backed blob store — `lib/src/object_store.dart` — that this app has never touched (verified: no `object_store`/`ObjectStore` reference anywhere under `lib/`). It's the object-storage sibling of the KV milestone: same "bucket backed by a magic-prefixed JetStream stream" shape, just for arbitrary byte payloads (files/blobs) instead of small key/value pairs. This milestone adds a fourth tab mirroring the existing KV Dashboard's bucket-list/object-list pattern.

### What `dart_nats` actually supports (verified against `dart_nats-1.1.1/lib/src/object_store.dart`)
- `client.jetStream().createObjectStore(ObjectStoreConfig(bucket:, storage:, replicas:, maxBytes:, ttl:))` / `objectStore(bucket, {create})` / `deleteObjectStore(bucket)` — backing stream `OBJ_<bucket>`, subjects `$O.<bucket>.>`.
- `ObjectStore.put(name, Uint8List, {description})` / `putBytes` / `putString` — chunks the payload into 128 KiB pieces published to `$O.<bucket>.C.<nuid>`, computes a SHA-256 digest, then publishes JSON metadata (`ObjectInfo`) to `$O.<bucket>.M.<base64(name)>`.
- `ObjectStore.get(name)` / `getBytes` / `getString` — resolves metadata via a JetStream direct-get call, spins up an ephemeral push consumer filtered to that object's chunk subject, reassembles the chunks, and verifies the SHA-256 digest before returning (throws on mismatch).
- `ObjectStore.delete(name)` — tombstones the metadata entry (`deleted: true`) and purges the chunk subject to reclaim space.
- `ObjectStore.list()` — an ephemeral consumer over `$O.<bucket>.M.>`, folding the metadata event stream into the current live object set (a later `deleted: true` removes an earlier `put` for the same name) — snapshot-only, timeout-bounded; unlike `KeyValue`, `ObjectStore` has **no `watch()`**, so the object list needs an explicit refresh rather than KV's automatic live updates.
- `ObjectStore.addLink()` / `addBucketLink()` — an object (or a whole bucket) can point at another object/bucket; `get()` resolves links recursively up to 5 hops.
- **Caveat worth surfacing in the UI/docs**: the package's own doc comment marks `ObjectStore` `EXPERIMENTAL: subject to change in future releases` — unlike `KeyValue`, which carries no such warning. Also worth re-checking live (per the KV milestone's lesson about `KeyValueConfig.toStreamConfig()` silently dropping `ttl`/replicas): confirm `ObjectStoreConfig.toStreamConfig()` doesn't have the same bug before trusting it.

**Live-server verification findings (2026-07-11)**: before writing any UI, probed the real API against a Docker `nats:latest -js` server (create bucket with `ttl`/`replicas` set → put a small object → put a 300 KiB object spanning 3 chunks → list → get both back and byte-compare → delete → list again → delete bucket). Everything worked correctly, including chunk reassembly and the SHA-256 digest check on download. Unlike the KV milestone, **`ObjectStoreConfig.toStreamConfig()` does *not* drop `ttl`/`replicas`** — confirmed via a raw `$JS.API.STREAM.INFO.<name>` request (bypassing the client's own parsing) that both actually reached the server. The one real gap found: `StreamInfo.fromJson()` in `dart_nats-1.1.1/lib/src/jetstream.dart` doesn't parse `max_age`/`num_replicas`/several other `StreamConfig` fields back out of the server's response at all (they're silently `null` on any `StreamInfo` read back, for *any* stream type, not just Object Store — a pre-existing gap, not specific to this milestone). This never blocked anything here because — like the KV and JetStream dashboards before it — the Object Store bucket list only ever displays `StreamInfo.state` (message/byte counts), never reads `.config` back for display. No in-app workaround was needed and no fork revival was warranted.

### UI Architecture & Concept
Fourth tab (`[📦 Object Store]`) alongside Live Messages / JetStream / KV, gated behind a new opt-in "Enable Object Store" setting (same pattern as JetStream/KV). Reuses the KV dashboard's master/detail layout: left pane lists buckets (Create/Delete), right pane lists objects in the selected bucket (name, size, chunk count, digest, mtime) with per-row Upload (native file picker → `put`), Download (native save dialog → `get` → write bytes), and Delete.

### Implementation Checklist
- [x] `lib/object_store_manager.dart` — thin wrapper mirroring `KvManager`/`JetStreamManager`: `listBuckets()`, `createBucket()`, `deleteBucket()`, `listObjects(bucket)`, `putObject()`, `getObject()`, `deleteObject()`. Unlike `KvManager`, `createBucket()` goes straight through the package's own `createObjectStore(ObjectStoreConfig(...))` rather than building a `StreamConfig` by hand, since live verification confirmed the package's own `toStreamConfig()` conversion isn't buggy here (see above).
- [x] `lib/object_store_bucket_dialog.dart` — Create Bucket form (name, storage, max size in MB, TTL in days, replicas), following `kv_bucket_dialog.dart`'s pattern.
- [x] `lib/object_store_dashboard.dart` — master/detail dashboard. Upload/Download are injectable (`pickUploadFile`/`saveDownloadedFile` constructor params, defaulting to real `file_picker`-backed implementations using the same `kIsWeb`/`dart:io` split as `main.dart`'s own `pickFile()`), so widget tests can drive the full upload/download flow with a fake file instead of the OS dialog.
- [x] Object row detail: name, human-readable size, chunk count, a shortened SHA-256 digest, and relative mtime. **Deleted state was dropped from scope** — `ObjectStore.list()` already folds tombstoned objects out of its result (a later `deleted: true` metadata event removes the earlier `put`), so a "deleted" flag would never be true on anything the list actually returns.
- [x] New pref `prefObjectStoreEnabled` / `defaultObjectStoreEnabled` (true, same "opt-out" pattern as JetStream/KV); the dynamic `TabController` (already built for 1–3 tabs since the KV milestone) now extends to 1–4.
- [x] Unit tests (pure-logic split, mirroring `kv_manager_test.dart`) + fake-manager widget tests (`test/object_store_manager_test.dart`, `test/object_store_bucket_dialog_test.dart`, `test/object_store_dashboard_test.dart` — the last covers Upload/Download/Delete/Refresh via the injected fake file-picker callbacks) + a live-server `integration_test/object_store_lifecycle_test.dart`: create bucket via the UI → a second, direct `dart_nats` client uploads a 300 KiB (3-chunk) object straight into the bucket → confirmed it does **not** appear until Refresh is tapped (no `watch()`) → tapping Refresh shows it → download (via the same manager class, bypassing only the native save-file dialog itself — see the test's doc comment) verified byte-for-byte against the original → delete object via the UI, confirmed gone server-side too → delete bucket via the UI.
- [x] Documented the upstream `EXPERIMENTAL` status in both `assets/app_help.md` (new "Object Store" section) and directly in the dashboard UI itself (an italic caption under the bucket list header), plus the no-live-`watch()`/explicit-Refresh caveat in both places.

---

## Milestone 8: Message Headers on Send (Low/Medium Priority)

### Objective
A symmetry gap: incoming NATS message headers are already parsed and displayed in all three message views (`main.dart:1043-1045`, `jetstream_message_view.dart:263-265`, `jetstream_consumer_tail_view.dart:103-105`), but there's no way to attach custom headers when publishing from `SendMessageDialog`. Headers are commonly used for correlation IDs, content-type, and tracing metadata — right now testing header-dependent server-side logic means reaching for another tool to publish.

### What `dart_nats` actually supports
`client.pub(subject, data, {String? replyTo, Header? header})` / `pubString(..., header: Header?)` (`client.dart:902-966`) — `Header` (`message.dart:9-81`) is an ordered key/value map plus a version line, sent using NATS's `HPUB` wire format.

### Implementation Checklist
- [x] Add a "Headers" section to `SendMessageDialog` — a dynamic key/value row list (add/remove rows) in a fixed-height, internally-scrollable area so the dialog doesn't resize as rows are added; rows with a blank key are dropped from what's sent. `initialHeaders` lets callers prefill it.
- [x] Wire it through `sendMessage()` in `lib/main.dart`: build a `Header` from non-empty rows and pass it to `pub()`/`pubString()`. `JetStream.publish()`/`publishString()` (`jetstream.dart:401-438`) already accept a `header`, so `JetStreamManager.publish()` was extended with the same optional param to forward it — the JetStream-ack toggle uses a different call path and needed its own plumbing.
- [x] Reflect sent headers in the UI's own feedback: the loopback subscription already round-trips a message's `Header` back through `Message.header`, and `MessageDetailDialog` already renders it — no receive-side changes needed. As a symmetry bonus, Replay (row menu and the `R` shortcut) and Edit & Send (row menu, the `E` shortcut, and `SendMessageDialog`'s `initialHeaders`) now also preserve/prefill the original message's headers instead of dropping them.
- [x] Unit/widget tests for the header row list (add/remove/empty-value handling, prefill) in `test/send_message_dialog_test.dart` + a live-server `integration_test/send_message_headers_test.dart` publishing with a header via the UI and asserting it round-trips into the received message's Detail dialog.

---

## Milestone 9: Queue Group Subscriptions (Medium Priority) — Completed

### Objective
`client.sub<T>(subject, {String? queueGroup})` (`client.dart:991-995`) supports NATS queue groups — the standard load-balancing primitive where only one member of a named group receives each message — but the app's only subscribe call site, `subscribeToSubject()` (`main.dart:850-857`), never passes one. Anyone wanting to verify queue-group behavior (e.g. "does my service correctly load-balance across replicas") currently has to reach for another tool alongside this one.

### Implementation Checklist
- [x] Add an optional queue-group field per subscription — built together with Milestone 11's Subscription Manager, so it's a field on `SubscriptionInfo` from the start rather than bolted onto the old comma-delimited text field.
- [x] Thread `queueGroup` through `_subscribeOne()` (renamed from `subscribeToSubject()`) into `natsClient.sub()`.
- [x] Surface the queue group (if any) per-subscription: a badge in the chip's label, and its own field in the Subscription Manager dialog / add-edit dialog.
- [x] Live-server verification: `integration_test/queue_group_test.dart` — the app's own subscription (given a queue group via the chip's edit dialog, live unsub+resub) plus a second bare `dart_nats` client in the same queue group, confirming a 20-message burst splits between them (every message landed on exactly one member) rather than both receiving everything.

**Note**: built together with Milestone 11 (Subscription Manager), since a queue group is a natural per-subscription attribute in that dialog rather than a bolt-on to the old single comma-delimited text field.

---

## Milestone 10: JetStream Account Info Panel (Low Priority) — Completed

### Objective
`checkAvailability()` in both `jetstream_manager.dart:94-97` and `kv_manager.dart:23-26` already calls `js.accountInfo()` on every JetStream/KV dashboard load, but only checks that it didn't throw — the real payload is discarded. `AccountInfo` (`jetstream.dart`, `Tier`/`APIStats`/`AccountInfo` classes) carries genuinely useful operational data that's already being fetched for free: memory/storage usage vs. reserved limits, stream/consumer counts, and API call/error/inflight stats.

### Implementation Checklist
- [x] Have `checkAvailability()` (or a sibling method) return the fetched `AccountInfo` instead of discarding it.
- [x] Add a small "Account Info" entry point (icon button or menu item) on the JetStream and/or KV dashboard header, opening a compact read-only dialog: memory/storage used vs. reserved, stream/consumer counts, API totals/errors/inflight, domain.
- [x] Unit tests for any new pure formatting logic (byte formatting, ratio display) + a widget test for the dialog against a fake `AccountInfo`; live-server verification that real values populate the dialog sensibly (doesn't need to assert exact numbers).

### Implementation Notes
Both managers gained `AccountInfo? lastAccountInfo` (populated as a side effect of `checkAvailability()`, so the dialog can open instantly with data already in hand) and `Future<AccountInfo> fetchAccountInfo()` for a manual refresh. A new shared `lib/account_info_dialog.dart` (`AccountInfoDialog`) is used by both `JetStreamDashboard` and `KvDashboard` — `AccountInfo` describes the whole account, not a specific stream/bucket, so one dialog covers both entry points (an `Icons.info_outline` button next to each dashboard's existing refresh button).

**Real bug found by live-server verification, not by reading the source** (same pattern as the NKey-auth and KV-`ttl`/replica-count findings from Milestones 4 and 2): vendored `dart_nats-1.1.1`'s `AccountInfo.fromJson()` (`jetstream.dart`) reads usage/limits from a nested `json['tier']` key. A real server's `$JS.API.INFO` response has no `tier` key at all for the common case of a single-tier (non-multi-tenant) account — those fields (`memory`, `storage`, `reserved_memory`, `reserved_storage`, `streams`, `consumers`) are at the top level instead. So `JetStream.accountInfo()` silently returns an all-zero `Tier` for almost every real deployment, which would have made this entire milestone useless. Fix: `jetstream_manager.dart` now has its own `fetchRawAccountInfo()` (raw `$JS.API.INFO` request) plus `accountInfoFromJson()`/`tierFromJson()` that read the correct top-level fields; both managers' `checkAvailability()`/`fetchAccountInfo()` go through these instead of `JetStream.accountInfo()`. A second, smaller finding along the way: a server represents an unset `reserved_storage` limit as a uint64 `-1` sentinel, which after JSON round-tripping through a double arrives as `18446744073709552000.0` — `tierFromJson` parses fields as `num?` rather than `int?` so this doesn't throw on cast, and `AccountInfoDialog` treats any reserved value `>= 2^62` as "unlimited" (alongside the `<= 0` case) so it doesn't render a multi-exabyte figure.

Test coverage: `test/jetstream_manager_test.dart` (`tierFromJson`/`accountInfoFromJson`, including a fixture captured verbatim from a live server's response and the huge-sentinel case), `test/account_info_dialog_test.dart` (cached-data render, fetch-when-nothing-cached, manual refresh, error state, the unlimited-usage-bar-omitted case for both `reserved <= 0` and the huge-sentinel case, Close button), plus a case in each of `test/jetstream_dashboard_test.dart` and `test/kv_dashboard_test.dart` confirming the dashboard's Account Info button surfaces `manager.lastAccountInfo` without an extra fetch. Live-server verification: a standalone script against a real `nats:latest -js` container (one JetStream stream + one KV bucket created first) confirmed `fetchAccountInfo()` now returns correct non-zero `streams`/`storage`/`api.total`, and that the sentinel-clamped `reservedStorage` doesn't throw.

---

## Milestone 11: Subscription Manager & Per-Subscription Color Indicators (Medium Priority) — Completed

### Objective
Today, subscribing to more than one subject means typing a comma-delimited list into a single Subjects text field (`main.dart:738-747`), parsed once at connect time — there's no way to add or remove an individual subscription after connecting, see which subjects are currently active at a glance, or tell which subscription a given Live Messages row actually matched once more than one is active. This milestone replaces the raw text field with a compact display + management dialog, and adds a small colored indicator per message row keyed to its originating subscription.

### What `dart_nats` actually supports
Each `Subscription` returned by `client.sub()` has its own numeric `sid`, and every `Message` carries the `sid` of the subscription that delivered it (`message.dart`: `Message(this.subject, this.sid, ...)`). That means messages can be tagged with their origin subscription for free — no need to re-derive it from subject-pattern matching, which would be ambiguous with overlapping wildcards — just track subscriptions in a `Map<int, SubscriptionInfo>` keyed by `sid` and look up by `event.sid` on arrival. `client.unSub(Subscription)` / `unSubById(int)` (`client.dart:1027-1044`) already support removing a single subscription without touching the others, which today's app never calls (subscriptions only ever end at disconnect).

### UI Architecture & Concept
Replace the free-text Subjects field in the connection bar with a compact read-only display (e.g. "3 subscriptions" or the first subject + "+2 more") plus a "Manage..." button opening a dialog: a list of active subscriptions, each showing its subject pattern, assigned color swatch, and (if Milestone 9 lands) queue group, with Add/Remove controls. Removing a row while connected calls `unSub()` immediately, not just at next reconnect. Each subscription gets a color automatically assigned from a small fixed palette (cycling if subscriptions outnumber the palette — this is a quick visual grouping aid, not a precise identity system). A small colored dot/bar per message row in the Live Messages list shows which subscription that message arrived on; a legend in the Manage dialog (or a tooltip on the dot) ties color back to subject.

### Implementation Checklist
- [x] Define a small themed color palette (8 colors, paired light/dark variants — `subscriptionPaletteDark`/`subscriptionPaletteLight` in `lib/constants.dart`, resolved at render time via `resolveSubscriptionColor()` in `lib/subscription_info.dart` so a theme toggle mid-session stays correct).
- [x] `SubscriptionInfo` model (subject, queue group — persisted; colorIndex, sid — runtime-only, never persisted) in `lib/subscription_info.dart`, replacing the old implicit list built from `subject.split(',')`. `sid` lifecycle is tied to `Client` object identity (nulled on reconnect/disconnect, populated on subscribe), not the noisy `Status` stream, since `dart_nats` already re-subscribes existing sids internally on reconnect.
- [x] `lib/subscription_manager_dialog.dart` — list + Add/Remove/queue-group-edit per row (queue-group edits commit on blur/submit, not per-keystroke, since each one is a real unsub+resub over the wire), modeled on `send_message_dialog.dart`'s header-row list pattern rather than `kv_bucket_dialog.dart` (a single-entry create form despite its name).
- [x] Replaced the Subjects `TextFormField` with `lib/subject_chips_row.dart` — one filled Material 3 chip per subscription (color-swatch avatar, queue-group badge, tap-to-edit, delete icon to unsubscribe immediately), collapsing overflow into a single "+N more" chip that opens the manager dialog. Legacy `prefSubject` (comma-delimited) migrates once into the new JSON `prefSubscriptions` key.
- [x] Live Messages rows get a small leading color dot (`_colorForSid()` in `main.dart`, linear scan by `message.sid`; renders nothing for a message from a since-removed/reconnected subscription) — fixed-width in both branches so title text doesn't shift row-to-row, composes fine with the existing Filter/Find highlighting and Milestone 6's row striping.
- [x] JetStream Browse Messages left out of scope, as anticipated — it binds to one stream/consumer at a time, not multiple ad hoc subscriptions.
- [x] Unit tests (`test/subscription_info_test.dart`: encode/decode, legacy migration, color cycling), widget tests (`test/subject_chips_row_test.dart`: chip rendering, tap vs. delete, overflow collapse at a narrow width and full render once widened; `test/subscription_manager_dialog_test.dart`: add/remove/edit, read-only subject, commit-on-blur), and a live-server `integration_test/subscription_chips_test.dart` (subscribe to two subjects via the chip UI, publish to both from a second client, assert distinct dot colors per row; remove one via its chip, publish again, confirm no new row).
- [x] **Follow-up (opt-out toggle)**: added a "Show Subscription Colors" `Switch` in `lib/settings_dialog.dart` (on by default; new `prefShowSubscriptionColors`/`defaultShowSubscriptionColors` in `lib/constants.dart`), gating rendering only — `SubscriptionInfo.colorIndex` assignment is untouched, so toggling off then back on restores each subscription's original color rather than reshuffling. `ColorTabChip.color` (`lib/color_tab_chip.dart`) became nullable and returns its `chip` child directly (no tab, no padding) when null, so no layout space is reserved for a hidden color — `SubjectChipsRow` and `SubscriptionManagerDialog` both thread a new `showSubscriptionColors` param through to it. The Live Messages row's 4px accent bar (`lib/main.dart`) is now conditionally included in its `Row`, not just painted transparent, for the same reason. Tests updated (`test/settings_dialog_test.dart`'s switch-index tests shifted by one, plus a new switch/onSave-param test; `test/subject_chips_row_test.dart` and `test/subscription_manager_dialog_test.dart` each gained a case asserting no color tab renders when the setting is off).

---

## Milestone 12: Connection Host/Port History (Low/Medium Priority) — Completed

### Objective
Previously only the single most-recently-used host and port were persisted (`constants.prefHost`/`prefPort`, overwritten on every successful connect, loaded once at startup) — no way to quickly reconnect to a server used a few connections ago without retyping it. This is a pure app-side UX improvement — not tied to any `dart_nats` API.

### Desired Behavior
Keep a small rolling history of previously-used **scheme+host+port** triples (a single paired entry per history item — selecting one fills scheme, host, and port together to a combination that was actually connected with before), most-recent-first, deduplicated. Surfaced as a dropdown anchored to the Host field that filters as the user types — pick from history, keep typing to narrow it, or ignore it and type a brand-new host.

### What actually shipped, vs. the original plan
- **Paired**, not independent per-field histories — as planned, but the triple is **scheme + host + port**, not just host + port (selecting an entry also updates the Scheme dropdown, not only Host/Port).
- **Cap raised from the originally-planned 5 to 10** — a deliberate call made with the user during implementation planning, not a default.
- **Delete support was added** (per-entry delete + a "Clear history" action) — not in the original "Desired Behavior," added because a plain rolling-cap list with no manual pruning felt incomplete once the dropdown UI was actually being designed.
- **Widget mechanism**: the original "Decided" section explicitly ruled out "a plain `Autocomplete` popup" in favor of a `DropdownMenu`-style affordance. In practice, Flutter's `DropdownMenu` turned out to be the wrong fit — its field always displays the *selected entry's full label*, and the requirement here is that the Host field shows/edits only the host while the dropdown rows show the full `scheme://host:port` string. `Autocomplete<ConnectionHistoryEntry>` does support exactly that split (`displayStringForOption` vs. a fully custom `optionsViewBuilder`), so the shipped version uses it — but with every row, the highlight, and the footer custom-built (`_ConnectionHistoryOptions` in `lib/main.dart`), not Autocomplete's default popup styling. So the *spirit* of "not a plain Autocomplete popup" (i.e. don't ship the unstyled default) held; the literal widget class did end up being `Autocomplete`.

### Implementation
- `lib/connection_history.dart` (new): `ConnectionHistoryEntry` (scheme/host/port + `fullUri` getter + `sameTarget()` identity), `encodeConnectionHistory()`/`decodeConnectionHistory()` (JSON list in one `SharedPreferences` key, mirroring `lib/subscription_info.dart`'s pattern), and a pure `recordConnection()` helper (move-to-front dedupe by target, capped at `maxConnectionHistory = 10`).
- `lib/constants.dart`: new `prefConnectionHistory` key.
- `lib/main.dart`: history loads at startup and threads through `MyApp`/`MyHomePage`; `_recordConnectionHistory()` is called from the `Status.connected` case (not on connect *attempt*, matching the original requirement that a failed/typo'd connect never pollutes history) and persists via `_persistConnectionHistory()`; `_deleteHistoryEntry()`/`_clearConnectionHistory()` mirror it for removal. The existing `natsConnect()` "last used" writes to `prefHost`/`prefPort` (last-session prefill, unrelated to this history list) were left alone and commented to disambiguate the two.
  - The Host field became `Autocomplete<ConnectionHistoryEntry>` with a custom `fieldViewBuilder` (host-only text, disabled while connected) and `optionsViewBuilder` (`_ConnectionHistoryOptions`, a themed `Material` list). Selecting a row (`_selectHistoryEntry`) sets scheme/host/port; the Scheme `DropdownButtonFormField` picks up the change via a new `key: ValueKey(scheme)` (its `initialValue` is otherwise read only once) and Port picks it up via a new `portController` (it was `initialValue`-based, no controller, before this milestone).
  - Keyboard nav (Up/Down/Enter, matching the app's existing keyboard-shortcut-friendly style) was a specific ask during implementation review — rows render from the `options` iterable `Autocomplete` itself passes in plus `AutocompleteHighlightedOption.of(context)`, rather than from raw live state, so the built-in highlight stays meaningful.

### Real bugs found by live manual testing, not by reading the source (same pattern as several earlier milestones)
Two rounds of this feature's delete/clear buttons silently not working, tracked down live rather than caught by `flutter analyze` (which stayed clean throughout):
1. **Focus-steal tears down the overlay mid-tap.** `Autocomplete` removes its whole options overlay the instant its field loses keyboard focus, and `IconButton`/`ListTile` normally grab focus as part of handling a tap — stealing focus from the Host field and destroying the overlay before `onPressed` fired, silently swallowing the tap (visible as a ripple with no effect). Fixed by wrapping the overlay's interactive content in `Focus(descendantsAreFocusable: false)`, which blocks focus acquisition for every descendant without affecting tap/click handling.
2. **A delete appeared to work, then silently reverted on the very next frame.** `optionsViewBuilder` hands the overlay a freshly `.toList()`'d `options` on *every* rebuild of the overlay — not only when Autocomplete's own filtered list actually changed. Deleting an entry itself triggers exactly such an unrelated rebuild (the parent `setState` in `_deleteHistoryEntry` recreates the `Autocomplete` widget with a new `optionsViewBuilder` closure, which `RawAutocomplete`'s `didUpdateWidget` reacts to by re-invoking `optionsViewBuilder` with its still-stale, pre-deletion internal `_options`). An unconditional local resync in `didUpdateWidget` was silently re-adding the just-deleted row on the very next frame. Fixed by gating the resync on `listEquals(oldWidget.options, widget.options)` rather than `identical` (`.toList()` always returns a new object even when content is unchanged) — only a *real* text-driven refilter should overwrite a local delete/clear.
3. (Smaller, cosmetic) A `ColoredBox` used to paint the keyboard-highlight tint around each row's `ListTile` tripped Flutter's debug-mode ink-visibility check (any background-colored widget between a `ListTile` and its nearest `Material` ancestor can occlude its ink splashes) — spammed "ListTile background color or ink splashes may be invisible" in the console. Fixed by using `ListTile`'s own `selected`/`selectedTileColor` properties instead of an external wrapper.

### Test coverage
- [x] `test/connection_history_test.dart` — pure logic: `fullUri`/`sameTarget`, encode/decode round-trip (including order preservation and the empty-list case), and `recordConnection()`'s insert/dedupe-and-move-to-front/distinct-target-by-scheme-or-port/cap-at-10/non-mutating behavior.
- [x] `integration_test/connection_history_test.dart` — dropdown UI mechanics against a seeded (no live server needed) history: shows on tap, filters as you type, selecting by mouse or by ArrowDown+Enter fills scheme/host/port, per-entry delete leaves the rest and persists, Clear history empties it and persists, an empty history shows no dropdown content.
- [x] `integration_test/record_connection_history_test.dart` — against a real `nats-server`: a successful connect records the target; a failed connect (connection refused) leaves history untouched. Confirmed the connection-refused path is safely caught internally by `dart_nats` (`_connectLoop`'s `try`/`catch` around `_connectUri`, distinct from the `-ERR` auth-failure code path Recipe H flags as unsafe to automate) — no uncaught zone error.
- [x] `assets/app_help.md`'s "Other Connection Info" section documents the history dropdown.

---

## Milestone 13: Message Direction Indicator (Incoming vs. Outgoing) (Low/Medium Priority, Optional)

### Objective
**Optional follow-up** — flagged by the user as something they may never get to; not on any particular timeline, and fine to stay `[ ]` indefinitely. Revisit only if it becomes an active want.

On the Live Messages tab, a sent (published) message currently doesn't appear in the message list at all unless the client also happens to be subscribed back to that exact subject (loopback) — `sendMessage()` (`lib/main.dart` around line 1399) calls `natsClient.pubString()` / `JetStreamManager.publish()` directly and never adds an entry to `items` itself. That makes "did I send this or receive this" hard to track even on subjects where both directions are visible today. This milestone adds: (1) tracking locally-sent messages as first-class list entries regardless of loopback subscription, and (2) a small visual indicator on each row distinguishing outgoing from incoming.

**JetStream note**: `lib/jetstream_message_view.dart`'s Browse Messages / Tail views have no send affordance of their own (verified — no `SendMessageDialog`/publish call anywhere in that file). Publishing into a stream only happens through the Live Messages tab's Send dialog via its "get delivery ack" (JetStream) toggle. So there is currently nothing to mark "outgoing" inside Browse Messages itself — this indicator applies to the Live Messages tab. Adding a dedicated publish affordance directly to the Browse view is out of scope here (see open question below); until/unless that exists, "can JetStream send?" is really "can you publish into a stream from the Send dialog," which it already can.

### Open Questions
- Should JetStream Browse Messages/Tail eventually get its own publish affordance (as opposed to only the shared Live Messages Send dialog)? Not currently planned; revisit only if this milestone's design surfaces a real need for it.
- Visual treatment: directional icon (↑/↓), color-coded row accent, or a text badge.

### Implementation Checklist
- [ ] Track locally-published messages from `sendMessage()` as list entries tagged outgoing, inserted through the same scroll-stability path (`_insertMessages`, Milestone 6) used for incoming arrivals — not dependent on loopback subscription.
- [ ] Add a direction indicator to each Live Messages row (visual TBD per the open question above).
- [ ] Confirm Filter/Find (Milestone 6) and the direction indicator compose cleanly.
- [ ] Unit/widget tests for direction tagging + rendering; live-server `integration_test` verification (send from the app, receive via a second publisher/subscriber, assert the indicator lands on the correct rows).

---

## Milestone 14: Request/Reply Correlation Improvements (Medium Priority, Optional)

### Objective
**Optional follow-up** — flagged by the user as something they may never get to; not on any particular timeline, and fine to stay `[ ]` indefinitely. Revisit only if it becomes an active want.

User feedback asked whether request/reply correlation could be improved. Today, "Reply To" (`lib/main.dart` around lines 1525-1532) only pre-fills the Send dialog's subject field with the original message's `replyTo` subject — it's an ordinary publish with no automatic pairing. True NATS request/reply (a private per-request inbox subject, awaited for a single correlated response) isn't used anywhere in the app today, so a real request/reply round trip wouldn't even show up in the message list (the app isn't subscribed to the inbox subject it would use).

### What `dart_nats` actually offers (verified against the vendored 1.1.1 source)
`Client.request<T>(subject, data, {timeout = 2s, jsonDecoder, header})` / `requestString<T>(...)`: lazily creates one shared wildcard subscription to `_INBOX.<clientNuid>.>`, generates a unique per-call reply subject, publishes with `replyTo` set to it, and awaits the first message seen on that inbox (default 2s timeout, throws `TimeoutException` on expiry). Correlation is a subject-string match inside the shared subscription's stream, not a keyed dispatch map. Calls are serialized via an internal `Mutex` — concurrent `request()` calls queue rather than run in parallel. The generated inbox subject isn't returned separately; the response `Message.subject` *is* the correlation key.

### Possible Directions (not yet decided)
- Add a "Request" mode to the Send dialog (alongside the existing JetStream-ack toggle) that calls `request()`/`requestString()` instead of a plain publish, then inserts both the outgoing request and its correlated incoming reply into the list as a linked pair — depends on Milestone 13's outgoing-message tracking.
- Alternatively/additionally, improve correlation for the plain-pub/sub style of request/reply many NATS users actually use (subscribe to a reply subject, publish with `replyTo` set, no `client.request()` involved) — likely worth supporting both patterns rather than assuming everyone uses the built-in `request()`.
- Visually link paired rows (shared correlation id, "jump to reply"/"jump to request", or adjacent grouping) instead of leaving the user to scan for a matching subject.
- A clear timeout/no-reply failure state in the UI, since `request()` throws `TimeoutException` rather than hanging silently.
- Design note: because `request()` is mutex-serialized inside `dart_nats`, rapid-fire requests from the UI would queue, not run in parallel — worth being deliberate about if the UI ever allows firing several at once.

### Implementation Checklist
- [ ] Decide UX: dedicated "Request" send mode using `client.request()`, enhanced correlation for the existing plain pub/sub "Reply To" flow, or both.
- [ ] Implement the chosen mechanism, building on Milestone 13's outgoing-message tracking so both halves of a pair are visible in the list.
- [ ] Visual/interaction linking between paired rows.
- [ ] Timeout/failure UX.
- [ ] Unit tests + live-server `integration_test` coverage.

---

## Milestone 15: Code Signing for Windows & macOS Builds (Low Priority, cost-gated, Optional)

### Objective
**Optional follow-up** — flagged by the user as something they may never get to; not on any particular timeline, and fine to stay `[ ]` indefinitely. Revisit only if it becomes an active want (or the cost/eligibility picture below changes enough to be worth another look).

Windows and macOS builds are currently unsigned: users hit "Unknown Publisher"/SmartScreen warnings on Windows and Gatekeeper "unidentified developer" blocks on macOS when running a downloaded build. Researched July 2026 — both are technically straightforward to wire into the existing [.github/workflows/build.yml](.github/workflows/build.yml); the real blocker is cost/eligibility, not feasibility.

### Findings
- **Windows — free option worth trying first**: [SignPath Foundation](https://signpath.org/) offers free OV-level code signing (via a managed CI pipeline) for qualifying open-source projects. Since this repo is public/open source, worth applying before paying for anything.
- **Windows — paid fallback**: Azure Trusted Signing (renamed **Artifact Signing** as of January 2026) is Microsoft's cloud-HSM signing service, ~$9.99/mo (5,000 signatures, 1 certificate profile) ≈ $120/yr, and integrates into GH Actions via the `Azure/trusted-signing-action` (or the newer `Azure/artifact-signing-action`). As of an April 2026 update it's GA and open to self-employed individuals (no more 3-year business-history requirement), but eligibility is geographically gated — sources vary between "US/Canada/EU/UK businesses" and "individuals limited to US/Canada" — so this needs a direct eligibility check against wherever the signing account would be held before committing money. Also worth knowing: as of a 2024 SmartScreen policy change, EV certificates no longer skip the reputation-building process — OV/Artifact-Signing and EV now behave the same way, so there's no reason to pay EV prices for instant trust anymore.
- **macOS**: requires an Apple Developer Program membership ($99/yr), a "Developer ID Application" certificate, and notarization (`xcrun notarytool submit` + `stapler`) — a standard, well-documented GH Actions pattern (import a `.p12` into a temporary keychain from a repo secret, `codesign` the `.app`/`.dmg`, notarize, staple). No free path here; the $99/yr is unavoidable for a legitimately signed/notarized macOS build.
- Both paths need secret management in GH Actions (a certificate/PFX or Azure credentials as encrypted repo secrets) and are additive to the existing `build-windows`/`build-macos` jobs, not a rework.

### Decision Needed Before Implementation
Whether to pursue SignPath Foundation's free-for-OSS route for Windows first; whether Azure Artifact Signing is worth ~$120/yr if SignPath doesn't pan out or doesn't fit; and whether the $99/yr Apple Developer Program cost is worth it for macOS given Milestone 3 already flagged macOS as never having been functionally verified at all (no Mac available) — signing a platform that isn't otherwise being tested may not be the best use of the budget until that gap closes.

### Implementation Checklist
- [ ] Apply to SignPath Foundation for free OSS code-signing eligibility (Windows).
- [ ] If not eligible/practical, evaluate Azure Artifact Signing cost/eligibility for this project's account.
- [ ] Decide whether to pursue macOS signing given the existing macOS-verification gap (Milestone 3).
- [ ] Wire the chosen signing step(s) into `.github/workflows/build.yml` as an additive post-build step, gated behind repo secrets so forks/PRs without those secrets still build (just unsigned).
- [ ] Document the signing setup (which secrets are needed, how to rotate/renew certs) in `AGENTS.md` or a new doc.

---

## Milestone 16: Apply the Latest Material 3 Standards (Low/Medium Priority) — Completed

### Objective
A user audit of the app's Material usage (already `useMaterial3: true`, seeded `ColorScheme`, no deprecated Material 2 widgets or APIs — `flutter analyze` was already clean) turned up two things the app hadn't adopted: OS-level dynamic color (Material You), and the newer M3 button primitives (`FilledButton`, `IconButton.filled`/`.filledTonal`/`.outlined`) added since this app's buttons were first written, back when `ElevatedButton` was the go-to "prominent" button. Per M3 guidance, `ElevatedButton` is now the *lowest*-emphasis contained button — `FilledButton` is the current default for a primary/high-emphasis action, and icon-only buttons have their own dedicated M3 variants rather than an `ElevatedButton` wrapping a bare `Icon`.

### Implementation Checklist
- [x] **OS dynamic color**: added `dynamic_color` and wrapped `MyApp`'s theme construction in a `DynamicColorBuilder` (`lib/main.dart`). When the embedder exposes a platform `ColorScheme` (confirmed live on Windows 11 — every integration test run logged `dynamic_color: Accent color detected.`, tracking the desktop's accent color), both the light and dark `ThemeData` use it; everywhere else it stays `null` and the existing `ColorScheme.fromSeed(seedColor: Colors.lightBlue.shade900)` is used unchanged, so nothing regresses on platforms without a dynamic-color implementation.
- [x] **Primary icon-only actions → `IconButton.filled`/`.filledTonal`/`.outlined`**: Connect (`Icons.check`) → `IconButton.filled`; Disconnect (`Icons.close`) and the Security Settings lock (`Icons.lock`) → `IconButton.filledTonal`; Clear/Delete (`Icons.delete`) → `IconButton.outlined`; Send (`Icons.send`) → `IconButton.filled` — all in `lib/main.dart`'s connection bar and bottom toolbar. The four file-picker "Browse" buttons (bare `Icons.folder_open`, previously `ElevatedButton`) in `lib/security_settings_dialog.dart` → `IconButton.filledTonal`.
- [x] **Labeled primary actions → `FilledButton.icon`**: "Browse Messages" (`lib/jetstream_dashboard.dart`), "Upload" (`lib/object_store_dashboard.dart`), "Put Value" (`lib/kv_dashboard.dart`) — each was the single highest-emphasis action in its row, previously `ElevatedButton.icon`.
- [x] **Pause/Resume → `FilledButton.tonal`**: kept as a `FilledButton` variant rather than `IconButton` since its content is a `Row` (icon + a conditional buffered-count pill), not a bare icon — `IconButton`'s `icon:` slot doesn't support that; the fixed-width/padding tuning from Milestone 6 (verified against a real wide-count overflow) was preserved as-is, just re-hosted on `FilledButton.styleFrom()` instead of `ElevatedButton.styleFrom()`.
- [x] **Left unchanged, already correct**: dialog actions (`TextButton` for Cancel/Save/Close — the correct M3 dialog-action pattern, not `ElevatedButton`), toolbar/app-bar icons (Settings gear, theme toggle, refresh — correctly plain `IconButton` with no filled/tonal treatment, since M3 reserves the filled variants for standalone emphasis, not routine toolbar actions), and `FloatingActionButton` (Jump to Top) — already the current M3 widget. No `Card` widgets exist anywhere in `lib/`, so there was nothing to migrate to `Card.filled`/`Card.outlined`.
- [x] Updated the finders in `test/jetstream_dashboard_test.dart`, `test/object_store_dashboard_test.dart`, and `test/kv_dashboard_test.dart` (all three: `ElevatedButton` → `FilledButton`) plus `integration_test/helpers/nats_test_app.dart`, `integration_test/authentication_test.dart`, `integration_test/jetstream_browse_test.dart`, `integration_test/kv_lifecycle_test.dart`, and `integration_test/screenshot_tour_test.dart` (Connect/Disconnect: `ElevatedButton` → `IconButton`, since `IconButton.filled`/`.filledTonal` are still the `IconButton` type; Browse Messages/Put Value/Pause/Resume: `ElevatedButton` → `FilledButton`). No test assumed a specific icon-button emphasis variant (`.filled` vs `.filledTonal` vs `.outlined`), only the base widget type, so none of those distinctions needed test-level assertions.
- [x] **Verification**: `flutter analyze` clean; all 213 widget/unit tests in `test/` pass. Live-server verification against a disposable Docker `nats:latest -js` container covered every changed button through its integration test: `connect_shortcut_test.dart` (Connect via `IconButton.filled`), `message_list_pause_test.dart` (Pause/Resume via `FilledButton.tonal`, including its wide-count-overflow regression case), `jetstream_browse_test.dart` and `jetstream_lifecycle_test.dart` (Browse Messages via `FilledButton.icon`, Send via `IconButton.filled`), `kv_lifecycle_test.dart` (Put Value via `FilledButton.icon`), `object_store_lifecycle_test.dart` (Upload via `FilledButton.icon`), and `live_messages_test.dart`/`live_messages_interactions_test.dart` (Send, Filter/Find, row actions) — all passed (a couple hit a known, pre-existing Windows `flutter test -d windows` flake — "the log reader stopped unexpectedly" when launching a new test binary immediately after a prior one exits — unrelated to this change, and each passed cleanly on an isolated re-run).
- [x] **Screenshots re-captured** (follow-up, done in a later session): ran `scripts/capture_screenshots.ps1` end-to-end against a fresh JetStream-enabled `nats-server` — all six `images/*.png` now show the M3 `FilledButton`/`IconButton.filled`/`.filledTonal` styling (e.g. JetStream's "Browse Messages" as a solid-filled button, the connection bar's filled Connect/tonal Disconnect/tonal lock icons, the tonal jump-to-top FAB).

---

## Milestone 17: NATS Server Monitoring Dashboard (Medium Priority)

### Objective
Every other tab in this app monitors things *through* the NATS protocol (streams, buckets, subscriptions) — nothing surfaces information *about* the server process itself. A real `nats-server` exposes a separate read-only HTTP monitoring API (default port `8222`, distinct from the NATS protocol port) with connection counts, memory/CPU, slow-consumer warnings, and cluster route health. Right now diagnosing "is the server under load" or "am I about to get disconnected as a slow consumer" means leaving this app for a browser tab or `nats-server`'s own `nats-top`.

### What's actually available (server-side HTTP API, not `dart_nats`)
This isn't a `dart_nats` API at all — it's a plain HTTP JSON endpoint on the server itself, so it goes through the `http` package already added for Milestone 5 (Update Notifications), not the NATS client connection. Endpoints (all `GET`, unauthenticated by default unless the operator locked them down):
- `/varz` — general server stats: uptime, version, config, in/out msgs & bytes, CPU, memory, slow consumer count.
- `/connz` — per-connection detail: client IP, subscriptions, in/out msgs & bytes, pending bytes, idle time; supports `?subs=1` for per-connection subject lists and pagination via `?offset=`/`?limit=`.
- `/subz` — subscription interest graph (subject, queue group, subscriber count).
- `/routez` / `/gatewayz` / `/leafz` — cluster/supercluster topology, only meaningful when the server is clustered.
- `/healthz` — simple up/down + JetStream health.
- Monitoring must be explicitly enabled server-side (`http_port`/`monitor_port` in the server config, or `-m 8222` on the CLI) — **not every server has it on**, so this needs a clear "monitoring unavailable" state rather than assuming it's always reachable, and a way to test the requests actually only kick in when the toggle in Settings (default off, since it's a second, non-NATS network endpoint) is enabled.

### UI Architecture & Concept
New tab (`[📊 Server Monitor]`) or a panel reachable from a toolbar icon, gated behind an opt-in "Enable Server Monitoring" setting (default **off**, unlike JetStream/KV/Object Store's default-on — this hits a different host:port than the NATS connection itself, so it shouldn't silently probe an endpoint the user didn't ask about) with its own configurable monitoring port field (defaulting to `8222`, prefilled from the connection's host). Dashboard shows: server identity/uptime/version card, live-refreshing connection count & in/out throughput, a slow-consumer warning banner if `varz.slow_consumers > 0`, and (if the JetStream tab is enabled) cross-links to the existing JetStream Account Info dialog rather than duplicating that data.

### Implementation Checklist
- [ ] `lib/server_monitor.dart` (new) — pure HTTP client wrapper (`fetchVarz()`, `fetchConnz()`, injectable `http.Client` for tests, matching `lib/update_checker.dart`'s pattern) parsing `/varz` and `/connz` JSON into typed models.
- [ ] New opt-in setting (`prefServerMonitoringEnabled`/default `false`) plus a monitoring-port field, in `lib/settings_dialog.dart` or a new small dialog.
- [ ] `lib/server_monitor_dashboard.dart` — new tab/panel: identity card, live-polled (not push — this is plain HTTP, no `watch()` equivalent) connection/throughput stats, slow-consumer warning, graceful "monitoring not reachable" state distinct from "monitoring disabled".
- [ ] Decide polling interval (balance freshness vs. hammering the server's monitoring endpoint) and whether `/connz` (potentially large on a busy server) is paginated in the UI.
- [ ] Unit tests for JSON parsing (mocked `http.Client`, mirroring `test/update_checker_test.dart`) + widget tests against a fake monitor client; live-server verification against a real `nats-server -m 8222`, including the "monitoring not enabled on this server" (connection refused / 404) path.
- [ ] Document in `assets/app_help.md`: what monitoring is, how to enable it server-side, and that it's a separate, unauthenticated-by-default HTTP endpoint (a real security consideration worth calling out, not just a feature note).

---

## Milestone 18: NATS Micro-services (Services API) Discovery (Medium Priority) — Completed

### Objective
The NATS ecosystem has a standardized [Services framework](https://docs.nats.io/using-nats/developer/services) (used by `nats.go`'s `micro` package, and others) where services self-register and respond to well-known discovery subjects. Right now this app has no way to answer "what services are currently running against this server" short of knowing their subjects in advance — a live "Services" panel would show what's actually listening.

### What `dart_nats` actually supports
Verified against vendored `dart_nats-1.1.2/lib/src/`: **nothing** — no `service.dart`/`Service`/`Micro` class anywhere. That gap closed from an unexpected direction mid-planning: the upstream maintainer (`chartchuo/dart-nats`) independently pushed a hosting-side implementation (`lib/src/micro.dart`: `ServiceConfig`/`Endpoint`/`MicroService`, `Client.addService()`) to their master, unreleased, right as this milestone was being scoped — letting a Dart client *become* an ADR-32 service, but with no discovery/client side to *find* one. Rather than duplicate that work or wait on their release cadence, the discovery half was built as the complement: `nverbeek/dart-nats` (an existing, previously-unused fork) was synced to their latest master, and `Client.discoverServices()`/`getServicesInfo()`/`getServicesStats()` were added to the same `micro.dart` on branch `feature/service-discovery`, reusing the response shape (`io.nats.micro.v1.*_response`) `MicroService` already produces so this interoperates with any ADR-32 service, not just Dart-hosted ones. This app's `pubspec.yaml` points at that fork branch via a `git:` dependency for now; an upstream PR is intentionally deferred until this app-side usage has proven the API out (see the fork's own commit and `CHANGELOG.md` `## Unreleased` entry for detail).
- Discovery is a request with **no payload** to `$SRV.PING` (all services reply), `$SRV.PING.<name>` (all instances of one service), or `$SRV.PING.<name>.<id>` (one instance) — since multiple services/instances can reply to the same discovery request, this isn't a single-reply `request()` call but a timed collection window (`newInbox()` + `sub()`, publish with that as `replyTo`, collect for a bounded `Duration`, then `unSub()`). `$SRV.INFO`/`$SRV.STATS` follow the same reply-fan-in shape for endpoint/subject and request-count/error-count/latency stats respectively.
- Response payloads are plain JSON (`{"id", "name", "version", "endpoints": [...]}` for INFO; request/error counts + average processing time per endpoint for STATS), parsed into `PingResponse`/`InfoResponse`/`EndpointInfo`/`StatsResponse`/`EndpointStatsInfo` in the fork — no new dependency needed on either side.

### UI Architecture & Concept
A **Services** tab, gated behind its own opt-in setting (default **off**, same reasoning as Milestone 17 — this actively publishes discovery requests onto the account rather than just reading passively). A **Discover** button fires the fan-in `$SRV.PING` request and populates a master list of service instances as replies trickle in over the collection window; selecting one fetches its `$SRV.INFO`/`$SRV.STATS` for an endpoints-and-per-endpoint-stats detail view, mirroring `ObjectStoreDashboard`'s master/detail, no-live-watch, explicit-Refresh shape (there's even less to watch here — every result is itself the reply to an explicit fan-out, not a listing of anything the server tracks persistently).

### Implementation Checklist
- [x] `lib/service_discovery_manager.dart` (new) — thin wrapper around the fork's `Client.discoverServices()`/`getServicesInfo()`/`getServicesStats()`, mirroring `KvManager`/`ObjectStoreManager`'s shape. Also home to `describeServiceDiscoveryError()` and the pure `formatNanos()` latency formatter.
- [x] New opt-in setting (`prefServiceDiscoveryEnabled`/default `false`), wired into `lib/settings_dialog.dart` and `lib/main.dart`'s `_visibleTabCount`/`_ensureTabController`.
- [x] `lib/service_discovery_dashboard.dart` — Discover button, live-populating master list as fan-in replies arrive (sorted by name then instance id), detail pane per service/instance (description, endpoints, subjects, request/error counts, average latency), a distinct "no longer responding" state when a previously-discovered instance doesn't answer a follow-up detail fetch.
- [x] Handles the empty case cleanly (no services running is common and not an error, shown as its own empty state rather than an error) with a bounded collection window (750ms default) so Discover always terminates.
- [x] Unit tests for the pure helpers (`test/service_discovery_manager_test.dart`) and widget tests against a fake manager (`test/service_discovery_dashboard_test.dart`, 8 cases: no-manager, pre-discovery prompt, populated list, empty result, error+Retry, full detail load, stopped-service detail, manager-reset-to-null). A live-server `integration_test/service_discovery_test.dart` stands up a real second `dart_nats` client hosting a fake ADR-32 service via the fork's own `addService()` (a real client on the wire replying to `$SRV.PING`/`INFO`/`STATS`, not a mock), enables the feature via Settings, discovers it, drives one real request through its endpoint and confirms the stats reflect it, then stops the service and confirms a fresh Discover no longer finds it.
- [x] Documented the Services API convention and this app's read-only/discovery-only scope (no service *hosting* from this app) in `assets/app_help.md`.

---

## Milestone 19: Multi-Select + Clipboard Copy (Medium Priority) — Completed

### Objective
The Live Messages list (and JetStream Browse Messages) has **no cap on how many messages it holds in memory** (confirmed: nothing in `lib/main.dart` bounds `items.length` — the list only ever shrinks via the user's own Clear button), so a long-running capture on a busy subject can realistically reach tens of thousands of rows. Today the only way to get that data out of the app is manually copying individual messages one at a time via the row menu. This started as a broader "Export/Import Captured Messages" milestone (file-based NDJSON export/import); once planning began, it was rescoped down to just multi-select + clipboard copy as a much lighter first cut that already solves the common "grab a few messages for a bug report" case without file dialogs or a large-export safeguard. The original file-based idea lived on as Milestone 22 (Low Priority) and was later completed — see that section below.

### Implementation
- [x] **Multi-select on the Live Messages list** — no checkboxes. **Shift+Click** extends/replaces a contiguous selection range from the last-clicked row; **Ctrl+Click** (Cmd+Click on Mac) toggles a single row into or out of the selection independently, without touching any other row, building a disconnected/non-contiguous selection and also becoming the new anchor for a later Shift+Click; **Ctrl+Shift+Up/Down** grows/shrinks the range by one row at a time from the current focus. Identity-based (`Set<Message<dynamic>>` in `lib/main.dart`, alongside a `Message?` anchor and a `_multiSelectActive` flag distinguishing "multi-select engaged but currently empty" from "never engaged, defer to the single-row `selectedIndex`"), not index-based — deliberately, so it survives `_insertMessages` prepending new rows above a scrolled-away viewport and `_runFilter` reassigning `filteredItems` wholesale, neither of which needs any shift-compensation the way the pre-existing single-row `selectedIndex` does. The existing single/double-tap-to-Detail logic is unchanged; a Shift/Ctrl+Click bypasses its 300ms debounce timer entirely (unambiguous intent), and any plain click collapses a multi-selection back to a single row, exactly like before this milestone.
- [x] **Two real bugs found by live manual testing, not caught by the automated tests as originally written** (same pattern as several earlier milestones): (1) a payload's line breaks were only escaped if they were a bare `\n` — payloads built from concatenated CRLF-terminated lines (e.g. NMEA sentences) left the `\r` behind, which still rendered as a real line break wherever the copied text was pasted; fixed by matching `\r\n`/`\r`/`\n` uniformly. (2) Ctrl+C silently did nothing whenever anything else (e.g. the Filter/Find field) had last held keyboard focus, since the app's shortcut-handling `Focus(onKeyEvent: ...)` only claims focus once via `autofocus: true` at first build and nothing ever reclaimed it afterward; fixed by having `_handleMessageTap` explicitly request focus onto a dedicated `_messageListFocusNode` on every row click (plain, Shift, or Ctrl), regardless of what had focus before.
- [x] **Ctrl+C** copies every selected row as one line per message (`subject: payload`), in on-screen top-to-bottom order, with a payload's own embedded line breaks escaped as a literal `\n` so the copied line count always equals the selected-message count. Unchanged for exactly one selected row (still the bare payload, no subject prefix) — preserves the pre-existing, already-tested single-select Ctrl+C behavior rather than a since-day-one format change.
- [x] A **"Copy Selected (N)"** entry was added to the existing per-row popup menu (`_buildSafePopupMenuButton`) alongside the pre-existing single-row `copy`, so the bulk action is discoverable without knowing the shortcut. It always operates on the existing selection regardless of which row's menu was opened — opening the menu on a row outside the current range does not implicitly fold it in (matches Explorer/Finder/VS Code convention).
- [x] Scope: Live Messages tab only — JetStream Browse Messages is a separate widget with no shared base and no existing selection state, so it's excluded here for the same reason Milestone 13 excluded it for "outgoing" tagging.
- [x] The status bar's existing "Total Messages: N, Showing: N" text now also shows "Selected: N" (via `_effectiveSelection().length`), but only appended when at least one row is selected — no "Selected: 0" clutter the rest of the time.
- [x] Tests: extended `integration_test/live_messages_interactions_test.dart` with a new case covering Shift+Click range selection, Ctrl+Shift+Up/Down grow/shrink, Ctrl+C on a multi-selection (including the embedded-newline escape), Ctrl+C on a single selection (regression guard on the unchanged format), the "Copy Selected (N)" menu item (including that opening it on a non-selected row doesn't fold that row in), selection surviving both a new message arriving mid-selection and a Filter-field change, a dedicated Ctrl+Click case (disconnected add/remove, toggling down to nothing without crashing, and moving the range anchor for a later Shift+Click), and the status bar's "Selected: N" text appearing/disappearing at the right points — run against a real local `nats-server`. `assets/app_help.md`'s "Message-Specific Shortcuts"/new "Multi-Select" sections document the behavior.

---

## Milestone 20: Per-Subscription Message Rate Sparkline (Low Priority, tentative)

### Objective
Milestone 11 already tags every message with its originating subscription's color via `sid`. This milestone would add a small rolling messages/sec indicator per subscription (e.g. next to its chip) so a noisy or unexpectedly quiet subject is visible at a glance instead of only inferable by watching the list scroll. **Flagged by the user as a "maybe"** — lowest-confidence item of this batch, worth a lighter design pass before committing to implementation, and it may turn out not to be worth the added chip-row complexity once mocked up.

### Implementation Checklist
- [ ] Decide visual treatment (tiny sparkline, a rate number, a pulsing dot) and where it lives (in the chip itself vs. only in the Subscription Manager dialog, given Milestone 11's own experience with chip crowding/measurement complexity).
- [ ] Compute a rolling rate per `sid` from existing arrival timestamps — no new `dart_nats` data needed, this is purely a local aggregation over what's already tagged.
- [ ] Confirm it doesn't reintroduce the offstage-measurement/`OverflowBox`/`Tooltip` pitfalls documented in Milestone 11's notes if implemented inside the chip row itself.
- [ ] Unit tests for the rate computation (fake clock) + widget/live-server verification that the displayed rate roughly tracks a known publish rate from a second test client.

---

## Milestone 21: Message Detail Headers Table + Raw Copy (Low Priority) — Completed

### Objective
`lib/message_detail_dialog.dart`'s Headers section (lines 109-121) currently renders all headers as a single flattened block — `headers.forEach((k, v) => headerText += '$k: $v\n')` into one `SelectableText`, no visual separation between keys and values once there's more than one header or a long value. The Payload section right below it already has a copy-to-clipboard `InkWell`/icon with a "Copied!" fade animation (lines 190-222); Headers has no equivalent, so copying header data means manually selecting text out of the flattened block. User-flagged as a readability gap while testing the JetStream message list.

### Desired Behavior
- Replace the flattened `SelectableText(headerText)` with a simple two-column grid/table (key | value), one row per header — a `Table`/`DataTable`-style layout, not a redesign of the whole dialog. Keep `Header Version` above it as-is (it's a single value, not a map, so it doesn't need tabular treatment).
- Add a copy button next to the Headers section header (mirroring the Payload copy button's icon/position/"Copied!" fade pattern) that copies the headers **raw**, in the same `key: value` newline-joined format already shown today — not the table markup, and not JSON — so the copied text is a plain, greppable/pasteable block identical in spirit to what Payload's copy button does for the payload.

### Implementation Checklist
- [x] Replace the Headers `SelectableText(headerText)` block in `lib/message_detail_dialog.dart` with a simple table/grid layout (key column, value column), keeping each value individually selectable.
- [x] Add a copy button for the Headers section reusing the existing `_showCopiedFeedback()`/`_fadeAnimation` mechanism already built for Payload, copying the same `k: v`-per-line raw text currently assembled into `headerText`.
- [x] Confirm behavior with zero headers (section already conditionally hidden — no change needed there) and with a large header value (long value shouldn't break the table layout — wrap or scroll, not overflow).
- [x] Update/extend `test/message_detail_dialog_test.dart` for the new table rendering and the headers-copy button + "Copied!" feedback.

### Follow-up: dialog width bug found via live testing
After shipping the table, live testing against a real server (multi-header messages published via `nats pub -H`) showed the dialog rendering far narrower than the window, with every header value wrapping into a tall column of 1-2-word lines even though most of the window was empty. Root cause: the value column used `FlexColumnWidth`, whose `minIntrinsicWidth`/`maxIntrinsicWidth` both hard-return `0.0` in the Flutter SDK (`packages/flutter/lib/src/rendering/table.dart`). `AlertDialog` already wraps its own content in an `IntrinsicWidth` to size itself (`packages/flutter/lib/src/material/dialog.dart`), so that `0.0` made the dialog completely ignore how wide the values were and collapse to just the key column's width, then cram everything else into whatever was left.

Fix: swapped the value column to `IntrinsicColumnWidth(flex: 1)`, which correctly reports each cell's natural unwrapped width for the dialog's own sizing pass while still flexing to fill/shrink at final layout. No other plumbing was needed — `Dialog`'s default `constraints` (`BoxConstraints(minWidth: 280.0)`, no max) plus the already-present `IntrinsicWidth` handle the rest. Verified with three scenarios at a realistic desktop window size (short headers + short payload → compact dialog; wide headers + short payload → dialog grows to fit headers; short headers + wide payload → dialog grows to fit payload instead), confirming the dialog now sizes to whichever section is widest, as requested. Live-verified against a real `nats-server` afterward.

**General lesson for this codebase**: any future `Table` inside an `AlertDialog` (or anything else that leans on `IntrinsicWidth` for auto-sizing) should use `IntrinsicColumnWidth(flex: ...)` rather than `FlexColumnWidth` for columns whose content should influence the container's size — `FlexColumnWidth` only works correctly when the container's width is already fixed by something else.

**Not done**: `images/Message Detail.png` in the README's screenshot tour still shows the old flattened-text Headers block, not the new table — same "left as a follow-up" situation Milestone 16 hit with its button-style screenshots. Needs the full `scripts/capture_screenshots.ps1`/`screenshot_tour_test.dart` pipeline to re-capture, not done as part of this session.

---

## Milestone 22: Export & Replay Captured Messages to/from File (Low Priority) — Completed

### Objective
Originally scoped as Milestone 19, this was descoped once its multi-select + clipboard-copy slice (now Milestone 19, completed) turned out sufficient for the common case of grabbing a few messages for a bug report. This is what's left: bulk export of a capture to a file (for offline analysis, or captures too large for a clipboard paste), and **replaying** a previously exported file by publishing every message in it back onto a connected server (e.g. to reproduce a captured sequence against a test server). Demoted to Low Priority and moved to the end of the list, then picked up and completed once a concrete need for file-based bulk export/replay came up.

**Naming note**: an earlier draft of this milestone called the file-loading half "Import" and scoped it as read-only offline browsing (load a file into the message list, no live server needed, nothing sent). That was replaced with **Replay** after clarifying the actual intent: select a file and have the app publish its messages back to the server, not just view them. This is a real behavioral fork, not just a rename — Replay requires an active connection and actually puts messages on the wire; the old read-only-browsing idea did not. If offline browsing (no live server, nothing published) turns out to be wanted too, that's a separate future addition, not part of this milestone as scoped now.

### Desired Behavior
- **Export selected**: reuses Milestone 19's multi-select range to let the user pick specific messages and export only those to a file.
- **Export all**: a separate action for the common "just dump everything" case — but given the list is unbounded (nothing in `lib/main.dart` bounds `items.length`), this needs an explicit, honest confirmation showing the real count before writing anything (e.g. "Export 42,318 messages?"), and a sensible safeguard past some threshold (a hard cap with "most recent N", or at minimum a stronger warning) rather than silently attempting to serialize an arbitrarily large in-memory list to JSON on the UI thread.
- **Replay**: select a previously exported file and publish every message in it (subject + payload + headers) back onto the currently connected server, in file order. Only available while connected. Given this actually puts traffic on the wire — potentially thousands of messages — needs its own honest confirmation showing the real count before firing ("Replay 4,210 messages to this server?"), plus three configurable knobs rather than a single fire-and-forget action:
  - **Message interval**: delay between each individual message within one pass through the file (default likely 0 = as fast as possible, but user-configurable so a real server/downstream consumer doesn't get hit with a sudden burst it doesn't expect).
  - **Repeat count**: how many times to replay the whole file (default **0** = play once, no repeat — matches "0 additional repeats" rather than "0 times total," needs a clear label so it doesn't read as "send nothing"). A positive N replays the full file N additional times after the first pass.
  - **Repeat interval**: a *separate* delay applied once per full pass, between the last message of one repeat and the first message of the next — distinct from the per-message interval above, since someone replaying a whole batch on a timer (e.g. "resend this captured sequence every 30 seconds") wants a pause between batches, not just between messages within a batch.
- Format: NDJSON (one JSON object per line: subject, payload, headers, timestamp, direction if Milestone 13 lands) — streams naturally to/from disk without holding a second full in-memory copy during export, and is trivially diffable/greppable outside the app too. The same format is both written by Export and read by Replay.
- **Surfacing — config dialog, then a non-blocking status banner**: Export is a one-shot confirm dialog (pick selection/all, see a count, click Export). Replay is more involved (file pick, three pacing fields, a live-computed total, a run that can take a long time), so it's two stages: a config dialog (mirroring `jetstream_stream_dialog.dart`'s form pattern) collecting the file + the three pacing fields + a live "will send N messages over ~M" preview, then on confirm the dialog closes and progress is surfaced via a new `ReplayBanner` — a sibling row above the message list, following the exact same pattern `lib/paused_banner.dart` already established (not a second modal), showing something like "Replaying 340/4,210 (repeat 2/5)" with a Stop button. This keeps the rest of the app usable during a long/repeating replay and lets the user watch replayed messages land live in the list as they're published.
- **Coexistence with `PausedBanner`**: Pause (does the list *render* new incoming arrivals) and Replay (is the app currently *publishing* outgoing messages) are orthogonal — a replayed message can loop back as an incoming arrival while the list is paused, so both banners can legitimately be active at once. Don't merge them into one combined banner/state machine; stack `ReplayBanner` and `PausedBanner` as two independent sibling rows in the same `Column`, each owning only its own state/actions, same as how `PausedBanner` itself was kept a plain sibling rather than a list item (see Milestone 6/"Also This Session" notes on why banners can't be list items here).

### Implementation Checklist
- [x] Large-export safeguard: warn-and-proceed, not a silent hard cap. `ExportConfirmDialog` always shows the real count and adds a warning paragraph past `largeExportWarningThreshold` (20,000) — it still exports everything if confirmed. Serialization in `lib/main.dart`'s `_exportMessages` runs in ~1000-message chunks with a `Future.delayed(Duration.zero)` yield between chunks so the UI thread doesn't freeze; true disk streaming was left as a future enhancement (the app already holds the full capture in memory as `Message` objects).
- [x] An "Export Selected (N)" action reusing Milestone 19's multi-select range, and a separate always-available "Export All (N)" action — both via a toolbar `PopupMenuButton` and, for Selected, a "Export Selected (N)" row-menu entry mirroring the existing "Copy Selected (N)".
- [x] `lib/message_export.dart` (new) — pure NDJSON serialize/parse logic (`ExportedMessage`, `encode/decodeExportedMessageLine`, `parseExportedMessagesNdjson`, `encodeExportedMessagesNdjson`), independent of `file_picker`/`Client` I/O, with the one bridging function (`exportedMessageFromNatsMessage`) kept separate so the rest of the module stays testable without a live connection. The parse half is shared by Replay.
- [x] Export via the existing `file_picker`-backed save-file pattern (mirroring Object Store's download flow, `_defaultSaveExportedMessages`); Replay via the existing open-file pattern (`_defaultPickReplayFile` in `lib/replay_config_dialog.dart`), publishing each parsed message via `natsClient.pub(...)` with raw bytes and `buffer: false` (not `pubString`, so a mid-replay disconnect fails fast instead of silently queuing).
- [x] Replay confirmation happens via `ReplayConfigDialog` (`lib/replay_config_dialog.dart`): real parsed message count, the three pacing fields (message interval, repeat count, repeat interval), and a live-updating "Will send N messages over ~M" preview (`count × (repeatCount + 1)`, plus estimated duration) before Start Replay is enabled; disabled entirely while disconnected.
- [x] Replay execution (`lib/main.dart`'s `_runReplay`) is cancelable mid-run: a `Completer<void>` stop signal is raced against both the per-message and per-pass waits via `Future.any`, so Stop halts before the next scheduled send rather than only between whole passes.
- [x] Scope: Live Messages tab only, matching Milestone 19's own scoping decision — JetStream Browse Messages has a different, consumer-backed data source and no shared base.
- [x] Tests: `test/message_export_test.dart` (NDJSON round-trip including binary-payload fidelity, blank-line/malformed-line handling, multi-message ordering), `test/replay_banner_test.dart`, `test/export_confirm_dialog_test.dart` (under/over-threshold, warn-and-proceed), `test/replay_config_dialog_test.dart` (disconnected-disables-Start, live preview formula incl. repeat-count-0, parse-error surfacing, exact onReplay payload) — all using injected fake file callbacks, no real OS dialog. A live-server `integration_test/live_messages_export_replay_test.dart` covers Export Selected → Replay round-tripping byte-for-byte, a repeat-count > 0 run honoring the repeat interval, and Stop halting a running replay promptly.
- [x] Documented the NDJSON format, the large-export warning, and the replay pacing/repeat/Stop behavior in `assets/app_help.md`, plus a disambiguation note between the per-row "Replay" (re-send one message) and this file-based "Replay" (bulk publish from a file).

---

## Milestone 23: Adopt Reconnect-Buffer Overflow Handling (`maxReconnectBuffer`) (Low Priority) — Unblocked

### Objective
Upstream commit `3d9bd9b` (landed on `chartchuo/dart-nats` master 2026-07-13, just ahead of this project's own service-discovery PR #44) gives `Client.connect()` a new `maxReconnectBuffer` parameter (default 1000). While disconnected, `pub()`/`pubString()` still queue outgoing messages in an internal buffer for replay once reconnected, but once that buffer hits `maxReconnectBuffer` entries, the call now **throws `NatsException`** instead of buffering forever. Today's uncapped behavior means a long outage combined with continued publishing grows that buffer without bound; the new behavior trades that for a hard failure once the cap is hit — better, but only if this app is ready to catch it.

### Unblocked (2026-07-16)
PR #44 has merged upstream into `chartchuo/dart-nats` master and shipped in the **1.2.0** release (published to pub.dev as **1.2.1**), which also carries this reconnect-buffer work. `pubspec.yaml` now depends on a normal `dart_nats: ^1.2.1` pub.dev version constraint (verified `maxReconnectBuffer` present in `client.dart`, both the constructor parameter and the throw site at the buffer-full check). No dependency blocker remains — this milestone is ready to implement.

### What needs to change
- **`lib/main.dart`'s three fire-and-forget `pubString()`/`pub()` call sites** (Send dialog ~line 2190, row-menu Replay ~line 2330, Ctrl+R/Edit & Send ~line 2442) currently have no try/catch around the publish call. None of them pass `buffer: false`, so all three rely on the default buffering behavior and would be first to hit a newly-thrown `NatsException` during a long outage with continued sending.
- Decide the UX for the overflow case — most likely a `SnackBar` (matching the app's existing error-surfacing pattern elsewhere) explaining that too many messages are queued while disconnected, rather than an uncaught exception reaching Flutter's error zone.
- Consider whether `maxReconnectBuffer`'s default (1000) is worth exposing as a setting, or left as the package default — no user request for this yet, so default to leaving it alone unless raised.
- Unit/widget test coverage for the new catch path (a fake client/manager throwing `NatsException` from a buffered publish), plus a live-server verification pass forcing a disconnect and publishing past the cap.

### Implementation Checklist
- [ ] Wrap the three fire-and-forget publish call sites in `lib/main.dart` with error handling for the new `NatsException` overflow case.
- [ ] Decide and implement the overflow UX (likely a `SnackBar`).
- [ ] Unit/widget tests for the new catch path.
- [ ] Live-server verification pass (force a disconnect, publish past the cap, confirm the new behavior surfaces cleanly).

---

## Milestone 24: Adopt Heartbeat Ping/Pong for Faster Dead-Connection Detection (Low Priority) — Unblocked

### Objective
The same upstream commit (`3d9bd9b`) adds a configurable heartbeat mechanism to `Client.connect()`: `pingInterval` (default 120s) and `maxPingsOut` (default 2). The client now sends periodic `PING`s while connected and, if `maxPingsOut` go unanswered, proactively tears down the socket and transitions to `Status.disconnected` — detecting a dead-but-not-yet-TCP-closed connection (e.g. a silently dropped network path, a hung proxy) faster than waiting on the OS-level TCP timeout alone. This is a pure reliability improvement that plugs into the app's existing `onConnect`/`onDisconnect`/reconnect flow (`lib/main.dart`'s `natsConnect()`) with no new UI required in the simplest case.

### Unblocked (2026-07-16)
Same dependency resolution as Milestone 23 — `dart_nats: ^1.2.1` on pub.dev carries this heartbeat work (verified `pingInterval`/`maxPingsOut` present in `client.dart`'s `connect()` and the ping-timer/dead-connection teardown logic). No dependency blocker remains.

### What needs to change
- Decide whether to pass non-default `pingInterval`/`maxPingsOut` values from `natsConnect()` in `lib/main.dart`, or accept the package defaults (120s / 2 pings ≈ up to 4 minutes to detect a dead connection) — no user complaint about reconnect latency has come up yet, so defaults are the likely starting point.
- Confirm this doesn't change observable behavior on the happy path (pings are transport-level, invisible to the UI) — mainly a live-server verification concern (kill the underlying TCP path without a clean close, e.g. a firewall rule or killing a proxy, and confirm `Status.disconnected`/reconnect fires within roughly `pingInterval * maxPingsOut` instead of whatever the OS TCP keepalive/timeout would otherwise take).
- No new preference/UI is anticipated unless a real need to tune the interval surfaces later.

### Implementation Checklist
- [ ] Decide on `pingInterval`/`maxPingsOut` values (defaults vs. app-chosen).
- [ ] Live-server verification: kill the underlying TCP path and confirm faster dead-connection detection.
- [ ] Confirm no regression on the happy-path reconnect flow.

---

## Milestone 25: Quick-Subscribe to Exact Subject from Message Row (Low/Medium Priority)

### Objective
A common exploration pattern: the user subscribes to a wide wildcard subject (e.g. `orders.>`) because they don't yet know the exact subject taxonomy, then wants to narrow down to just one or two specific subjects they've spotted going by. Today that means opening the Subscription Manager dialog and typing the exact subject out by hand. This milestone adds a shortcut directly on a Live Messages row — "Subscribe to this exact subject" — that adds `message.subject` as its own new subscription via the existing add-subscription path (`lib/main.dart`'s `_addSubscription`, `lib/subscription_manager_dialog.dart`), with the user then free to remove the original wildcard chip (its existing × delete affordance from Milestone 11) to shrink down to just what they care about, live, with no reconnect.

This is a complement to the existing Filter box, not a replacement: Filter narrows what's already been received and rendered (client-side only, no effect on the wire); this feature narrows what the app actually subscribes to and receives from the server in the first place.

### Desired Behavior
- New row-menu entry (and/or context action), e.g. "Subscribe to This Subject", using the row's literal `message.subject` — not a pattern/wildcard guess.
- Adding it goes through the same live-subscribe path Milestone 11 already built (`natsClient.sub()` immediately if connected), so it takes effect without needing to reconnect or open the full manager dialog.
- No auto-removal of the wider subscription that originally delivered the message — NATS subscriptions overlap rather than replace each other, so until the user manually removes the wide one (via its existing chip × icon) they'll receive the message twice (once per matching subscription). Surface this plainly — e.g. a brief SnackBar noting the new subscription was added and that the existing wildcard subscription still applies — rather than let duplicate delivery look like a bug.
- Disabled/hidden for a row whose subject is already covered by an existing *exact* subscription (no point adding a literal duplicate); still offered when only a wildcard subscription currently covers it.

### Implementation Checklist
- [ ] Add the row-menu entry in `lib/main.dart`'s message popup menu, reusing `_addSubscription`/`SubscriptionInfo` (Milestone 11) with the row's exact subject and no queue group.
- [ ] Surface the "you may now receive this subject twice until you remove the wildcard" caveat (SnackBar or similar), following this app's existing error/notice SnackBar pattern.
- [ ] Guard against adding a literal duplicate of a subject that's already its own exact subscription.
- [ ] Unit/widget test coverage for the new menu entry (added subscription list, duplicate-guard, disconnected state) plus a live-server verification pass: subscribe wide, receive a message, use the shortcut, confirm the new exact subscription is active server-side (e.g. via a second direct `dart_nats` client or `$SYS` subscription info), then remove the wildcard chip and confirm delivery continues uninterrupted for the exact subject.
