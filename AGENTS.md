# Agentic Development Guide (`AGENTS.md`)

Welcome! This document is a living, context-bootstrapping architectural and operational guide designed for **AI Development Agents** (such as Gemini CLI, GitHub Copilot, Cursor, Cline, Windsurf, Sweep, etc.) and human contributors. It provides an immediate, dense, and high-fidelity mapping of the **NATS Client UI** workspace, its architectural patterns, development workflows, and guardrails.

---

## 1. System & Project Overview

**NATS Client UI** is a cross-platform desktop & web application written in Flutter. It provides a visual, real-time message stream monitor, subscriber, and publisher for NATS server message brokers.

### Core Capabilities
- **Multi-Scheme Connection**: Connect to a single NATS server using plain TCP sockets (`nats://`) or WebSockets (`ws://`).
- **Platform Limitations**: 
  - Desktop clients (Windows, macOS, Linux) support both `nats://` (TCP) and `ws://` (WebSocket) schemes.
  - The Web client (running in browsers/Docker) **only** supports the `ws://` scheme due to browser-level TCP socket restrictions.
- **TLS & Mutual TLS**: Custom TLS authentication support using PEM-formatted trusted CA certificates, client certificate chains, and private keys.
- **Real-Time Stream**: Subscribe to multiple comma-separated subjects (supporting wildcards like `*` and `>`), filter incoming payloads in real-time, search and highlight text with regex, and send/publish custom messages.
- **Connection History**: the Host field (`lib/main.dart`) is an editable `Autocomplete` backed by `lib/connection_history.dart` — its dropdown offers up to 10 previously-*successfully*-connected `scheme://host:port` targets (most-recent-first, deduplicated by target), filtering as you type; selecting one fills scheme, host, and port together. Per-entry delete and a "Clear history" action live in the same dropdown. Recorded only on `Status.connected`, not on every connect attempt, so failed/typo'd attempts never pollute the list.
- **Per-Subscription Color Indicators**: each subscription is auto-assigned a color, shown as a chip accent (toolbar chip row + Subscription Manager dialog) and a Live Messages row accent bar, toggleable via the "Show Subscription Colors" setting (on by default). The toggle only gates rendering — `SubscriptionInfo.colorIndex` assignment is untouched — so turning it off and back on restores each subscription's original color. When off, no layout space is reserved for the hidden color (`ColorTabChip.color` is nullable and skips its tab entirely; the message row's accent bar is conditionally omitted, not just painted transparent).
- **JetStream Dashboard** (`lib/jetstream_*.dart`, toggleable via the "Enable JetStream" setting): monitor streams and consumers, create/purge/delete streams, create/delete consumers (push or pull, any ack policy), browse a stream's messages live, tail a specific consumer with Ack/Nak/Term actions, and publish with JetStream delivery acknowledgement from the regular Send Message dialog.
- **Key-Value Stores Dashboard** (`lib/kv_*.dart`, toggleable via the "Enable Key-Value Stores" setting): monitor and manage KV buckets (backed by JetStream) — create/delete buckets, put/edit/delete/purge keys with optimistic-concurrency conflict detection on edit, per-key revision history, live search, and real-time updates via `KeyValue.watch()` (including changes made by other clients).
- **Object Store Dashboard** (`lib/object_store_*.dart`, toggleable via the "Enable Object Store" setting): monitor and manage Object Store buckets (also backed by JetStream) — create/delete buckets, upload/download/delete objects (blobs), live search. Object Store is an `EXPERIMENTAL` API in the underlying `dart_nats` package, and has no `watch()` equivalent (unlike KV), so the object list needs an explicit Refresh rather than updating live.
- **Services Dashboard** (`lib/service_discovery_*.dart`, toggleable via the "Enable Service Discovery" setting, **off by default** unlike the other three): discovers NATS Microservices (ADR-32 `$SRV.*` convention) currently running on the account — Discover fans a request out and collects replies for a bounded window, selecting a result shows its endpoints and per-endpoint request/error/latency stats. Read-only/discovery-only; this app doesn't host services itself. Relies on `discoverServices()`/`getServicesInfo()`/`getServicesStats()`, which don't exist in mainline `dart_nats` — see the `dart_nats` dependency note below.
- **Data Syntax Highlighting**: Automatic pretty-printing and syntax highlighting of JSON payloads inside detailed message dialogs.
- **State & Size Persistence**: Remembers recent connection setups, theme preferences, and window size/position across runs.
- **Update Notifications** (`lib/update_checker.dart`, toggleable via the "Check for Updates" setting): checks GitHub Releases for this repo on startup and, if newer than the running version, shows a dismissible top-right popover linking to the release. No auto-download/install — this app only distributes via GitHub Releases.
- **Multi-Select + Clipboard Copy** (Live Messages tab): Shift+Click/Ctrl+Click/Ctrl+Shift+Up/Down select a range or disconnected set of rows; Ctrl+C or the row menu's "Copy Selected (N)" copies them as plain text, one `subject: payload` line per message.
- **Export & Replay** (`lib/message_export.dart`, `lib/replay_config_dialog.dart`, `lib/replay_banner.dart`, `lib/export_confirm_dialog.dart`): bulk-exports captured Live Messages to an NDJSON file (Selected or All, base64 payloads for lossless binary round-tripping, warn-and-proceed past `largeExportWarningThreshold`), and replays a previously exported file by publishing every message back onto the connected server with configurable message-interval/repeat-count/repeat-interval pacing, a live "will send N messages" preview, and a cancelable `ReplayBanner` that can coexist with the Pause banner.

