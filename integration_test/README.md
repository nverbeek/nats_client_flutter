# Testing

Two suites with different patterns. Don't mix them up.

| Suite | Needs | Run |
|---|---|---|
| `test/` | Nothing; fakes only | `flutter test test/` |
| `integration_test/` | A JetStream-enabled `nats-server` (plus the auth fixtures for `authentication_test.dart`) | `flutter test integration_test/<file>.dart -d windows` |

Run integration tests **one file per invocation**. Passing several files to one `flutter test` fails to relaunch the app for the second file, at least on Windows. CI (`.github/workflows/build.yml`) loops over the files the same way on Linux under Xvfb, skipping `screenshot_tour_test.dart` and `macos_file_picker_sandbox_test.dart`.

## Servers

**JetStream** (covers core pub/sub, JetStream, KV and Object Store, since KV and Object Store buckets are JetStream streams):

```sh
docker run -d --name nats-js -p 4222:4222 -p 8222:8222 nats:latest -js -m 8222
```

`-m 8222` turns on the monitoring port `server_monitor_test.dart` reads; passing any arguments replaces the image's defaults, so without it nothing listens on 8222. Drop `-js` to exercise the app's "JetStream not enabled" state. To get demo data for manual poking, see `scripts/README.md`. When done: `docker rm -f nats-js`.

**Auth fixtures** for `authentication_test.dart`, one server per method. NATS's `authorization` block and operator/JWT mode are mutually exclusive, so they can't share a server:

```powershell
docker run -d --name nats-fixture-userpass -p 4300:4222 -v "${PWD}/integration_test/fixtures/auth/userpass.conf:/etc/nats/nats-server.conf:ro" nats:latest -c /etc/nats/nats-server.conf
docker run -d --name nats-fixture-token    -p 4301:4222 -v "${PWD}/integration_test/fixtures/auth/token.conf:/etc/nats/nats-server.conf:ro"    nats:latest -c /etc/nats/nats-server.conf
docker run -d --name nats-fixture-nkey     -p 4302:4222 -v "${PWD}/integration_test/fixtures/auth/nkey.conf:/etc/nats/nats-server.conf:ro"     nats:latest -c /etc/nats/nats-server.conf
docker run -d --name nats-fixture-creds    -p 4303:4222 -v "${PWD}/integration_test/fixtures/auth/creds.conf:/etc/nats/nats-server.conf:ro"    nats:latest -c /etc/nats/nats-server.conf
```

When done: `docker rm -f nats-fixture-userpass nats-fixture-token nats-fixture-nkey nats-fixture-creds`.

- The fixture credentials (`fixtures/auth/*.conf`, `test-user.creds`) are throwaway, non-expiring test material, not real secrets. The `.creds` one was generated once with `nsc` (`nsc init` + `nsc generate config --mem-resolver`). The NKey seed lives in `authentication_test.dart` next to its public key in `nkey.conf`.
- `userpass.conf` also defines `integration-test-restricted`, which is denied `forbidden.>`. It backs the permission-denied SnackBar and chip-flag test.
- A first-connect TLS failure (untrusted server cert) has no committed test, because that would mean committing a server private key. To check it by hand, start `nats:latest` with a throwaway self-signed `tls { cert_file, key_file }` config and connect with no trusted certificate configured. Expect `connectionFailureTls`.

## Widget tests (`test/`)

- **JetStream:** extend `FakeJetStreamManager` in `test/jetstream_dashboard_test.dart`. Most methods have an overridable `xImpl` function field. The KV, Object Store and Services dashboards have equivalent fakes in their own test files.
- **Standalone dialogs:** `pumpWidget` the dialog wrapped in `MaterialApp`/`Scaffold`; see `test/jetstream_stream_dialog_test.dart`.
- **`MyHomePage` (Live Messages):** there's no injection point for the connection, so anything needing a live connection is integration-only. List, selection and shortcut behavior can still be widget-tested. Pump `MyHomePage` inside `ChangeNotifierProvider<ThemeModel>` + `MaterialApp`/`LoaderOverlay` at a 1280x720 `tester.view`, and feed messages into `handleIncomingMessage()`. See `test/live_messages_shortcut_focus_test.dart`.
- **Browse Messages:** `OrderedConsumer.messages()`/`stop()` are overridable; see `_FakeOrderedConsumer` in `test/jetstream_message_view_test.dart`.
- `test/widget_test.dart` is an unused stub. Don't add tests there.

## Integration tests (`integration_test/`)

Use `helpers/nats_test_app.dart`: `pumpConnectedApp`, `pumpDisconnectedApp`, `disconnectApp`, `pumpUntil`, `waitForSnackBarGone`. Sharp edges:

- **Dashboard state:** `JetStreamDashboard`'s state doesn't survive switching tabs and back (no keep-alive). Re-select the stream or consumer after any trip through Live Messages.
- **SnackBars:** a SnackBar at the bottom can absorb taps meant for the bottom toolbar, and `pumpAndSettle()` doesn't wait out its display time. Call `waitForSnackBarGone(tester)` after anything that shows one.
- **Finders:**
  - `find.byTooltip(...)` returns the `Tooltip`, not the `IconButton`. To inspect `onPressed`, use `find.ancestor(of: ..., matching: find.byType(IconButton))`.
  - `find.text(...)` also matches `EditableText`, and every `Text` builds its own `RichText`. Match the app's own widgets (e.g. `RegexTextHighlight.text`) instead of guessing at Flutter's render tree.
- **Keyboard focus:** tapping a `ListTile` doesn't give it keyboard focus. For a bare-letter shortcut after selecting a row, call `Focus.of(tester.element(rowFinder)).requestFocus()`.
- **Nak:** Nak causes a real redelivery, so a second row with the same payload can appear. New deliveries insert at index 0, so prefer `.last` to re-locate the row you acted on.
- **Tests that don't fit the loop:**
  - `macos_file_picker_sandbox_test.dart` runs only in CI's `test-macos` job. That job has no Docker, so it uses Homebrew's `nats-server`. It drives real Open/Save panels under the App Sandbox through `scripts/ci/drive_macos_file_panel.applescript`, and checks that a read outside the container is denied. The job also runs a couple of regular integration tests on macOS as a smoke check.
  - `screenshot_tour_test.dart` is driven by `scripts/capture_screenshots.ps1`; don't run it directly. See `scripts/README.md`.

## Update notifications (manual)

`test/update_checker_test.dart` covers the logic against a mocked `http.Client`. The popover itself calls the real GitHub API. To see it, temporarily lower `pubspec.yaml`'s `version:` below the latest release. Then run a throwaway integration test that calls `app.main()` and `pumpUntil` finds `'Update available'`. Delete the file and **restore the version** afterwards, or the shipped build will nag about updates that don't exist. For the negative path, set the version to the latest tag and confirm no popover appears.
