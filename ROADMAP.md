# NATS Client UI — Feature Expansion Roadmap (`ROADMAP.md`)

This living roadmap tracks feature milestones for the **NATS Client UI**, covering JetStream, Key-Value Stores, Object Store, Services discovery, expanded authentication, and general UX. Completed milestones are condensed to one line each — the code and its own comments/tests are the source of truth for how they work now. Full detail is kept only for milestones that aren't done yet, so there's enough context to actually pick them up later.

This app depends on the official mainline `dart_nats` package (`^1.2.2`), including several fixes contributed upstream by this project (see Milestones 18 and 26 below).

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
- [ ] **M13** *(optional — may never be picked up)*: Message Direction Indicator (incoming vs. outgoing). Not started.
- [ ] **M14**: Request/Reply Correlation Improvements. Not started — see below.
- [ ] **M15** *(optional, cost-gated)*: Windows distribution via Microsoft Store (free MSIX signing) + unsigned GitHub Releases; Linux distribution via Snap Store; macOS code signing still decision-pending. Not started — Windows/Linux approach decided 2026-07-18, implementation not begun.
- [x] **M16**: Material 3 standards — OS dynamic color, `FilledButton`/`IconButton` variants.
- [ ] **M17**: NATS Server Monitoring Dashboard. Not started — see below.
- [x] **M18**: NATS Micro-services (Services API) Discovery.
- [x] **M19**: Multi-Select + Clipboard Copy.
- [ ] **M20** *(tentative — user flagged as a "maybe")*: Per-Subscription Message Rate Sparkline. Not started — see below.
- [x] **M21**: Message Detail Headers Table + Raw Copy.
- [x] **M22**: Export & Replay Captured Messages to/from File.
- [x] **M23**: Reconnect-Buffer Overflow Handling (`maxReconnectBuffer`).
- [x] **M24**: Heartbeat Ping/Pong for Faster Dead-Connection Detection.
- [ ] **M25**: Quick-Subscribe to Exact Subject from Message Row. Not started — see below.
- [x] **M26**: Adopted `dart_nats` JetStream/KV Bug Fixes (upstream PR #45; app now depends on the resulting `dart_nats` 1.2.2 release).
- [x] **Connect via Ctrl+Enter** *(small standalone addition, not numbered)*: fires Connect while focus is in the Host, Port, or Subjects field.
- [x] **M27**: Stream Edit + richer `StreamConfig` exposure — `StreamConfigDialog` (renamed from `CreateStreamDialog`) now doubles as an Edit form, pre-filled via a new `JetStreamManager.streamDetail()` that reads the fields `StreamInfo.fromJson` drops off the raw JSON (same pattern as M29's `consumerDetail()`/`bucketStatus()`), and exposes storage/retention/discard policy, size/count limits, and the allow-rollup/deny-delete/deny-purge flags at both create and edit time; edit submits via a new `JetStreamManager.updateStream()`, with any server-side rejection (e.g. an in-place storage-type change) surfacing through the existing error-SnackBar path rather than being pre-guessed client-side.
- [x] **M28**: Hex/Binary Payload View — Text/Hex toggle in Message Detail's Payload section, auto-selecting Hex whenever the payload isn't valid UTF-8.
- [x] **M29**: KV Bucket Info + Consumer Detail Depth — `KvManager.bucketStatus()` and `JetStreamManager.consumerDetail()` issue the same raw `$JS.API.STREAM.INFO`/`$JS.API.CONSUMER.INFO` requests `dart_nats` 1.2.3 makes internally and read TTL/replicas and ack-wait/max-deliver/max-ack-pending off the JSON directly, since the package's own typed classes don't parse those fields even though the server always sends them; Bucket Info dialog and a refreshable Consumer Detail dialog surface them.
- [ ] **M30**: Upstream-First `dart_nats` Round (consumer pause/resume, filtered stream purge, Object Store streaming). Not started — see below.
- [x] **M31**: Reconnect State Restoration (remaining half) — a `reconnectSignal` fired only on a real post-bounce reconnect (not the existing blip-tolerance) lets Browse Messages/Tail auto-retry out of a stuck error state and KV auto-refresh its selected bucket's keys/watch; healthy listings still use explicit Refresh, and an explicit Disconnect still fully resets everything.
- [x] **M32**: Screenshot Border/Drop-Shadow Polish — subtle hairline border + soft drop shadow added to `Format-Screenshot`, all six `images/*.png` reprocessed.
- [x] **Row Right-Click Context Menu** *(small standalone addition, not numbered)*: right-clicking a row — on the Live Messages tab, JetStream Browse Messages, JetStream Consumer Tail, or KV Store keys — opens the same action menu as that row's trailing overflow (⋮) button, anchored at the click point instead of the row's trailing edge.

---

## Milestone 13: Message Direction Indicator (Incoming vs. Outgoing) (Low/Medium Priority, Optional)

### Objective
**Optional follow-up** — flagged by the user as something they may never get to; not on any particular timeline, and fine to stay `[ ]` indefinitely. Revisit only if it becomes an active want.

On the Live Messages tab, a sent (published) message currently doesn't appear in the message list at all unless the client also happens to be subscribed back to that exact subject (loopback) — `sendMessage()` (`lib/main.dart`) calls `natsClient.pubString()` / `JetStreamManager.publish()` directly and never adds an entry to `items` itself. That makes "did I send this or receive this" hard to track even on subjects where both directions are visible today. This milestone adds: (1) tracking locally-sent messages as first-class list entries regardless of loopback subscription, and (2) a small visual indicator on each row distinguishing outgoing from incoming.

**JetStream note**: `lib/jetstream_message_view.dart`'s Browse Messages / Tail views have no send affordance of their own. Publishing into a stream only happens through the Live Messages tab's Send dialog via its "get delivery ack" (JetStream) toggle. So there is currently nothing to mark "outgoing" inside Browse Messages itself — this indicator applies to the Live Messages tab.

### Implementation Checklist
- [ ] Track locally-published messages from `sendMessage()` as list entries tagged outgoing, inserted through the same scroll-stability path (`_insertMessages`) used for incoming arrivals — not dependent on loopback subscription.
- [ ] Add a direction indicator to each Live Messages row (visual TBD — directional icon, color-coded row accent, or a text badge).
- [ ] Confirm Filter/Find and the direction indicator compose cleanly.
- [ ] Unit/widget tests for direction tagging + rendering; live-server `integration_test` verification.

---

## Milestone 14: Request/Reply Correlation Improvements (Medium Priority)

### Objective
Ranked by a recent feature-gap survey as the single biggest daily-use gap in the app — the closest thing to a `nats req` equivalent. Today, "Reply To" only pre-fills the Send dialog's subject field with the original message's `replyTo` subject — it's an ordinary publish with no automatic pairing. True NATS request/reply (a private per-request inbox subject, awaited for a single correlated response) isn't used anywhere in the app today, so a real request/reply round trip wouldn't even show up in the message list (the app isn't subscribed to the inbox subject it would use).

### What `dart_nats` actually offers (verified present in 1.2.2's `client.dart`)
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

## Milestone 15: Windows Store + Snap Store Distribution, macOS Code Signing (Low Priority, cost-gated, Optional)

### Objective
**Optional follow-up** — flagged by the user as something they may never get to. Windows and macOS builds are currently unsigned: users hit "Unknown Publisher"/SmartScreen warnings on Windows and Gatekeeper "unidentified developer" blocks on macOS. Linux has no equivalent OS-level gate, but has no store presence either — direct-download ZIP only today.

**Decision made 2026-07-18**: pursue dual distribution for Windows — publish a signed build via the **Microsoft Store** (Microsoft signs the MSIX for free as part of Store certification, sidestepping SignPath/Azure Artifact Signing entirely) while **keeping the existing GitHub Releases EXE/ZIP unsigned** on purpose, for now — no code-signing cert spend for that path. Also publish to the **Snap Store** for Linux, fully automated the same way. macOS remains undecided/deferred (still cost-gated).

### Findings — Windows
- Individual **and** company Microsoft Store developer registration is free as of a late-2025/2026 policy change (the old ~$19/~$99 one-time fees are gone).
- MSIX packages distributed through the Store are **signed by Microsoft for free** as part of certification — no SignPath Foundation application or Azure Artifact Signing subscription needed for that distribution channel.
- This only covers the Store-distributed MSIX. The GitHub Releases EXE/ZIP is a separate artifact and stays unsigned deliberately (SmartScreen warning included) — this is the accepted tradeoff, not a gap to close later.

### Automating Microsoft Store submission via GitHub Actions
- Package the Windows build as MSIX using the [`msix`](https://pub.dev/packages/msix) pub package (a `msix_config:` block in `pubspec.yaml`, then `dart run msix:create` against the `flutter build windows` output) — this is the standard way Flutter Windows apps produce a Store-ready package.
- Use Microsoft's [`msstore-cli`](https://github.com/microsoft/msstore-cli) (Microsoft Store Developer CLI) in the workflow — install via the `setup-msstore-cli` GitHub Action, authenticate with stored Partner Center credentials (Azure AD app registration: tenant ID/client ID/client secret as repo secrets), then `msstore package .` + `msstore publish` to build and submit. This is the actively-maintained tool; the older `StoreBroker` PowerShell module is Microsoft's legacy equivalent, prefer `msstore-cli`.
- One-time manual prerequisite: the app must already exist in Partner Center with at least one completed submission (store listing, screenshots, age rating, privacy policy) and `msstore init` run once in the repo — after that, version-bump submissions on tagged releases can run unattended, added as a new job in `.github/workflows/build.yml` alongside the existing `build-windows-x64`/`build-windows-arm64` jobs.

### Automating Snap Store submission via GitHub Actions
- **Decision made 2026-07-18**: publish to the **Snap Store** for Linux — it was evaluated against Flathub and chosen for being the closer analog to the Windows Store flow above: no manual review gate on updates after one-time publisher setup, so it's fully "tag a release, it ships," same shape as this repo's other build jobs. (Flathub, by comparison, gates every update behind at least a bot-opened PR merge — considered and passed over for that reason.)
- Add a `snapcraft.yaml` (this app has none today) wrapping the existing `flutter build linux --release` bundle (`build/linux/x64/release/bundle`) as the snap's payload.
- Use [`snapcore/action-build`](https://github.com/snapcore/action-build) to build the `.snap` from that `snapcraft.yaml`, then [`snapcore/action-publish`](https://github.com/snapcore/action-publish) to push it to the Store's `stable` (or a staged `edge`/`beta`) channel — authenticated via a `snapcraft export-login` token generated once locally and stored as a repo secret.
- One-time manual prerequisite: register the snap name on the Snap Store (`snapcraft register`) and complete the store listing (description, icon, screenshots) — after that, `action-build` + `action-publish` on tagged releases needs no further manual review step.

### Implementation Checklist
- [ ] Set up a free Microsoft Store developer account; complete the one-time manual Partner Center listing pass (screenshots, listing details, age rating, privacy policy).
- [ ] Add the `msix` pub package + `msix_config:` to `pubspec.yaml`.
- [ ] Add a GH Actions job (using `setup-msstore-cli` + `msstore package`/`msstore publish`) that packages and submits the Store build on tagged releases, gated behind repo secrets so it's a no-op on forks/PRs without them.
- [ ] Leave the existing Windows EXE/ZIP GitHub Release artifact unsigned, as decided.
- [ ] Register the snap name on the Snap Store and complete its one-time store listing.
- [ ] Add `snapcraft.yaml` packaging the `flutter build linux` bundle.
- [ ] Add a GH Actions job (`snapcore/action-build` + `snapcore/action-publish`, `snapcraft export-login` token as a repo secret) that builds and publishes the snap on tagged releases, gated behind repo secrets so it's a no-op on forks/PRs without them.
- [ ] Decide macOS signing (Apple Developer Program, $99/yr, no free path) separately — still open, still tied to Milestone 3's existing macOS-never-verified gap (no Mac available to test on).
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

## Milestone 20: Per-Subscription Message Rate Sparkline (Low Priority, tentative)

### Objective
Milestone 11 already tags every message with its originating subscription's color via `sid`. This milestone would add a small rolling messages/sec indicator per subscription (e.g. next to its chip) so a noisy or unexpectedly quiet subject is visible at a glance instead of only inferable by watching the list scroll. **Flagged by the user as a "maybe"** — lowest-confidence item of this batch, worth a lighter design pass before committing to implementation.

### Implementation Checklist
- [ ] Decide visual treatment (tiny sparkline, a rate number, a pulsing dot) and where it lives (in the chip itself vs. only in the Subscription Manager dialog).
- [ ] Compute a rolling rate per `sid` from existing arrival timestamps — no new `dart_nats` data needed, this is purely a local aggregation over what's already tagged.
- [ ] If implemented inside the chip row itself, confirm it doesn't reintroduce the offstage-measurement/`OverflowBox`/`Tooltip` pitfalls that `subject_chips_row.dart`'s own doc comments describe from building its overflow-collapse logic.
- [ ] Unit tests for the rate computation (fake clock) + widget/live-server verification that the displayed rate roughly tracks a known publish rate from a second test client.

---

## Milestone 25: Quick-Subscribe to Exact Subject from Message Row (Low/Medium Priority)

### Objective
A common exploration pattern: the user subscribes to a wide wildcard subject (e.g. `orders.>`) because they don't yet know the exact subject taxonomy, then wants to narrow down to just one or two specific subjects they've spotted going by. Today that means opening the Subscription Manager dialog and typing the exact subject out by hand. This milestone adds a shortcut directly on a Live Messages row — "Subscribe to this exact subject" — that adds `message.subject` as its own new subscription via the existing add-subscription path, with the user then free to remove the original wildcard chip to shrink down to just what they care about, live, with no reconnect.

This is a complement to the existing Filter box, not a replacement: Filter narrows what's already been received and rendered (client-side only); this feature narrows what the app actually subscribes to and receives from the server in the first place.

### Desired Behavior
- New row-menu entry (e.g. "Subscribe to This Subject"), using the row's literal `message.subject` — not a pattern/wildcard guess.
- Adding it goes through the same live-subscribe path Milestone 11 already built, so it takes effect without needing to reconnect or open the full manager dialog.
- No auto-removal of the wider subscription that originally delivered the message — surface a brief SnackBar noting the new subscription was added and that the existing wildcard subscription still applies, rather than let duplicate delivery look like a bug.
- Disabled/hidden for a row whose subject is already covered by an existing *exact* subscription.

### Implementation Checklist
- [ ] Add the row-menu entry in `lib/main.dart`'s message popup menu, reusing `_addSubscription`/`SubscriptionInfo` with the row's exact subject and no queue group.
- [ ] Surface the "you may now receive this subject twice until you remove the wildcard" caveat.
- [ ] Guard against adding a literal duplicate of a subject that's already its own exact subscription.
- [ ] Unit/widget test coverage plus a live-server verification pass: subscribe wide, receive a message, use the shortcut, confirm the new exact subscription is active server-side, then remove the wildcard chip and confirm delivery continues uninterrupted for the exact subject.

---

## Milestone 30: Upstream-First `dart_nats` Round (Medium Priority)

### Objective
Three real feature gaps are blocked at the `dart_nats` package level, not by anything this app can work around locally. This project has direct contributor access to `chartchuo/dart-nats` (established via PR #45) — use it again rather than waiting on someone else to add these.

### What's blocked
- **Consumer pause/resume** (NATS 2.11): no `$JS.API.CONSUMER.PAUSE` call anywhere in the package (verified against 1.2.2's `jetstream.dart`) — would need a new method added upstream before this app can expose it.
- **Filtered/keep/sequence-bounded stream purge**: `JsStream.purge()` sends an empty request body today — the server-side `filter`/`keep`/`seq` purge options aren't modeled at all, so this app's Purge is necessarily all-or-nothing.
- **Object Store streaming + chunk-orphan cleanup**: both directions buffer the whole object in memory with no streaming option, and overwriting an existing object leaves its previous chunks orphaned server-side rather than purging them.

### Implementation Checklist
- [ ] Add pause/resume support to `ConsumerConfig`/a new `JetStream` method, following PR #45's pattern (branch on `chartchuo/dart-nats`, verify against the package's own test suite, cross-check the published pub.dev artifact before cutting over).
- [ ] Add filter/keep/seq parameters to `JsStream.purge()`.
- [ ] Add a streaming upload/download path to `ObjectStore` (or at least chunk-by-chunk callback support) and purge the previous object's chunks on overwrite.
- [ ] Once merged/published, app-side UI follow-up is separate future work — this milestone is scoped to the package-level fix only.

---

## Parked Notes (not milestones of their own)

Small, standalone ideas noted in passing during other milestones' work — kept here for later rather than expanded into full milestone sections.

- JetStream Browse/Tail rows show only the stream sequence chip, no arrival timestamp — Live Messages already has one (Settings' "Show Message Timestamps"); extending it to these two views is a small follow-up, distinct from Milestone 28's hex/binary payload view.
- KV snapshot↔watch gap: `KvDashboard` lists keys, *then* starts the watch — a put/delete landing in that narrow window can be missed until a manual Refresh. This is a permanent library-semantics limitation (`watch()` has no "resume from last-seen" option) that exists on every `_loadKeys` call, not just around a reconnect — Milestone 31's reconnect-triggered re-snapshot narrows the specific *reconnect-gap* version of this race but doesn't (and can't, app-side) close the general one.
- Offline (no-publish) browsing of a previously-exported NDJSON file — loading a file into the message list read-only, no live server needed, nothing sent. Distinct from the existing file-based Replay (which requires a connection and actually publishes); noted as a possible future addition if the need comes up.