---

## 2. Directory Map & Repository Structure

Below is the structured layout of the workspace, pointing you to relevant files depending on your task.

```
nats_client_flutter/
├── .github/workflows/
│   └── build.yml               # CI: `test` job (real nats:latest -js + Xvfb, runs test/ + integration_test/)
│                                #   gates every build/release job via `needs: test`, then multi-platform builds & Docker publishing
├── assets/
│   ├── app_help.md             # Standard application markdown help file loaded dynamically in-app
│   └── app_launcher_icon.svg   # Source SVG launcher icon (used to regenerate platform-native icons)
├── images/                     # App screenshots used in the main README.md
├── lib/                        # Core application source code
│   ├── color_tab_chip.dart     # Shared colored "bookmark tab" wrapper for a chip; `color` is nullable — null skips the tab/padding entirely (used when subscription colors are toggled off)
│   ├── connection_history.dart # `ConnectionHistoryEntry` model + encode/decode + `recordConnection()` (dedupe/cap at 10), backing the Host field's history dropdown
│   ├── constants.dart          # Connection state text, defaults, colors, and SharedPreferences keys
│   ├── export_confirm_dialog.dart # "Export Selected/All" confirmation dialog — real message count, warn-and-proceed past `largeExportWarningThreshold`
│   ├── format_utils.dart       # decodeMessageText(), formatCompactCount() ("1.1k"-style, Pause's buffered-count pill), formatGroupedCount() (exact comma-grouped counts), formatEstimatedDuration() — shared text-formatting helpers
│   ├── help_dialog.dart        # Stateless widget dialog that parses and displays assets/app_help.md
│   ├── highlight_theme.dart    # Theme configurations for the code highlighter
│   ├── jetstream_consumer_dialog.dart    # "Create Consumer" dialog (push/pull, ack/deliver policy)
│   ├── jetstream_consumer_tail_view.dart # Live tail of a named consumer with Ack/Nak/Term actions
│   ├── jetstream_dashboard.dart          # Stream/consumer monitor + mutations (JetStream tab's main widget)
│   ├── jetstream_manager.dart            # Thin, testable wrapper around client.jetStream() calls
│   ├── jetstream_message_view.dart       # Ephemeral ordered-consumer "Browse Messages" tail
│   ├── jetstream_stream_dialog.dart      # "Create Stream" dialog (name, subjects, max age, replicas)
│   ├── kv_bucket_dialog.dart    # "Create Bucket" dialog (name, history depth, TTL, replicas)
│   ├── kv_dashboard.dart        # Bucket/key monitor + mutations + live watch (Key-Value Stores tab's main widget)
│   ├── kv_manager.dart          # Thin, testable wrapper around client.jetStream()/KeyValue calls
│   ├── kv_put_dialog.dart       # "Put Value"/"Edit Value" dialog (locks Key + shows revision on edit)
│   ├── main.dart               # Main entry point, ThemeModel provider, and MyHomePage (core state machine)
│   ├── message_detail_dialog.dart # Dialog widget for inspecting subject, headers, and pretty JSON payloads
│   ├── message_export.dart     # Pure NDJSON serialize/parse for Export/Replay (`ExportedMessage`, encode/decode line, `parseExportedMessagesNdjson`) — no `file_picker`/`Client` I/O, so it's unit-testable standalone
│   ├── object_store_bucket_dialog.dart # "Create Bucket" dialog (name, storage, max size, TTL, replicas)
│   ├── object_store_dashboard.dart     # Bucket/object monitor + upload/download/delete (Object Store tab's main widget; no live watch)
│   ├── object_store_manager.dart       # Thin, testable wrapper around client.jetStream()/ObjectStore calls
│   ├── paused_banner.dart      # Sibling banner (never a list item) shown above the message list while Pause is active
│   ├── regex_text_highlight.dart  # Custom inline text highlighting engine using regex substring matching
│   ├── replay_banner.dart      # Sibling banner shown above the message list while a file-based Replay is running; can coexist with `paused_banner.dart` (orthogonal states)
│   ├── replay_config_dialog.dart # Replay's file-pick + pacing (message interval, repeat count/interval) dialog, with a live "will send N messages over ~M" preview
│   ├── security_settings_dialog.dart # TLS config file selector (Trusted Cert, Cert Chain, Private Key paths)
│   ├── send_message_dialog.dart # Form dialog for publishing/sending standard, edit-replay, or JetStream payloads
│   ├── service_discovery_dashboard.dart # Fan-out Discover + master/detail service/endpoint/stats view (Services tab's main widget; no live watch)
│   ├── service_discovery_manager.dart   # Thin, testable wrapper around client.discoverServices()/getServicesInfo()/getServicesStats() (fork-only API)
│   ├── settings_dialog.dart    # App options dialog (font size, retry interval, JetStream toggle, Key-Value toggle, Object Store toggle, Service Discovery toggle, update-check toggle, subscription-colors toggle)
│   ├── subject_chips_row.dart  # Toolbar chip row replacing the old Subjects text field (one chip per subscription, color swatch, overflow "+N more")
│   ├── subscription_info.dart  # `SubscriptionInfo` model (subject/queueGroup persisted, colorIndex/sid runtime-only) + `resolveSubscriptionColor()`
│   ├── subscription_manager_dialog.dart # Full subscription list dialog (add/remove/queue-group-edit per row, live unsub/resub)
│   └── update_checker.dart     # Pure logic/network split for the GitHub Releases update check (fetchLatestRelease, isNewerVersion)
├── scripts/                    # Icon generator, mockup testing, and screenshot utilities
│   ├── generate_icons.js       # Custom Node.js sharp-based cross-platform transparent icon generator
│   ├── generate_icons.bat      # Helper batch script to run generate_icons.js
│   ├── jetstream_demo.ps1      # pwsh-only (see Recipe E): seeds demo streams + a publish loop (or -Iterations N for a finite run)
│   ├── kv_demo.ps1             # pwsh-only: seeds a demo KV bucket ("app-config") with a handful of realistic keys, for Recipe G's screenshot
│   ├── object_store_demo.ps1   # pwsh-only: seeds a demo Object Store bucket ("documents") via seed_object_store.dart, for Recipe G's screenshot
│   ├── seed_object_store.dart  # dart_nats-based Object Store seeder (avoids a CLI mtime-parsing mismatch — see Recipe G)
│   ├── message_pub.ps1         # PowerShell script publishing mockup JSON payload streams to NATS subjects
│   ├── capture_screenshots.ps1 # pwsh-only (see Recipe G): regenerates images/*.png used by the README
│   ├── _image_processing.ps1  # Shared crop/round-corner helper, dot-sourced by capture_screenshots.ps1 and images/process_screenshots.ps1
│   └── package.json            # Node.js dependencies (sharp, png-to-ico) for icon generation
├── test/                       # Fast widget/unit tests — fakes only, no server needed (see Recipe F)
│   ├── jetstream_dashboard_test.dart, jetstream_manager_test.dart, jetstream_*_dialog_test.dart, ...
│   ├── kv_dashboard_test.dart, kv_manager_test.dart, kv_bucket_dialog_test.dart, kv_put_dialog_test.dart
│   ├── object_store_dashboard_test.dart, object_store_manager_test.dart, object_store_bucket_dialog_test.dart
│   ├── message_detail_dialog_test.dart, settings_dialog_test.dart, security_settings_dialog_test.dart, update_checker_test.dart, ...
│   ├── message_export_test.dart, replay_banner_test.dart, export_confirm_dialog_test.dart, replay_config_dialog_test.dart # Milestone 22 (Export/Replay): NDJSON round-trip + injected-fake-file widget tests
│   └── connection_history_test.dart # Pure logic: encode/decode round-trip, recordConnection() dedupe/cap/move-to-front
├── integration_test/           # Real-backend end-to-end tests against a live nats-server (see Recipe E/F)
│   ├── helpers/nats_test_app.dart       # pumpConnectedApp/disconnectApp/pumpUntil/waitForSnackBarGone
│   ├── helpers/screenshot_signal.dart   # File-handshake helper used only by screenshot_tour_test.dart (see Recipe G)
│   ├── live_messages_test.dart          # Core pub/sub round trip
│   ├── live_messages_interactions_test.dart # Filter/Find/row menu/keyboard shortcuts
│   ├── live_messages_export_replay_test.dart # Export Selected -> Replay byte-for-byte round trip, repeat-interval pacing, and Stop canceling a running replay
│   ├── send_message_headers_test.dart   # A header attached in Send Message round-trips into the received message's Detail dialog
│   ├── jetstream_lifecycle_test.dart    # Full stream/consumer mutation lifecycle incl. Ack/Nak/Term
│   ├── kv_lifecycle_test.dart           # Full KV bucket/key mutation lifecycle incl. live external updates + optimistic-concurrency conflict
│   ├── object_store_lifecycle_test.dart # Full Object Store bucket/object lifecycle incl. explicit-Refresh (no watch()) + byte-for-byte download verification
│   ├── jetstream_browse_test.dart       # The ephemeral "Browse Messages" ordered-consumer view (Filter/Find, Pause/Resume/Delete)
│   ├── message_list_pause_test.dart     # Live Messages Pause/Resume, wide buffered-count, scroll-position-stable bursts + row-banding color stability
│   ├── message_row_extent_test.dart     # Fixed-height row overflow guard (long message, max font size, both line-count settings)
│   ├── connect_shortcut_test.dart       # Ctrl+Enter in Host/Port/Subjects fires Connect while disconnected
│   ├── connection_history_test.dart     # Host field's history dropdown: show/filter/select (mouse + keyboard)/delete/clear (no server needed)
│   ├── record_connection_history_test.dart # A successful connect records history; a failed (connection-refused) connect does not
│   ├── subscription_chips_test.dart     # Two subjects added live via the chip UI get distinct message-row accent colors; removing one via its chip stops further delivery
│   ├── settings_tab_toggle_test.dart    # Regression: toggling JetStream/KV/Object Store off+on in Settings must not break the TabController (no server needed)
│   └── screenshot_tour_test.dart        # Drives the app through the README's screenshots — run via scripts/capture_screenshots.ps1, not directly
├── Dockerfile                  # Multi-stage Docker container (Debian Flutter builder -> Alpine Nginx host)
├── analysis_options.yaml       # Static analysis and lints configuration (extends flutter_lints/flutter.yaml)
└── pubspec.yaml                # Flutter project specifications and library dependencies
```

