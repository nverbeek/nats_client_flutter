# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap details the development plan, UI architecture, and implementation milestones for expanding the **NATS Client UI** with core advanced NATS ecosystem capabilities: **JetStream (Phase B)** and **Key-Value Stores (Phase A)**.

These features are made possible by our successful migration to the official mainline `dart_nats: ^1.1.1` package.

---

## Progress Overview
- [x] **Milestone 0**: Migrate custom fork to mainline `dart_nats: ^1.1.1` and verify compatibility.
- [ ] **Milestone 1**: Design & Implement **Phase B: JetStream Stream & Consumer Monitor** (High Priority).
- [ ] **Milestone 2**: Design & Implement **Phase A: Key-Value (KV) Store Inspector** (Medium Priority).
- [ ] **Milestone 3**: Clean up, finalize error handling, write widget/unit tests, and bundle releases.

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
- [ ] **UI Infrastructure**:
  - [ ] Add a `TabController` or bottom/side rail routing to swap active dashboard panels.
  - [ ] Refactor main view into modular widget layout tabs to prevent `lib/main.dart` from bloating.
- [ ] **JetStream Backend Core (`lib/jetstream_manager.dart`)**:
  - [ ] Instantiate `JetStream` client using `var js = JetStream(natsClient)`.
  - [ ] Add methods to fetch stream configurations (`js.getStreamNames()`, `js.getStreamInfo(name)`).
  - [ ] Add stream management capability:
    - [ ] Create a stream dialog (specifying Stream Name, Subjects, maxAge, replicas).
    - [ ] Delete a stream.
    - [ ] Purge a stream (`JsStream.purge()`).
- [ ] **Consumer Management**:
  - [ ] Retrieve consumer lists (`js.getConsumerNames(stream)`, `js.getConsumerInfo(stream, consumer)`).
  - [ ] Build a **"Create Consumer" dialog** supporting both push (deliver subject) and pull models.
- [ ] **Stream Message Inspection**:
  - [ ] Support loading historical payloads or batching messages using Pull Consumers (`Consumer.fetch(batchSize)`).
  - [ ] Enable standard NATS acknowledgment buttons (`Ack`, `Nak`, `Term`) on pulled JetStream payloads.

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
- [ ] **Quality Assurance**:
  - [ ] Fix any deprecated API alerts (e.g. migrate `withOpacity` instances to `.withValues()`).
  - [ ] Add comprehensive unit and widget tests under `test/` verifying the new layouts.
- [ ] **Build Pipeline**:
  - [ ] Verify that GitHub Actions CI runner (`.github/workflows/build.yml`) packages releases successfully.
