import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
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
import 'connection_history.dart';
import 'constants.dart' as constants;
import 'format_utils.dart';
import 'export_confirm_dialog.dart';
import 'jetstream_dashboard.dart';
import 'jetstream_manager.dart';
import 'kv_dashboard.dart';
import 'kv_manager.dart';
import 'message_detail_dialog.dart';
import 'message_export.dart';
import 'object_store_dashboard.dart';
import 'object_store_manager.dart';
import 'paused_banner.dart';
import 'replay_banner.dart';
import 'replay_config_dialog.dart';
import 'send_message_dialog.dart';
import 'help_dialog.dart';
import 'service_discovery_dashboard.dart';
import 'service_discovery_manager.dart';
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
    await prefs.setString(
        constants.prefSubscriptions, encodeSubscriptionList(tempSubscriptions));
  }

  // connection history: JSON list of previously-used {scheme, host, port}
  // targets, offered by the Host field's dropdown. Empty until the first
  // successful connect.
  List<ConnectionHistoryEntry> tempConnectionHistory = const [];
  String? historyJson = prefs.getString(constants.prefConnectionHistory);
  if (historyJson != null && historyJson.isNotEmpty) {
    tempConnectionHistory = decodeConnectionHistory(historyJson);
  }

  // get the application's version number
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String appVersion = packageInfo.version;

  // run the ui
  runApp(MyApp(appVersion, tempScheme, tempHost, tempPort, tempSubscriptions,
      tempConnectionHistory, tempTheme));
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
      this.subscriptions, this.connectionHistory, this.theme,
      {super.key});

  final String appVersion;
  final String scheme;
  final String host;
  final String port;
  final List<SubscriptionInfo> subscriptions;
  final List<ConnectionHistoryEntry> connectionHistory;
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
                      port, subscriptions, connectionHistory),
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
      this.port, this.subscriptions, this.connectionHistory,
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
  final List<ConnectionHistoryEntry> connectionHistory;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with WindowListener, TickerProviderStateMixin {
  String host = constants.defaultHost;
  String port = constants.defaultPort;
  List<SubscriptionInfo> subscriptions = [];
  // Previously-used connection targets, offered by the Host field's dropdown.
  List<ConnectionHistoryEntry> connectionHistory = [];
  // Controller (rather than initialValue) so a history selection can push a
  // new value into the Port field visibly -- see _selectHistoryEntry.
  late TextEditingController portController;
  // Message-row color indicator lookup: colorIndex captured per message at
  // arrival time (see _subscribeOne). An Expando rather than a Map so
  // entries never need manual pruning -- once a Message drops out of
  // items/filteredItems with nothing else referencing it, its entry here
  // becomes collectible too.
  final Expando<int> _messageColorIndex = Expando<int>();
  int _nextColorIndex = 0;
  // Arrival-time tagging for Export's `capturedAt` field. `Message`
  // (dart_nats) has no timestamp field of its own; an Expando follows the
  // exact same precedent as `_messageColorIndex` immediately above so
  // entries never need manual pruning.
  final Expando<DateTime> _messageCapturedAt = Expando<DateTime>();
  var availableSchemes = <String>['ws://', 'nats://'];
  String scheme = constants.defaultScheme;
  String fullUri = '';
  int selectedIndex = -1;
  // Multi-select for bulk copy (Shift+Click, Ctrl+Click, Ctrl+Shift+Up/
  // Down). Identity-based (a Set of the actual Message objects, not
  // indices) so it survives _insertMessages prepending rows and _runFilter
  // swapping filteredItems out wholesale -- unlike selectedIndex, no
  // shift-compensation is ever needed since membership is by object
  // identity, not position.
  final Set<Message<dynamic>> _multiSelected = {};
  // Whether _multiSelected is the current source of truth for "what's
  // selected" (true once a Shift/Ctrl-gesture has run), as opposed to the
  // plain single-row model (selectedIndex alone). This can't be inferred
  // from `_multiSelected.isEmpty` -- Ctrl+Click toggling every selected row
  // back off legitimately leaves the set empty while still meaning "nothing
  // is selected", which is different from "multi-select was never engaged,
  // defer to selectedIndex". A plain click resets this to false.
  bool _multiSelectActive = false;
  // Fixed end of the current Shift+Click/Ctrl+Shift+Up/Down range. Stored as
  // a Message reference (re-located by identity in filteredItems each time a
  // range is computed) rather than a raw index, since filteredItems can be
  // re-sorted/replaced by a filter change or reordered by inserts underneath
  // a stored index but not underneath an object reference. Ctrl+Click also
  // moves this to the clicked row, so a later Shift+Click extends from
  // wherever the user last clicked (with or without Ctrl), matching
  // standard file-manager behavior.
  Message<dynamic>? _selectionAnchor;
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

  // Replay: orthogonal to `messagesPaused` -- Pause governs whether the list
  // *renders* new arrivals, Replay governs whether the app is currently
  // *publishing* outgoing messages from a loaded file. A replayed message
  // can loop back as an incoming arrival while the list is paused, so both
  // can legitimately be active at once (see `ReplayBanner`'s doc comment).
  bool _isReplaying = false;
  int _replaySentCount = 0;
  int _replayTotalCount = 0;
  int _replayCurrentPass = 1;
  int _replayTotalPasses = 1;
  Completer<void>? _replayStopSignal;
  // Anchors the Export menu to its trigger button -- opened via `showMenu`
  // rather than `PopupMenuButton`'s own `icon` param so the trigger can be a
  // real `IconButton.outlined` and match the Clear/Send/Replay buttons
  // beside it exactly (`PopupMenuButton.icon` renders a plain, un-outlined
  // IconButton with no way to apply that style).
  final GlobalKey _exportMenuButtonKey = GlobalKey();

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

  // Service Discovery tab
  bool serviceDiscoveryEnabled = constants.defaultServiceDiscoveryEnabled;
  final GlobalKey<ServiceDiscoveryDashboardState>
      _serviceDiscoveryDashboardKey = GlobalKey();

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
  ServiceDiscoveryManager? _serviceDiscoveryManager;
  bool isConnected = false;
  String connectionStateString = constants.disconnected;

  var filterBoxController = TextEditingController();
  var findBoxController = TextEditingController();

  // Focus nodes for keyboard shortcuts
  final FocusNode _filterFocusNode = FocusNode();
  final FocusNode _findFocusNode = FocusNode();
  // The outer Focus(onKeyEvent: ...) below has no explicit FocusNode of its
  // own by default -- its `autofocus: true` only claims focus once, at first
  // build. Once the user focuses anything else (Filter/Find, a dialog
  // field, ...), message-row keyboard shortcuts (D/R/E/Ctrl+C/Escape/
  // Ctrl+Shift+Up/Down) silently stop firing because nothing is focused for
  // the key event to bubble up from. Selecting a row via _handleMessageTap
  // explicitly reclaims focus onto this node so the shortcuts keep working
  // no matter what had focus beforehand.
  final FocusNode _messageListFocusNode = FocusNode();

  // user preferences
  late SharedPreferences prefs;
  double messageFontSize = 14.0;
  int retryInterval = constants.defaultRetryInterval;
  bool updateCheckEnabled = constants.defaultUpdateCheckEnabled;
  bool showSubscriptionColors = constants.defaultShowSubscriptionColors;
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
    connectionHistory =
        List<ConnectionHistoryEntry>.from(widget.connectionHistory);
    portController = TextEditingController(text: widget.port);
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
    _messageListFocusNode.dispose();
    _tabController.dispose();
    portController.dispose();
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
      retryInterval = prefs.getInt(constants.prefRetryInterval) ??
          constants.defaultRetryInterval;
      jetStreamEnabled = prefs.getBool(constants.prefJetStreamEnabled) ??
          constants.defaultJetStreamEnabled;
      kvEnabled =
          prefs.getBool(constants.prefKvEnabled) ?? constants.defaultKvEnabled;
      objectStoreEnabled = prefs.getBool(constants.prefObjectStoreEnabled) ??
          constants.defaultObjectStoreEnabled;
      serviceDiscoveryEnabled =
          prefs.getBool(constants.prefServiceDiscoveryEnabled) ??
              constants.defaultServiceDiscoveryEnabled;
      updateCheckEnabled = prefs.getBool(constants.prefUpdateCheckEnabled) ??
          constants.defaultUpdateCheckEnabled;
      showSubscriptionColors =
          prefs.getBool(constants.prefShowSubscriptionColors) ??
              constants.defaultShowSubscriptionColors;
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
    prefs.setInt(constants.prefRetryInterval, retryInterval);
    prefs.setBool(constants.prefJetStreamEnabled, jetStreamEnabled);
    prefs.setBool(constants.prefKvEnabled, kvEnabled);
    prefs.setBool(constants.prefObjectStoreEnabled, objectStoreEnabled);
    prefs.setBool(
        constants.prefServiceDiscoveryEnabled, serviceDiscoveryEnabled);
    prefs.setBool(constants.prefUpdateCheckEnabled, updateCheckEnabled);
    prefs.setBool(constants.prefShowSubscriptionColors, showSubscriptionColors);
  }

  /// Handles tap logic to distinguish between single and double taps
  void _handleMessageTap(int index) {
    // Reclaim keyboard focus for the message list's shortcuts (D/R/E/
    // Ctrl+C/Escape/Ctrl+Shift+Up/Down) regardless of what had focus before
    // this click -- e.g. the Filter/Find field. Without this, clicking a
    // row doesn't grant it keyboard focus the way clicking a text field
    // does, so those shortcuts would silently have nothing to bubble up
    // from and do nothing.
    _messageListFocusNode.requestFocus();

    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift+Click: intent is unambiguous (extend/replace the selection
      // range), so skip the single/double-tap timer entirely rather than
      // waiting 300ms to disambiguate from a double-tap-to-Detail.
      _tapTimer?.cancel();
      _lastTappedIndex = null;
      setState(() {
        _selectRange(index);
      });
      return;
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Ctrl+Click (Cmd+Click on Mac): same reasoning as Shift+Click above
      // -- unambiguous intent, skip the tap timer.
      _tapTimer?.cancel();
      _lastTappedIndex = null;
      setState(() {
        _toggleSelection(index);
      });
      return;
    }

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
          // A plain click always collapses back to single-row selection,
          // clearing any multi-select range/toggle set from a previous
          // Shift/Ctrl-gesture.
          _multiSelected.clear();
          _multiSelectActive = false;
          _selectionAnchor = null;
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

  /// Extends/replaces the multi-select range using `_selectionAnchor` as the
  /// fixed end and `targetIndex` (into `filteredItems`) as the moving end.
  /// Shared by Shift+Click and Ctrl+Shift+Up/Down. Must be called inside a
  /// `setState`.
  void _selectRange(int targetIndex) {
    var anchorIndex = _selectionAnchor != null
        ? filteredItems.indexOf(_selectionAnchor!)
        : -1;
    if (anchorIndex == -1) {
      // No anchor yet, or the previous anchor scrolled out of the current
      // filtered view -- seed a fresh one from the existing single
      // selection (if any), otherwise from the click/move target itself.
      anchorIndex = selectedIndex >= 0 && selectedIndex < filteredItems.length
          ? selectedIndex
          : targetIndex;
      _selectionAnchor = filteredItems[anchorIndex];
    }

    final lo = anchorIndex <= targetIndex ? anchorIndex : targetIndex;
    final hi = anchorIndex <= targetIndex ? targetIndex : anchorIndex;
    _multiSelected
      ..clear()
      ..addAll(filteredItems.sublist(lo, hi + 1));
    selectedIndex = targetIndex;
    _multiSelectActive = true;
  }

  /// Ctrl+Click (Cmd+Click on Mac): toggles a single row's membership in the
  /// multi-selection without touching any other row -- builds a
  /// disconnected/non-contiguous selection (e.g. rows 1-4 plus row 6), and
  /// toggling an already-selected row deselects just that one. The clicked
  /// row also becomes the new anchor/focus for a subsequent Shift+Click or
  /// Ctrl+Shift+Up/Down, matching standard file-manager behavior (Explorer/
  /// Finder). Must be called inside a `setState`.
  void _toggleSelection(int index) {
    // Bridge the implicit single-selection (selectedIndex alone) into the
    // explicit multi-select set on the first Shift/Ctrl-gesture, so
    // toggling adds to what's actually shown as selected rather than
    // starting from a stale empty set.
    if (!_multiSelectActive &&
        selectedIndex >= 0 &&
        selectedIndex < filteredItems.length) {
      _multiSelected.add(filteredItems[selectedIndex]);
    }
    final target = filteredItems[index];
    if (!_multiSelected.remove(target)) {
      _multiSelected.add(target);
    }
    selectedIndex = index;
    _selectionAnchor = target;
    _multiSelectActive = true;
  }

  /// The set of messages bulk actions (Ctrl+C, "Copy Selected", row
  /// highlighting) should act on: `_multiSelected` once a Shift/Ctrl-gesture
  /// has engaged multi-select mode (which may legitimately be empty, e.g.
  /// every row was Ctrl+Click-toggled back off), otherwise the single
  /// `selectedIndex` row (or empty if nothing is selected at all). This
  /// makes `_multiSelected` transparently subsume today's pre-existing
  /// single-select behavior for any caller that only needs to know "what's
  /// currently selected".
  Set<Message<dynamic>> _effectiveSelection() {
    if (_multiSelectActive) {
      return _multiSelected;
    }
    if (selectedIndex >= 0 && selectedIndex < filteredItems.length) {
      return {filteredItems[selectedIndex]};
    }
    return {};
  }

  /// Matches any line-break style (`\r\n`, bare `\r`, or bare `\n`) so every
  /// flavor collapses to the same literal `\n` marker in `_copyMultiSelection`
  /// -- replacing only `\n` would leave a bare `\r` (common in payloads built
  /// from concatenated CRLF-terminated lines, e.g. NMEA sentences) still
  /// rendering as a real line break wherever the copied text gets pasted.
  static final RegExp _anyLineBreak = RegExp(r'\r\n|\r|\n');

  /// Copies every message in `selection` as one line per message
  /// (`subject: payload`), in on-screen top-to-bottom order regardless
  /// of the order `selection` iterates in. Payload line breaks are escaped
  /// as a literal `\n` so the copied line count always equals the message
  /// count.
  Future<void> _copyMultiSelection(Set<Message<dynamic>> selection) async {
    final ordered = filteredItems.where(selection.contains);
    final text = ordered
        .map((m) =>
            '${m.subject}: ${decodeMessageText(m.byte).replaceAll(_anyLineBreak, r'\n')}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showSnackBar('Copied ${selection.length} messages to clipboard!');
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
      // selectedIndex is an index into filteredItems, which is about to be
      // replaced wholesale -- capture the previously-selected message by
      // identity first and re-locate it in the new list, rather than
      // leaving selectedIndex pointing at an unrelated row (or past the
      // end) once the filter changes what's visible.
      final previouslySelected =
          selectedIndex >= 0 && selectedIndex < filteredItems.length
              ? filteredItems[selectedIndex]
              : null;
      setState(() {
        filteredItems = results;
        selectedIndex = previouslySelected != null
            ? results.indexOf(previouslySelected)
            : -1;
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

  /// Live Messages is always tab 0; JetStream, Key-Value, Object Store, and
  /// Services each add one more tab, in that order, when their respective
  /// settings toggle is on.
  int get _visibleTabCount =>
      1 +
      (jetStreamEnabled ? 1 : 0) +
      (kvEnabled ? 1 : 0) +
      (objectStoreEnabled ? 1 : 0) +
      (serviceDiscoveryEnabled ? 1 : 0);

  /// `TabController.length` is fixed at construction, but which tabs are
  /// visible can change at runtime (the JetStream/KV/Object Store/Services
  /// toggles in Settings).
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
    _serviceDiscoveryManager = ServiceDiscoveryManager(natsClient);

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
    // we can read these out at startup. these are the single "last used"
    // values that prefill the fields next launch -- distinct from the
    // connection history list (prefConnectionHistory), which is a deduped set
    // recorded only on a *successful* connect (see _recordConnectionHistory).
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
            _recordConnectionHistory(scheme, host, port);
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
      _messageCapturedAt[event] = DateTime.now();
      handleIncomingMessage(event);
    });
  }

  Future<void> _persistSubscriptions() async {
    await prefs.setString(
        constants.prefSubscriptions, encodeSubscriptionList(subscriptions));
  }

  Future<void> _persistConnectionHistory() async {
    await prefs.setString(constants.prefConnectionHistory,
        encodeConnectionHistory(connectionHistory));
  }

  /// Records a successfully-used target at the front of the history (deduped,
  /// capped). Fires from the Status.connected handler, including on reconnects
  /// -- recordConnection just moves an existing entry back to the front.
  void _recordConnectionHistory(String scheme, String host, String port) {
    setState(() {
      connectionHistory =
          recordConnection(connectionHistory, scheme, host, port);
    });
    _persistConnectionHistory();
  }

  void _deleteHistoryEntry(ConnectionHistoryEntry entry) {
    setState(() {
      connectionHistory =
          connectionHistory.where((e) => !e.sameTarget(entry)).toList();
    });
    _persistConnectionHistory();
  }

  void _clearConnectionHistory() {
    setState(() => connectionHistory = []);
    _persistConnectionHistory();
  }

  /// Fills scheme + host + port from a chosen history entry. The Autocomplete
  /// writes the host into its own field; the scheme dropdown picks up the new
  /// value via its ValueKey(scheme), and the Port field via portController.
  void _selectHistoryEntry(ConnectionHistoryEntry entry) {
    setState(() {
      scheme = entry.scheme;
      host = entry.host;
      port = entry.port;
    });
    portController.text = entry.port;
    updateFullUri();
  }

  /// The Host input: an editable [Autocomplete] whose field shows/edits only
  /// the host while its dropdown offers full 'scheme+host:port' history
  /// entries. Selecting one fills scheme + host + port (see
  /// [_selectHistoryEntry]). The overlay stays keyboard-navigable by rendering
  /// the options iterable Autocomplete passes in, in lock-step with its
  /// built-in highlight (see [_ConnectionHistoryOptions]).
  Widget _buildHostField() {
    return Autocomplete<ConnectionHistoryEntry>(
      displayStringForOption: (entry) => entry.host,
      initialValue: TextEditingValue(text: widget.host),
      optionsBuilder: (TextEditingValue value) {
        // No history while connected -- the field is disabled too.
        if (currentStatus != Status.disconnected) {
          return const Iterable<ConnectionHistoryEntry>.empty();
        }
        final query = value.text.trim().toLowerCase();
        // Show the whole list on focus / while the box still shows the
        // committed host; otherwise substring-filter on host or full URI.
        if (query.isEmpty || query == host.toLowerCase()) {
          return connectionHistory;
        }
        return connectionHistory.where((e) =>
            e.host.toLowerCase().contains(query) ||
            e.fullUri.toLowerCase().contains(query));
      },
      onSelected: _selectHistoryEntry,
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          enabled: (currentStatus == Status.disconnected),
          onChanged: (value) {
            host = value;
            updateFullUri();
          },
          // Plain Enter selects the highlighted history row.
          onFieldSubmitted: (_) => onFieldSubmitted(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Host',
            labelText: 'Host',
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _ConnectionHistoryOptions(
          options: options.toList(),
          onSelected: onSelected,
          onDelete: _deleteHistoryEntry,
          onClear: _clearConnectionHistory,
        );
      },
    );
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
        onRemove: existing == null ? null : () => _removeSubscription(existing),
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

  /// Arrival time captured for `capturedAt` in an Export -- `null` for a
  /// message that was published locally rather than received (e.g. a
  /// replayed message that loops back is tagged normally by `_subscribeOne`
  /// like any other arrival).
  DateTime? _capturedAtFor(Message<dynamic> message) =>
      _messageCapturedAt[message];

  void _showSubscriptionManagerDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => SubscriptionManagerDialog(
        subscriptions: subscriptions,
        isDark: Provider.of<ThemeModel>(context, listen: false).isDark(),
        showSubscriptionColors: showSubscriptionColors,
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

  void _startReplay(List<ExportedMessage> messages, Duration messageInterval,
      int repeatCount, Duration repeatInterval) {
    if (_isReplaying) return;
    unawaited(
        _runReplay(messages, messageInterval, repeatCount, repeatInterval));
  }

  /// The cancelable replay loop. Publishes every message in [messages],
  /// [repeatCount] additional times after the first pass, waiting
  /// [messageInterval] between messages within a pass and [repeatInterval]
  /// between passes. Both waits are raced against [_replayStopSignal] so
  /// Stop is responsive mid-wait, not just between sends.
  Future<void> _runReplay(List<ExportedMessage> messages,
      Duration messageInterval, int repeatCount, Duration repeatInterval) async {
    final totalPasses = repeatCount + 1;
    final totalCount = messages.length * totalPasses;
    final stopSignal = Completer<void>();
    _replayStopSignal = stopSignal;

    setState(() {
      _isReplaying = true;
      _replaySentCount = 0;
      _replayTotalCount = totalCount;
      _replayCurrentPass = 1;
      _replayTotalPasses = totalPasses;
    });

    outer:
    for (var pass = 1; pass <= totalPasses; pass++) {
      if (mounted) setState(() => _replayCurrentPass = pass);

      for (var i = 0; i < messages.length; i++) {
        if (!mounted || stopSignal.isCompleted) break outer;
        if (currentStatus != Status.connected) {
          showSnackBar('Replay stopped: connection lost.');
          break outer;
        }

        final message = messages[i];
        final header =
            (message.headers != null && message.headers!.isNotEmpty)
                ? Header(headers: message.headers)
                : null;
        await natsClient.pub(message.subject, message.payload,
            header: header, buffer: false);
        if (mounted) setState(() => _replaySentCount++);

        final isLastMessageOfPass = i == messages.length - 1;
        if (!isLastMessageOfPass && messageInterval > Duration.zero) {
          await Future.any(
              [Future.delayed(messageInterval), stopSignal.future]);
          if (stopSignal.isCompleted) break outer;
        }
      }

      final isLastPass = pass == totalPasses;
      if (!isLastPass && repeatInterval > Duration.zero) {
        await Future.any([Future.delayed(repeatInterval), stopSignal.future]);
        if (stopSignal.isCompleted) break outer;
      }
    }

    _replayStopSignal = null;
    if (mounted) setState(() => _isReplaying = false);
  }

  void _stopReplay() {
    _replayStopSignal?.complete();
  }

  /// Injectable so tests can supply a chosen file's bytes without automating
  /// a real OS file dialog -- `null` (the default) leaves `ReplayConfigDialog`
  /// to fall back to its own real `file_picker`-backed default.
  Future<(Uint8List, String)?> Function()? replayPickFileOverride;

  Future<void> showReplayConfigDialog() async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      builder: (context) => ReplayConfigDialog(
        isConnected: currentStatus == Status.connected,
        onReplay: _startReplay,
        pickFile: replayPickFileOverride,
      ),
    );
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

  /// Real, `file_picker`-backed implementation of saving exported message
  /// bytes to disk -- the default used outside of tests, mirroring
  /// `object_store_dashboard.dart`'s `_defaultSaveDownloadedFile` exactly.
  static Future<void> _defaultSaveExportedMessages(
      String suggestedName, Uint8List bytes) async {
    if (kIsWeb) {
      await FilePicker.platform
          .saveFile(fileName: suggestedName, bytes: bytes);
      return;
    }
    final path = await FilePicker.platform.saveFile(fileName: suggestedName);
    if (path != null) {
      await File(path).writeAsBytes(bytes);
    }
  }

  /// Injectable so tests can capture exported bytes without automating a
  /// real OS save dialog -- `MyHomePage` has no existing fake-injection
  /// seam, so this lives directly on the state rather than the widget.
  Future<void> Function(String suggestedName, Uint8List bytes)
      saveExportedMessages = _defaultSaveExportedMessages;

  /// Messages serialized per yield to `Future.delayed(Duration.zero)` while
  /// exporting, so a large export doesn't freeze the UI thread.
  static const _exportChunkSize = 1000;

  /// Opens the Export menu ("Export Selected (N)"/"Export All (N)") anchored
  /// under the toolbar's Export button, keyed by [_exportMenuButtonKey].
  Future<void> _showExportMenu(int selectedCount, int totalCount) async {
    final renderBox =
        _exportMenuButtonKey.currentContext!.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'export_selected',
          enabled: selectedCount > 0,
          child: Text('Export Selected ($selectedCount)'),
        ),
        PopupMenuItem(
          value: 'export_all',
          enabled: totalCount > 0,
          child: Text('Export All ($totalCount)'),
        ),
      ],
    );
    if (value != null) {
      _showExportDialog(exportAll: value == 'export_all');
    }
  }

  /// Resolves which messages an Export action applies to and opens the
  /// confirmation dialog. `exportAll` exports every captured message (top-
  /// to-bottom order, independent of an active Filter -- "Export All" means
  /// everything captured); otherwise exports the current selection,
  /// recovering on-screen order from the unordered Set the same way
  /// `_copyMultiSelection` does.
  void _showExportDialog({required bool exportAll}) {
    final List<Message<dynamic>> messages;
    if (exportAll) {
      messages = items;
    } else {
      final selection = _effectiveSelection();
      messages = filteredItems.where(selection.contains).toList();
    }
    if (messages.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) => ExportConfirmDialog(
        count: messages.length,
        sourceLabel: exportAll ? 'captured' : 'selected',
        onConfirm: () => _exportMessages(messages),
      ),
    );
  }

  Future<void> _exportMessages(List<Message<dynamic>> messages) async {
    try {
      // The actual expensive work (JSON-encode + base64-encode each
      // payload, then UTF-8-encode the resulting line) happens inside this
      // chunked/yielded loop, not after it -- an earlier version bridged
      // `Message` -> `ExportedMessage` here (cheap) but then ran the real
      // encoding as one unbroken pass over the whole list afterward, which
      // defeated the point of chunking for a large export.
      final bytesBuilder = BytesBuilder(copy: false);
      for (var i = 0; i < messages.length; i += _exportChunkSize) {
        final end = (i + _exportChunkSize < messages.length)
            ? i + _exportChunkSize
            : messages.length;
        for (var j = i; j < end; j++) {
          final exported = exportedMessageFromNatsMessage(messages[j],
              capturedAt: _capturedAtFor(messages[j]));
          bytesBuilder.add(utf8.encode(encodeExportedMessageLine(exported)));
          bytesBuilder.addByte(0x0A); // '\n'
        }
        if (end < messages.length) {
          await Future.delayed(Duration.zero);
        }
      }

      final bytes = bytesBuilder.takeBytes();
      final suggestedName =
          'nats-export-${DateTime.now().millisecondsSinceEpoch}.ndjson';
      await saveExportedMessages(suggestedName, bytes);
      if (mounted) {
        showSnackBar('Exported ${messages.length} message(s).');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar('Export failed: $e');
      }
    }
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
          initialRetryInterval: retryInterval,
          initialJetStreamEnabled: jetStreamEnabled,
          initialKvEnabled: kvEnabled,
          initialObjectStoreEnabled: objectStoreEnabled,
          initialServiceDiscoveryEnabled: serviceDiscoveryEnabled,
          initialUpdateCheckEnabled: updateCheckEnabled,
          initialShowSubscriptionColors: showSubscriptionColors,
          onSave: (
            fontSize,
            retryIntervalValue,
            jetStreamEnabledValue,
            kvEnabledValue,
            objectStoreEnabledValue,
            serviceDiscoveryEnabledValue,
            updateCheckEnabledValue,
            showSubscriptionColorsValue,
          ) {
            final updateCheckJustEnabled =
                updateCheckEnabledValue && !updateCheckEnabled;
            setState(() {
              messageFontSize = fontSize;
              retryInterval = retryIntervalValue;
              jetStreamEnabled = jetStreamEnabledValue;
              kvEnabled = kvEnabledValue;
              objectStoreEnabled = objectStoreEnabledValue;
              serviceDiscoveryEnabled = serviceDiscoveryEnabledValue;
              updateCheckEnabled = updateCheckEnabledValue;
              showSubscriptionColors = showSubscriptionColorsValue;
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
    final header = (headers != null && headers.isNotEmpty)
        ? Header(headers: headers)
        : null;

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
          // The bulk action always operates on the existing multi-selection
          // regardless of which row's menu was opened -- opening the menu
          // on a row outside the current range does NOT implicitly fold it
          // in (matches Explorer/Finder/VS Code convention).
          final selection = _effectiveSelection();
          return [
            const PopupMenuItem(
              value: 'copy',
              child: Text('Copy'),
            ),
            if (selection.length > 1)
              PopupMenuItem(
                value: 'copy_selected',
                child: Text('Copy Selected (${selection.length})'),
              ),
            if (selection.length > 1)
              PopupMenuItem(
                value: 'export_selected',
                child: Text('Export Selected (${selection.length})'),
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
            case 'copy_selected':
              await _copyMultiSelection(_effectiveSelection());
              break;
            case 'export_selected':
              _showExportDialog(exportAll: false);
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
    // Only shown in the status bar's message-count text below when
    // something is actually selected -- an always-present "Selected: 0"
    // would just be noise alongside Total/Showing.
    final selectedCount = _effectiveSelection().length;

    return Focus(
      focusNode: _messageListFocusNode,
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
            // Ctrl+Shift+Up/Down: grow/shrink the multi-select range by one
            // row at a time from the current anchor.
            else if ((event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp) &&
                HardwareKeyboard.instance.isControlPressed &&
                HardwareKeyboard.instance.isShiftPressed) {
              final delta =
                  event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
              final newIndex =
                  (selectedIndex + delta).clamp(0, filteredItems.length - 1);
              setState(() {
                _selectRange(newIndex);
              });
              return KeyEventResult.handled;
            }
            // Handle Ctrl+C/Cmd+C shortcut
            else if (event.logicalKey == LogicalKeyboardKey.keyC &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              // Read the selected message(s) from `_effectiveSelection()`
              // itself rather than `filteredItems[selectedIndex]` -- once
              // Ctrl+Click can toggle rows independently of `selectedIndex`
              // (which tracks the last-clicked row, not necessarily one
              // that's still selected), the two can disagree.
              final selection = _effectiveSelection();
              if (selection.length > 1) {
                _copyMultiSelection(selection);
              } else if (selection.isNotEmpty) {
                Clipboard.setData(ClipboardData(
                    text: decodeMessageText(selection.first.byte)));
                showSnackBar('Copied to clipboard!');
              }
              return KeyEventResult.handled;
            }
            // Handle Esc key to un-select message
            else if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                selectedIndex = -1;
                _multiSelected.clear();
                _multiSelectActive = false;
                _selectionAnchor = null;
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
                        // Keyed on scheme so a history selection (which sets
                        // scheme in setState) rebuilds this field with a fresh
                        // initialValue -- initialValue is otherwise read once.
                        key: ValueKey(scheme),
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
                        child: _withConnectShortcut(_buildHostField()),
                      ),
                    ),
                    Flexible(
                      flex: 1,
                      child: _withConnectShortcut(TextFormField(
                        enabled: (currentStatus == Status.disconnected),
                        controller: portController,
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
                          isDark:
                              Provider.of<ThemeModel>(context, listen: false)
                                  .isDark(),
                          showSubscriptionColors: showSubscriptionColors,
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
                  if (serviceDiscoveryEnabled) const Tab(text: 'Services'),
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
                        if (serviceDiscoveryEnabled)
                          ServiceDiscoveryDashboard(
                            key: _serviceDiscoveryDashboardKey,
                            manager: currentStatus == Status.connected
                                ? _serviceDiscoveryManager
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
                  Text('Total Messages: ${items.length}, '
                      'Showing: ${filteredItems.length}'
                      '${selectedCount > 0 ? ', Selected: $selectedCount' : ''}'
                      '  |  '),
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
  /// A fixed extent (rather than letting each row size itself to its text)
  /// is what lets the list compensate the scroll offset *exactly* when new
  /// messages are prepended above a scrolled-away viewport (see
  /// `_insertMessages`), and also lets the scrollbar/fling locate any row
  /// analytically instead of building off-screen rows to measure them —
  /// the difference between smooth and janky on a list of thousands.
  /// Derived from the current font size so rows are always tall enough for
  /// their single line of text at whatever size the user picks; longer
  /// text is still clipped with an ellipsis exactly as before. The 56px
  /// floor keeps a short line from producing a row shorter than the
  /// trailing controls' tap target.
  double get _messageRowExtent {
    final textBlockHeight = messageFontSize * 1.3;
    final withPadding = textBlockHeight + 24;
    return withPadding > 56.0 ? withPadding : 56.0;
  }

  /// Builds the "Live Messages" tab content: the scrolling message list plus
  /// the bottom toolbar (clear/send/filter/find). Unchanged from before the
  /// JetStream tab was introduced, just extracted so it can be reused as a
  /// `TabBarView` page.
  Widget _buildLiveMessagesTab(Color evenRowColor, Color oddRowColor) {
    // Computed once per rebuild rather than once per row inside itemBuilder.
    final effectiveSelection = _effectiveSelection();
    return Column(
      children: <Widget>[
        if (_isReplaying)
          ReplayBanner(
            sentCount: _replaySentCount,
            totalCount: _replayTotalCount,
            currentPass: _replayCurrentPass,
            totalPasses: _replayTotalPasses,
            onStop: _stopReplay,
          ),
        if (messagesPaused)
          PausedBanner(
            pendingCount: pendingMessages.length,
            onResume: _resumeMessageList,
          ),
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
                          if (showSubscriptionColors)
                            Container(
                              key: const ValueKey('subscriptionColorBar'),
                              width: 4,
                              color: subColor ?? Colors.transparent,
                            ),
                          Expanded(
                            child: ListTile(
                              // ListTile centers its title within its own
                              // *computed natural* height, not whatever
                              // height it's actually given -- when the 56px
                              // floor in _messageRowExtent kicks in (small
                              // font sizes), that natural height is smaller
                              // than the row's real itemExtent, and without
                              // this the leftover space silently lands
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // Band by distance from the oldest message
                              // (always at the bottom), not the raw index:
                              // prepending new messages shifts every
                              // existing row's index, so banding on the
                              // index would flip every stripe as messages
                              // arrive. Distance-from-oldest is fixed per
                              // message, so stripes stay put.
                              tileColor: effectiveSelection.contains(message)
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
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
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
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
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
            Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 5, 10),
              child: IconButton.outlined(
                  key: _exportMenuButtonKey,
                  tooltip: 'Export messages',
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                  // Enabled whenever there's anything captured at all, even
                  // with no selection -- "Export All" doesn't need one, and
                  // disabling the whole button on selection alone would make
                  // that option unreachable from the toolbar.
                  onPressed: items.isNotEmpty
                      ? () => _showExportMenu(
                          effectiveSelection.length, items.length)
                      : null,
                  icon: const Icon(
                    Icons.file_download,
                    size: 18,
                  )),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 5, 10),
              child: IconButton.outlined(
                  tooltip: 'Replay messages from file',
                  style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
                  onPressed: currentStatus == Status.connected && !_isReplaying
                      ? showReplayConfigDialog
                      : null,
                  icon: const Icon(
                    Icons.upload_file,
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

/// Dropdown overlay for the Host field's connection history. Rows are rendered
/// from the [options] iterable Autocomplete passes in -- kept in lock-step with
/// its built-in highlight so Up/Down/Enter work -- with the highlighted row
/// tinted and scrolled into view. Each row carries an inline delete; a footer
/// clears the whole list. Deletes mutate the parent's list (via [onDelete]/
/// [onClear]); the visible rows re-sync on the next keystroke or reopen, since
/// Autocomplete only recomputes [options] when the field text changes.
class _ConnectionHistoryOptions extends StatefulWidget {
  const _ConnectionHistoryOptions({
    required this.options,
    required this.onSelected,
    required this.onDelete,
    required this.onClear,
  });

  final List<ConnectionHistoryEntry> options;
  final AutocompleteOnSelected<ConnectionHistoryEntry> onSelected;
  final ValueChanged<ConnectionHistoryEntry> onDelete;
  final VoidCallback onClear;

  @override
  State<_ConnectionHistoryOptions> createState() =>
      _ConnectionHistoryOptionsState();
}

class _ConnectionHistoryOptionsState extends State<_ConnectionHistoryOptions> {
  final ScrollController _scrollController = ScrollController();
  // Autocomplete only calls optionsBuilder -- and so only passes this widget
  // a fresh `options` -- when the field's text changes. A local copy lets an
  // inline delete/clear tap remove a row immediately instead of leaving it
  // visible until the next keystroke or reopen.
  late List<ConnectionHistoryEntry> _visibleOptions;

  @override
  void initState() {
    super.initState();
    _visibleOptions = List.of(widget.options);
  }

  @override
  void didUpdateWidget(covariant _ConnectionHistoryOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // optionsViewBuilder hands us a freshly `.toList()`'d `options` on every
    // rebuild of this overlay, not only when Autocomplete's own filtered
    // list actually changed -- e.g. _handleDelete's call into the parent
    // setState triggers exactly such a rebuild. Only resync from the
    // incoming list when its *content* actually changed (a real text-driven
    // refilter); otherwise this would silently undo the local removal
    // _handleDelete/_handleClear just applied, since the stale content would
    // reappear on the very next frame.
    if (!listEquals(oldWidget.options, widget.options)) {
      _visibleOptions = List.of(widget.options);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDelete(ConnectionHistoryEntry entry) {
    widget.onDelete(entry);
    setState(() {
      _visibleOptions.removeWhere((e) => identical(e, entry));
    });
  }

  void _handleClear() {
    widget.onClear();
    setState(() => _visibleOptions = []);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Indexes into Autocomplete's own (unfiltered-by-us) options list, so it
    // can point past the end of _visibleOptions right after a local delete --
    // harmless, the loop below just won't match it until the next sync.
    final highlightedIndex = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          // The overlay is anchored to the field but sized against the
          // screen, so bound the width to keep the menu readable but sane.
          constraints: const BoxConstraints(
              maxHeight: 280, minWidth: 280, maxWidth: 460),
          // Autocomplete tears this whole overlay down the instant the Host
          // field loses keyboard focus, and IconButton/ListTile normally grab
          // focus as part of handling a tap -- which would steal focus from
          // the field and destroy the overlay mid-gesture, silently
          // swallowing the tap before onTap/onPressed fires. Blocking focus
          // acquisition for every descendant keeps the field focused (and
          // this overlay alive) through the whole gesture, so taps land.
          child: Focus(
            descendantsAreFocusable: false,
            child: ListView(
              controller: _scrollController,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final (index, entry) in _visibleOptions.indexed)
                  Builder(builder: (context) {
                    final highlight = index == highlightedIndex;
                    if (highlight) {
                      // Mirror Flutter's own _AutocompleteOptions: scroll the
                      // keyboard-highlighted row into view after layout.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        Scrollable.ensureVisible(context, alignment: 0.5);
                      });
                    }
                    return ListTile(
                      dense: true,
                      // selectedTileColor (not a ColoredBox wrapper) paints
                      // the highlight -- wrapping ListTile in an opaque-ish
                      // ancestor between it and the overlay's own Material
                      // trips Flutter's "ink splashes may be invisible"
                      // debug check, since InkWell paints splashes on the
                      // nearest Material ancestor and a paint layer in
                      // between can occlude them.
                      selected: highlight,
                      selectedTileColor:
                          colorScheme.onSurface.withValues(alpha: 0.08),
                      title:
                          Text(entry.fullUri, overflow: TextOverflow.ellipsis),
                      onTap: () => widget.onSelected(entry),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove',
                        onPressed: () => _handleDelete(entry),
                      ),
                    );
                  }),
                if (_visibleOptions.isNotEmpty) const Divider(height: 1),
                if (_visibleOptions.isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_sweep, color: colorScheme.error),
                    title: Text('Clear history',
                        style: TextStyle(color: colorScheme.error)),
                    onTap: _handleClear,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
