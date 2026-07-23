# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap tracks feature milestones for the **NATS Client UI**, covering JetStream, Key-Value Stores, Object Store, Services discovery, expanded authentication, and general UX. Completed milestones are condensed to one line each — the code and its own comments/tests are the source of truth for how they work now. Full detail is kept only for milestones that aren't done yet, so there's enough context to actually pick them up later.

This app depends on the official mainline `dart_nats` package (`^1.4.0`), including several fixes contributed upstream by this project (see Milestones 18, 26, and 30 below).

---

## Progress Overview

- [x] **M0**: Migrated off a custom fork to mainline `dart_nats`.
- [x] **M1**: JetStream Stream & Consumer Monitor — browse, create/delete/purge streams and consumers, publish into a stream, Ack/Nak/Term on a tailed consumer.
- [x] **M2**: Key-Value (KV) Store Inspector — bucket/key CRUD, live watch, optimistic-concurrency edits.
- [x] **M3**: Testing & release cleanup — CI, test coverage, Windows/Linux/Web platform verification. *macOS has never been functionally verified — compiles in CI but no Mac has been available to run it.*
- [x] **M4**: Expanded Authentication — username/password, token, NKey seed, `.creds` file.
- [x] **M5**: Update Notifications — checks GitHub Releases on startup, opt-out toggle.
- [x] **M6**: Live Message List UX — Filter/Find on JetStream Browse Messages, scroll-stable inserts on both message lists, Pause/Resume.
- [x] **M7**: Object Store Inspector — bucket/object CRUD, chunked upload/download with digest verification.
- [x] **M8**: Message Headers on Send.
- [x] **M9**: Queue Group Subscriptions.
- [x] **M10**: JetStream Account Info Panel.
- [x] **M11**: Subscription Manager & per-subscription color indicators (chip row replacing the old comma-delimited Subjects field).
- [x] **M12**: Connection Host/Port History — remembers up to 10 previously-successful targets.
- [x] **M13** *(won't do)*: Message Direction Indicator (incoming vs. outgoing). Dropped 2026-07-22 — user no longer interested.
- [x] **M14** *(won't do)*: Request/Reply Correlation Improvements. Dropped 2026-07-22 — user no longer interested.
- [ ] **M15**: Windows distribution via Microsoft Store (free MSIX signing) + unsigned GitHub Releases. Not started — decided 2026-07-18. *(Linux/Snap Store distribution and macOS code signing dropped 2026-07-22 — Snap Store no longer wanted, macOS cost prohibitive.)*
- [x] **M16**: Material 3 standards — OS dynamic color, `FilledButton`/`IconButton` variants.
- [ ] **M17**: NATS Server Monitoring Dashboard. Not started — see below.
- [x] **M18**: NATS Micro-services (Services API) Discovery.
- [x] **M19**: Multi-Select + Clipboard Copy.
- [x] **M20** *(won't do)*: Per-Subscription Message Rate Sparkline. Dropped 2026-07-19 — user no longer interested.
- [x] **M21**: Message Detail Headers Table + Raw Copy.
- [x] **M22**: Export & Replay Captured Messages to/from File.
- [x] **M23**: Reconnect-Buffer Overflow Handling (`maxReconnectBuffer`).
- [x] **M24**: Heartbeat Ping/Pong for Faster Dead-Connection Detection.
- [x] **M25**: Quick-Subscribe to Exact Subject from Message Row — a "Subscribe to This Subject" entry in the Live Messages row menu (`_buildRowMenuItems`/`_handleRowMenuSelection` in `lib/main.dart`) calls a new `_subscribeToExactSubject()`, which goes through the existing `_addSubscription()` live-subscribe path with the row's literal `message.subject` and no queue group, leaving any wider subscription that delivered the row untouched and surfacing a SnackBar noting the possible double-delivery; the menu entry itself is hidden once an exact subscription for that subject already exists.
- [x] **M26**: Adopted `dart_nats` JetStream/KV Bug Fixes (upstream PR #45; app now depends on the resulting `dart_nats` 1.2.2 release).
- [x] **Connect via Ctrl+Enter** *(small standalone addition, not numbered)*: fires Connect while focus is in the Host, Port, or Subjects field.
- [x] **M27**: Stream Edit + richer `StreamConfig` exposure — `StreamConfigDialog` (renamed from `CreateStreamDialog`) now doubles as an Edit form, pre-filled via a new `JetStreamManager.streamDetail()` that reads the fields `StreamInfo.fromJson` drops off the raw JSON (same pattern as M29's `consumerDetail()`/`bucketStatus()`), and exposes storage/retention/discard policy, size/count limits, and the allow-rollup/deny-delete/deny-purge flags at both create and edit time; edit submits via a new `JetStreamManager.updateStream()`, with any server-side rejection (e.g. an in-place storage-type change) surfacing through the existing error-SnackBar path rather than being pre-guessed client-side.
- [x] **M28**: Hex/Binary Payload View — Text/Hex toggle in Message Detail's Payload section, auto-selecting Hex whenever the payload isn't valid UTF-8.
- [x] **M29**: KV Bucket Info + Consumer Detail Depth — `KvManager.bucketStatus()` and `JetStreamManager.consumerDetail()` issue the same raw `$JS.API.STREAM.INFO`/`$JS.API.CONSUMER.INFO` requests `dart_nats` 1.2.3 makes internally and read TTL/replicas and ack-wait/max-deliver/max-ack-pending off the JSON directly, since the package's own typed classes don't parse those fields even though the server always sends them; Bucket Info dialog and a refreshable Consumer Detail dialog surface them.
- [x] **M30**: Upstream-First `dart_nats` Round — consumer pause/resume (`dart_nats` 1.3.0), filtered/keep/seq stream purge, and Object Store streaming put/get + chunk-orphan cleanup on overwrite (`dart_nats` 1.4.0), all merged and released directly by this project's owner via `dart-nats/dart-nats`'s own GitHub Actions CI/pub.dev pipeline. Scoped to the package-level fix only, per the milestone's own original scoping — app-side adoption (dependency bump + UI) is separate future work; see Parked Notes below.
- [x] **M31**: Reconnect State Restoration (remaining half) — a `reconnectSignal` fired only on a real post-bounce reconnect (not the existing blip-tolerance) lets Browse Messages/Tail auto-retry out of a stuck error state and KV auto-refresh its selected bucket's keys/watch; healthy listings still use explicit Refresh, and an explicit Disconnect still fully resets everything.
- [x] **M32**: Screenshot Border/Drop-Shadow Polish — subtle hairline border + soft drop shadow added to `Format-Screenshot`, all six `images/*.png` reprocessed.
- [x] **Row Right-Click Context Menu** *(small standalone addition, not numbered)*: right-clicking a row — on the Live Messages tab, JetStream Browse Messages, JetStream Consumer Tail, or KV Store keys — opens the same action menu as that row's trailing overflow (⋮) button, anchored at the click point instead of the row's trailing edge.
- [x] **M33**: `dart_nats` 1.4.0 Adoption — Consumer Pause/Resume + Filtered Purge — app-side follow-up to M30's package-level-only scope. Bumped the dependency to `^1.4.0`; added `JetStreamManager.pauseConsumer()`/`resumeConsumer()` with a Pause/Resume action + duration prompt (`jetstream_pause_dialog.dart`) on Consumer Detail; extended `JetStreamManager.purgeStream()`/the Purge dialog (`jetstream_purge_dialog.dart`) with `filter`/`keep`/`seq` options (defaulting to the original all-or-nothing behavior). Object Store streaming (`putStream()`/`getStream()`) deliberately **not** adopted — the real memory cost starts one layer up in `file_picker`'s eager buffering, so switching just the manager would add complexity for no actual benefit (see the code comment on `largeObjectTransferWarningThreshold` in `object_store_manager.dart`); the chunk-orphan-on-overwrite fix is still gained for free from the dependency bump alone. Live-server verification (real `nats-server` 2.14.3) caught a genuine `dart_nats` parsing gap: the server nests a paused consumer's `pause_until` inside `config`, not at the response's top level where `ConsumerInfo.fromJson` looks for it, so `info.paused` reads correctly but `info.pauseUntil` is always `null` — worked around with the same raw-JSON-bypass pattern `consumerDetail()` already used for `ack_wait`/`max_deliver`/`max_ack_pending` (worth fixing upstream in `dart-nats` too, but out of scope for this app-side release).

---

## Milestone 15: Windows Store Distribution (Low Priority)

### Objective
Windows builds are currently unsigned: users hit "Unknown Publisher"/SmartScreen warnings. **Decision made 2026-07-18, scope narrowed 2026-07-22**: publish a signed build via the **Microsoft Store** (Microsoft signs the MSIX for free as part of Store certification, sidestepping SignPath/Azure Artifact Signing entirely) while **keeping the existing GitHub Releases EXE/ZIP unsigned** on purpose, for now — no code-signing cert spend for that path.

Linux Snap Store distribution and macOS code signing were both dropped 2026-07-22 (Snap Store no longer wanted; macOS cost prohibitive) — see the Dropped/Won't-Do section below for the record of what was scoped out.

### Findings
- Individual **and** company Microsoft Store developer registration is free as of a late-2025/2026 policy change (the old ~$19/~$99 one-time fees are gone).
- MSIX packages distributed through the Store are **signed by Microsoft for free** as part of certification — no SignPath Foundation application or Azure Artifact Signing subscription needed for that distribution channel.
- This only covers the Store-distributed MSIX. The GitHub Releases EXE/ZIP is a separate artifact and stays unsigned deliberately (SmartScreen warning included) — this is the accepted tradeoff, not a gap to close later.

### Automating Microsoft Store submission via GitHub Actions
- Package the Windows build as MSIX using the [`msix`](https://pub.dev/packages/msix) pub package (a `msix_config:` block in `pubspec.yaml`, then `dart run msix:create` against the `flutter build windows` output) — this is the standard way Flutter Windows apps produce a Store-ready package.
- Use Microsoft's [`msstore-cli`](https://github.com/microsoft/msstore-cli) (Microsoft Store Developer CLI) in the workflow — install via the `setup-msstore-cli` GitHub Action, authenticate with stored Partner Center credentials (Azure AD app registration: tenant ID/client ID/client secret as repo secrets), then `msstore package .` + `msstore publish` to build and submit. This is the actively-maintained tool; the older `StoreBroker` PowerShell module is Microsoft's legacy equivalent, prefer `msstore-cli`.
- One-time manual prerequisite: the app must already exist in Partner Center with at least one completed submission (store listing, screenshots, age rating, privacy policy) and `msstore init` run once in the repo — after that, version-bump submissions on tagged releases can run unattended, added as a new job in `.github/workflows/build.yml` alongside the existing `build-windows-x64`/`build-windows-arm64` jobs.

### Implementation Checklist
- [ ] Set up a free Microsoft Store developer account; complete the one-time manual Partner Center listing pass (screenshots, listing details, age rating, privacy policy).
- [x] Add the `msix` pub package + `msix_config:` to `pubspec.yaml`.
- [ ] Add a GH Actions job (using `setup-msstore-cli` + `msstore package`/`msstore publish`) that packages and submits the Store build on tagged releases, gated behind repo secrets so it's a no-op on forks/PRs without them.
- [ ] Leave the existing Windows EXE/ZIP GitHub Release artifact unsigned, as decided.
- [x] Skip the GitHub Releases update check on Store-managed installs — `update_checker.dart`'s `isStoreManagedInstall()` detects an MSIX install (Windows, via a `...\WindowsApps\...` executable path) or a Snap-confined runtime (via the `SNAP` env var, left over from before Snap Store distribution was dropped — harmless to keep) and `main.dart` skips `checkForUpdates()` for either; only the direct-download exe/zip self-checks GitHub.
- [ ] Document the publishing/signing setup (which secrets, how to rotate/renew) in `AGENTS.md` or a new doc.

---

## Milestone 17: NATS Server Monitoring Dashboard (Medium Priority)

### Objective
Every other tab in this app monitors things *through* the NATS protocol (streams, buckets, subscriptions) — nothing surfaces information *about* the server process itself. A real `nats-server` exposes a separate read-only HTTP monitoring API (default port `8222`, distinct from the NATS protocol port) with connection counts, memory/CPU, slow-consumer warnings, and cluster route health. Right now diagnosing "is the server under load" or "am I about to get disconnected as a slow consumer" means leaving this app for a browser tab or `nats-server`'s own `nats-top`.

### What's actually available (server-side HTTP API, not `dart_nats`)
Goes through the `http` package already added for Milestone 5, not the NATS client connection. Endpoints (all `GET`, unauthenticated by default unless the operator locked them down): `/varz` (general stats), `/connz` (per-connection detail, paginated via `?offset=`/`?limit=`), `/subz` (subscription interest graph), `/routez`/`/gatewayz`/`/leafz` (cluster topology), `/healthz`. Monitoring must be explicitly enabled server-side (`http_port`/`-m 8222`) — not every server has it on, so this needs a clear "monitoring unavailable" state, not an assumed-reachable one.

### UI Architecture & Concept
New tab (`[📊 Server Monitor]`) or a panel reachable from a toolbar icon, gated behind an opt-in "Enable Server Monitoring" setting (default **off**, unlike JetStream/KV/Object Store — this hits a different host:port than the NATS connection itself) with its own configurable monitoring port field (defaulting to `8222`, prefilled from the connection's host). Dashboard shows: server identity/uptime/version card, live-polled connection count & in/out throughput, a slow-consumer warning banner, and (if the JetStream tab is enabled) cross-links to the existing JetStream Account Info dialog rather than duplicating that data.

### Implementation Checklist
- [ ] `lib/server_monitor.dart` (new) — pure HTTP client wrapper (`fetchVarz()`, `fetchConnz()`, injectable `http.Client` for tests, matching `lib/update_checker.dart`'s pattern) parsing `/varz` and `/connz` JSON into typed models.
- [ ] New opt-in setting (`prefServerMonitoringEnabled`/default `false`) plus a monitoring-port field.
- [ ] `lib/server_monitor_dashboard.dart` — new tab/panel: identity card, live-polled connection/throughput stats, slow-consumer warning, graceful "monitoring not reachable" state distinct from "monitoring disabled".
- [ ] Decide polling interval and whether `/connz` (potentially large on a busy server) is paginated in the UI.
- [ ] Unit tests for JSON parsing (mocked `http.Client`) + widget tests against a fake monitor client; live-server verification against a real `nats-server -m 8222`, including the "monitoring not enabled" path.
- [ ] Document in `assets/app_help.md`: what monitoring is, how to enable it server-side, and that it's a separate, unauthenticated-by-default HTTP endpoint (a real security consideration, not just a feature note).

---

## Dropped / Won't-Do Milestones

Kept as a one-line record of ideas that were scoped out, not to be picked up.

- **M13 — Message Direction Indicator** *(dropped 2026-07-22)*: would have tracked locally-sent Live Messages as first-class list entries (not dependent on loopback subscription) and added a visual outgoing/incoming indicator per row. User no longer interested.
- **M14 — Request/Reply Correlation Improvements** *(dropped 2026-07-22)*: would have added a dedicated "Request" send mode using `dart_nats`'s `client.request()`/`requestString()` (or improved correlation for the plain pub/sub "Reply To" flow), with paired-row linking and timeout/failure UX. User no longer interested.
- **M15's Linux/Snap Store scope** *(dropped 2026-07-22)*: would have published to the Snap Store via `snapcraft.yaml` + `snapcore/action-build`/`action-publish` on tagged releases. User no longer interested in Snap Store distribution.
- **M15's macOS code signing** *(dropped 2026-07-22)*: would have pursued Apple Developer Program signing ($99/yr, no free path). Cost prohibitive; also still tied to Milestone 3's macOS-never-verified gap (no Mac available to test on).
- **M20 — Per-Subscription Message Rate Sparkline** *(dropped 2026-07-19)*: would have added a small rolling messages/sec indicator per subscription (e.g. next to its chip), using Milestone 11's existing `sid` tagging. User no longer interested.

---

## Parked Notes (not milestones of their own)

Small, standalone ideas noted in passing during other milestones' work — kept here for later rather than expanded into full milestone sections.

- JetStream Browse/Tail rows show only the stream sequence chip, no arrival timestamp — Live Messages already has one (Settings' "Show Message Timestamps"); extending it to these two views is a small follow-up, distinct from Milestone 28's hex/binary payload view.
- KV snapshot↔watch gap: `KvDashboard` lists keys, *then* starts the watch — a put/delete landing in that narrow window can be missed until a manual Refresh. This is a permanent library-semantics limitation (`watch()` has no "resume from last-seen" option) that exists on every `_loadKeys` call, not just around a reconnect — Milestone 31's reconnect-triggered re-snapshot narrows the specific *reconnect-gap* version of this race but doesn't (and can't, app-side) close the general one.
- Offline (no-publish) browsing of a previously-exported NDJSON file — loading a file into the message list read-only, no live server needed, nothing sent. Distinct from the existing file-based Replay (which requires a connection and actually publishes); noted as a possible future addition if the need comes up.
- Object Store streaming (`ObjectStore.putStream()`/`getStream()`, `dart_nats` 1.4.0): still not adopted app-side, by deliberate decision (see M33) — would only pay off alongside a separate rework of `object_store_dashboard.dart`'s `pickUploadFile`/`saveDownloadedFile` to stream from disk instead of eagerly buffering, which is a bigger, riskier change than fits a small release.
- The `dart_nats` `ConsumerInfo.fromJson` bug M33 found and worked around app-side (`pause_until` nested under `config` in the real server's `$JS.API.CONSUMER.INFO` response, not top-level where the package looks for it) is worth fixing upstream in `dart-nats` directly, same as the KV ttl/replicas and account-info `tier` bugs before it — not done yet, no upstream issue/PR opened.