---

## 3. Tech Stack & Architectural Design

### Core Libraries (from `pubspec.yaml`)
- **`dart_nats`**: Low-level NATS client protocol handler. **Currently a `git:` dependency** pointing at `nverbeek/dart-nats` (a fork), branch `feature/service-discovery` — not mainline pub.dev, as of Milestone 18. The fork adds `Client.discoverServices()`/`getServicesInfo()`/`getServicesStats()` on top of the hosting-side `addService()`/`MicroService` (ADR-32 Microservices) the upstream maintainer landed unreleased just before this milestone. An upstream PR is intentionally deferred until this app's usage has proven the API out — see ROADMAP.md's Milestone 18 section and the fork's own `CHANGELOG.md` `## Unreleased` entry. Revert `pubspec.yaml` to a normal `^x.y.z` pub.dev constraint once/if that (or an equivalent) lands upstream.
- **`provider`**: Used for lightweight application state, specifically managing dark/light `ThemeModel`.
- **`window_manager`**: Handles window resizing, positioning, and persistence on Desktop.
- **`loader_overlay`**: Displays asynchronous loading/connecting modal states.
- **`flutter_highlighter`**: Renders code highlighting for JSON payloads.
- **`shared_preferences`**: Local local key-value storage engine.
- **`markdown_widget`**: Parses and displays rich help text from markdown files.
- **`flutter_svg`**: Renders SVG vector icons.
- **`file_picker`**: Supports secure file path selection for TLS/MTLS configurations.
- **`http`**: Used only by `lib/update_checker.dart` to call the GitHub Releases API — this app's sole outbound HTTP dependency beyond the NATS protocol itself.
- **`url_launcher`**: Opens the GitHub release page in the system browser from the update-available popover.
- **`integration_test`** (dev, SDK-native — no version to track): Drives the real app end-to-end against a real `nats-server`. See Recipe E/F.

