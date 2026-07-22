# Privacy Policy

**Last updated: 2026-07-21**

NATS Client ("the app") is a desktop client for connecting to NATS
messaging servers. This policy explains what data the app handles and,
just as importantly, what it does not.

## Data you provide

When you connect to a NATS server, the app uses the host, port, and any
credentials (username/password, token, NKey seed, or `.creds` file) you
enter solely to establish that connection. This information is sent only
to the server you specify — it is never sent to the app's developer or
any third party.

Connection details and app settings (e.g. recent servers, UI preferences)
are stored locally on your device and are never transmitted anywhere.

## Message and server data

Messages you publish, subscribe to, or browse (including via JetStream,
Key/Value, and Object Store) are exchanged directly between the app and
the NATS server you connect to. The app does not copy, log, or transmit
this data to any server operated by the developer.

## Network requests made by the app itself

The only network request the app makes that is *not* to a server you
configured is a check against GitHub's public API
(`api.github.com/repos/nverbeek/nats_client_flutter/releases/latest`) to
see whether a newer version is available. This request contains no
personal or usage data — it is a plain, unauthenticated GET request, and
its result only affects whether an "update available" notice is shown.

## What the app does not do

- No analytics, telemetry, or usage tracking.
- No crash reporting or error reporting service.
- No user accounts, sign-in, or advertising identifiers.
- No data is sold, shared, or monetized in any way.

## Changes to this policy

If this policy changes, the "Last updated" date above will change and the
new version will be published at the same location.

