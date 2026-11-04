# Docker image server and `nats://` relay

This is the Docker image's server, a separate Dart package with its own analysis and tests. It serves the Flutter web build and relays `nats://` for the browser. User-facing setup (contexts, Kubernetes, env vars) is in the root README's Docker section. This file covers how it works and what to keep intact when changing it.

Browsers have no TCP sockets, but NATS over WebSocket uses the same bytes as NATS over TCP. So the server relays a browser WebSocket at `nats-tcp?host=H&port=P` to the NATS server over TCP. The browser runs the NATS protocol through `dart_nats`'s ordinary `ws` path.

| File | Role |
|---|---|
| `lib/relay.dart` | `createHandler()`/`RelayConfig`: static files, the `nats-tcp` endpoint (INFO check, TLS, CONNECT auth injection, allowlist, page-origin check), the `contexts` list, the `nats-monitor` proxy |
| `lib/context.dart` | `NatsContext`/`ContextSet`: NATS CLI contexts from a mounted dir plus the CLI's env vars; `applyAuth()` (nonce signing via dart_nats `Nkeys`) |
| `bin/server.dart` | Entry point. Env: `PORT`, `WEB_ROOT`, `NATS_TCP_RELAY`, `NATS_TCP_ALLOWED_HOSTS`, `NATS_UI_ALLOWED_ORIGINS`, `NATS_CONTEXTS`, `NATS_CONTEXT`, `NATS_URL` & co. |
| `tool/smoke.dart` | CI smoke test of a running image against a real nats-server |
| `../../lib/tcp_relay.dart` | The app side: `tcpRelayAvailable`, `tcpRelayUri()`/`tcpRelayContextUri()`, `tcpRelayRefusalReason()`, `fetchRelayContexts()` |

## App side

- **Docker-only.** The Dockerfile builds the web app with `--dart-define=NATS_TCP_RELAY=true`, which makes `tcpRelayAvailable` true and keeps `nats://` in the scheme list on web. Other web builds offer `ws://` only. `natsConnect()` swaps a web `nats://` URI for `tcpRelayUri(Uri.base, ...)`. That URI is same-origin, uses `wss` under https, and is relative to the page.
- **Sub-paths.** `web/index.html` deliberately has no `<base href>`, so don't restore the template's `$FLUTTER_BASE_HREF`. Flutter's loader and asset URLs then resolve against the page, so one image works at `/` and behind a prefix-stripping proxy at e.g. `/nats/`. This relies on the default hash URL strategy; `usePathUrlStrategy()` would need a base tag again. Keep any new URL the app fetches relative to `Uri.base`.
- **Contexts.** `_loadRelayContexts()` fetches the list and preselects the selected context (`NATS_CONTEXT`, else `context.txt`, else the only one). Contexts are `ConnectionHistoryEntry`s with a runtime-only `contextName`, listed above the history in the Host dropdown. Editing scheme/host/port clears the selection (`_dropRelayContextIfChanged`). With a context selected, `natsConnect()` uses `tcpRelayContextUri`, skips the page's own auth, and doesn't record history.
- **Clusters.** Relayed connections pass `ignoreDiscoveredServers: true`. A cluster's advertised `connect_urls` are TCP addresses the browser would otherwise try directly.
- **Refusals.** A refusal is sent as `-ERR 'NATS TCP relay: <reason>'`. `dart_nats` passes it to `onError`, and `natsConnect()` shows it on a first connect (`tcpRelayRefusalReason()`). After a successful connect it keeps retrying. The marker string is duplicated in `lib/tcp_relay.dart` and `lib/relay.dart`, so keep the two in sync.

## Guardrails