### State & Execution Architecture

1. **Centralized State Machine (`MyHomePageState` in `lib/main.dart`)**:
   - Unlike larger multi-screen apps, this client manages its primary connection state, NATS client subscriptions, active message arrays, search filters, and configuration states inside `lib/main.dart` under `_MyHomePageState`.
   - **Connection Lifecycle**: Initiated in `natsConnect()`, which configures the socket connection or WebSocket connection depending on the selected scheme. If TLS is enabled, a custom `SecurityContext` is created dynamically using files picked by the user and loaded into memory.
   - **Reconnection Loop**: An active subscription or client disconnect registers state triggers. When a connection is severed unexpectedly, the application retries connection indefinitely based on the interval stored in SharedPreferences.
   - **Stream Handling**: Subscription callbacks run in the background. Incoming messages are piped through `handleIncomingMessage()`, which auto-parses headers, tracks history bounds, formats JSON strings, and triggers `setState()`.

2. **Dialog-Driven Modular UI (`lib/*_dialog.dart`)**:
   - Secondary features (Help, Settings, Security, Publish, Message Detail) are abstracted into modular dialog widgets.
   - **Callback Pattern**: The main page opens these dialogs passing initial parameter states and callback handler functions (e.g. `onSave` callbacks) to update the primary state and write changes directly to `SharedPreferences`.

