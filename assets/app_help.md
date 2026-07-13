# NATS Client (v%APP_VERSION%)
This NATS client is a cross-platform client intended for use with NATS servers. This client supports WebSocket and TCP NATS connection schemes, including TLS and Mutual TLS connections.

This client supports Windows, macOS and Web platforms.

# Theme
The application has two themes, **light** and **dark**. The theme may be changed by using the 💡 toggle. The last-used theme is persisted between application runs.

# Settings
The application provides a settings dialog (⚙️ button in the toolbar) with the following options:

- **Message Font Size**: Adjusts the font size of messages in the message list.
- **Reconnect Interval**: Controls the amount of time between reconnection attempts.
- **Enable JetStream**: Shows or hides the JetStream tab (see below). On by default; turning it off doesn't affect your connection or the Live Messages tab, it just hides the JetStream UI for users who don't need it.
- **Enable Key-Value Stores**: Shows or hides the Key-Value Stores tab (see below). On by default; same "just hides the UI" behavior as the JetStream toggle.
- **Enable Object Store**: Shows or hides the Object Store tab (see below). On by default; same "just hides the UI" behavior as the JetStream toggle.
- **Check for Updates**: Controls whether the app checks GitHub for a newer release on startup (see Update Notifications below). On by default.

# Connection
## Schemes
The following schemes are supported:

- **nats://** - Plain TCP socket. This scheme will auto-adjust to TLS if the server requires it. See TLS Notes below.
- **ws://** - WebSocket variant, see note below

**NOTE:** The `ws://` scheme **requires WebSocket to be enabled on your NATS server instance.** By default, NATS server does not enable WebSocket support. You must manually configure the server instance to open WS on the port of your choosing.

Additionally, the `nats://` scheme is unavailable when this client is running in a browser. This is because browsers do not support TCP sockets, and thus we cannot use the normal NATS connection scheme. For browsers, we only can use WebSocket connections, which requires enabling the server-side support in the above note.

## Other Connection Info
The rest of the connection information is straightforward:

- **Host**: IP or DNS address of the NATS server host
- **Port**: Associated NATS port
- **Subjects**: The desired subjects you'd like to subscribe to. This allows a comma-separated list of subjects to be defined, ie `test.*, test.*.*`.

Each time the Connect button is pressed, the current connection information is persisted and remembered for the next time the application runs.

## TLS Notes
When the **nats://** scheme is used, the application will automatically attempt a TLS connection (including Mutual TLS) when the server requires it. By default, the security context falls back on the host OS for certificates. However, this behavior can be customized using the 🔒 button next to the scheme selection box.

The Security Settings dialog allows the user to specify the certificates and keys used to establish the connection with the server. At this time, only files of PEM type are supported. The following settings are available:

- **Trusted Certificate**: Path to a PEM file containing X509 certificates, usually root certificates from certificate authorities.
- **Certificate Chain**: Path to a PEM file containing X509 certificates, starting with the root authority and intermediate authorities forming the signed chain to the server certificate, and ending with the server certificate. The private key for this certificate is set with **Private Key** setting.
- **Private Key**: Path to a PEM file containing an encrypted private key.

## Authentication
Beyond TLS/mTLS, the Security Settings dialog (🔒 button) also has an **Authentication** section for the application-level auth mechanisms NATS servers commonly require. Pick a **Method** from the dropdown; only the fields relevant to that method are shown:

- **None**: No application-level credentials are sent (default).
- **Username & Password**: Sends the given username and password as part of the connection handshake.
- **Token**: Sends a single bearer token as part of the connection handshake.
- **NKey Seed**: Sends the public key derived from the given `SU...` seed; the client signs the server's nonce challenge automatically. The seed field is obscured like a password, with a 👁 toggle to reveal it.
- **Credentials File (.creds)**: Loads a decentralized JWT + NKey `.creds` file (the format used by NGS/Synadia Cloud and self-hosted operator-mode NATS) via the same **Browse** pattern used for the certificate fields above.

These are real secrets, so unlike the connection fields and certificate paths above (which are always remembered), they are **not persisted by default**. Check **Remember credentials on this device** to save them (stored locally, not encrypted); leave it unchecked to re-enter them each time the application starts.

If the server rejects your credentials, the status bar and a notification will say "Authentication failed — check your credentials" rather than the generic connection-failure message.

## Connection Status
The connection status is shown on the bottom right of the application in the status bar at all times.

All connection definition entry widgets are disabled when a connection is active. You must disconnect the active connection to edit the connection details.

If a connection is lost or unavailable at request time, the client will indefinitely attempt reconnection on a short interval. To stop reconnecting, simply select the Disconnect button.