- **Not a general TCP proxy.** A target whose first line isn't `INFO ` is refused.
- **Host allowlist.** `NATS_TCP_ALLOWED_HOSTS` is optional; empty means any NATS server (`RelayConfig.allows`). Connecting *as* a context is always allowed. Loading contexts deliberately doesn't narrow the allowlist. The credentials only ever go to a context's own servers either way, and users expect to reach anything they have credentials for.
- **Which page may use it** (`RelayConfig.pageRefusal`, for both `nats-tcp` and `contexts`):
  - A browser's `Origin` must be the relay's own page (`Host`, or a proxy's `X-Forwarded-Host`) or be listed in `NATS_UI_ALLOWED_ORIGINS`.
  - A missing `Origin` means a non-browser client. `Origin: null` (sandboxed iframes, local files) is always refused and can't be listed.
  - With contexts loaded, the `Host` name must also be `localhost`, `*.localhost`, an IP literal, or a listed origin's host. This guards against DNS rebinding. The check uses `Host` alone, never `X-Forwarded-Host`, because a same-origin `fetch` may set the latter. A proxy in front must preserve `Host`.
  - The check runs after the WebSocket upgrade and refuses with `-ERR`, not a 403, so the app can show why. `contexts` answers 403 `{"error"}`, which the app shows as a SnackBar.
- **Input limits.** The browser may send at most 64 KiB before the server answers. The first `CONNECT` line must be under 64 KiB and valid UTF-8 (`_maxBrowserBuffer`). Query values in logs and refusals go through `_printable`.
- **Keepalive.** The relay pings the browser every 30 s (`RelayConfig.pingInterval`) so ingress idle timeouts don't drop quiet sessions. Log lines name the client (`X-Forwarded-For`, else the peer).
- **Monitoring proxy** (`nats-monitor?path=varz|connz|healthz|gatewayz&host=H|context=C&port=P`, `_monitorHandler`), for the app's Server tab when the browser can't reach a server's monitoring port itself (a host only the container resolves, a context, an https page). It has the same page check and allowlist as `nats-tcp`; a context fetches from its own servers. Only those four paths and `/connz`'s `sort`/`offset`/`limit` are forwarded (`limit` capped at 100), redirects aren't followed, and a request gets 5 s and 4 MiB. An answer is passed on only if it's JSON with a `server_id` (`status` for `/healthz`), the HTTP version of the INFO check, so the proxy can't read other web services the container reaches. Refusals are `{"error"}`: 504 for no answer, 502 for "not a monitoring endpoint", which the app's `ServerMonitorClient` maps to its own error kinds. Targets are asked over http; one whose answer is Go's "Client sent an HTTP request to an HTTPS server" (`https_port`, e.g. demo.nats.io) is asked again over https and remembered by `host:port` (up to 256). https trusts the system roots, plus a context's CA and client certificate (`NatsContext.securityContext()`). The path constant is duplicated in `lib/tcp_relay.dart` (`tcpRelayMonitorPath`).
- **`NATS_TCP_RELAY=off`** refuses every relay connection with a reason instead of dropping the endpoint. `nats://` is in the scheme list at compile time, so a missing endpoint would leave the app retrying with no explanation.

## TLS

The browser can't run TLS inside the WebSocket, so the relay does it (`_Relay._open`). After a plain INFO, it upgrades in place with `SecureSocket.secure` when INFO says `tls_required`, the URL is `tls://`, or the context names TLS files. With the context's `tls_first`, it connects TLS-first. Trust is the system roots (the `scratch` image gets `/etc/ssl/certs` from the Dart runtime) plus the context's `ca`, and `cert`/`key` give mTLS. INFO is forwarded unchanged, so `tls_required` still drives the app's lock icon. `dart_nats`'s `ws` path never attempts its own upgrade.

## Contexts (`lib/context.dart`)

- Every `*.json` in `/nats-contexts` (or `NATS_CONTEXTS`) is a NATS CLI context named by its file. `NATS_URL` & co. add one named `default`. The CLI reads `NATS_URL/USER/PASSWORD/CREDS/NKEY/CERT/KEY/CA`; `NATS_TOKEN/JWT/SEED` are this image's own.
- A file a context names (creds, nkey, cert, key, ca) is found at its path (`~` expanded, `file://` stripped) or by file name next to the contexts. A context made on another machine therefore works when its files are dropped beside it.
- `password`/`token`/`user_jwt`/`user_seed` may be `env://VAR` or `file://path`, like jsm.go's `resolveLiteral`. Other schemes make the context unusable. Credentials in the URL (`user:pass@`, `token@`) apply when the context has none of its own, and never appear in `ContextServer.toString()`.
- **Keep secrets and paths out of the browser and logs.**
  - Problems found at load (a missing file, a JWT without a seed, a bad PEM) make the context unusable. The reason names files but not paths, because `NatsContext.error` reaches the browser. Paths and OS errors go only to the startup log.
  - A JSON parse failure logs only its position, because `FormatException.toString()` quotes the failing line, which can hold a password.
  - `GET contexts` lists name/description/server/selected/error, never secrets.
- `nats-tcp?context=NAME` calls `resolveAuth()`, which re-reads the credential files (`NatsContext.files`) so a rotated Secret is used on the next connect. It connects to the context's servers in order. `_ConnectRewriter` then replaces the auth in the browser's first `CONNECT` with the context's (user/pass, token, or jwt/nkey plus the signed nonce).
- Unsupported, and logged as such: nsc lookups, SOCKS proxies, JetStream domains/prefixes, the Windows cert store.

## Image

- **User and port.** The image runs as uid 65532 on port 8080, for Kubernetes' restricted Pod Security Standard. `USER` is numeric because `scratch` has no `/etc/passwd`. Mounted files must be readable by that user. The server binds IPv6 (dual-stack) and falls back to IPv4.
- **Multi-arch** (`linux/amd64` + `linux/arm64`). Only the relay binary and its runtime libraries differ per architecture. The Flutter and relay build stages run on `$BUILDPLATFORM`, and `dart compile exe --target-arch` cross-compiles the relay, so no stage runs under emulation. Keep any new `RUN` step in a `$BUILDPLATFORM` stage, or the build will need QEMU.

## Tests

- `dart test` here uses fake TCP servers, so no NATS server is needed. The TLS tests skip if `openssl` isn't on `PATH`. App-side tests: `test/tcp_relay_test.dart` and `test/relay_context_host_field_test.dart`.
- CI's `build-docker` job builds each architecture and smoke-tests both with `tool/smoke.dart` (arm64 runs under QEMU there). The smoke tests cover: by host against a real `nats` service; as a `default` context from `NATS_URL`; as a mounted context for each of the four auth fixtures; and a foreign `--origin`, which must be refused. Only then does the job push the multi-arch tag.
- mTLS (manual): run `nats:latest` with `tls { ... verify: true }` and a throwaway openssl CA, on one Docker network with the image. Mount a context naming the CA and a client cert/key, then run `dart run tool/smoke.dart <url> --context <name>`.
- Manual end-to-end:
  1. `docker network create natsnet`
  2. `docker run -d --name nats-js --network natsnet nats:latest -js`
  3. `docker run -d -p 8080:8080 --network natsnet nats-client-flutter`
  4. Open http://localhost:8080 and connect to `nats://nats-js:4222`. The host is resolved inside the container, so `localhost` won't work.
