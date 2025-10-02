# NATS Client (v%APP_VERSION%)
This NATS client is a cross-platform client intended for use with NATS servers. This client supports WebSocket and TCP NATS connection schemes, including TLS and Mutual TLS connections.

This client supports Windows, macOS and Web platforms.

# Theme
The application has two themes, **light** and **dark**. The theme may be changed by using the 💡 toggle. The last-used theme is persisted between application runs.

# Settings
The application provides a settings dialog (⚙️ button in the toolbar) with the following options:

- **Message Font Size**: Adjusts the font size of messages in the message list.
- **Single Line Messages**: If enabled, each message in the list is displayed on a single line (with ellipsis for overflow). If disabled, messages can span multiple lines (up to 5 lines).
- **Reconnect Interval**: Controls the amount of time between reconnection attempts.

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

## Connection Status
The connection status is shown on the bottom right of the application in the status bar at all times.

All connection definition entry widgets are disabled when a connection is active. You must disconnect the active connection to edit the connection details.

If a connection is lost or unavailable at request time, the client will indefinitely attempt reconnection on a short interval. To stop reconnecting, simply select the Disconnect button.

# Message List
Incoming messages are displayed as they arrive in the message list. The list is in newest to oldest order (newest on top).

Each message has the following information/options:

- The data of the message is displayed (clipped after 5 vertical lines, or 1 line if single-line mode is enabled in settings).
- On the right, in a "chip" widget is the subject of the message
- On the right, a 3 dot menu button is available, with the following options:

    - **Copy**: Copies the message data to the clipboard
    - **Detail**: If the message is JSON based, opens a dialog and displays a formatted view. Otherwise, the dialog will just show the original content.
    - **Replay**: Re-sends the message exactly as defined, with the same subject and data.
    - **Edit & Send** - Opens a dialog pre-filled with the message's subject and data, allowing you to edit prior to sending again.
    - **Reply To** - If the selected message has a replyTo subject defined, this option opens a send message box where the subject is pre-filled with the replyTo subject.

# Keyboard Shortcuts

## Global Shortcuts
These shortcuts work from anywhere in the application:

- **`Ctrl + F`** (Windows/Linux) or **`Cmd + F`** (Mac) - Focus the Find text field
- **`Ctrl + Shift + F`** (Windows/Linux) or **`Cmd + Shift + F`** (Mac) - Focus the Filter text field

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
- **Send Message**: Opens a dialog with subject and data fields, allowing the user to send a custom message.
- **Filter**: This field filters the message list upon each character typed in the box. The filter operation is a **case-insensitive contains** on the message data only.
- **Find**: This field will highlight results found in the message data. Searches all items and highlights matches within the list.

# Status Bar
The status bar displays relevant information about the application, and also the current connection status. The bar will be **green** when the connection is active, and **grey** all other times.

The bar also shows:

- **Message Count**: Displays the total number of messages currently in the list, as well as how many are displaying (if a filter is applied).
- **URL**: The current fully-qualified URL being used. If the 🔒 icon appears, it means the connection is using TLS.
- **Status**: Current connection status.