# Message List
Incoming messages are displayed as they arrive in the message list. The list is in newest to oldest order (newest on top).

Each message has the following information/options:

- The data of the message is displayed on a single line, clipped with an ellipsis if it doesn't fit.
- On the right, in a "chip" widget is the subject of the message
- On the right, a 3 dot menu button is available, with the following options:

    - **Copy**: Copies the message data to the clipboard
    - **Detail**: If the message is JSON based, opens a dialog and displays a formatted view. Otherwise, the dialog will just show the original content.
    - **Replay**: Re-sends the message exactly as defined, with the same subject and data.
    - **Edit & Send** - Opens a dialog pre-filled with the message's subject and data, allowing you to edit prior to sending again.
    - **Reply To** - If the selected message has a replyTo subject defined, this option opens a send message box where the subject is pre-filled with the replyTo subject.

# JetStream
When **Enable JetStream** is on (the default) and you're connected to a server or account with JetStream enabled, a **JetStream** tab appears alongside **Live Messages**. It's a monitoring and management dashboard for streams and consumers.

## Streams
The left-hand pane lists all streams on the account. Selecting a stream shows its subjects, storage type, retention policy, and message/byte counts on the right.

- **Add Stream**: Opens a dialog to create a new stream (name, comma-separated subjects, optional max age in days, and replica count).
- **Browse Messages**: Opens a live tail of the selected stream's contents. This uses a temporary, auto-cleaning consumer under the hood — no manual consumer setup required just to look at what's in a stream. Disabled when the stream has no messages yet. Includes its own Filter/Find fields, a Pause/Resume toggle, and a Clear button, working the same way as their Live Messages tab counterparts described below.
- **Purge**: Deletes all messages in the stream but keeps the stream and its consumers. Asks for confirmation first.
- **Delete Stream**: Permanently deletes the stream, its messages, and its consumers. Asks for confirmation first.

## Consumers
Each stream's consumers are listed below its details. Tapping a consumer opens a detail dialog (type, ack policy, deliver policy, pending/redelivered counts) with **Delete** and **Tail** actions.

- **Create Consumer**: Opens a dialog to create a new consumer on the selected stream — durable name (leave blank for an ephemeral consumer), optional filter subject, push (with a deliver subject) or pull, ack policy, and deliver policy.
- **Delete**: Removes the consumer. Asks for confirmation first. Only available for named (non-ephemeral) consumers.
- **Tail**: Opens a live view of messages delivered to that specific consumer. If the consumer's ack policy is `explicit`, each message gets **Ack**, **Nak** (redeliver), and **Term** (stop redelivery) buttons; once you act on a message, its buttons disable. Consumers with any other ack policy show the same messages with those buttons disabled, since the server isn't expecting acks for them.

## Publishing into a stream
The regular **Send Message** dialog (see Tools, below) gets a **Publish via JetStream (get delivery ack)** checkbox whenever JetStream is available and connected. Checking it publishes through JetStream instead of a plain core NATS publish, and shows the stream name and assigned sequence number once the server acknowledges it.

# Key-Value Stores
When **Enable Key-Value Stores** is on (the default) and you're connected to a server or account with JetStream enabled (KV buckets are themselves backed by JetStream streams), a **Key-Value Stores** tab appears. It's a monitoring and management dashboard for KV buckets and their keys.

## Buckets
The left-hand pane lists all KV buckets on the account. Selecting a bucket shows its keys on the right, with live search.

- **Create Bucket**: Opens a dialog to create a new bucket — name, history depth (how many past revisions are kept per key), optional TTL in days, and replica count.
- **Delete** (trash icon on each bucket row): Permanently deletes the bucket and all of its keys. Asks for confirmation first.

## Keys
Once a bucket is selected, its keys are listed with their current value, revision number, and last-updated time. The list updates live as keys change, including changes made by other clients.

- **Search Keys**: Narrows the list to keys whose name contains the search text (case-insensitive).
- **Put Value**: Opens a dialog to create a new key with a text/JSON value.
- Each key's 3-dot menu (or tapping the row) offers:
    - **Edit**: Opens the same dialog pre-filled with the key's current value, using an optimistic-concurrency check — if the key changed since it was loaded, the save is rejected rather than silently overwriting someone else's change.
    - **History**: Shows every past revision of the key (value and operation), newest first.
    - **Delete**: Adds a deletion tombstone. Past revisions are kept and still visible in History. Asks for confirmation first.
    - **Purge**: Permanently removes all history for the key, not just the current value. Asks for confirmation first.