3. **Window Metrics Preservation**:
   - On Desktop platforms, a `WindowListener` is attached to the widget tree. `onWindowResized()` and `onWindowMoved()` trigger debounced updates to local preference storage. At app startup, `main()` reads these parameters to reconstruct the application boundary bounds identically.

---

## 4. Development Recipes & Workflows

### Recipe A: Adding a New Dialog / UI Feature
1. Create a dedicated dialog file under `lib/` named `[feature_name]_dialog.dart`.
2. Define a clean `StatelessWidget` or `StatefulWidget` using standard Material design patterns. Do not use external CSS or UI frameworks unless specifically authorized.
3. Pass input data and action callback handlers as constructor parameters:
   ```dart
   class CustomDialog extends StatelessWidget {
     final VoidCallback onSubmit;
     const CustomDialog({super.key, required this.onSubmit});
     // ...
   }
   ```
4. Integrate the dialog into `lib/main.dart` by adding a trigger method in `_MyHomePageState`:
   ```dart
   Future<void> showCustomDialog() async {
     await showDialog(
       context: context,
       builder: (context) => const CustomDialog(...),
     );
   }
   ```

### Recipe B: Extending/Modifying Connection Logic
- All connection parameters should be configured and validated in `natsConnect()` inside `lib/main.dart`.
- If introducing custom credentials, parameters, or configurations, declare corresponding keys in `lib/constants.dart`.
- Ensure settings are properly hydrated inside `initializePreferences()` and persisted correctly.

### Recipe C: Regenerating Transparent Launcher Icons
If you modify the master launcher SVG icon at `assets/app_launcher_icon.svg`, do not use generic launcher icon generation packages as they may break transparent layers. Instead, execute the custom script suite:
```powershell
# Navigate to the scripts directory
cd scripts
# Install required Node dependencies (sharp & png-to-ico)
npm install
# Run the generator
npm run generate
```
This automatically replaces native icon artifacts for Android, iOS, Web, macOS, Windows, and Linux.

### Recipe D: Local Mock Testing (NATS Streams)
To test the visual stream, searching, filtering, and detail dialogue features without an external production broker:
1. Spin up a local NATS broker: `nats-server` (or run a docker container: `docker run -d -p 4222:4222 -p 8222:8222 nats`).
2. Run the application locally and connect to `nats://127.0.0.1:4222`.
3. Execute the PowerShell mockup publishing script to pipe simulated real-time data:
   ```powershell
   ./scripts/message_pub.ps1
   ```
   This script queries local environments or pipes embedded mock JSON data sets (cars, animal taxonomies, telemetry) to the `>` subject tree.

### Recipe E: Local JetStream Testing
The JetStream tab (Milestone 1 in `ROADMAP.md`) needs a JetStream-*enabled* server — plain `nats-server`/`nats` (no flag) does not have JetStream turned on, and the app's own "Enable JetStream" setting only controls whether the tab is shown, not whether the server supports it.

