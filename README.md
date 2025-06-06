# <img src="./assets/app_launcher_icon.svg" width="36" height="36" alt="NATS Client Logo" style="vertical-align: text-bottom"> NATS Client UI
This NATS client is a cross-platform desktop & web application written in Flutter. The client allows users to easily watch & manage NATS messages.

# Platforms
This application currently supports Windows, Linux, macOS and Web platforms. 

# Main Features
- Connect to a single NATS server using either plain (`nats://`) or WebSocket (`ws://`) schemes
- TLS connection support with optional custom certificates
- Subscribe to multiple subjects
- Automatic re-connect upon lost connection
- Filter received messages
- Find text in received messages
- Send custom messages
- See message details, such as headers, subject and payload. JSON payloads are automatically formatted and syntax highlighted as well!
- Light and Dark themes
- Most recent connection information & theme are persisted between app runs
- Message view settings

# Screenshots
<br/>

![Message View](./images/Messages.png)

<br/>

![Filter & Sort](./images/Filter%20and%20Sort.png)

<br/>

![Message View](./images/Message%20Detail.png)

# Application Usage
See the [help documentation](./assets/app_help.md) for more details on how to use the application.

# Docker
This application is also available via [Docker Hub](https://hub.docker.com/repository/docker/nverbeek/nats-client-flutter). Please note that running the application in Docker means you're running the web flavor. Only the `ws://` scheme is available in the browser as explained in the [help documentation](./assets/app_help.md). Be sure to enable WebSocket support on your target NATS server if you intend to use the Docker version.

To install and run via Docker:
```
docker run -d -p 8080:80 --name nats-client nverbeek/nats-client-flutter
```

You may then access the application in your favorite browser at http://localhost:8080.

# Building
To build NATS Client UI, you must first [install Flutter](https://docs.flutter.dev/get-started/install) for your platform, [and get an editor](https://docs.flutter.dev/get-started/editor). I highly recommend Android Studio for building, but VS Code is a great second option.

Both Android Studio and VS Code, when setup properly, will automatically offer devices to run this application on and debug.

To build a release, use the following command for your target platform:

```
flutter build windows
flutter build macos
flutter build linux
flutter build web
```

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
