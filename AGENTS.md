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
- **JetStream Dashboard** (`lib/jetstream_*.dart`, toggleable via the "Enable JetStream" setting): monitor streams and consumers, create/purge/delete streams, create/delete consumers (push or pull, any ack policy), browse a stream's messages live, tail a specific consumer with Ack/Nak/Term actions, and publish with JetStream delivery acknowledgement from the regular Send Message dialog.
- **Data Syntax Highlighting**: Automatic pretty-printing and syntax highlighting of JSON payloads inside detailed message dialogs.
- **State & Size Persistence**: Remembers recent connection setups, theme preferences, and window size/position across runs.

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
│   ├── constants.dart          # Connection state text, defaults, colors, and SharedPreferences keys
│   ├── help_dialog.dart        # Stateless widget dialog that parses and displays assets/app_help.md
│   ├── highlight_theme.dart    # Theme configurations for the code highlighter
│   ├── jetstream_consumer_dialog.dart    # "Create Consumer" dialog (push/pull, ack/deliver policy)
│   ├── jetstream_consumer_tail_view.dart # Live tail of a named consumer with Ack/Nak/Term actions
│   ├── jetstream_dashboard.dart          # Stream/consumer monitor + mutations (JetStream tab's main widget)
│   ├── jetstream_manager.dart            # Thin, testable wrapper around client.jetStream() calls
│   ├── jetstream_message_view.dart       # Ephemeral ordered-consumer "Browse Messages" tail
│   ├── jetstream_stream_dialog.dart      # "Create Stream" dialog (name, subjects, max age, replicas)
│   ├── main.dart               # Main entry point, ThemeModel provider, and MyHomePage (core state machine)
│   ├── message_detail_dialog.dart # Dialog widget for inspecting subject, headers, and pretty JSON payloads
│   ├── regex_text_highlight.dart  # Custom inline text highlighting engine using regex substring matching
│   ├── security_settings_dialog.dart # TLS config file selector (Trusted Cert, Cert Chain, Private Key paths)
│   ├── send_message_dialog.dart # Form dialog for publishing/sending standard, edit-replay, or JetStream payloads
│   └── settings_dialog.dart    # App options dialog (font sizes, line wrapping, retry intervals, JetStream toggle)
├── scripts/                    # Icon generator, mockup testing, and screenshot utilities
│   ├── generate_icons.js       # Custom Node.js sharp-based cross-platform transparent icon generator
│   ├── generate_icons.bat      # Helper batch script to run generate_icons.js
│   ├── jetstream_demo.ps1      # pwsh-only (see Recipe E): seeds demo streams + a publish loop (or -Iterations N for a finite run)
│   ├── message_pub.ps1         # PowerShell script publishing mockup JSON payload streams to NATS subjects
│   ├── capture_screenshots.ps1 # pwsh-only (see Recipe G): regenerates images/*.png used by the README
│   ├── _image_processing.ps1  # Shared crop/round-corner helper, dot-sourced by capture_screenshots.ps1 and images/process_screenshots.ps1
│   └── package.json            # Node.js dependencies (sharp, png-to-ico) for icon generation
├── test/                       # Fast widget/unit tests — fakes only, no server needed (see Recipe F)
│   ├── jetstream_dashboard_test.dart, jetstream_manager_test.dart, jetstream_*_dialog_test.dart, ...
│   └── message_detail_dialog_test.dart, settings_dialog_test.dart, security_settings_dialog_test.dart, ...
├── integration_test/           # Real-backend end-to-end tests against a live nats-server (see Recipe E/F)
│   ├── helpers/nats_test_app.dart       # pumpConnectedApp/disconnectApp/pumpUntil/waitForSnackBarGone
│   ├── helpers/screenshot_signal.dart   # File-handshake helper used only by screenshot_tour_test.dart (see Recipe G)
│   ├── live_messages_test.dart          # Core pub/sub round trip
│   ├── live_messages_interactions_test.dart # Filter/Find/row menu/keyboard shortcuts
│   ├── jetstream_lifecycle_test.dart    # Full stream/consumer mutation lifecycle incl. Ack/Nak/Term
│   ├── jetstream_browse_test.dart       # The ephemeral "Browse Messages" ordered-consumer view
│   └── screenshot_tour_test.dart        # Drives the app through the README's screenshots — run via scripts/capture_screenshots.ps1, not directly
├── Dockerfile                  # Multi-stage Docker container (Debian Flutter builder -> Alpine Nginx host)
├── analysis_options.yaml       # Static analysis and lints configuration (extends flutter_lints/flutter.yaml)
└── pubspec.yaml                # Flutter project specifications and library dependencies
```

---

## 3. Tech Stack & Architectural Design

### Core Libraries (from `pubspec.yaml`)
- **`dart_nats`**: Low-level NATS client protocol handler.
- **`provider`**: Used for lightweight application state, specifically managing dark/light `ThemeModel`.
- **`window_manager`**: Handles window resizing, positioning, and persistence on Desktop.
- **`loader_overlay`**: Displays asynchronous loading/connecting modal states.
- **`flutter_highlighter`**: Renders code highlighting for JSON payloads.
- **`shared_preferences`**: Local local key-value storage engine.
- **`markdown_widget`**: Parses and displays rich help text from markdown files.
- **`flutter_svg`**: Renders SVG vector icons.
- **`file_picker`**: Supports secure file path selection for TLS/MTLS configurations.
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

1. Prerequisites on `PATH`: `flutter`, `docker`, the `nats` CLI, and ImageMagick (`magick`) — same as Recipe E/F plus the same ImageMagick dependency as `images/process_screenshots.ps1`.
2. Run (from the repo root, under `pwsh`, not Windows PowerShell):
   ```powershell
   pwsh ./scripts/capture_screenshots.ps1
   ```
3. What it does: starts a disposable JetStream-enabled `nats-server` in Docker (or reuses whatever's already listening on port 4222, e.g. a Recipe E container you left running), seeds it (`jetstream_demo.ps1 -Iterations 5`), launches `flutter test integration_test/screenshot_tour_test.dart -d windows`, and as that test reaches each screen (Messages, Filter and Sort, Message Detail, JetStream), captures the live "NATS Client" window and writes the cropped/rounded result straight into `images/<name>.png`, overwriting the existing file.
4. If you add a new screen worth screenshotting, add a checkpoint to `screenshot_tour_test.dart` (call `signaler.capture(tester, 'Some Name')` once the screen is settled) and reference `./images/Some%20Name.png` from the README — no changes needed to the capture script itself.
5. Only the Windows target has been wired up (matches how `images/process_screenshots.ps1` already assumes `magick`/pwsh on Windows) — there's no Linux/macOS equivalent of the Win32 `PrintWindow` capture yet.

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
- **Avoid Over-Bloating `main.dart`**: `lib/main.dart` is currently the core state machine but sits at ~1500 lines. If you are adding complex new business logic (e.g., historical state export, complex message parsers, database storage), extract helper classes, utilities, or managers to new, self-contained files inside `lib/` rather than adding length to `main.dart`.
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