1. Start a JetStream-enabled broker with Docker (requires the `nats` CLI on the host for the demo script; the server itself needs no extra tooling):
   ```powershell
   docker run -d --name nats-js -p 4222:4222 -p 8222:8222 nats:latest -js
   ```
   (Drop the trailing `-js` to start a server *without* JetStream — useful for exercising the app's "JetStream not enabled" empty state.)
2. Run the application and connect to `nats://127.0.0.1:4222`.
3. Populate the server with demo streams and a steady trickle of messages so there's something to see in the dashboard. Run it with **`pwsh`, not `powershell.exe`** — Windows PowerShell 5.1 prepends a UTF-8 BOM when piping strings to a native process's stdin, which corrupts the JSON payloads regardless of `$OutputEncoding`; the script's `#Requires -PSEdition Core` will error out early if you run it under 5.1 instead of silently producing bad test data:
   ```powershell
   pwsh ./scripts/jetstream_demo.ps1
   ```
   This creates a couple of sample streams (e.g. `orders`, `telemetry`) via `nats stream add` and then loops `nats pub`, so switching to the JetStream tab shows real, growing streams and "Browse Messages" has live data to tail.
4. When finished: `docker rm -f nats-js`.

KV buckets are themselves backed by JetStream streams (`KV_<bucket>`), so the Key-Value Stores tab and `integration_test/kv_lifecycle_test.dart` need no separate fixture — the same JetStream-enabled server above is sufficient. The same is true of Object Store buckets (`OBJ_<bucket>`) and `integration_test/object_store_lifecycle_test.dart`.

### Recipe F: Writing New Tests
Two distinct suites, two distinct patterns — don't mix them up:

- **Widget tests (`test/`)**: no live server. For anything touching `JetStreamManager`, extend the `FakeJetStreamManager` in `test/jetstream_dashboard_test.dart` (override the specific method(s) you need; most already have an overridable `xImpl` function field). For standalone dialogs (`Create Stream`, `Create Consumer`, `Settings`, `Security Settings`, `Message Detail`, `Send Message`), just `pumpWidget` the dialog directly wrapped in a `MaterialApp`/`Scaffold` — see `test/jetstream_stream_dialog_test.dart` or `test/settings_dialog_test.dart` for the pattern. `MyHomePage` itself (Live Messages tab) has no fake-injection point (`natsClient` is constructed internally), so its controls can only be covered by integration tests.
- **Integration tests (`integration_test/`)**: real server, real app, via `helpers/nats_test_app.dart`'s `pumpConnectedApp`/`disconnectApp`/`pumpUntil`/`waitForSnackBarGone`. A few sharp edges worth knowing before you hit them yourself:
  - `JetStreamDashboard`'s state does **not** survive switching away from the JetStream tab and back (no `AutomaticKeepAliveClientMixin`) — re-select the stream/consumer after any trip through `Live Messages`.
  - A `SnackBar` sitting at the bottom of the screen can silently absorb taps meant for the bottom toolbar; `pumpAndSettle()` doesn't wait out its full display duration. Call `waitForSnackBarGone(tester)` after anything that shows one.
  - `find.byTooltip(...)` returns the `Tooltip` wrapper, not the `IconButton` inside it — use `find.ancestor(of: ..., matching: find.byType(IconButton))` to inspect `onPressed`.
  - `find.text(...)` also matches `EditableText`, and a plain `Text` widget always builds its own internal `RichText` — a predicate checking both `Text` and `RichText` double-counts every unstyled row. Match your own custom widgets (e.g. `RegexTextHighlight.text`) directly instead of guessing at Flutter's internal render tree.
  - Tapping a `ListTile` doesn't grant it keyboard focus the way tapping a text field does — if a shortcut test needs `selectedIndex` set and then a bare-letter key event to reach the app's `Focus(onKeyEvent: ...)`, explicitly call `Focus.of(tester.element(rowFinder)).requestFocus()` after selecting the row, or the key event has nothing focused to bubble up from.
  - Nak causes a *real* server redelivery — a second row with the same payload can legitimately appear afterward. Prefer `.last` when re-locating "the row I just acted on" (new deliveries insert at index 0).

### Recipe G: Regenerating README Screenshots
The images under `images/` (referenced from the README's "Screenshots" section) are captured automatically, not hand-taken. A real OS-level window screenshot (title bar and all) can only come from a process other than the one being photographed, so this is two cooperating processes: `scripts/capture_screenshots.ps1` (host) and `integration_test/screenshot_tour_test.dart` (drives the real app), trading turns through plain files under `build/.screenshot_signals/` — see `integration_test/helpers/screenshot_signal.dart` for the handshake and `scripts/capture_screenshots.ps1`'s header comment for the Win32 capture side.

1. Prerequisites on `PATH`: `flutter`, `dart` (ships with the Flutter SDK — needed by `object_store_demo.ps1`, see below), `docker`, the `nats` CLI, and ImageMagick (`magick`) — same as Recipe E/F plus the same ImageMagick dependency as `images/process_screenshots.ps1`.
2. Run (from the repo root, under `pwsh`, not Windows PowerShell):
   ```powershell
   pwsh ./scripts/capture_screenshots.ps1
   ```
3. What it does: starts a disposable JetStream-enabled `nats-server` in Docker (or reuses whatever's already listening on port 4222, e.g. a Recipe E container you left running), seeds it (`jetstream_demo.ps1 -Iterations 5`, then `kv_demo.ps1` for the `app-config` demo bucket, then `object_store_demo.ps1` for the `documents` demo bucket — KV and Object Store both ride on the same JetStream-enabled server, no separate containers), launches `flutter test integration_test/screenshot_tour_test.dart -d windows`, and as that test reaches each screen (Messages, Filter and Sort, Message Detail, JetStream, Key-Value Stores, Object Store), captures the live "NATS Client" window and writes the cropped/rounded result straight into `images/<name>.png`, overwriting the existing file. The Messages capture's seed step also publishes 15 filler rows, styled as plausible telemetry/system traffic on their own subjects (never matched by the 'animal'/'family' filter-and-find demo), purely so the list overflows the window — the test then scrolls down and pauses before capturing, so that one screenshot shows the Pause and Jump-to-top buttons in their active states instead of adding dedicated screenshots for them.

   `object_store_demo.ps1` is the odd one out: it seeds through a small `dart run` script (`scripts/seed_object_store.dart`) calling `dart_nats`'s own `ObjectStore.put()` directly, rather than the `nats object put` CLI command `kv_demo.ps1`'s KV equivalent uses. Confirmed live: the CLI's own object-metadata writer leaves `mtime` as Go's zero-value time (`0001-01-01T00:00:00Z`), which `dart_nats` parses literally — the app would then show something like "739807d ago" instead of "just now" for CLI-seeded demo objects. Real uploads through the app's own Upload button are unaffected (the app's own `ObjectStore.put()` call always sets `mtime` itself); this only bit the *demo seeding* path.
4. If you add a new screen worth screenshotting, add a checkpoint to `screenshot_tour_test.dart` (call `signaler.capture(tester, 'Some Name')` once the screen is settled) and reference `./images/Some%20Name.png` from the README. If it needs its own demo data (like the KV bucket above), add a seed step to `capture_screenshots.ps1`'s "Seeding..." block too — otherwise no changes needed to the capture script itself.
5. Only the Windows target has been wired up (matches how `images/process_screenshots.ps1` already assumes `magick`/pwsh on Windows) — there's no Linux/macOS equivalent of the Win32 `PrintWindow` capture yet.

### Recipe H: Local Authentication Testing
`integration_test/authentication_test.dart` (Milestone 4 in `ROADMAP.md`) verifies the "correct credentials connect successfully" path for all four auth methods against real servers — one server per method, since NATS's simple `authorization` block (user/pass, token, bare nkey) and its operator/JWT mode are mutually exclusive server configs, so this can't be one shared container like Recipe E's JetStream server.

1. Start all four fixture servers (safe to leave running; each is a disposable container):
   ```powershell
   docker run -d --name nats-fixture-userpass -p 4300:4222 -v "${PWD}/integration_test/fixtures/auth/userpass.conf:/etc/nats/nats-server.conf:ro" nats:latest -c /etc/nats/nats-server.conf
   docker run -d --name nats-fixture-token -p 4301:4222 -v "${PWD}/integration_test/fixtures/auth/token.conf:/etc/nats/nats-server.conf:ro" nats:latest -c /etc/nats/nats-server.conf
   docker run -d --name nats-fixture-nkey -p 4302:4222 -v "${PWD}/integration_test/fixtures/auth/nkey.conf:/etc/nats/nats-server.conf:ro" nats:latest -c /etc/nats/nats-server.conf
   docker run -d --name nats-fixture-creds -p 4303:4222 -v "${PWD}/integration_test/fixtures/auth/creds.conf:/etc/nats/nats-server.conf:ro" nats:latest -c /etc/nats/nats-server.conf
   ```
2. Run the test file: `flutter test integration_test/authentication_test.dart -d windows` (all four `testWidgets` run fine in one invocation/process, unlike the multi-*file* limitation noted in Recipe F).
3. When finished: `docker rm -f nats-fixture-userpass nats-fixture-token nats-fixture-nkey nats-fixture-creds`.

The fixture credentials (`integration_test/fixtures/auth/*.conf` and `test-user.creds`) are throwaway, non-expiring, committed test material — not real secrets. The `.creds` one was generated once via the official `nsc` CLI (`nsc init` + `nsc generate config --mem-resolver`); there's no need to regenerate it unless it's lost. The NKey fixture's seed lives directly in `authentication_test.dart` next to its public key in `nkey.conf`.

**Deliberately not automated**: the "wrong credentials show the friendly error" path. `dart_nats`'s `-ERR` handler completes an internal `Completer` that's never awaited on this app's `retryCount: -1` connect path, which Dart reports as an uncaught zone error — harmless for the real app (`runApp()`'s `runZonedGuarded` zone swallows it after logging) but fatal under `flutter test`'s stricter zone. If you need to re-verify this by hand, use a standalone `dart run --packages=.dart_tool/package_config.json some_probe.dart` script with your own `runZonedGuarded`, not `integration_test`.

### Recipe I: Verifying Update Notifications
`lib/update_checker.dart`'s `isNewerVersion()`/`fetchLatestRelease()` are covered by `test/update_checker_test.dart` against a mocked `http.Client` (`package:http/testing.dart`'s `MockClient`) — no live call needed for routine test runs. But the actual in-app popover (`_showUpdateAvailablePopover()` in `lib/main.dart`) has no fake-injection point and talks to the real `https://api.github.com/repos/nverbeek/nats_client_flutter/releases/latest`, so verifying *that* end-to-end means hitting the live API, not a local fixture like Recipe E/H's server-backed features.

