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
- **Data Syntax Highlighting**: Automatic pretty-printing and syntax highlighting of JSON payloads inside detailed message dialogs.
- **State & Size Persistence**: Remembers recent connection setups, theme preferences, and window size/position across runs.

---

## 2. Directory Map & Repository Structure

Below is the structured layout of the workspace, pointing you to relevant files depending on your task.

```
nats_client_flutter/
├── .github/workflows/
│   └── build.yml               # CI/CD GitHub Actions workflow (multi-platform builds & Docker publishing)
├── assets/
│   ├── app_help.md             # Standard application markdown help file loaded dynamically in-app
│   └── app_launcher_icon.svg   # Source SVG launcher icon (used to regenerate platform-native icons)
├── images/                     # App screenshots used in the main README.md
├── lib/                        # Core application source code
│   ├── constants.dart          # Connection state text, defaults, colors, and SharedPreferences keys
│   ├── help_dialog.dart        # Stateless widget dialog that parses and displays assets/app_help.md
│   ├── highlight_theme.dart    # Theme configurations for the code highlighter
│   ├── main.dart               # Main entry point, ThemeModel provider, and MyHomePage (core state machine)
│   ├── message_detail_dialog.dart # Dialog widget for inspecting subject, headers, and pretty JSON payloads
│   ├── regex_text_highlight.dart  # Custom inline text highlighting engine using regex substring matching
│   ├── security_settings_dialog.dart # TLS config file selector (Trusted Cert, Cert Chain, Private Key paths)
│   ├── send_message_dialog.dart # Form dialog for publishing/sending standard or edit-replay payloads
│   └── settings_dialog.dart    # App options dialog (font sizes, line wrapping, retry intervals)
├── scripts/                    # Icon generator and mockup testing utilities
│   ├── generate_icons.js       # Custom Node.js sharp-based cross-platform transparent icon generator
│   ├── generate_icons.bat      # Helper batch script to run generate_icons.js
│   ├── message_pub.ps1         # PowerShell script publishing mockup JSON payload streams to NATS subjects
│   └── package.json            # Node.js dependencies (sharp, png-to-ico) for icon generation
├── test/
│   └── widget_test.dart        # Test suite root (contains empty main, ready for unit & widget tests)
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
Execute the widget and unit test suites:
```bash
flutter test
```

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
3. **Regression Testing**: If you modify the connection or messaging behavior, write a corresponding unit test inside `test/widget_test.dart` or create a new test file under `test/` (e.g. `test/connection_test.dart`). Verify that your change does not break existing test runs.
