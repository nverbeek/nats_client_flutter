# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap details the development plan, UI architecture, and implementation milestones for expanding the **NATS Client UI** with core advanced NATS ecosystem capabilities: **JetStream (Phase B)**, **Key-Value Stores (Phase A)**, and **Expanded Authentication (Phase D)**.

These features are made possible by our successful migration to the official mainline `dart_nats: ^1.1.1` package.

---

## Progress Overview
- [x] **Milestone 0**: Migrate custom fork to mainline `dart_nats: ^1.1.1` and verify compatibility.
- [x] **Milestone 1**: Design & Implement **Phase B: JetStream Stream & Consumer Monitor** (High Priority). 1a (read-only monitor) and 1b (mutations) complete.
- [ ] **Milestone 2**: Design & Implement **Phase A: Key-Value (KV) Store Inspector** (Medium Priority).
- [~] **Milestone 3**: Clean up, finalize error handling, write widget/unit tests, and bundle releases. Real-backend `integration_test/` suite + CI `test` job landed; detailed coverage gap list captured below, not yet closed.
- [ ] **Milestone 4**: Design & Implement **Phase D: Expanded Authentication Support** (username/password, token, NKey, `.creds`) (Medium Priority).

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

### Implementation Checklist
- [ ] **Bucket Selection**:
  - [ ] Fetch the list of all registered KV buckets using standard management APIs.
  - [ ] Implement a **"Create Bucket"** form (specifying Bucket Name, history depth, TTL, replicas).
  - [ ] Implement a **"Delete Bucket"** command.
- [ ] **Key-Value Inspection Backend (`lib/kv_manager.dart`)**:
  - [ ] Bind selected bucket to `KeyValue` controller using `js.keyValue(bucketName)`.
  - [ ] Fetch key entries using `kv.get(key)`. Include automatic filtering of tombstones (deleted/purged keys) supported in `dart_nats 1.1.1`.
- [ ] **Key Mutation & Concurrency**:
  - [ ] Build **"Put Value"** dialog form supporting JSON/text string values.
  - [ ] Implement key deletions (`kv.delete(key)`) and purges (`kv.purge(key)`).
  - [ ] Add Optimistic Concurrency checks using revisions retrieved via `kv.getRevision(key)`.
- [ ] **Live Watcher Integration**:
  - [ ] Support real-time updates of the key listing pane using stream listeners on `kv.watch()`.

---

## Milestone 3: Clean up, Testing & Release

- [ ] **Platform Verification**:
  - [ ] Ensure that native desktop builds (Windows, Linux, macOS) compile smoothly and function on all newly introduced tabs.
  - [ ] Verify that Flutter Web operates gracefully. Include explicit guards (e.g. `kIsWeb` alerts) on features that are completely blocked by WebSocket scheme boundaries.
- [~] **Quality Assurance**:
  - [ ] Fix any deprecated API alerts (e.g. migrate `withOpacity` instances to `.withValues()`).
  - [x] Add comprehensive unit and widget tests under `test/` verifying the new JetStream layouts (`test/jetstream_dashboard_test.dart`, `test/jetstream_manager_test.dart`, `test/send_message_dialog_test.dart`).
  - [x] Add a real-backend `integration_test/` suite (against an actual JetStream-enabled `nats-server`, not fakes) covering the core pub/sub round trip and the full JetStream stream/consumer mutation lifecycle — see `integration_test/live_messages_test.dart` and `integration_test/jetstream_lifecycle_test.dart`.
  - [ ] **Coverage gap list** (audited by hand against every interactive control in `lib/`; ~90 controls found, ~21 touched by either suite — see conversation history for the full per-screen breakdown). Roughly ranked by usage × how untested it is:
    - [ ] **Message Detail dialog** — opened from the message list, Browse Messages, and the Consumer Tail view; never opened by either test suite. Widget test for copy/animation/no-payload states; one integration tap to prove it opens from a real message.
    - [ ] **Settings & Security Settings dialogs** — font size, retry interval, JetStream toggle, and all three TLS cert fields are completely untested. Pure widget-test material, no server needed — cheapest gap to close relative to its size.
    - [ ] **Live Messages tab's daily-use controls** — Filter, Find, and the per-row menu (Copy/Detail/Replay/Edit & Send/Reply To) have zero tests despite being the app's core daily-use feature. Filter/Find are widget-test material; Replay/Edit & Send/Reply To want a live connection, so integration tests.
    - [ ] **JetStream Browse Messages view** (`lib/jetstream_message_view.dart`) — flagged as untestable-via-fake back in Milestone 1a and still unexercised now that real-server integration tests exist (the JetStream integration test tails a named consumer instead of using "Browse Messages"). Add an integration scenario that browses a stream with existing messages.
    - [ ] **Nak / Term buttons** (`lib/jetstream_consumer_tail_view.dart`) — only Ack is proven against a real server; Nak/redelivery and Term semantics are different enough server-side to deserve their own assertions.
    - [ ] **Form validation & conditional fields** — empty Stream Name/Subjects errors, the Push-Consumer-without-Deliver-Subject validator, and non-default Ack/Deliver Policy dropdown values are all untested, pure widget-test material.
    - [ ] **Error/retry paths** — stream-list retry, consumer-list retry, and the Browse/Tail views' retry-on-error each need a "make the fake throw" widget test, mirroring the pattern already used for the top-level availability-check retry.
    - [ ] **Keyboard shortcuts** — ⌘F, ⌘⇧F, D, R, E, ⌘C, Esc, and Ctrl+Enter in Send Message all duplicate button functionality but exercise a separate `Shortcuts`/`Actions` code path that's currently untested.
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
- **NKey seed** — `client.seed = 'SU...'` set before connecting; the client automatically signs the server's nonce challenge (`_sign()` in `client.dart`) with no further wiring needed.
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
- [ ] **`lib/security_settings_dialog.dart`**: add an "Authentication" section below the existing TLS fields (behind a divider) — method dropdown + conditional fields: username/password text fields, token text field, NKey seed text field with an obscure/reveal toggle (like a password field), and a `.creds` file picker reusing the existing `pickFile()` / `file_picker` pattern already used for the cert pickers. No new toolbar button — same 🔒 icon and dialog as today, just with more in it.
- [ ] **`lib/main.dart`**: wire the selected method into `natsConnect()` by building the appropriate `ConnectOption` and/or setting `natsClient.seed` / calling `natsClient.loadCredentialsFile()` before `connect()`.
- [ ] **`lib/constants.dart`**: new preference keys for the auth method + its fields, following the existing TLS key-naming convention.
- [ ] **Opt-in persistence**: only write secrets to `SharedPreferences` when "Remember credentials on this device" is checked; reuse the existing gzip+base64 encoding already used for the TLS private key field for the `.creds` file contents.
- [ ] **Clearer auth-failure feedback**: differentiate an authorization-violation close from a generic connection failure in `natsConnect()`'s error handling, and surface a specific message (e.g. "Authentication failed — check your credentials") instead of the generic "Failed to connect!".
- [ ] Update `assets/app_help.md` with a new "Authentication" section documenting each method, mirroring the existing "TLS Notes" section.
- [ ] Add unit tests for whichever parts are pure/testable (e.g. building a `ConnectOption` from form state) following the same "pure logic vs. network calls" split used in `lib/jetstream_manager.dart` and `test/jetstream_manager_test.dart`.