1. Temporarily lower `pubspec.yaml`'s `version:` below the real latest published tag (check it with `curl -s https://api.github.com/repos/nverbeek/nats_client_flutter/releases/latest` if unsure) — this makes the real API register as "newer" without needing a mock.
2. Drive it with a throwaway `integration_test/` file (`app.main()` + `pumpUntil(() => find.text('Update available').evaluate().isNotEmpty)`, same pattern as every other integration test) and run it via `flutter test <file> -d windows`. Don't commit this file — delete it once you're done; there's nothing here a fixture server could stand in for.
3. Restore `pubspec.yaml`'s real version afterward. Forgetting this step means the shipped build will nag about "updates" that don't exist.
4. To check the negative path (no popover when already up to date), temporarily set the version to match the real latest tag instead and confirm no popover appears within a few seconds.

---

## 5. Build, Lint & Test Command Reference

Always run the following commands to validate the workspace before committing.

### Environment Setup & Dependency Installation
```bash
flutter pub get
```

### Code Formatting
Ensure all modified files adhere strictly to the Dart SDK formatter style guidelines:
```bash
flutter format .
```

### Static Analysis & Lint Enforcement
Analyze the codebase against standard lints defined in `analysis_options.yaml`:
```bash
flutter analyze
```
*Note: Ensure there are absolutely no errors, warnings, or info lints before pushing changes.*

