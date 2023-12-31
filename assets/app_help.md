# NATS Client (v%APP_VERSION%)
This NATS client is a cross-platform client intended for use with NATS servers. This client only supports WebSocket and plain NATS connection schemes.

This client supports Windows, macOS and Web platforms.

# Theme
The application has two themes, **light** and **dark**. The theme may be changed by using the 💡 toggle. The last-used theme is persisted between application runs.

# Connection
## Schemes
The following schemes are supported:

- **nats://** - Plain TCP socket
- **ws://** - WebSocket variant, see note below

**NOTE:** The ws:// scheme **requires WebSocket to be enabled on your NATS server instance.** By default, NATS server does not enable WebSocket support. You must manually configure the server instance to open WS on the port of your choosing.

Additionally, the nats:// scheme is unavailable when this client is running in a browser. This is because browsers do not support TCP sockets, and thus we cannot use the normal NATS connection scheme. For browsers, we only can use WebSocket connections, which requires enabling the server-side support in the above note.

## Other Connection Info
The rest of the connection information is straightforward:

- **Host**: IP or DNS address of the NATS server host
- **Port**: Associated NATS port
- **Subjects**: The desired subjects you'd like to subscribe to. This allows a comma-separated list of subjects to be defined, ie `test.*, test.*.*`.

Each time the Connect button is pressed, the current connection information is persisted and remembered for the next time the application runs.

## Connection Status
The connection status is shown on the bottom right of the application in the status bar at all times.

All connection definition entry widgets are disabled when a connection is active. You must disconnect the active connection to edit the connection details.

If a connection is lost or unavailable at request time, the client will indefinitely attempt reconnection on a short interval. To stop reconnecting, simply select the Disconnect button.

# Message List
Incoming messages are displayed as they arrive in the message list. The list is in newest to oldest order (newest on top).

Each message has the following information/options:

- The data of the message is displayed (clipped after 5 vertical lines).
- On the right, in a "chip" widget is the subject of the message
- On the right, a 3 dot menu button is available, with the following options:

    - **Copy**: Copies the message data to the clipboard
    - **Detail**: If the message is JSON based, opens a dialog and displays a formatted view. Otherwise, the dialog will just show the original content.
    - **Replay**: Re-sends the message exactly as defined, with the same subject and data.
    - **Edit & Send** - Opens a dialog pre-filled with the message's subject and data, allowing you to edit prior to sending again.
    - **Reply To** - If the selected message has a replyTo subject defined, this option opens a send message box where the subject is pre-filled with the replyTo subject.

# Tools
At the bottom of the window are several tools:

- **Clear**: Removes all current messages from the view. This is a permanent operation.
- **Send Message**: Opens a dialog with subject and data fields, allowing the user to send a custom message.
- **Filter**: This field filters the message list upon each character typed in the box. The filter operation is a **case-insensitive contains** on the message data only.
- **Find**: This field will highlight results found in the message data. Searches all items and highlights matches within the list.

# Status Bar
The status bar displays relevant information about the application, and also the current connection status. The bar will be **green** when the connection is active, and **grey** all other times.

The bar also shows:

- **Message Count**: Displays the total number of messages currently in the list, as well as how many are displaying (if a filter is applied)
- **URL**: The current fully-qualified URL being used
- **Status**: Current connection status