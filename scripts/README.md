# Scripts

| Script | Purpose |
|---|---|
| `message_pub.ps1` | Publishes a few embedded sample JSON payloads (`animal.*`, `car.*`) via `nats pub`, for poking at Live Messages |
| `jetstream_demo.ps1` | Creates demo streams (`orders`, `telemetry`) and loops `nats pub`; `-Iterations N` for a finite run |
| `kv_demo.ps1` | Seeds a demo KV bucket (`app-config`) |
| `object_store_demo.ps1` + `seed_object_store.dart` | Seeds a demo Object Store bucket (`documents`) |
| `capture_screenshots.ps1` + `_image_processing.ps1` | Regenerates the README screenshots in `images/` |
| `generate_icons.js` (`npm run generate`) | Regenerates every platform's launcher icon from `assets/app_launcher_icon.svg` |
| `ci/` | CI-only: macOS signing/notarization, Homebrew cask, macOS file-panel driver (see `RELEASING.md`) |

The demo seeders and `capture_screenshots.ps1` need **`pwsh` (PowerShell 7+), not Windows PowerShell 5.1**. 5.1 prepends a UTF-8 BOM when piping to a native process's stdin, which corrupts the JSON payloads. Their `#Requires -PSEdition Core` line makes that fail loudly. The demo seeders need the `nats` CLI on `PATH` and a JetStream-enabled server (see `integration_test/README.md`).

`object_store_demo.ps1` seeds through `dart_nats`'s `ObjectStore.put()` rather than `nats object put`. The CLI leaves `mtime` at Go's zero time, which the app would show as "739807d ago". Uploads through the app are unaffected.

## Screenshots

```powershell
pwsh ./scripts/capture_screenshots.ps1
```

Needs `flutter`, `dart`, `docker`, the `nats` CLI and ImageMagick (`magick`) on `PATH`. Windows only, because the capture uses Win32 `PrintWindow`.

A window screenshot with its title bar has to come from another process. So this script and `integration_test/screenshot_tour_test.dart` cooperate through files under `build/.screenshot_signals/`; the script's header comment explains the handshake. The script starts a disposable JetStream server, or reuses whatever is on port 4222, and seeds it with all three demo scripts. It then runs the tour test, captures each screen it reaches, and overwrites `images/<name>.png` with the cropped, rounded result.

To add a screen, call `signaler.capture(tester, 'Some Name')` in the tour test once the screen settles, and reference `./images/Some%20Name.png` from the README. If the screen needs its own demo data, add a seed step to the script's "Seeding..." block.

## Icons

`assets/app_launcher_icon.svg` is the official NATS icon from [cncf/artwork](https://github.com/cncf/artwork) (`projects/nats/icon/color/nats-icon-color.svg`), **unmodified**. NATS's CNCF trademark guidelines forbid altered or look-alike logos, and the NATS maintainers asked for the official icon (nats-io/nats-site#1121). Don't redesign, recolor or crop it. Don't show it in the app's UI either: it appears only as the launcher icon and the Windows title bar icon.

If the official artwork changes, replace the SVG and run:

```sh
cd scripts
npm install
npm run generate
```

This writes the Android, iOS, web (including maskable), macOS, Windows (`.ico`) and Linux icons. It uses sharp + png-to-ico rather than `flutter_launcher_icons`, which can break transparency.