# Object Store
When **Enable Object Store** is on (the default) and you're connected to a server or account with JetStream enabled (Object Store buckets are themselves backed by JetStream streams), an **Object Store** tab appears. It's a monitoring and management dashboard for Object Store buckets and the objects (blobs/files) inside them.

**Object Store is an `EXPERIMENTAL` feature of the underlying NATS client library** — its behavior may change in a future release of this app as the library evolves. Unlike Key-Value Stores, it also has no live-update mechanism: the object list is a point-in-time snapshot, so use **Refresh** to see objects uploaded by other clients.

## Buckets
The left-hand pane lists all Object Store buckets on the account. Selecting a bucket shows its objects on the right, with live search.

- **Create Bucket**: Opens a dialog to create a new bucket — name, storage type (File or Memory), optional max size in MB, optional TTL in days, and replica count.
- **Delete** (trash icon on each bucket row): Permanently deletes the bucket and all of its objects. Asks for confirmation first.

## Objects
Once a bucket is selected, its objects are listed with their size, chunk count, a shortened SHA-256 digest, and last-modified time.

- **Search Objects**: Narrows the list to objects whose name contains the search text (case-insensitive).
- **Refresh**: Reloads the object list from the server — there's no live watch for Object Store, so this is the only way to see objects uploaded by other clients.
- **Upload**: Opens your OS's file picker; the selected file is uploaded under its original filename, overwriting any existing object with that name.
- Each object row offers:
    - **Download**: Opens your OS's save-file dialog and writes the downloaded bytes there, after the client verifies the object's SHA-256 digest.
    - **Delete**: Permanently deletes the object. Asks for confirmation first.

# Keyboard Shortcuts

## Global Shortcuts
These shortcuts work from anywhere in the application, targeting whichever message list is currently showing — the Live Messages tab, or the JetStream Browse Messages view if that's what's open:

- **`Ctrl + F`** (Windows/Linux) or **`Cmd + F`** (Mac) - Focus the Find text field
- **`Ctrl + Shift + F`** (Windows/Linux) or **`Cmd + Shift + F`** (Mac) - Focus the Filter text field

## Connection Bar Shortcuts
While focus is in the Host, Port, or Subjects field and the client isn't already connected:

- **`Ctrl + Enter`** (Windows/Linux) or **`Cmd + Enter`** (Mac) - Connect

## Message-Specific Shortcuts
When a message is selected (highlighted), the following keyboard shortcuts are available:

- **`d`** - Open Detail dialog
- **`r`** - Execute Replay (re-send the message)
- **`e`** - Open Edit & Send dialog
- **`Ctrl + C`** (Windows/Linux) or **`Cmd + C`** (Mac) - Copy message content to clipboard
- **`Esc`** - Un-select the currently selected message

## Send Message Dialog Shortcuts
When the Send Message dialog is open:

- **`Ctrl + Enter`** (Windows/Linux) or **`Cmd + Enter`** (Mac) - Send the message

# Tools
At the bottom of the window are several tools:

- **Clear**: Removes all current messages from the view. This is a permanent operation.
- **Pause**: Freezes the on-screen list — no new rows appear — while the connection stays open and messages keep arriving in the background. The button shows a small count of how many arrived while paused (e.g. `12`, `1.1k`); pressing it again (now labeled **Resume**) reveals everything that came in.
- **Send Message**: Opens a dialog with subject and data fields, allowing the user to send a custom message.
- **Filter**: This field filters the message list upon each character typed in the box. The filter operation is a **case-insensitive contains** on the message data only.
- **Find**: This field will highlight results found in the message data. Searches all items and highlights matches within the list.

# Status Bar
The status bar displays relevant information about the application, and also the current connection status. The bar will be **green** when the connection is active, and **grey** all other times.

The bar also shows:

- **Message Count**: Displays the total number of messages currently in the list, as well as how many are displaying (if a filter is applied).
- **URL**: The current fully-qualified URL being used. If the 🔒 icon appears, it means the connection is using TLS.
- **Status**: Current connection status.

# Update Notifications
This app is only distributed through GitHub Releases — there's no app-store or in-place auto-update mechanism. To help you know when a new version is out, the app checks GitHub's Releases API once on startup (a single anonymous request; no data about you or your connections is sent).

If a newer version than the one you're running has been published, a small popover appears in the top-right corner with a **View Release** button that opens the release page in your browser, and an **X** to dismiss it for the rest of the session. Nothing downloads or installs automatically — you still grab the new build from GitHub yourself, same as always.

This check can be turned off entirely via the **Check for Updates** toggle in Settings.