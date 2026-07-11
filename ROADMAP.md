# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap details the development plan, UI architecture, and implementation milestones for expanding the **NATS Client UI** with core advanced NATS ecosystem capabilities: **JetStream (Phase B)**, **Key-Value Stores (Phase A)**, **Expanded Authentication (Phase D)**, and **Update Notifications (Phase E)**.

These features are made possible by our successful migration to the official mainline `dart_nats: ^1.1.1` package.

---

## Progress Overview
- [x] **Milestone 0**: Migrate custom fork to mainline `dart_nats: ^1.1.1` and verify compatibility.
- [x] **Milestone 1**: Design & Implement **Phase B: JetStream Stream & Consumer Monitor** (High Priority). 1a (read-only monitor) and 1b (mutations) complete.
- [x] **Milestone 2**: Design & Implement **Phase A: Key-Value (KV) Store Inspector** (Medium Priority). Implementation, docs, unit/widget tests, and a live-server verification pass (full bucket/key lifecycle, live cross-client updates, and the optimistic-concurrency conflict path) are done.
- [x] **Milestone 3**: Clean up, finalize error handling, write widget/unit tests, and bundle releases. Quality Assurance and Platform Verification are done for Windows, Linux, and Web (including confirming JetStream works over the web target's forced `ws://` scheme).
- [x] **Milestone 4**: Design & Implement **Phase D: Expanded Authentication Support** (username/password, token, NKey, `.creds`) (Medium Priority). Implementation, docs, unit/widget tests, and a live-server verification pass (correct + wrong credentials) are done for all four methods.
- [x] **Milestone 5**: Design & Implement **Phase E: Update Notifications** (Low Priority). Checks GitHub Releases on startup and surfaces a dismissible in-app notice when a newer version is published; opt-out toggle in Settings. Implementation, unit tests, and a live-API verification pass (both the update-available and up-to-date paths) are done.
- [x] **Milestone 6**: Design & Implement **Phase F: Live Message List UX Improvements** (Medium Priority). Filter/Find on the JetStream Browse Messages view (plus tab-aware Ctrl+F/Ctrl+Shift+F), scroll-position-preserving inserts on both message lists (verified correct and performant at thousands-of-messages/large-burst scale), and a Pause/Resume control on both. Implementation and a live-server verification pass are done.
- [ ] **Milestone 7**: Design & Implement **Message Direction Indicator (Incoming vs. Outgoing)** (Low/Medium Priority). Not started.
- [ ] **Milestone 8**: Design & Implement **Request/Reply Correlation Improvements** (Medium Priority). Not started.
- [ ] **Milestone 9**: Investigate & Implement **Code Signing for Windows & macOS Builds** (Low Priority, cost-gated). Not started — research done, decision on which paid/free path pending.

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

## Milestone 7: Message Direction Indicator (Incoming vs. Outgoing) (Low/Medium Priority)

### Objective
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

## Milestone 8: Request/Reply Correlation Improvements (Medium Priority)

### Objective
User feedback asked whether request/reply correlation could be improved. Today, "Reply To" (`lib/main.dart` around lines 1525-1532) only pre-fills the Send dialog's subject field with the original message's `replyTo` subject — it's an ordinary publish with no automatic pairing. True NATS request/reply (a private per-request inbox subject, awaited for a single correlated response) isn't used anywhere in the app today, so a real request/reply round trip wouldn't even show up in the message list (the app isn't subscribed to the inbox subject it would use).

### What `dart_nats` actually offers (verified against the vendored 1.1.1 source)
`Client.request<T>(subject, data, {timeout = 2s, jsonDecoder, header})` / `requestString<T>(...)`: lazily creates one shared wildcard subscription to `_INBOX.<clientNuid>.>`, generates a unique per-call reply subject, publishes with `replyTo` set to it, and awaits the first message seen on that inbox (default 2s timeout, throws `TimeoutException` on expiry). Correlation is a subject-string match inside the shared subscription's stream, not a keyed dispatch map. Calls are serialized via an internal `Mutex` — concurrent `request()` calls queue rather than run in parallel. The generated inbox subject isn't returned separately; the response `Message.subject` *is* the correlation key.

### Possible Directions (not yet decided)
- Add a "Request" mode to the Send dialog (alongside the existing JetStream-ack toggle) that calls `request()`/`requestString()` instead of a plain publish, then inserts both the outgoing request and its correlated incoming reply into the list as a linked pair — depends on Milestone 7's outgoing-message tracking.
- Alternatively/additionally, improve correlation for the plain-pub/sub style of request/reply many NATS users actually use (subscribe to a reply subject, publish with `replyTo` set, no `client.request()` involved) — likely worth supporting both patterns rather than assuming everyone uses the built-in `request()`.
- Visually link paired rows (shared correlation id, "jump to reply"/"jump to request", or adjacent grouping) instead of leaving the user to scan for a matching subject.
- A clear timeout/no-reply failure state in the UI, since `request()` throws `TimeoutException` rather than hanging silently.
- Design note: because `request()` is mutex-serialized inside `dart_nats`, rapid-fire requests from the UI would queue, not run in parallel — worth being deliberate about if the UI ever allows firing several at once.

### Implementation Checklist
- [ ] Decide UX: dedicated "Request" send mode using `client.request()`, enhanced correlation for the existing plain pub/sub "Reply To" flow, or both.
- [ ] Implement the chosen mechanism, building on Milestone 7's outgoing-message tracking so both halves of a pair are visible in the list.
- [ ] Visual/interaction linking between paired rows.
- [ ] Timeout/failure UX.
- [ ] Unit tests + live-server `integration_test` coverage.

---

## Milestone 9: Code Signing for Windows & macOS Builds (Low Priority, cost-gated)

### Objective
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
