import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'auth_manager.dart';
import 'constants.dart' as constants;
import 'format_utils.dart';
import 'jetstream_dashboard.dart';
import 'jetstream_manager.dart';
import 'kv_dashboard.dart';
import 'kv_manager.dart';
import 'message_detail_dialog.dart';
import 'object_store_dashboard.dart';
import 'object_store_manager.dart';
import 'send_message_dialog.dart';
import 'help_dialog.dart';
import 'settings_dialog.dart';
import 'security_settings_dialog.dart';
import 'subject_chips_row.dart';
import 'subscription_info.dart';
import 'subscription_manager_dialog.dart';
import 'update_checker.dart';

void main() async {
  // must wait for widgets to initialize before we are able to use SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize window manager on non-web platforms
  if (!kIsWeb) {
    await windowManager.ensureInitialized();

    // setup a reference to the shared preferences instance
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // get the window's last size and position from the last run (if applicable)
    var windowWidth = 1280.0;
    var windowHeight = 720.0;
    var lastWidth = prefs.getDouble(constants.prefLastWidth);
    var lastHeight = prefs.getDouble(constants.prefLastHeight);
    double? windowPositionX;
    double? windowPositionY;
    var lastPositionX = prefs.getDouble(constants.prefLastPositionX);
    var lastPositionY = prefs.getDouble(constants.prefLastPositionY);

    if (lastWidth != null) {
      windowWidth = lastWidth;
    }
    if (lastHeight != null) {
      windowHeight = lastHeight;
    }
    if (lastPositionX != null) {
      windowPositionX = lastPositionX;
    }
    if (lastPositionY != null) {
      windowPositionY = lastPositionY;
    }

    // set the window options (including size)
    WindowOptions windowOptions = WindowOptions(
      size: Size(windowWidth, windowHeight),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );

    // if there was a saved position, restore that
    if (windowPositionX != null && windowPositionY != null) {
      windowManager.setPosition(Offset(windowPositionX, windowPositionY));
    }

    // finally, show the window
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // setup a reference to the shared preferences instance
  SharedPreferences prefs = await SharedPreferences.getInstance();

  // attempt to read previous connection info from preferences
  String? tempScheme = prefs.getString(constants.prefScheme);
  String? tempHost = prefs.getString(constants.prefHost);
  String? tempPort = prefs.getString(constants.prefPort);
  String? tempTheme = prefs.getString(constants.prefTheme);

  // if needed, default the values
  tempScheme ??= constants.defaultScheme;
  tempHost ??= constants.defaultHost;
  tempPort ??= constants.defaultPort;
  tempTheme ??= constants.darkTheme;

  // subscriptions: prefer the new JSON list; otherwise do a one-time
  // migration of the legacy comma-delimited subject string, writing the
  // result back so this branch is only hit once.
  List<SubscriptionInfo> tempSubscriptions;
  String? subscriptionsJson = prefs.getString(constants.prefSubscriptions);
  if (subscriptionsJson != null && subscriptionsJson.isNotEmpty) {
    tempSubscriptions = decodeSubscriptionList(subscriptionsJson);
  } else {
    String? legacySubject = prefs.getString(constants.prefSubject);
    tempSubscriptions = (legacySubject != null && legacySubject.isNotEmpty)
        ? migrateFromLegacySubject(legacySubject)
        : [SubscriptionInfo(subject: constants.defaultSubject, colorIndex: 0)];
    await prefs.setString(constants.prefSubscriptions,
        encodeSubscriptionList(tempSubscriptions));
  }

  // get the application's version number
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String appVersion = packageInfo.version;

  // run the ui
  runApp(MyApp(appVersion, tempScheme, tempHost, tempPort, tempSubscriptions,
      tempTheme));
}

/// Class to handle theme changes
class ThemeModel with ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  ThemeModel(String defaultTheme) {
    // set the initial theme
    // this will be the last theme used by the user, or the default (dark)
    if (defaultTheme == constants.darkTheme) {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
    }
  }

  /// Toggles the theme between dark and light
  void toggleMode() {
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Returns [true] if the current theme is dark
  bool isDark() {
    if (_mode == ThemeMode.dark) {
      return true;
    }
    return false;
  }
}

/// Main application starting point
class MyApp extends StatelessWidget {
  const MyApp(this.appVersion, this.scheme, this.host, this.port,
      this.subscriptions, this.theme,
      {super.key});

  final String appVersion;
  final String scheme;
  final String host;
  final String port;
  final List<SubscriptionInfo> subscriptions;
  final String theme;

  /// Root UI of the entire application
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeModel>(
      create: (_) => ThemeModel(theme),
      child: Consumer<ThemeModel>(
        builder: (_, model, __) {
          // DynamicColorBuilder surfaces the platform's Material You palette
          // (Android 12+, and any other embedder that implements the dynamic
          // color platform channel) when available; lightDynamic/darkDynamic
          // are both null everywhere else (Windows/Linux/macOS/Web today),
          // in which case the existing seeded scheme is used unchanged.
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              return MaterialApp(
                title: 'NATS Client',
                debugShowCheckedModeBanner: false,
                theme: _buildThemeData(lightDynamic),
                darkTheme:
                    _buildThemeData(darkDynamic, brightness: Brightness.dark),
                themeMode: model.mode,
                home: LoaderOverlay(
                  child: MyHomePage(appVersion, 'NATS Client', scheme, host,
                      port, subscriptions),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Builds a Material 3 [ThemeData], preferring the platform's dynamic
  /// [ColorScheme] (Material You) when the embedder provides one and
  /// falling back to a scheme seeded from the app's own brand color.
  static ThemeData _buildThemeData(ColorScheme? dynamicScheme,
      {Brightness brightness = Brightness.light}) {
    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
            brightness: brightness, seedColor: Colors.lightBlue.shade900);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
    );
  }
}

/// Ctrl+Enter (Cmd+Enter on Mac) from the Host/Port/Subjects fields fires
/// Connect while disconnected — see `_withConnectShortcut` below.
class _ConnectIntent extends Intent {
  const _ConnectIntent();
}

class MyHomePage extends StatefulWidget {
  const MyHomePage(this.appVersion, this.title, this.scheme, this.host,
      this.port, this.subscriptions,
      {super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String appVersion;
  final String title;
  final String scheme;
  final String host;
  final String port;
  final List<SubscriptionInfo> subscriptions;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with WindowListener, TickerProviderStateMixin {
  String host = constants.defaultHost;
  String port = constants.defaultPort;
  List<SubscriptionInfo> subscriptions = [];
  // Message-row color indicator lookup: colorIndex captured per message at
  // arrival time (see _subscribeOne). An Expando rather than a Map so
  // entries never need manual pruning -- once a Message drops out of
  // items/filteredItems with nothing else referencing it, its entry here
  // becomes collectible too.
  final Expando<int> _messageColorIndex = Expando<int>();
  int _nextColorIndex = 0;
  var availableSchemes = <String>['ws://', 'nats://'];
  String scheme = constants.defaultScheme;
  String fullUri = '';
  int selectedIndex = -1;
  String currentFilter = '';
  String currentFind = '';
  Status currentStatus = Status.disconnected;
  bool tlsConnection = false;
  List<Message<dynamic>> filteredItems = [];
  List<Message<dynamic>> items = [];

  // Pause: while true, incoming messages are buffered here (still arriving,
  // still counted) instead of touching `items`/the rendered list at all.
  bool messagesPaused = false;
  final List<Message<dynamic>> pendingMessages = [];

  // A NATS subject can deliver far faster than the UI needs to reflect it —
  // incoming messages land here first (cheap O(1) append) and get flushed
  // into `items` at most once per `_incomingFlushInterval`, so a burst of
  // hundreds of messages costs one list mutation, not hundreds.
  final List<Message<dynamic>> _incomingBatch = [];
  Timer? _incomingFlushTimer;
  static const _incomingFlushInterval = Duration(milliseconds: 32);

  // JetStream tab
  bool jetStreamEnabled = constants.defaultJetStreamEnabled;
  late TabController _tabController;
  final GlobalKey<JetStreamDashboardState> _jetStreamDashboardKey = GlobalKey();

  // Key-Value tab
  bool kvEnabled = constants.defaultKvEnabled;
  final GlobalKey<KvDashboardState> _kvDashboardKey = GlobalKey();

  // Object Store tab
  bool objectStoreEnabled = constants.defaultObjectStoreEnabled;
  final GlobalKey<ObjectStoreDashboardState> _objectStoreDashboardKey =
      GlobalKey();

  // Add a ScrollController for the ListView
  final ScrollController _listScrollController = ScrollController();

  // Whether the "jump to top" button should be shown — true once the user
  // has scrolled away from the top of the (newest-at-top) list.
  bool _showJumpToTop = false;

  // Variables for handling single/double tap detection
  Timer? _tapTimer;
  int? _lastTappedIndex;

  // nats stuff
  late Client natsClient;
  JetStreamManager? _jetStreamManager;
  KvManager? _kvManager;
  ObjectStoreManager? _objectStoreManager;
  bool isConnected = false;
  String connectionStateString = constants.disconnected;

  var filterBoxController = TextEditingController();
  var findBoxController = TextEditingController();

  // Focus nodes for keyboard shortcuts
  final FocusNode _filterFocusNode = FocusNode();
  final FocusNode _findFocusNode = FocusNode();

  // user preferences
  late SharedPreferences prefs;
  double messageFontSize = 14.0;
  bool messageSingleLine = false;
  int retryInterval = constants.defaultRetryInterval;
  bool updateCheckEnabled = constants.defaultUpdateCheckEnabled;
  OverlayEntry? _updateOverlayEntry;

  // authentication
  AuthMethod authMethod = AuthMethod.none;
  String authUsername = '';
  String authPassword = '';
  String authToken = '';
  String authNkeySeed = '';
  Uint8List? authCredsFileBytes;
  String authCredsFileName = '';
  bool rememberCredentials = false;

  @override
  initState() {
    initializePreferences();
    filteredItems = items;
    scheme = widget.scheme;
    host = widget.host;
    port = widget.port;
    subscriptions = List<SubscriptionInfo>.from(widget.subscriptions);
    _nextColorIndex = subscriptions.length;
    updateFullUri();
    _tabController = TabController(length: _visibleTabCount, vsync: this);
    _listScrollController.addListener(_updateJumpToTopVisibility);
    super.initState();

    // add a listener for window events, such as size/position changes (desktop only)
    if (!kIsWeb) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    _updateOverlayEntry?.remove();
    if (!kIsWeb) {
      windowManager.removeListener(this);
    }
    _listScrollController.removeListener(_updateJumpToTopVisibility);
    _listScrollController.dispose(); // Dispose the controller
    _tapTimer?.cancel(); // Cancel any pending timer
    _incomingFlushTimer?.cancel();
    _filterFocusNode.dispose(); // Dispose focus nodes
    _findFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void onWindowResized() {
    if (!kIsWeb) {
      windowManager.getSize().then((windowSize) => {
            prefs.setDouble(constants.prefLastWidth, windowSize.width),
            prefs.setDouble(constants.prefLastHeight, windowSize.height)
          });
    }
  }

  @override
  void onWindowMoved() {
    if (!kIsWeb) {
      windowManager.getPosition().then((windowPosition) => {
            prefs.setDouble(constants.prefLastPositionX, windowPosition.dx),
            prefs.setDouble(constants.prefLastPositionY, windowPosition.dy),
          });
    }
  }

  /// initialize the shared preferences instance
  Future<void> initializePreferences() async {
    prefs = await SharedPreferences.getInstance();
    loadMessageSettings();
  }

  void loadMessageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      messageFontSize = prefs.getDouble('messageFontSize') ?? 14.0;
      messageSingleLine = prefs.getBool('messageSingleLine') ?? false;
      retryInterval = prefs.getInt(constants.prefRetryInterval) ??
          constants.defaultRetryInterval;
      jetStreamEnabled = prefs.getBool(constants.prefJetStreamEnabled) ??
          constants.defaultJetStreamEnabled;
      kvEnabled =
          prefs.getBool(constants.prefKvEnabled) ?? constants.defaultKvEnabled;
      objectStoreEnabled = prefs.getBool(constants.prefObjectStoreEnabled) ??
          constants.defaultObjectStoreEnabled;
      updateCheckEnabled = prefs.getBool(constants.prefUpdateCheckEnabled) ??
          constants.defaultUpdateCheckEnabled;
      loadAuthSettings(prefs);
      _ensureTabController();
    });

    if (updateCheckEnabled) {
      checkForUpdates();
    }
  }

  /// Checks GitHub for a newer published release than the running app
  /// version, and if found, surfaces a dismissible popover with a button to
  /// view it. Best-effort and silent on failure — this is a convenience
  /// notification, not something that should ever interrupt the user.
  void checkForUpdates() async {
    final release = await fetchLatestRelease();
    if (release == null || !mounted) return;
    if (!isNewerVersion(release.version, widget.appVersion)) return;

    _showUpdateAvailablePopover(release);
  }

  /// Shows a small, self-dismissing-only-on-request popover in the
  /// top-right corner announcing [release]. Uses a raw [OverlayEntry]
  /// rather than a [SnackBar]/[MaterialBanner] — both anchor to the bottom
  /// or span the full window width, which is a lot of visual weight for a
  /// one-line "there's a new version" notice with a single link.
  void _showUpdateAvailablePopover(ReleaseInfo release) {
    _updateOverlayEntry?.remove();

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        return Positioned(
          top: 16,
          right: 16,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * -12),
                child: child,
              ),
            ),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 300,
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.system_update_alt,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Update available',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text('Version ${release.version} is out.',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Transform.translate(
                              offset: const Offset(-8, 0),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  launchUrl(Uri.parse(release.htmlUrl),
                                      mode: LaunchMode.externalApplication);
                                },
                                child: const Text('View Release'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Dismiss',
                      onPressed: () {
                        entry.remove();
                        _updateOverlayEntry = null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _updateOverlayEntry = entry;
    overlay.insert(entry);
  }

  /// Loads persisted authentication settings, but only if the user
  /// previously opted in via "Remember credentials on this device" —
  /// otherwise auth fields start blank each launch.
  void loadAuthSettings(SharedPreferences prefs) {
    rememberCredentials =
        prefs.getBool(constants.prefRememberCredentials) ?? false;
    if (!rememberCredentials) return;

    final methodName = prefs.getString(constants.prefAuthMethod);
    if (methodName != null && methodName.isNotEmpty) {
      authMethod = AuthMethod.values.byName(methodName);
    }
    authUsername = prefs.getString(constants.prefAuthUsername) ?? '';
    authPassword = prefs.getString(constants.prefAuthPassword) ?? '';
    authToken = prefs.getString(constants.prefAuthToken) ?? '';
    authNkeySeed = prefs.getString(constants.prefAuthNkeySeed) ?? '';
    authCredsFileName = prefs.getString(constants.prefAuthCredsFileName) ?? '';
    final savedCredsFile = prefs.getString(constants.prefAuthCredsFile);
    if (savedCredsFile != null && savedCredsFile.isNotEmpty) {
      authCredsFileBytes =
          Uint8List.fromList(gzip.decode(base64.decode(savedCredsFile)));
    }
  }

  void saveMessageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('messageFontSize', messageFontSize);
    prefs.setBool('messageSingleLine', messageSingleLine);
    prefs.setInt(constants.prefRetryInterval, retryInterval);
    prefs.setBool(constants.prefJetStreamEnabled, jetStreamEnabled);
    prefs.setBool(constants.prefKvEnabled, kvEnabled);
    prefs.setBool(constants.prefObjectStoreEnabled, objectStoreEnabled);
    prefs.setBool(constants.prefUpdateCheckEnabled, updateCheckEnabled);
  }

  /// Handles tap logic to distinguish between single and double taps
  void _handleMessageTap(int index) {
    // Cancel any existing timer
    _tapTimer?.cancel();

    if (_lastTappedIndex == index) {
      // This is a double tap on the same item
      _lastTappedIndex = null;
      showDetailDialog(filteredItems[index]);
    } else {
      // This might be a single tap, start a timer to check
      _lastTappedIndex = index;
      _tapTimer = Timer(const Duration(milliseconds: 300), () {
        // Timer expired, this was a single tap
        setState(() {
          if (index == selectedIndex) {
            // user tapped the already-selected item.
            // un-select it
            selectedIndex = -1;
          } else {
            selectedIndex = index;
          }
        });
        _lastTappedIndex = null;
      });
    }
  }

  void _runFilter() {
    List<Message<dynamic>> results = [];
    if (currentFilter.isEmpty) {
      // if the search field is empty or only contains white-space, we'll display all items
      results = items;
    } else {
      // filter the items based on the message payload against the search term
      results = items
          .where((message) => decodeMessageText(message.byte)
              .toLowerCase()
              // we use the toLowerCase() method to make it case-insensitive
              .contains(currentFilter.toLowerCase()))
          .toList();
    }

    if (mounted) {
      setState(() {
        filteredItems = results;
      });
    }
  }

  void updateFullUri() {
    if (mounted) {
      setState(() {
        fullUri = '$scheme$host:$port';
      });
    }
  }

  /// Live Messages is always tab 0; JetStream, Key-Value, and Object Store
  /// each add one more tab, in that order, when their respective settings
  /// toggle is on.
  int get _visibleTabCount =>
      1 +
      (jetStreamEnabled ? 1 : 0) +
      (kvEnabled ? 1 : 0) +
      (objectStoreEnabled ? 1 : 0);

  /// `TabController.length` is fixed at construction, but which tabs are
  /// visible can change at runtime (the JetStream/KV/Object Store toggles in
  /// Settings).
  /// Call this any time either toggle changes so the controller always
  /// matches what's actually shown; a no-op if the count didn't change.
  void _ensureTabController() {
    final desired = _visibleTabCount;
    if (_tabController.length == desired) return;
    final oldIndex = _tabController.index;
    _tabController.dispose();
    _tabController = TabController(
      length: desired,
      vsync: this,
      initialIndex: oldIndex.clamp(0, desired - 1),
    );
  }

  /// Wraps a Host/Port/Subjects field so Ctrl+Enter (Cmd+Enter on Mac) fires
  /// Connect while focus is in it and the client isn't already connected —
  /// mirrors the same `Shortcuts`/`Actions` pattern `SendMessageDialog` uses
  /// for its own Ctrl+Enter-to-send shortcut.
  Widget _withConnectShortcut(Widget child) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const _ConnectIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
            const _ConnectIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ConnectIntent: CallbackAction<_ConnectIntent>(
            onInvoke: (_ConnectIntent intent) {
              if (currentStatus == Status.disconnected) {
                natsConnect();
              }
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }

  void natsConnect() async {
    natsClient = Client();
    // sids are only meaningful for the lifetime of one Client instance --
    // null them all out now that we've discarded the old one.
    for (final info in subscriptions) {
      info.sid = null;
    }
    _jetStreamManager = JetStreamManager(natsClient);
    _kvManager = KvManager(natsClient);
    _objectStoreManager = ObjectStoreManager(natsClient);

    // surface authentication failures distinctly from generic connection
    // failures (a bad password/token/nkey/creds file closes the connection
    // via a server -ERR, rather than throwing out of connect() below)
    natsClient.onError = (dynamic error) {
      debugPrint('NATS client error: $error');
      if (error != null && isAuthenticationError(error as Object)) {
        showSnackBar(constants.authenticationFailure);
      }
    };

    // save the user's connection properties to preferences.
    // we can read these out at startup.
    await prefs.setString(constants.prefScheme, scheme);
    await prefs.setString(constants.prefHost, host);
    await prefs.setString(constants.prefPort, port);
    await prefs.setString(
        constants.prefSubscriptions, encodeSubscriptionList(subscriptions));

    debugPrint('About to connect to $fullUri');
    try {
      Uri uri = Uri.parse(fullUri);
      natsClient.statusStream.listen((Status event) {
        debugPrint('Connection status event $event');
        currentStatus = event;
        String stateString = '';

        switch (event) {
          case Status.connected:
            setStateConnected();
            stateString = constants.connected;
            if (natsClient.info?.tlsRequired == true) {
              tlsConnection = true;
            } else {
              tlsConnection = false;
            }
            break;
          case Status.closed:
          case Status.disconnected:
            setStateDisconnected();
            currentStatus = Status.disconnected;
            stateString = constants.disconnected;
            break;
          case Status.tlsHandshake:
            stateString = constants.tlsHandshake;
            break;
          case Status.infoHandshake:
            stateString = constants.infoHandshake;
            break;
          case Status.reconnecting:
            stateString = constants.reconnecting;
            break;
          case Status.connecting:
            stateString = constants.connecting;
            break;
        }

        // Add mounted check before calling setState
        if (mounted) {
          setState(() {
            connectionStateString = stateString;
          });
        }
      });

      // subscribe to everything the user has configured; each entry already
      // has a stable colorIndex from when it was added, _subscribeOne fills
      // in its sid
      for (final info in subscriptions) {
        _subscribeOne(info);
      }

      // get the security context if applicable
      SecurityContext? securityContext = getSecurityContext();

      // apply the currently selected authentication method. Username/password,
      // token, and NKey seed all ride along in ConnectOption (NKey also
      // needs `client.seed` set so dart_nats can sign the server's nonce
      // challenge); credentials files are loaded directly on the client,
      // which derives its own jwt/sig from them.
      ConnectOption? authConnectOption = buildAuthConnectOption(
        method: authMethod,
        username: authUsername,
        password: authPassword,
        token: authToken,
        nkeySeed: authNkeySeed,
      );
      if (authMethod == AuthMethod.nkeySeed && authNkeySeed.isNotEmpty) {
        natsClient.seed = authNkeySeed;
      } else if (authMethod == AuthMethod.credentialsFile &&
          authCredsFileBytes != null) {
        natsClient.loadCredentials(utf8.decode(authCredsFileBytes!));
      }

      // finally, make the connection attempt
      await natsClient.connect(uri,
          retry: true,
          retryCount: -1,
          retryInterval: retryInterval,
          connectOption: authConnectOption,
          securityContext: securityContext as dynamic);
    } on TlsException {
      showSnackBar(constants.connectionFailure);
      setStateDisconnected();
    } on HttpException {
      showSnackBar(constants.connectionFailure);
      setStateDisconnected();
    } on Exception {
      showSnackBar(constants.connectionFailure);
      setStateDisconnected();
    } catch (_) {
      showSnackBar(constants.connectionFailure);
      setStateDisconnected();
    }
  }

  /// Creates a SecurityContext instance based on the currently configured
  /// certificates. Returns a null [SecurityContext] if no certificates
  /// are configured. Not available on web platform.
  SecurityContext? getSecurityContext() {
    // SecurityContext is not available on web platform
    if (kIsWeb) {
      return null;
    }

    // read out the certificate paths from preferences

    // trusted certificate
    var savedTrustedCertificate =
        prefs.getString(constants.prefTrustedCertificate);
    List<int>? savedTrustedCertificateBytes;
    if (savedTrustedCertificate != null && savedTrustedCertificate.isNotEmpty) {
      savedTrustedCertificateBytes =
          gzip.decode(base64.decode(savedTrustedCertificate));
    }

    // certificate chain
    var savedCertificateChain = prefs.getString(constants.prefCertificateChain);
    List<int>? savedCertificateChainBytes;
    if (savedCertificateChain != null && savedCertificateChain.isNotEmpty) {
      savedCertificateChainBytes =
          gzip.decode(base64.decode(savedCertificateChain));
    }

    // private key
    var savedPrivateKey = prefs.getString(constants.prefPrivateKey);
    List<int>? savedPrivateKeyBytes;
    if (savedPrivateKey != null && savedPrivateKey.isNotEmpty) {
      savedPrivateKeyBytes = gzip.decode(base64.decode(savedPrivateKey));
    }

    // create a new SecurityContext
    SecurityContext? securityContext = SecurityContext();
    var useSecurityContext = false;
    if (savedTrustedCertificateBytes != null) {
      securityContext.setTrustedCertificatesBytes(savedTrustedCertificateBytes);
      useSecurityContext = true;
    }
    if (savedCertificateChainBytes != null) {
      securityContext.useCertificateChainBytes(savedCertificateChainBytes);
      useSecurityContext = true;
    }
    if (savedPrivateKeyBytes != null) {
      securityContext.usePrivateKeyBytes(savedPrivateKeyBytes);
      useSecurityContext = true;
    }

    if (!useSecurityContext) {
      securityContext = null;
    }
    return securityContext;
  }

  void _subscribeOne(SubscriptionInfo info) {
    debugPrint('Subscribing to ${info.subject}'
        '${info.queueGroup != null ? ' (queue group: ${info.queueGroup})' : ''}');
    var sub = natsClient.sub(info.subject, queueGroup: info.queueGroup);
    info.sid = sub.sid;

    sub.stream.listen((event) {
      // Tag with this subscription's colorIndex at arrival time -- info.sid
      // gets nulled on every disconnect (see natsDisconnect/natsConnect), so
      // looking that up dynamically at render time would make every
      // already-received message's color indicator disappear the moment you
      // disconnect. colorIndex is stable for the subscription's lifetime, so
      // capturing it once here survives disconnects/reconnects.
      _messageColorIndex[event] = info.colorIndex;
      handleIncomingMessage(event);
    });
  }

  Future<void> _persistSubscriptions() async {
    await prefs.setString(
        constants.prefSubscriptions, encodeSubscriptionList(subscriptions));
  }

  /// Adds a new subscription, live-subscribing immediately if already
  /// connected. Used by both the chip row's "+" and the manager dialog's
  /// "Add" button.
  void _addSubscription(String subject, String? queueGroup) {
    final trimmedSubject = subject.trim();
    final normalizedQueueGroup =
        (queueGroup != null && queueGroup.trim().isNotEmpty)
            ? queueGroup.trim()
            : null;
    final alreadyExists = subscriptions.any((info) =>
        info.subject == trimmedSubject &&
        info.queueGroup == normalizedQueueGroup);
    if (alreadyExists) {
      showSnackBar('Already subscribed to $trimmedSubject');
      return;
    }

    final info = SubscriptionInfo(
      subject: trimmedSubject,
      queueGroup: normalizedQueueGroup,
      colorIndex: _nextColorIndex++,
    );
    setState(() {
      subscriptions.add(info);
    });
    _persistSubscriptions();
    if (currentStatus == Status.connected) {
      _subscribeOne(info);
    }
  }

  /// Removes a subscription, live-unsubscribing immediately if connected.
  /// This is what a chip's delete icon (x) calls directly -- no confirmation,
  /// matching how the rest of this toolbar behaves.
  void _removeSubscription(SubscriptionInfo info) {
    if (currentStatus == Status.connected && info.sid != null) {
      natsClient.unSubById(info.sid!);
    }
    setState(() {
      subscriptions.remove(info);
    });
    _persistSubscriptions();
  }

  /// Changes an existing subscription's queue group. There's no wire op to
  /// change a queue group in place, so this is an unsub+resub when connected
  /// (which produces a new sid).
  void _updateQueueGroup(SubscriptionInfo info, String? newQueueGroup) {
    final normalized =
        (newQueueGroup != null && newQueueGroup.trim().isNotEmpty)
            ? newQueueGroup.trim()
            : null;
    if (normalized == info.queueGroup) return;

    if (currentStatus == Status.connected && info.sid != null) {
      natsClient.unSubById(info.sid!);
    }
    setState(() {
      info.queueGroup = normalized;
    });
    _persistSubscriptions();
    if (currentStatus == Status.connected) {
      _subscribeOne(info);
    }
  }

  void _showEditSubscriptionDialog(SubscriptionInfo? existing) {
    showDialog<void>(
      context: context,
      builder: (context) => SubscriptionEditDialog(
        existing: existing,
        onSave: (subject, queueGroup) {
          if (existing == null) {
            _addSubscription(subject, queueGroup);
          } else {
            _updateQueueGroup(existing, queueGroup);
          }
        },
        onRemove:
            existing == null ? null : () => _removeSubscription(existing),
      ),
    );
  }

  /// Resolves the color indicator for a Live Messages row from the
  /// colorIndex captured at arrival time (see _subscribeOne). Returns null
  /// (render nothing) for a message that arrived before this feature
  /// existed, if that's even reachable. Colors stay theme-reactive (resolved
  /// against the *current* brightness on every call) even though the
  /// colorIndex itself was captured once.
  Color? _colorForMessage(Message<dynamic> message, BuildContext context) {
    final colorIndex = _messageColorIndex[message];
    if (colorIndex == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return resolveSubscriptionColor(colorIndex, isDark);
  }

  void _showSubscriptionManagerDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => SubscriptionManagerDialog(
        subscriptions: subscriptions,
        isDark: Provider.of<ThemeModel>(context, listen: false).isDark(),
        onAdd: _addSubscription,
        onRemove: _removeSubscription,
        onQueueGroupChanged: _updateQueueGroup,
      ),
    );
  }

  void handleIncomingMessage(Message<dynamic> event) {
    if (!mounted) return;
    // Cheap regardless of arrival rate: just buffer, then coalesce into one
    // UI update per `_incomingFlushInterval` (see the field doc comment).
    _incomingBatch.add(event);
    _incomingFlushTimer ??=
        Timer(_incomingFlushInterval, _flushIncomingMessages);
  }

  void _flushIncomingMessages() {
    _incomingFlushTimer = null;
    if (!mounted || _incomingBatch.isEmpty) return;
    // `_incomingBatch` accumulates in arrival order (oldest of the batch
    // first); `items`/`pendingMessages` are newest-first, so reverse it once
    // here rather than doing anything per-message.
    final newestFirst = _incomingBatch.reversed.toList(growable: false);
    _incomingBatch.clear();

    if (messagesPaused) {
      setState(() {
        pendingMessages.insertAll(0, newestFirst);
      });
      return;
    }

    _insertMessages(newestFirst);
  }

  /// Inserts a newest-first batch at the front of `items`, keeping the
  /// user's view stable.
  ///
  /// The list is newest-at-top, top-anchored (a plain, non-reversed
  /// `ListView`), so new messages are prepended at the top. If the user is
  /// already at the top they stay there and the new newest simply appears
  /// above — the natural "follow the latest" behavior. If they've scrolled
  /// down to read older messages, prepending would otherwise shove the
  /// whole list down and move the viewport out from under them; to prevent
  /// that we shift the scroll offset down by exactly the height of the rows
  /// we just added, so the messages already on screen don't visually move.
  ///
  /// That exact compensation is only possible because every row has a fixed
  /// `_messageRowExtent` (see its doc comment) — the added height is simply
  /// the growth in `maxScrollExtent`, which for a fixed-extent list is
  /// exact rather than an estimate.
  void _insertMessages(List<Message<dynamic>> newestFirst) {
    if (newestFirst.isEmpty) return;
    final hasClients = _listScrollController.hasClients;
    final atTop = !hasClients || _listScrollController.offset <= 1.0;
    final oldOffset = hasClients ? _listScrollController.offset : 0.0;
    final oldMax =
        hasClients ? _listScrollController.position.maxScrollExtent : 0.0;

    setState(() {
      items.insertAll(0, newestFirst);
      if (selectedIndex > -1) {
        selectedIndex += newestFirst.length;
      }
    });
    _runFilter();

    // At the top: nothing to do — the offset stays 0 and the new newest
    // message renders at the top on its own. Scrolled away: shift down by
    // however much the content above the viewport grew, keeping the same
    // messages under the user's eyes.
    if (!atTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_listScrollController.hasClients) return;
        final newMax = _listScrollController.position.maxScrollExtent;
        final target = oldOffset + (newMax - oldMax);
        _listScrollController.jumpTo(target > newMax ? newMax : target);
      });
    }
  }

  /// Tracks whether the list has scrolled away from the top so the "jump to
  /// top" button can be shown/hidden. No-op instant jump — nothing to
  /// animate since it's a single frame either way.
  void _updateJumpToTopVisibility() {
    if (!_listScrollController.hasClients) return;
    final show = _listScrollController.offset > 1.0;
    if (show != _showJumpToTop) {
      setState(() => _showJumpToTop = show);
    }
  }

  void _jumpToTop() {
    if (_listScrollController.hasClients) {
      _listScrollController.jumpTo(0);
    }
  }

  void _pauseMessageList() {
    setState(() => messagesPaused = true);
  }

  void _resumeMessageList() {
    final buffered = List<Message<dynamic>>.of(pendingMessages);
    setState(() {
      pendingMessages.clear();
      messagesPaused = false;
    });
    _insertMessages(buffered);
  }

  void setStateConnected() {
    if (mounted) {
      setState(() {
        isConnected = true;
      });
    }
  }

  void setStateDisconnected() {
    if (mounted) {
      setState(() {
        isConnected = false;
        connectionStateString = constants.disconnected;
      });
    }
  }

  void natsDisconnect() async {
    await natsClient.forceClose();

    for (final info in subscriptions) {
      info.sid = null;
    }

    if (mounted) {
      setState(() {
        isConnected = false;
      });
    }
  }

  void clearMessageList() {
    if (mounted) {
      setState(() {
        items.clear();
        filteredItems.clear();
        pendingMessages.clear();
        _incomingBatch.clear();
      });
    }
  }

  void showSnackBar(String message,
      {SnackBarAction? action, Duration? duration}) {
    // Add mounted check before accessing context
    if (!mounted) return;

    try {
      final theme = Theme.of(context);

      var snackBar = SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        action: action,
        duration: duration ?? const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 4,
      );

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      // Log error but don't crash the app
      debugPrint('Error showing snackbar: $e');
    }
  }

  /// Shows a dialog containing [Message] details including headers and payload.
  Future<void> showDetailDialog(Message message) async {
    var headerVersion = '';
    Map<String, String> headers = <String, String>{};

    // process the headers, if they exist
    if (message.header != null) {
      headerVersion = message.header?.version ?? '';
      headers = message.header?.headers ?? <String, String>{};
    }

    final text = decodeMessageText(message.byte);
    String formattedJson = '';
    try {
      var json = jsonDecode(text);
      var encoder = const JsonEncoder.withIndent("    ");

      formattedJson = encoder.convert(json);
    } on FormatException {
      formattedJson = text;
    }

    // Add mounted check before using context after async gap
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return MessageDetailDialog(
          headerVersion: headerVersion,
          headers: headers,
          formattedJson: formattedJson,
        );
      },
    );
  }

  /// Displays a dialog allowing a user to send a custom message.
  /// Subject box will be pre-filled with [subject] or [replyToSubject] if provided.
  /// Data box will be pre-filled with [data] if provided.
  /// Header rows will be pre-filled with [initialHeaders] if provided.
  Future<void> showSendMessageDialog(
      String? subject, String? replyToSubject, String? data,
      [Map<String, String>? initialHeaders]) async {
    var subjectBoxController = TextEditingController();
    var dataBoxController = TextEditingController();

    if (subject != null && subject.isNotEmpty) {
      subjectBoxController.text = subject;
    }
    if (data != null && data.isNotEmpty) {
      dataBoxController.text = data;
    }

    // Add mounted check before using context after async gap
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return SendMessageDialog(
          subjectController: subjectBoxController,
          dataController: dataBoxController,
          jetStreamAvailable: jetStreamEnabled &&
              _jetStreamManager != null &&
              currentStatus == Status.connected,
          initialHeaders: initialHeaders,
          onSend: (subject, data, useJetStream, headers) {
            sendMessage(subject, data, useJetStream, headers);
          },
        );
      },
    );
  }

  Future<void> showHelpDialog() async {
    String markdownData =
        await DefaultAssetBundle.of(context).loadString('assets/app_help.md');
    markdownData =
        markdownData.replaceFirst('%APP_VERSION%', widget.appVersion);
    // Add mounted check before using context after async gap
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => HelpDialog(markdownData: markdownData),
    );
  }

  void showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return SettingsDialog(
          initialFontSize: messageFontSize,
          initialSingleLine: messageSingleLine,
          initialRetryInterval: retryInterval,
          initialJetStreamEnabled: jetStreamEnabled,
          initialKvEnabled: kvEnabled,
          initialObjectStoreEnabled: objectStoreEnabled,
          initialUpdateCheckEnabled: updateCheckEnabled,
          onSave: (
            fontSize,
            singleLine,
            retryIntervalValue,
            jetStreamEnabledValue,
            kvEnabledValue,
            objectStoreEnabledValue,
            updateCheckEnabledValue,
          ) {
            final updateCheckJustEnabled =
                updateCheckEnabledValue && !updateCheckEnabled;
            setState(() {
              messageFontSize = fontSize;
              messageSingleLine = singleLine;
              retryInterval = retryIntervalValue;
              jetStreamEnabled = jetStreamEnabledValue;
              kvEnabled = kvEnabledValue;
              objectStoreEnabled = objectStoreEnabledValue;
              updateCheckEnabled = updateCheckEnabledValue;
              _ensureTabController();
            });
            saveMessageSettings();
            if (updateCheckJustEnabled) {
              checkForUpdates();
            }
          },
        );
      },
    );
    // Add mounted check after async gap
    if (!mounted) return;
  }

  Future<void> showSecuritySettingsDialog() async {
    var trustedCertificateController = TextEditingController();
    var certificateChainController = TextEditingController();
    var privateKeyController = TextEditingController();

    // grab the certificate locations out of preferences
    var savedTrustedCertificateName =
        prefs.getString(constants.prefTrustedCertificateName);
    var savedCertificateChainName =
        prefs.getString(constants.prefCertificateChainName);
    var savedPrivateKeyName = prefs.getString(constants.prefPrivateKeyName);

    // set the value of each entry box to the saved value
    if (savedTrustedCertificateName != null) {
      trustedCertificateController.text = savedTrustedCertificateName;
    }
    if (savedCertificateChainName != null) {
      certificateChainController.text = savedCertificateChainName;
    }
    if (savedPrivateKeyName != null) {
      privateKeyController.text = savedPrivateKeyName;
    }

    // auth fields are seeded from in-memory state, not preferences directly —
    // they may only live in memory for this session if "remember" is off
    var usernameController = TextEditingController(text: authUsername);
    var passwordController = TextEditingController(text: authPassword);
    var tokenController = TextEditingController(text: authToken);
    var nkeySeedController = TextEditingController(text: authNkeySeed);
    var credsFileController = TextEditingController(text: authCredsFileName);

    // Add mounted check before using context after async gap
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return SecuritySettingsDialog(
          trustedCertificateController: trustedCertificateController,
          certificateChainController: certificateChainController,
          privateKeyController: privateKeyController,
          onTrustedCertificatePick: () {
            pickFile().then((chosenFile) {
              handleTrustedCertificateFile(
                  chosenFile.$1, chosenFile.$2, trustedCertificateController);
            });
          },
          onCertificateChainPick: () {
            pickFile().then((chosenFile) {
              handleCertificateChainFile(
                  chosenFile.$1, chosenFile.$2, certificateChainController);
            });
          },
          onPrivateKeyPick: () {
            pickFile().then((chosenFile) {
              handlePrivateKeyFile(
                  chosenFile.$1, chosenFile.$2, privateKeyController);
            });
          },
          onClearTrustedCertificate: () {
            clearTrustedCertificate(trustedCertificateController);
          },
          onClearCertificateChain: () {
            clearCertificateChain(certificateChainController);
          },
          onClearPrivateKey: () {
            clearPrivateKey(privateKeyController);
          },
          initialAuthMethod: authMethod,
          onAuthMethodChanged: (method) {
            authMethod = method;
            persistAuthSettingsIfRemembered();
          },
          usernameController: usernameController,
          passwordController: passwordController,
          tokenController: tokenController,
          nkeySeedController: nkeySeedController,
          credsFileController: credsFileController,
          onUsernameChanged: (value) {
            authUsername = value;
            persistAuthSettingsIfRemembered();
          },
          onPasswordChanged: (value) {
            authPassword = value;
            persistAuthSettingsIfRemembered();
          },
          onTokenChanged: (value) {
            authToken = value;
            persistAuthSettingsIfRemembered();
          },
          onNkeySeedChanged: (value) {
            authNkeySeed = value;
            persistAuthSettingsIfRemembered();
          },
          onCredsFilePick: () {
            pickFile(allowedExtensions: ['creds']).then((chosenFile) {
              handleCredsFile(
                  chosenFile.$1, chosenFile.$2, credsFileController);
            });
          },
          onClearCredsFile: () {
            clearCredsFile(credsFileController);
          },
          initialRememberCredentials: rememberCredentials,
          onRememberCredentialsChanged: (remember) {
            rememberCredentials = remember;
            prefs.setBool(constants.prefRememberCredentials, remember);
            if (remember) {
              persistAuthSettings();
            } else {
              clearPersistedAuthSettings();
            }
          },
        );
      },
    );
  }

  /// Prompts the user to pick a certificate (or credentials) file
  Future<(Uint8List?, String)> pickFile(
      {List<String> allowedExtensions = const ['pem']}) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );

    if (result != null) {
      // user selected a file, get a reference to it
      PlatformFile file = result.files.first;

      // reference the name of the file, which should work on all platforms
      String fileName = file.name;

      // now get the bytes per platform
      Uint8List? fileBytes;
      if (kIsWeb) {
        // on web, the bytes are automatically filled by the file picker
        fileBytes = file.bytes;
      } else if (file.path != null) {
        // on other platforms, create a File instance and read the file bytes
        File tempFile = File(file.path!);
        fileBytes = tempFile.readAsBytesSync();
      }
      return (fileBytes, fileName);
    } else {
      // User canceled the picker
    }

    return (null, '');
  }

  /// Handles the UI updates and preferences saving after a Trusted Certificate file is chosen by the user.
  void handleTrustedCertificateFile(
      Uint8List? fileBytes, String fileName, TextEditingController controller) {
    if (fileBytes != null) {
      // set the text box value to the name of the file
      controller.text = fileName;

      // compress the bytes with gzip to reduce the size
      final gZipBytes = gzip.encode(fileBytes);

      // save the bytes by base64 encoding them
      prefs.setString(
          constants.prefTrustedCertificate, base64.encode(gZipBytes));
      prefs.setString(constants.prefTrustedCertificateName, fileName);
    }
  }

  /// Clears the trusted certificate file information from the text input and preferences
  void clearTrustedCertificate(TextEditingController controller) {
    controller.text = '';
    prefs.setString(constants.prefTrustedCertificate, '');
    prefs.setString(constants.prefTrustedCertificateName, '');
  }

  /// Handles the UI updates and preferences saving after a Certificate Chain file is chosen by the user.
  void handleCertificateChainFile(
      Uint8List? fileBytes, String fileName, TextEditingController controller) {
    if (fileBytes != null) {
      // set the text box value to the name of the file
      controller.text = fileName;

      // compress the bytes with gzip to reduce the size
      final gZipBytes = gzip.encode(fileBytes);

      // save the bytes by base64 encoding them
      prefs.setString(constants.prefCertificateChain, base64.encode(gZipBytes));
      prefs.setString(constants.prefCertificateChainName, fileName);
    }
  }

  /// Clears the certificate chain file information from the text input and preferences
  void clearCertificateChain(TextEditingController controller) {
    controller.text = '';
    prefs.setString(constants.prefCertificateChain, '');
    prefs.setString(constants.prefCertificateChainName, '');
  }

  /// Handles the UI updates and preferences saving after a Private Key file is chosen by the user.
  void handlePrivateKeyFile(
      Uint8List? fileBytes, String fileName, TextEditingController controller) {
    if (fileBytes != null) {
      // set the text box value to the name of the file
      controller.text = fileName;

      // compress the bytes with gzip to reduce the size
      final gZipBytes = gzip.encode(fileBytes);

      // save the bytes by base64 encoding them
      prefs.setString(constants.prefPrivateKey, base64.encode(gZipBytes));
      prefs.setString(constants.prefPrivateKeyName, fileName);
    }
  }

  /// Clears the private key file information from the text input and preferences
  void clearPrivateKey(TextEditingController controller) {
    controller.text = '';
    prefs.setString(constants.prefPrivateKey, '');
    prefs.setString(constants.prefPrivateKeyName, '');
  }

  /// Handles the UI updates and in-memory state after a `.creds` file is
  /// chosen by the user. Only written to preferences if the user has opted
  /// in via "Remember credentials on this device".
  void handleCredsFile(
      Uint8List? fileBytes, String fileName, TextEditingController controller) {
    if (fileBytes != null) {
      controller.text = fileName;
      authCredsFileBytes = fileBytes;
      authCredsFileName = fileName;
      persistAuthSettingsIfRemembered();
    }
  }

  /// Clears the credentials file information from the text input and in-memory state
  void clearCredsFile(TextEditingController controller) {
    controller.text = '';
    authCredsFileBytes = null;
    authCredsFileName = '';
    persistAuthSettingsIfRemembered();
  }

  /// Persists the current in-memory authentication state to preferences,
  /// but only if "Remember credentials on this device" is enabled.
  void persistAuthSettingsIfRemembered() {
    if (rememberCredentials) {
      persistAuthSettings();
    }
  }

  /// Writes the current in-memory authentication state to preferences.
  void persistAuthSettings() {
    prefs.setString(constants.prefAuthMethod, authMethod.name);
    prefs.setString(constants.prefAuthUsername, authUsername);
    prefs.setString(constants.prefAuthPassword, authPassword);
    prefs.setString(constants.prefAuthToken, authToken);
    prefs.setString(constants.prefAuthNkeySeed, authNkeySeed);
    prefs.setString(constants.prefAuthCredsFileName, authCredsFileName);
    final credsBytes = authCredsFileBytes;
    if (credsBytes != null) {
      final gZipBytes = gzip.encode(credsBytes);
      prefs.setString(constants.prefAuthCredsFile, base64.encode(gZipBytes));
    } else {
      prefs.setString(constants.prefAuthCredsFile, '');
    }
  }

  /// Wipes any persisted authentication secrets from preferences (used when
  /// the user turns off "Remember credentials on this device"), keeping
  /// them only in memory for the rest of this session.
  void clearPersistedAuthSettings() {
    prefs.setString(constants.prefAuthMethod, '');
    prefs.setString(constants.prefAuthUsername, '');
    prefs.setString(constants.prefAuthPassword, '');
    prefs.setString(constants.prefAuthToken, '');
    prefs.setString(constants.prefAuthNkeySeed, '');
    prefs.setString(constants.prefAuthCredsFile, '');
    prefs.setString(constants.prefAuthCredsFileName, '');
  }

  Future<void> sendMessage(String subject, String data,
      [bool useJetStream = false, Map<String, String>? headers]) async {
    final header =
        (headers != null && headers.isNotEmpty) ? Header(headers: headers) : null;

    if (!useJetStream) {
      natsClient.pubString(subject, data, header: header);
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final manager = _jetStreamManager;
    if (manager == null) return;

    try {
      final ack = await manager.publish(subject, data, header: header);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Published to stream "${ack.stream}" at seq ${ack.sequence}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeJetStreamError(e),
            // The theme's default SnackBar text color (`onSurface`) doesn't
            // contrast against an `error` background — see the identical
            // comment in JetStreamDashboard._showSnack.
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Creates a safe PopupMenuButton that handles mounted state properly
  Widget _buildSafePopupMenuButton(int index) {
    return PopupMenuButton<String>(
      key: ValueKey('popup_${filteredItems[index].hashCode}'),
      padding: EdgeInsets.zero,
      itemBuilder: (context) {
        // Add mounted check before accessing context
        if (!mounted) return [];

        try {
          return [
            const PopupMenuItem(
              value: 'copy',
              child: Text('Copy'),
            ),
            const PopupMenuItem(
              value: 'detail',
              child: Text('Detail'),
            ),
            PopupMenuItem(
              value: 'replay',
              enabled: currentStatus == Status.connected,
              child: Text(
                'Replay',
                style: currentStatus == Status.connected
                    ? null
                    : TextStyle(
                        color: Theme.of(context).disabledColor,
                      ),
              ),
            ),
            PopupMenuItem(
              value: 'edit_and_send',
              enabled: currentStatus == Status.connected,
              child: Text(
                'Edit & Send',
                style: currentStatus == Status.connected
                    ? null
                    : TextStyle(
                        color: Theme.of(context).disabledColor,
                      ),
              ),
            ),
            PopupMenuItem(
              value: 'reply_to',
              enabled: currentStatus == Status.connected,
              child: Text(
                'Reply To',
                style: currentStatus == Status.connected
                    ? null
                    : TextStyle(
                        color: Theme.of(context).disabledColor,
                      ),
              ),
            )
          ];
        } catch (e) {
          // If there's an error accessing context, return empty list
          debugPrint('Error building popup menu items: $e');
          return [];
        }
      },
      onSelected: (String value) async {
        // Add mounted check before processing selection
        if (!mounted) return;

        try {
          switch (value) {
            case 'copy':
              await Clipboard.setData(ClipboardData(
                  text: decodeMessageText(filteredItems[index].byte)));
              if (mounted) {
                showSnackBar('Copied to clipboard!');
              }
              break;
            case 'detail':
              if (mounted) {
                showDetailDialog(filteredItems[index]);
              }
              break;
            case 'replay':
              if (mounted && currentStatus == Status.connected) {
                natsClient.pubString(filteredItems[index].subject!,
                    decodeMessageText(filteredItems[index].byte),
                    header: filteredItems[index].header);
              }
              break;
            case 'edit_and_send':
              if (mounted && currentStatus == Status.connected) {
                showSendMessageDialog(
                    filteredItems[index].subject!,
                    null,
                    decodeMessageText(filteredItems[index].byte),
                    filteredItems[index].header?.headers);
              }
              break;
            case 'reply_to':
              if (mounted && currentStatus == Status.connected) {
                if (filteredItems[index].replyTo != null &&
                    filteredItems[index].replyTo!.isNotEmpty) {
                  showSendMessageDialog(
                      filteredItems[index].replyTo, null, null);
                } else {
                  showSnackBar('This message has no replyTo subject');
                }
              }
              break;
          }
        } catch (e) {
          // Log error but don't crash the app
          debugPrint('Error handling popup menu selection: $e');
          if (mounted) {
            showSnackBar('An error occurred. Please try again.');
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    updateFullUri();

    // if running in a browser, remove the option for nats://.
    // browsers only support web sockets, so TCP connections aren't possible.
    // to avoid confusion, only offer web socket connection variants.
    if (kIsWeb) {
      scheme = 'ws://';
      availableSchemes.remove('nats://');
    }

    // Define custom colors for message list rows based on theme
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Even row: subtle tint
    final messageRowEvenColor = isDark
        ? Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(40), theme.colorScheme.surface)
        : Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(20), theme.colorScheme.surface);
    // Odd row: more contrast
    final messageRowOddColor = isDark
        ? Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(80),
            theme.colorScheme.surface)
        : Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(140),
            theme.colorScheme.surface);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Global shortcuts (work regardless of message selection)
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            if (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                // Ctrl+Shift+F or Cmd+Shift+F - Focus Filter field.
                // On the JetStream tab, prefer the Browse Messages view's
                // own Filter field (if it's currently showing); otherwise
                // fall back to the Live Messages tab's.
                final focusedJetStream = _tabController.index == 1 &&
                    (_jetStreamDashboardKey.currentState?.focusFilterField() ??
                        false);
                if (!focusedJetStream) {
                  _filterFocusNode.requestFocus();
                }
                return KeyEventResult.handled;
              } else {
                // Ctrl+F or Cmd+F - Focus Find field (same tab-aware logic
                // as above).
                final focusedJetStream = _tabController.index == 1 &&
                    (_jetStreamDashboardKey.currentState?.focusFindField() ??
                        false);
                if (!focusedJetStream) {
                  _findFocusNode.requestFocus();
                }
                return KeyEventResult.handled;
              }
            }
          }

          // Message-specific shortcuts (only when a message is selected)
          if (selectedIndex >= 0 && selectedIndex < filteredItems.length) {
            // Handle single key shortcuts
            if (event.logicalKey == LogicalKeyboardKey.keyD) {
              showDetailDialog(filteredItems[selectedIndex]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
              if (currentStatus == Status.connected) {
                natsClient.pubString(filteredItems[selectedIndex].subject!,
                    decodeMessageText(filteredItems[selectedIndex].byte),
                    header: filteredItems[selectedIndex].header);
              } else {
                showSnackBar('Not connected, cannot replay message');
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
              if (currentStatus == Status.connected) {
                showSendMessageDialog(
                    filteredItems[selectedIndex].subject!,
                    null,
                    decodeMessageText(filteredItems[selectedIndex].byte),
                    filteredItems[selectedIndex].header?.headers);
              } else {
                showSnackBar('Not connected, cannot send message');
              }
              return KeyEventResult.handled;
            }
            // Handle Ctrl+C/Cmd+C shortcut
            else if (event.logicalKey == LogicalKeyboardKey.keyC &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              Clipboard.setData(ClipboardData(
                  text: decodeMessageText(filteredItems[selectedIndex].byte)));
              showSnackBar('Copied to clipboard!');
              return KeyEventResult.handled;
            }
            // Handle Esc key to un-select message
            else if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                selectedIndex = -1;
              });
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: (() {
            final theme = Theme.of(context);
            final surface = theme.colorScheme.surface;
            final isDark = theme.brightness == Brightness.dark;
            return Color.alphaBlend(
              Colors.black
                  .withAlpha(isDark ? 80 : 20), // 20% for dark, 8% for light
              surface,
            );
          })(),
          scrolledUnderElevation: 0,
          leadingWidth: 48, // Reduce the default leading width
          titleSpacing: 0, // Remove the default title spacing
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SvgPicture.asset(
              'assets/app_launcher_icon.svg',
              width: 32,
              height: 32,
            ),
          ),
          title: Text(widget.title),
          actions: [
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: showSettingsDialog),
            IconButton(
                icon: const Icon(Icons.lightbulb),
                onPressed: () {
                  ThemeModel themeModel =
                      Provider.of<ThemeModel>(context, listen: false);
                  themeModel.toggleMode();
                  if (themeModel.isDark()) {
                    prefs.setString(constants.prefTheme, constants.darkTheme);
                  } else {
                    prefs.setString(constants.prefTheme, constants.lightTheme);
                  }
                }),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
              child: IconButton(
                  icon: const Icon(Icons.question_mark),
                  onPressed: () => showHelpDialog()),
            )
          ],
        ),
        body: Column(
          children: <Widget>[
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), labelText: 'Scheme'),
                        items: availableSchemes.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        initialValue: scheme,
                        onChanged: (currentStatus != Status.disconnected)
                            ? null
                            : (value) {
                                scheme = value!;
                                updateFullUri();
                              },
                        hint: const Text('Scheme'),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: IconButton.filledTonal(
                          tooltip: 'Security Settings',
                          style: IconButton.styleFrom(
                              minimumSize: const Size(50, 50)),
                          onPressed: (currentStatus == Status.disconnected)
                              ? showSecuritySettingsDialog
                              : null,
                          icon: const Icon(Icons.lock)),
                    ),
                    Flexible(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                        child: _withConnectShortcut(TextFormField(
                          enabled: (currentStatus == Status.disconnected),
                          initialValue: widget.host,
                          onChanged: (value) {
                            host = value;
                            updateFullUri();
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Host',
                            labelText: 'Host',
                          ),
                        )),
                      ),
                    ),
                    Flexible(
                      flex: 1,
                      child: _withConnectShortcut(TextFormField(
                        enabled: (currentStatus == Status.disconnected),
                        initialValue: widget.port,
                        onChanged: (value) {
                          port = value;
                          updateFullUri();
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Port',
                          labelText: 'Port',
                        ),
                      )),
                    ),
                    Flexible(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                        // Unlike Host/Port/Scheme, this stays interactive
                        // while connected: adding/removing a chip live
                        // subscribes/unsubscribes immediately (see
                        // _addSubscription/_removeSubscription) instead of
                        // only taking effect on the next connect.
                        child: _withConnectShortcut(SubjectChipsRow(
                          subscriptions: subscriptions,
                          isDark: Provider.of<ThemeModel>(context,
                                  listen: false)
                              .isDark(),
                          onTapChip: _showEditSubscriptionDialog,
                          onRemoveChip: _removeSubscription,
                          onAdd: () => _showEditSubscriptionDialog(null),
                          onOpenManager: _showSubscriptionManagerDialog,
                        )),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: IconButton.filled(
                          tooltip: 'Connect',
                          style: IconButton.styleFrom(
                              minimumSize: const Size(50, 50)),
                          onPressed: (currentStatus == Status.disconnected)
                              ? natsConnect
                              : null,
                          icon: const Icon(Icons.check)),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: IconButton.filledTonal(
                          tooltip: 'Disconnect',
                          style: IconButton.styleFrom(
                              minimumSize: const Size(50, 50)),
                          onPressed: (currentStatus != Status.disconnected)
                              ? natsDisconnect
                              : null,
                          icon: const Icon(Icons.close)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1), // Divider below the top toolbar
            if (_visibleTabCount > 1)
              TabBar(
                controller: _tabController,
                tabs: [
                  const Tab(text: 'Live Messages'),
                  if (jetStreamEnabled) const Tab(text: 'JetStream'),
                  if (kvEnabled) const Tab(text: 'Key-Value Stores'),
                  if (objectStoreEnabled) const Tab(text: 'Object Store'),
                ],
              ),
            Expanded(
              child: _visibleTabCount > 1
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLiveMessagesTab(
                            messageRowEvenColor, messageRowOddColor),
                        if (jetStreamEnabled)
                          JetStreamDashboard(
                            key: _jetStreamDashboardKey,
                            manager: currentStatus == Status.connected
                                ? _jetStreamManager
                                : null,
                          ),
                        if (kvEnabled)
                          KvDashboard(
                            key: _kvDashboardKey,
                            manager: currentStatus == Status.connected
                                ? _kvManager
                                : null,
                          ),
                        if (objectStoreEnabled)
                          ObjectStoreDashboard(
                            key: _objectStoreDashboardKey,
                            manager: currentStatus == Status.connected
                                ? _objectStoreManager
                                : null,
                          ),
                      ],
                    )
                  : _buildLiveMessagesTab(
                      messageRowEvenColor, messageRowOddColor),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(5, 2, 10, 4),
              color: Provider.of<ThemeModel>(context, listen: false).isDark()
                  ? isConnected
                      ? constants.connectedLight
                      : constants.disconnectedLight
                  : isConnected
                      ? constants.connectedDark
                      : constants.disconnectedDark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                      'Total Messages: ${items.length}, Showing: ${filteredItems.length}  |  '),
                  Text('URL: $fullUri'),
                  if (isConnected && tlsConnection)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 2, 0, 0),
                      child: Icon(Icons.lock_outline,
                          size: 15,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                  const Text('  |  '),
                  Text('Status: $connectionStateString'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The fixed height of every message row.
  ///
  /// A fixed extent (rather than letting each row size itself to its 1–5
  /// lines of text) is what lets the list compensate the scroll offset
  /// *exactly* when new messages are prepended above a scrolled-away
  /// viewport (see `_insertMessages`), and also lets the scrollbar/fling
  /// locate any row analytically instead of building off-screen rows to
  /// measure them — the difference between smooth and janky on a list of
  /// thousands. Derived from the current font size and single-line setting
  /// so rows are always tall enough for their text at whatever size the
  /// user picks; longer text is still clipped with an ellipsis exactly as
  /// before. The 56px floor keeps a single short line from producing a row
  /// shorter than the trailing controls' tap target.
  double get _messageRowExtent {
    final lines = messageSingleLine ? 1 : 5;
    final textBlockHeight = lines * messageFontSize * 1.3;
    final withPadding = textBlockHeight + 24;
    return withPadding > 56.0 ? withPadding : 56.0;
  }

  /// Builds the "Live Messages" tab content: the scrolling message list plus
  /// the bottom toolbar (clear/send/filter/find). Unchanged from before the
  /// JetStream tab was introduced, just extracted so it can be reused as a
  /// `TabBarView` page.
  Widget _buildLiveMessagesTab(Color evenRowColor, Color oddRowColor) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: [
              Scrollbar(
                controller: _listScrollController,
                thumbVisibility:
                    true, // Always show the scrollbar when scrollable
                child: ListView.builder(
                  controller: _listScrollController,
                  // Newest-at-top, top-anchored (a plain, non-reversed list):
                  // messages fill from the top down, the latest arrives at the
                  // top, and a short list sits at the top with empty space
                  // below rather than clinging to the bottom. Stable scrolling
                  // when new messages are prepended above a scrolled-away
                  // viewport is handled in `_insertMessages` by shifting the
                  // offset, which is exact only because every row is a fixed
                  // `_messageRowExtent` tall (see that getter's doc comment).
                  itemExtent: _messageRowExtent,
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final message = filteredItems[index];
                    final subColor = _colorForMessage(message, context);
                    return Material(
                      key: ObjectKey(message),
                      // A full-height bar (rather than a small leading dot)
                      // reads more clearly at a glance and doesn't compete
                      // with ListTile's own leading/minLeadingWidth slot.
                      // CrossAxisAlignment.stretch makes the bar span the
                      // row's full itemExtent height.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            key: const ValueKey('subscriptionColorBar'),
                            width: 4,
                            color: subColor ?? Colors.transparent,
                          ),
                          Expanded(
                            child: ListTile(
                              // ListTile centers its title within its own
                              // *computed natural* height, not whatever
                              // height it's actually given -- itemExtent
                              // reserves room for up to 5 lines (see
                              // _messageRowExtent) even when a message only
                              // needs 1, so without this, ListTile computes
                              // titleY assuming the smaller natural height
                              // and the leftover space silently lands
                              // entirely below the text instead of being
                              // split evenly. Telling it the *real* target
                              // height makes its own centering math correct.
                              minTileHeight: _messageRowExtent,
                              title: RegexTextHighlight(
                                text: decodeMessageText(message.byte),
                                searchTerm: currentFind,
                                fontSize: messageFontSize,
                                highlightStyle: TextStyle(
                                  background: Paint()
                                    ..color = Theme.of(context)
                                        .colorScheme
                                        .inversePrimary,
                                  fontSize: messageFontSize,
                                ),
                                maxLines: messageSingleLine ? 1 : 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // Band by distance from the oldest message
                              // (always at the bottom), not the raw index:
                              // prepending new messages shifts every
                              // existing row's index, so banding on the
                              // index would flip every stripe as messages
                              // arrive. Distance-from-oldest is fixed per
                              // message, so stripes stay put.
                              tileColor: selectedIndex == index
                                  ? Theme.of(context).colorScheme.inversePrimary
                                  : (filteredItems.length - 1 - index) % 2 == 0
                                      ? evenRowColor
                                      : oddRowColor,
                              onTap: () => _handleMessageTap(index),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 450),
                                    child: Tooltip(
                                      message: message.subject!,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 0, 5, 0),
                                        child: Chip(
                                            label: Text(message.subject!,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: messageFontSize,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface,
                                                ))),
                                      ),
                                    ),
                                  ),
                                  _buildSafePopupMenuButton(index),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showJumpToTop)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    mini: true,
                    tooltip: 'Jump to top',
                    onPressed: _jumpToTop,
                    child: const Icon(Icons.vertical_align_top),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1), // Divider above the bottom toolbar
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 5, 10),
              child: IconButton.outlined(
                  tooltip: 'Clear messages',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(50, 50)),
                  onPressed: clearMessageList,
                  icon: const Icon(
                    Icons.delete,
                    size: 18,
                  )),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 5, 10),
              // Fixed width rather than letting the button size itself to
              // its content: the buffered-count pill's text changes length
              // as the count grows (e.g. "1" -> "1.2k"), and without a
              // fixed slot that shifted every control to its right on each
              // flush. Wide enough for icon + a realistic wide count
              // ("1.2k") plus this `FilledButton`'s own padding, verified
              // against a real overflow this size was previously too
              // narrow to catch (a single-digit count never exposed it).
              child: SizedBox(
                  height: 50,
                  width: 108,
                  child: Tooltip(
                    message: messagesPaused
                        ? 'Resume (${pendingMessages.length} buffered)'
                        : 'Pause incoming messages',
                    child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: messagesPaused
                            ? _resumeMessageList
                            : _pauseMessageList,
                        // A `Badge` here used to overlap the icon closely
                        // enough that it was hard to tell Pause from Resume
                        // at a glance without the tooltip — a plain Row
                        // with the count as a separate pill keeps the icon
                        // fully visible.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              messagesPaused ? Icons.play_arrow : Icons.pause,
                              size: 18,
                            ),
                            if (messagesPaused && pendingMessages.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  formatCompactCount(pendingMessages.length),
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                ),
                              ),
                          ],
                        )),
                  )),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 5, 10),
              child: IconButton.filled(
                  tooltip: 'Send message',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(50, 50)),
                  onPressed: currentStatus == Status.connected
                      ? () {
                          showSendMessageDialog(null, null, null);
                        }
                      : null,
                  icon: const Icon(
                    Icons.send,
                    size: 18,
                  )),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                child: TextFormField(
                  controller: filterBoxController,
                  focusNode: _filterFocusNode,
                  onChanged: (value) {
                    currentFilter = value;
                    _runFilter();
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Filter',
                    labelText: 'Filter',
                    prefixIcon: const Icon(Icons.filter_list),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          filterBoxController.clear();
                          currentFilter = '';
                          _runFilter();
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                child: TextFormField(
                  controller: findBoxController,
                  focusNode: _findFocusNode,
                  onChanged: (value) {
                    setState(() {
                      currentFind = value;
                    });
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Find',
                    labelText: 'Find',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          findBoxController.clear();
                          currentFind = '';
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