### Run Local Debug Build
```bash
flutter run -d <target_device_id_or_platform>
```

### Run Tests
Fast widget/unit tests (`test/`, fakes only, no server needed):
```bash
flutter test test/
```
Real-backend integration tests (`integration_test/`, needs a local JetStream-enabled `nats-server` — see Recipe E) — run **one file per invocation**, not the whole directory: passing multiple files to a single `flutter test integration_test` invocation is known to fail to relaunch the app for the second file on at least the Windows desktop target.
```bash
flutter test integration_test/live_messages_test.dart -d windows
```
CI runs both suites (see `.github/workflows/build.yml`'s `test` job) on every push/PR and gates every build/release job on them.

### Building Platform Artifacts
```bash
# Build desktop packages
flutter build windows
flutter build macos
flutter build linux

# Build web distribution folder (output: build/web/)
flutter build web
```

### Build Docker Container (Web Flavor)
To package the web version of the application inside an alpine-nginx container:
```bash
docker build -t nats-client-flutter .
```

---

## 6. AI Agent Guidelines & Coding Guardrails

### Coding & Architectural Principles
- **Avoid Over-Bloating `main.dart`**: `lib/main.dart` is the core state machine and already several thousand lines long (growing with nearly every milestone). If you are adding complex new business logic (e.g., message parsers, serialization formats, storage), extract helper classes, utilities, or managers to new, self-contained files inside `lib/` — `main.dart` should mostly hold state fields, orchestration methods, and widget wiring that call into them (see `lib/message_export.dart`/`lib/replay_config_dialog.dart` vs. Milestone 22's `_exportMessages`/`_runReplay` in `main.dart` for the split).
- **Prefer Composition & Material 3 Primitives**: Rely on clean composition and vanilla Material 3 styling components. Check and maintain visual coherence with existing screens (see screenshots inside `images/`).
- **Strict Lint Compliance**: Never use linter ignore statements (`// ignore: ...`) or suppress warning markers unless there is an absolute, well-documented platform-level compiler barrier. Maintain type safety, avoiding unnecessary casts (`as`) or dynamically typed constructs (`dynamic`) where explicit typing can be defined.

### Security Protocols
- **No Hardcoded Secrets**: Under no circumstances should you print, log, or commit passwords, credentials, keys, or private certificates.
- **Client TLS Cert Files**: The TLS setting expects file paths. Ensure that client certificates and private keys remain strictly on the host system. The app stores these paths in `SharedPreferences` for user convenience. When working with paths, never write fallback hardcoded certificate paths to any git-tracked resource.
- **Exclude Generated Artifacts**: Ensure all local `.env`, certificates, `scripts/node_modules`, or system-specific builds remain strictly ignored by git (abide by rules defined in `.gitignore`).

### Verification & Quality Mandate
1. **Formatting**: Always format your modified code using `flutter format .` prior to finishing.
2. **Analysis**: Always execute `flutter analyze` to ensure the project passes compile validation.
3. **Regression Testing**: If you modify UI or logic covered by an existing test file, run it and keep it green. If you add a new dialog or `JetStreamManager` method, add a corresponding widget test under `test/` (see Recipe F for the patterns to reuse — `widget_test.dart` itself is an unused stub, not a place to add tests). If the change can only be verified against a real server (a new connection-state path, a new JetStream mutation, a new keyboard shortcut), add or extend an `integration_test/` file instead.
