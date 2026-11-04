# AGENTS.md

NATS Client UI: a Flutter desktop (Windows, macOS, Linux) and web app for watching and publishing NATS messages and managing JetStream, Key-Value, Object Store and Services, plus a Server tab that reads nats-server's HTTP monitoring endpoint. Desktop supports `nats://` (TCP) and `ws://`. Web supports `ws://` only, except in the Docker image, whose server relays `nats://` over TCP.

## Commands

```sh
flutter pub get
dart format .                     # whole repo, last step of every change
flutter analyze                   # must be clean: no errors, warnings or infos
flutter test test/                # widget/unit tests, no server needed
flutter test integration_test/live_messages_test.dart -d windows   # ONE file per invocation; needs a server
cd docker/tcp_relay && dart pub get && dart analyze --fatal-infos && dart test   # separate package
docker build -t nats-client-flutter .
```

CI (`.github/workflows/build.yml`) runs all of the above on every push and gates every build/release job on them.

## Where things are

`lib/` is flat. Files are named by feature prefix (`jetstream_`, `kv_`, `object_store_`, `service_discovery_`, `server_monitor_`) and role:

- `*_manager.dart`: thin, testable wrapper around `dart_nats` calls. Tests fake these.
- `*_dashboard.dart`: a feature tab's main widget. Each feature tab has a Settings toggle.
- `*_dialog.dart`: a dialog that takes initial values and callbacks (e.g. `onSave`) as constructor args. The caller in `main.dart` applies the result and persists it.
- `main.dart` (~4,000 lines): `MyHomePage` is the central state machine. `natsConnect()` handles connect/TLS/auth/reconnect, `handleIncomingMessage()` the Live Messages pipeline, and `initializePreferences()` loads settings.
- `constants.dart`: defaults and `SharedPreferences` keys. Add new pref keys here and load them in `initializePreferences()`.

Other docs (read the one that matches your task before starting):

| Doc | Covers |
|---|---|
| `integration_test/README.md` | Starting test servers, auth fixtures, fakes to reuse, integration-test gotchas |
| `docker/tcp_relay/README.md` | The Docker server and `nats://` relay: security guardrails, contexts, TLS, image constraints |
| `scripts/README.md` | Demo data seeders, README screenshot capture, launcher icons |
| `RELEASING.md` | Version bump, tagging, what publishes where, CI secrets, macOS signing |
| `README.md` | User-facing features and Docker/Kubernetes setup |
| `assets/app_help.md` | In-app help, rendered by `help_dialog.dart` |
| `CHANGELOG.md` | User-facing release notes; a section is added in the release PR |
| `PRIVACY.md` | Privacy policy; update it if the app's network or storage behavior changes |

## Conventions

- **Keep `main.dart` from growing.** Put new logic (parsers, serialization, storage, network) in its own file in `lib/` and leave `main.dart` with state, orchestration and wiring. Example: `message_export.dart` (pure NDJSON) and `replay_config_dialog.dart` vs. `_exportMessages`/`_runReplay` in `main.dart`.
- **Material 3 primitives only**, no extra UI frameworks. Match the existing screens (`images/`).
- **Row menus:** every message list (Live Messages, Browse Messages, Consumer Tail) and KV key rows has a `_buildRowMenuItems`/`_handleRowMenuSelection`/`_showRowContextMenu` trio. The ⋮ button and right-click share it, so change the trio, not one trigger.
- **Shared chip styling** lives in `subject_chip_style.dart`. The subscription-color setting only gates rendering: `colorIndex` assignment stays untouched, and a hidden color reserves no space.
- **Connection history** is recorded only on `Status.connected`, never on an attempt.
- **Dashboards don't keep state** across tab switches. They re-sync after a real reconnect through `reconnectSignal` (`reconnect_detector.dart`). Otherwise listings use explicit Refresh. Object Store and Services have no live watch.
- **The Server tab** (`server_monitor.dart`, no `dart_nats`: plain HTTP to the monitoring port) polls only while mounted, so leaving the tab stops it. Its chart history lives in `ServerMonitorSession`, which `main.dart` creates per connection only while the tab is enabled. `/connz` is fetched every 5th poll because it's expensive for the server; sorting and paging are the server's, so don't add client-side sort or filter on a single page.
- **When typed `dart_nats` classes drop fields the server sends** (e.g. `ack_wait`, KV TTL, `pause_until`), the managers read the raw `$JS.API.*` JSON. See `JetStreamManager.consumerDetail()`.
- **Update docs alongside UI changes.** A user-visible change updates `assets/app_help.md`, and the README's feature list if it's a feature.

## `dart_nats`

A normal pub.dev dependency (`^1.7.1`, repo [dart-nats/dart-nats](https://github.com/dart-nats/dart-nats)). This project's owner also owns that repo and the pub.dev package. When a feature needs a library change, land it upstream and cut a release rather than working around it or forking. A `dependency_overrides` pin is fine only while verifying an unreleased change. To read the library source, find its pub-cache path in `.dart_tool/package_config.json`; don't search the filesystem. Object Store is `EXPERIMENTAL` upstream.

## Tests

- A new dialog, manager method or pure helper gets a widget/unit test in `test/`.
- Behavior that needs a real server (connection states, JetStream mutations, keyboard shortcuts in the live app) gets an `integration_test/` file.
- If you change code an existing test covers, run that test.
- `test/widget_test.dart` is an unused stub.
- Patterns and gotchas: `integration_test/README.md`.

## Guardrails

- **Lints:** no `// ignore:` comments. Avoid `dynamic` and unnecessary `as` casts where a real type exists.
- **Secrets:** never print, log or commit credentials, keys or certificates. The only committed credentials are the throwaway test fixtures in `integration_test/fixtures/auth/`.
- **Picked files:** read or write a file immediately after its native panel returns, and store the **contents**, not the path. TLS/`.creds` files are stored gzip+base64 in prefs; see `handleTrustedCertificateFile()`. The macOS App Sandbox only grants access for that pick, so a stored path fails on the next launch.
- **macOS entitlements:** both `macos/Runner/*.entitlements` need `com.apple.security.files.user-selected.read-write`, or every file panel fails. CI asserts it.
- **Icon:** `assets/app_launcher_icon.svg` is the official NATS icon and must stay unmodified, launcher-only, never in the UI (CNCF trademark; see `scripts/README.md`).
- **Docker relay:** read `docker/tcp_relay/README.md` before touching `docker/tcp_relay/`, `lib/tcp_relay.dart` or `web/index.html`. Its origin/host checks are security boundaries. `web/index.html` must not get a `<base href>`.
- Keep `.env` files, certificates, `scripts/node_modules` and build output out of git.

## Before you're done

1. `dart format .` over the whole repo, last, so no formatter drift reaches unrelated files.
2. `flutter analyze` is clean, and if you touched the relay, so is `dart analyze --fatal-infos` in `docker/tcp_relay`.
3. Relevant tests pass. Say which integration tests you couldn't run.
4. Docs that describe what you changed are updated (see the table above).
