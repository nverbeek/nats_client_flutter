# NATS Client UI
[![Build](https://github.com/nverbeek/nats_client_flutter/actions/workflows/build.yml/badge.svg)](https://github.com/nverbeek/nats_client_flutter/actions/workflows/build.yml)

This NATS client is a cross-platform desktop & web application written in Flutter. The client allows users to easily watch & manage NATS messages.

<a href="https://apps.microsoft.com/detail/9NVR7NHHL4FB?mode=direct">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://get.microsoft.com/images/en-us%20light.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://get.microsoft.com/images/en-us%20dark.svg">
    <img src="https://get.microsoft.com/images/en-us%20dark.svg" width="200" alt="Get it from Microsoft">
  </picture>
</a>

On macOS, install it with [Homebrew](https://brew.sh):

```sh
brew install --cask nverbeek/tap/nats-client-ui
```

# Platforms
This application currently supports Windows, Linux, macOS and Web platforms. Downloads for every platform are on the [Releases](https://github.com/nverbeek/nats_client_flutter/releases) page. The macOS DMG is signed and notarized by Apple.

# Main Features
- Connect to a single NATS server using either plain (`nats://`) or WebSocket (`ws://`) schemes
- TLS connection support with optional custom certificates
- **Authentication support**: username/password, bearer token, NKey seed, or decentralized JWT+NKey (`.creds` file) — configured in the same Security Settings dialog as TLS, with credentials remembered only if you opt in
- Subscribe to multiple subjects (optionally in a queue group), each with its own auto-assigned color shown on its chip and matching Live Messages rows, so it's easy to tell at a glance which subscription a message came from — toggle it off in Settings ("Show Subscription Colors", on by default) if you'd rather not see them
- Automatic re-connect upon lost connection
- **Connection history**: the Host field remembers up to 10 previously-used `scheme://host:port` targets, offered in a searchable dropdown as you type — pick one to fill in the scheme, host, and port at once, or delete individual entries / clear the whole history from the same dropdown. Only successful connections are remembered, so typos and unreachable hosts don't clutter the list.
- Filter received messages
- Find text in received messages
- Pause the message list to freeze it while you work, without stopping arrivals in the background. Scrolling down holds new messages too, behind a **↑ N new** button that takes you back to the top to see them
- Multi-select messages (Shift+Click, Ctrl+Click, Ctrl+Shift+Up/Down for a range or disconnected set) and copy them to the clipboard as plain text
- **Export & Replay**: bulk-export captured messages (a selection, or everything captured) to an NDJSON file — with a warning if the export is large — then **Replay** a previously exported file by publishing every message back onto the connected server, with configurable pacing (delay between messages, repeat count, delay between repeats) and a live progress banner with a Stop button
- Send custom messages, with optional headers
- See message details, such as headers, subject and payload. JSON payloads are automatically formatted and syntax highlighted, binary payloads can be viewed as hex, and protobuf payloads can be decoded without their schema (field numbers and values).
- Light and Dark themes
- Most recent connection information & theme are persisted between app runs
- **Pinned fields**: pin JSON fields (like `label` or `items[*].sku`) to show their values in columns at the start of every Live Messages and Browse Messages row, picked straight from a message with **Pin Fields…**
- **Wrapping long messages**: let long Live Messages and Browse Messages rows wrap to a set number of lines (1–20)
- Message view settings: adjustable font size (messages use a monospace font), an optional per-row arrival timestamp, an option to hide the subject chip, and a configurable cap on how many messages are kept in memory (1k–100k, or unlimited)
- **JetStream support** (optional, on by default — toggle it off in Settings if you don't need it):
  - Monitor streams and their consumers, including message/byte counts, retention, and ack/redelivery stats
  - Create, edit, purge (all, keep newest N, or up to a sequence), and delete streams; create, pause, and delete consumers (push or pull, any ack policy)
  - Browse a stream's messages live (with its own Filter/Find and Pause/Resume), or tail a specific consumer and Ack / Nak / Term individual messages
  - Publish messages with JetStream delivery acknowledgement straight from the regular Send Message dialog
- **Key-Value Stores support** (optional, on by default — toggle it off in Settings if you don't need it):
  - Browse KV buckets and their keys, with live search
  - Create and delete buckets (name, history depth, TTL, replicas)
  - Put, edit, delete, and purge keys, with optimistic-concurrency protection so a stale edit is rejected instead of silently overwriting someone else's change
  - View a key's full revision history
  - Key list updates live as changes happen — including changes made by other clients
- **Object Store support** (optional, on by default — toggle it off in Settings if you don't need it). This uses an `EXPERIMENTAL` API in the underlying NATS client library, so its behavior may change in a future release:
  - Browse Object Store buckets and their objects, with live search
  - Create and delete buckets (name, storage type, max size, TTL, replicas)
  - Upload, download, and delete objects (blobs/files) of any size — large uploads are chunked automatically, and downloads are verified against the object's SHA-256 digest
  - Object list is a snapshot refreshed on demand (no live-update mechanism, unlike Key-Value Stores)
- **Service Discovery support** (optional, **off by default** — turn it on in Settings): discovers [NATS Microservices](https://docs.nats.io/using-nats/developer/services) (the ADR-32 "Services API" convention) currently running and reachable on the account, showing each instance's endpoints and per-endpoint request/error/latency stats. Read-only/discovery-only — this app doesn't host services of its own.
- **Server monitoring** (optional, **off by default** — turn it on in Settings): a Server tab that polls the connected server's HTTP monitoring endpoint (`/varz`, `/connz`) for its identity, load, a live throughput chart and a server-sorted, paged list of client connections. Needs the server's monitoring port (`-m 8222`).
- **Update notifications** (optional, on by default): checks this repo's GitHub Releases on startup and shows a small dismissible popover with a link if a newer version is available. Nothing downloads or installs automatically; it just tells you a new build exists. Microsoft Store installs skip this check, since the Store handles their updates. Homebrew users can also run `brew upgrade`.

# Screenshots

![Message View](./images/Messages.png)
![Filter & Sort](./images/Filter%20and%20Sort.png)
![Message View](./images/Message%20Detail.png)
![JetStream Dashboard](./images/JetStream.png)
![Key-Value Stores](./images/Key-Value%20Stores.png)
![Object Store](./images/Object%20Store.png)
![Server Monitoring](./images/Server.png)

These are generated automatically — see `scripts/capture_screenshots.ps1` if you're regenerating them after a UI change.

# Application Usage
See the [help documentation](./assets/app_help.md) for more details on how to use the application.

# Docker
This application is also available via [Docker Hub](https://hub.docker.com/repository/docker/nverbeek/nats-client-flutter). Running it in Docker means you're running the web flavor in your browser. Both schemes are available:

- `ws://` connects from the browser straight to the server, which needs WebSocket enabled on your NATS server.
- `nats://` connects through a small relay inside the container, which opens the TCP connection for the browser, so the server needs no WebSocket configuration. The relay handles TLS too: servers that require it, and `tls://` URLs, are verified against the publicly trusted certificate authorities.

The image is published for both `linux/amd64` and `linux/arm64`, so it runs natively on Intel/AMD and ARM machines (including Apple Silicon Macs, Windows on ARM and Raspberry Pi). To install and run via Docker:
```
docker run -d -p 8080:8080 --name nats-client nverbeek/nats-client-flutter
```

You may then access the application in your favorite browser at http://localhost:8080.

The container listens on port 8080 and doesn't run as root (it runs as uid 65532). Before 1.0.20 it listened on port 80; `-e PORT=80` brings that back if you can't change your port mapping.

With `nats://`, the host is resolved from inside the container, so `localhost` means the container itself. For a server on your machine use `host.docker.internal`; for a server in another container, put both on the same Docker network and use its container name.

## NATS contexts
If you use the [NATS CLI](https://github.com/nats-io/natscli), mount your contexts and the app can connect as any of them, with no credentials typed into the browser:
```
docker run -d -p 8080:8080 --user "$(id -u):$(id -g)" \
  -v ~/.config/nats/context:/nats-contexts:ro nverbeek/nats-client-flutter
```
> [!WARNING]
> **Anyone who can open the page can connect as your contexts**, with their permissions. The secrets never reach the browser, but the container uses them for whoever asks. Keep the page private: open it from your own machine, through `kubectl port-forward`, or behind a proxy that makes people sign in. Contexts with read-only or otherwise limited users are a good idea.

- Each `*.json` file in the directory is a context, named after its file. They appear at the top of the Host dropdown. The selected one (`NATS_CONTEXT`, else the CLI's `context.txt`, else the only context) is filled in when the page opens, so you can just press Connect.
- The container authenticates as the context: user/password, token, NKey, or a `.creds` file, or credentials in its URL (`nats://user:password@host`). It also does the context's TLS: its CA, a client certificate and key for mutual TLS, and `tls_first`. Credentials and keys stay in the container; the browser only sees each context's name, description and server.
- Files a context refers to (`.creds`, NKey seed, certificates) must be readable inside the container: either mount them at the same path, or put them next to the context files and the container finds them by file name (so give them different names).
- The NATS CLI writes these files readable only by you. `--user "$(id -u):$(id -g)"` runs the container as you, so it can read them through the mount.
- Credential files are read again for every connection, so a rotated `.creds` file (or Kubernetes Secret) is used from the next connection on, without a restart.
- The directory is watched too: a context added, changed or removed while the container runs is picked up within a few seconds, and appears in the Host dropdown the next time the page is loaded. A context that can't be used yet, such as one whose `.creds` file hasn't arrived, is retried until it can. The container logs the new list.
- A password, token, `user_jwt` or `user_seed` can also be `env://VARIABLE` or `file://path`, as with the NATS CLI. Other references (`op://`, `nsc://`) aren't supported.
- Only the app's own page can use the container, so other websites can't use it through your browser. Once contexts are loaded, the page must also be opened at `localhost`, a `*.localhost` name, or an IP address, and that applies to every `nats://` connection, including ones to a host you type in. To open the page under another name, such as behind an ingress, list it: `-e NATS_UI_ALLOWED_ORIGINS=https://nats-ui.example.com`. If contexts may be added later, list it from the start, because the rule applies as soon as the first one appears. A proxy in front must pass the browser's `Host` header through; ingress-nginx, Traefik and oauth2-proxy do by default.
- `NATS_CONTEXTS` points at a different directory than `/nats-contexts`.

For a single connection, the NATS CLI's own environment variables work without any files. They define a context named `default`:
```
docker run -d -p 8080:8080 -e NATS_URL=tls://connect.ngs.global -e NATS_CREDS=/creds/app.creds \
  -v ~/app.creds:/creds/app.creds:ro nverbeek/nats-client-flutter
```
Supported: the CLI's `NATS_URL`, `NATS_USER`, `NATS_PASSWORD`, `NATS_CREDS`, `NATS_NKEY`, `NATS_CERT`, `NATS_KEY` and `NATS_CA`, plus `NATS_TOKEN`, `NATS_JWT` and `NATS_SEED`, which only this image reads. The container logs which contexts it loaded, and why any of them can't be used.

## Kubernetes
The image runs under the restricted Pod Security Standard as is. A minimal setup, with contexts from a Secret, reached through `kubectl port-forward svc/nats-ui 8080:8080`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nats-ui-contexts
stringData:
  prod.json: |
    {"description": "Production", "url": "nats://nats.nats.svc:4222", "creds": "prod.creds"}
  prod.creds: |
    -----BEGIN NATS USER JWT-----
    ...
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nats-ui
spec:
  selector:
    matchLabels: {app: nats-ui}
  template:
    metadata:
      labels: {app: nats-ui}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        fsGroup: 65532
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: nats-ui
          image: nverbeek/nats-client-flutter
          ports: [{containerPort: 8080}]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          readinessProbe:
            httpGet: {path: /, port: 8080}
          volumeMounts:
            - {name: contexts, mountPath: /nats-contexts, readOnly: true}
      volumes:
        - name: contexts
          secret: {secretName: nats-ui-contexts, defaultMode: 0440}
---
apiVersion: v1
kind: Service
metadata:
  name: nats-ui
spec:
  selector: {app: nats-ui}
  ports: [{port: 8080}]
```
- Mount the Secret as a directory, not with `subPath`: only a directory mount picks up a rotated Secret, or a context added to it.
- `NATS_URL` and friends work from a Secret through `env`/`envFrom` as well.
- Behind an ingress: put sign-in in front of it (for example oauth2-proxy or your ingress's own auth), and with contexts set `NATS_UI_ALLOWED_ORIGINS` to the page's address. A k3d `*.localhost` host name needs no setting. The relay pings the browser every 30 seconds, so ingress idle timeouts don't drop quiet sessions.
- Under a path, such as `http://localhost/nats/`: route the prefix to the container and strip it (Traefik's StripPrefix, or ingress-nginx's `rewrite-target`). The page uses only relative URLs, so no other setting is needed. Redirect `/nats` to `/nats/`, because without the trailing slash the browser resolves those URLs from `/`.

### Contexts from other teams' namespaces
When one team deploys this UI as part of a shared platform and other teams add their own NATS servers later, those teams can't edit the UI's configuration. They can still publish a context for it. A sidecar such as [k8s-sidecar](https://github.com/kiwigrid/k8s-sidecar) (the one Grafana uses for dashboards) copies every labelled Secret into the contexts directory, and the container picks each one up while it runs:
```yaml
# In the UI's Deployment: share an emptyDir between the sidecar and the UI.
      containers:
        - name: nats-ui
          # ...as above, with this mount instead of the Secret volume:
          volumeMounts:
            - {name: contexts, mountPath: /nats-contexts, readOnly: true}
        - name: contexts
          image: quay.io/kiwigrid/k8s-sidecar  # pin a release
          env:
            - {name: LABEL, value: nats-ui/context}
            - {name: LABEL_VALUE, value: "true"}
            - {name: RESOURCE, value: secret}
            - {name: NAMESPACE, value: "team-a,team-b"}
            - {name: FOLDER, value: /nats-contexts}
          volumeMounts:
            - {name: contexts, mountPath: /nats-contexts}
      volumes:
        - {name: contexts, emptyDir: {}}
---
# In a team's own chart:
apiVersion: v1
kind: Secret
metadata:
  name: team-a-nats-ui-context
  namespace: team-a
  labels: {nats-ui/context: "true"}
stringData:
  team-a.json: |
    {"description": "Team A", "url": "nats://nats.team-a.svc:4222", "creds": "team-a.creds"}
  team-a.creds: |
    -----BEGIN NATS USER JWT-----
    ...
```
- The sidecar needs a ServiceAccount allowed to `get`, `list` and `watch` Secrets in those namespaces. Its README has the RBAC.
- Each key becomes a file, so file names must be unique across teams. Prefixing them with the team's name works.
- The files must be readable by uid 65532. With the pod's `fsGroup: 65532`, the files the sidecar writes into the emptyDir belong to that group.
- **Whoever can create a labelled Secret in a watched namespace can add a context, and a context isn't limited by `NATS_TCP_ALLOWED_HOSTS`.** List the namespaces you trust rather than `ALL`.

## Which servers the relay connects to
- It connects to any server that answers like a NATS server, and to every context's servers.
- `NATS_TCP_ALLOWED_HOSTS` limits the servers you can reach by typing a host. It's a comma-separated list of entries, each optionally followed by `:port`:
  - a host name or IP address: `nats-prod`, `10.0.0.5`
  - a wildcard for every name under a domain: `*.svc.cluster.local` matches `nats.team-a.svc.cluster.local`, but not `svc.cluster.local` itself
  - a CIDR range: `10.96.0.0/12`. It matches an IP address in the range, and a name that resolves into it. The relay then connects only to the resolved addresses inside the range, so the DNS answer it checked is the one it uses. In Kubernetes, the cluster's Service range allows every Service however its name is typed (`nats.team-a`, `nats.team-a.svc`, ...), including ones added later.
  - an IPv6 address with a port is written in brackets: `[fd00::1]:4222`
- Contexts are always allowed. The list also applies to the Server tab, which the image fetches through its own server: an entry without a port covers both ports, but an entry with a port only covers that port, so list the monitoring port too (`nats-prod:4222,nats-prod:8222`). The container logs a warning for an entry it can't read; such an entry allows nothing.
  ```
  docker run -d -p 8080:8080 -e NATS_TCP_ALLOWED_HOSTS=nats-prod,nats-dev:4222,*.nats.internal,10.96.0.0/12 nverbeek/nats-client-flutter
  ```
- In Kubernetes, the list is the app's own limit, not a network boundary. A NetworkPolicy on the UI's pod is what actually limits what the container can reach.
- `NATS_TCP_RELAY=off` turns the relay off, so only `ws://` connections work; `nats://` stays in the app's list, but connecting with it shows that it's turned off.

# Testing
This project has two test suites:

- **`test/`** — fast widget and unit tests that don't need a running NATS server (dialogs, form validation, pure logic). Run with:
  ```
  flutter test test/
  ```
- **`integration_test/`** — end-to-end tests that drive the real app against a real, locally-running `nats-server`: messaging, JetStream, Key-Value, Object Store, Services, Server monitoring, Export/Replay, and each authentication method. See [integration_test/README.md](./integration_test/README.md) for starting the servers, then run each file on its own, e.g.:
  ```
  flutter test integration_test/live_messages_test.dart -d windows
  ```

GitHub Actions runs both suites on every push and pull request, and every release build is gated on them passing.

# Building
To build NATS Client UI, you must first [install Flutter](https://docs.flutter.dev/get-started/install) for your platform, [and get an editor](https://docs.flutter.dev/get-started/editor). I highly recommend Android Studio for building, but VS Code is a great second option.

Both Android Studio and VS Code, when setup properly, will automatically offer devices to run this application on and debug.

To build a release, use the following command for your target platform:

```
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build web --release
```

## Release Artifacts
Release bundles are produced by GitHub Actions for tagged builds. The workflow publishes desktop and web artifacts for:

- Windows x64 and Windows ARM64 packages
- Linux bundles
- macOS: a signed, notarized DMG, plus a Homebrew cask in [nverbeek/homebrew-tap](https://github.com/nverbeek/homebrew-tap)
- Web builds
- Docker images

This makes it straightforward to ship the app across desktop and web targets without manually packaging each build.

## Docker Build
To build a docker version of the client, run the following command (from the root of the source code):
```
docker build -t nats-client-flutter .
```

# Contributing
I am always looking for suggestions on how to improve the NATS Client UI. If you find any bugs or have an idea for a new feature, please let me know by opening a report in the [issue tracker](https://github.com/nverbeek/nats_client_flutter/issues) on GitHub.

You may directly contribute your own code by submitting a pull request.

# License
This project is licensed under the [MIT License](./LICENSE).

# Acknowledgements
This app is powered by [dart_nats](https://github.com/dart-nats/dart-nats), the NATS client library for Dart, originally created by [chartchuo].
