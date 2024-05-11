import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atelier-cave-dark.dart';
import 'package:flutter_highlighter/themes/atelier-cave-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart' as constants;

void main() async {
  // must wait for widgets to initialize before we are able to use SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  // setup a reference to the shared preferences instance
  SharedPreferences prefs = await SharedPreferences.getInstance();

  // attempt to read previous connection info from preferences
  String? tempScheme = prefs.getString(constants.prefScheme);
  String? tempHost = prefs.getString(constants.prefHost);
  String? tempPort = prefs.getString(constants.prefPort);
  String? tempSubject = prefs.getString(constants.prefSubject);
  String? tempTheme = prefs.getString(constants.prefTheme);

  // if needed, default the values
  tempScheme ??= constants.defaultScheme;
  tempHost ??= constants.defaultHost;
  tempPort ??= constants.defaultPort;
  tempSubject ??= constants.defaultSubject;
  tempTheme ??= constants.darkTheme;

  // get the application's version number
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String appVersion = packageInfo.version;

  // run the ui
  runApp(MyApp(
      appVersion, tempScheme, tempHost, tempPort, tempSubject, tempTheme));
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
  const MyApp(this.appVersion, this.scheme, this.host, this.port, this.subject,
      this.theme,
      {super.key});

  final String appVersion;
  final String scheme;
  final String host;
  final String port;
  final String subject;
  final String theme;

  /// Root UI of the entire application
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeModel>(
      create: (_) => ThemeModel(theme),
      child: Consumer<ThemeModel>(
        builder: (_, model, __) {
          return MaterialApp(
            title: 'NATS Client',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme:
                  ColorScheme.fromSeed(seedColor: Colors.lightBlue.shade900),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  brightness: Brightness.dark,
                  seedColor: Colors.lightBlue.shade900),
            ),
            themeMode: model.mode,
            home: LoaderOverlay(
              child: MyHomePage(
                  appVersion, 'NATS Client', scheme, host, port, subject),
            ),
          );
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage(this.appVersion, this.title, this.scheme, this.host,
      this.port, this.subject,
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
  final String subject;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String host = constants.defaultHost;
  String port = constants.defaultPort;
  String subject = constants.defaultSubject;
  var availableSchemes = <String>['ws://', 'nats://'];
  String scheme = constants.defaultScheme;
  String fullUri = '';
  int selectedIndex = -1;
  String currentFilter = '';
  String currentFind = '';
  Status currentStatus = Status.disconnected;
  List<Message<dynamic>> filteredItems = [];
  List<Message<dynamic>> items = [];

  // nats stuff
  late Client natsClient;
  bool isConnected = false;
  String connectionStateString = constants.disconnected;

  var filterBoxController = TextEditingController();
  var findBoxController = TextEditingController();

  // user preferences
  late SharedPreferences prefs;

  @override
  initState() {
    initializePreferences();
    filteredItems = items;
    scheme = widget.scheme;
    host = widget.host;
    port = widget.port;
    subject = widget.subject;
    updateFullUri();
    super.initState();
  }

  /// initialize the shared preferences instance
  initializePreferences() async {
    prefs = await SharedPreferences.getInstance();
  }

  void _runFilter() {
    List<Message<dynamic>> results = [];
    if (currentFilter.isEmpty) {
      // if the search field is empty or only contains white-space, we'll display all items
      results = items;
    } else {
      // filter the items based on the message payload against the search term
      results = items
          .where((message) => message.string
              .toLowerCase()
              // we use the toLowerCase() method to make it case-insensitive
              .contains(currentFilter.toLowerCase()))
          .toList();
    }

    // Refresh the UI
    setState(() {
      filteredItems = results;
    });
  }

  void updateFullUri() {
    setState(() {
      fullUri = '$scheme$host:$port';
    });
  }

  void natsConnect() async {
    natsClient = Client();

    // save the user's connection properties to preferences.
    // we can read these out at startup.
    await prefs.setString(constants.prefScheme, scheme);
    await prefs.setString(constants.prefHost, host);
    await prefs.setString(constants.prefPort, port);
    await prefs.setString(constants.prefSubject, subject);

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

        setState(() {
          connectionStateString = stateString;
        });
      });

      // process the subjects, see if there are more than one
      if (subject.contains(',')) {
        // there are more than one subject to listen to
        var subjects = subject.split(',');

        for (String subject in subjects) {
          subscribeToSubject(subject.trim());
        }
      } else {
        subscribeToSubject(subject.trim());
      }

      // get the security context if applicable
      SecurityContext? securityContext = getSecurityContext();

      // finally, make the connection attempt
      await natsClient.connect(uri,
          retry: true, retryCount: -1, securityContext: securityContext);
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
  /// are configured.
  SecurityContext? getSecurityContext() {
    // raed out the certificate paths from preferences

    // trusted certificate
    var savedTrustedCertificate =
        prefs.getString(constants.prefTrustedCertificate);
    List<int>? savedTrustedCertificateBytes;
    if (savedTrustedCertificate != null) {
      savedTrustedCertificateBytes =
          gzip.decode(base64.decode(savedTrustedCertificate));
    }

    // certificate chain
    var savedCertificateChain = prefs.getString(constants.prefCertificateChain);
    List<int>? savedCertificateChainBytes;
    if (savedCertificateChain != null) {
      savedCertificateChainBytes =
          gzip.decode(base64.decode(savedCertificateChain));
    }

    // private key
    var savedPrivateKey = prefs.getString(constants.prefPrivateKey);
    List<int>? savedPrivateKeyBytes;
    if (savedPrivateKey != null) {
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

  void subscribeToSubject(subject) {
    debugPrint('Subscribing to $subject');
    var sub = natsClient.sub(subject);

    sub.stream.listen((event) {
      handleIncomingMessage(event);
    });
  }

  void handleIncomingMessage(event) {
    debugPrint(event.string);
    setState(() {
      items.insert(0, event);
      // if an item is selected, we need to move the selection since
      // we just put a new item in the list
      if (selectedIndex > -1) {
        selectedIndex += 1;
      }
      _runFilter();
    });
  }

  void setStateConnected() {
    setState(() {
      isConnected = true;
      if (context.mounted) {}
    });
  }

  void setStateDisconnected() {
    setState(() {
      isConnected = false;
      connectionStateString = constants.disconnected;
      if (context.mounted) {}
    });
  }

  void natsDisconnect() async {
    await natsClient.forceClose();

    setState(() {
      isConnected = false;
    });
  }

  void clearMessageList() {
    setState(() {
      items.clear();
      filteredItems.clear();
    });
  }

  void showSnackBar(String message) {
    var snackBar = SnackBar(
      content: Text(message),
    );

    // Find the ScaffoldMessenger in the widget tree
    // and use it to show a SnackBar.
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
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

    String headerText = '';
    if (headers.isNotEmpty) {
      headers.forEach((k, v) => headerText += '$k: $v\n');
      headerText = headerText.trim();
    }

    // format the data, if we can
    var formattedJson = '';
    try {
      var json = jsonDecode(message.string);
      var encoder = const JsonEncoder.withIndent("  ");
      formattedJson = encoder.convert(json);
    } on FormatException {
      formattedJson = message.string;
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Message Detail'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                if (headerVersion.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                    child: Text(
                      'Header Version',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                if (headerVersion.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                    child: SelectableText(headerVersion),
                  ),
                if (headers.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                    child: Text(
                      'Headers',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                if (headers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                    child: SelectableText(headerText),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                  child: Text(
                    'Payload',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                  child: HighlightView(
                    formattedJson,
                    language: 'json',
                    theme:
                        Provider.of<ThemeModel>(context, listen: false).isDark()
                            ? atelierCaveDarkTheme
                            : atelierCaveLightTheme,
                    padding: const EdgeInsets.all(10),
                    textStyle: const TextStyle(
                        fontSize: 14,
                        fontFamily:
                            'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Displays a dialog allowing a user to send a custom message.
  /// Subject box will be pre-filled with [subject] or [replyToSubject] if provided.
  /// Data box will be pre-filled with [data] if provided.
  Future<void> showSendMessageDialog(
      String? subject, String? replyToSubject, String? data) async {
    var subjectBoxController = TextEditingController();
    var dataBoxController = TextEditingController();

    if (subject != null && subject.isNotEmpty) {
      subjectBoxController.text = subject;
    }
    if (data != null && data.isNotEmpty) {
      dataBoxController.text = data;
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Send Message'),
          content: Column(
            children: <Widget>[
              TextFormField(
                maxLines: null,
                controller: subjectBoxController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Subject',
                  labelText: 'Subject',
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                  child: TextFormField(
                    expands: true,
                    controller: dataBoxController,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Data',
                      labelText: 'Data',
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Send'),
              onPressed: () {
                natsClient.pubString(subjectBoxController.value.text,
                    dataBoxController.value.text);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Displays an application help dialog containing a syntax-highlighted markdown document.
  Future<void> showHelpDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: ListBody(
                children: [
                  FutureBuilder(
                      future: DefaultAssetBundle.of(context)
                          .loadString('assets/app_help.md')
                          .then((value) => value.replaceFirst(
                              '%APP_VERSION%', widget.appVersion)),
                      builder: (context, snapshot) {
                        return MarkdownBody(
                          data: snapshot.data ?? '',
                          shrinkWrap: true,
                        );
                      }),
                ],
              ),
            )),
      ),
    );
  }

  /// Displays a dialog allowing a user to select certificates.
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

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Security Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: [
                  Flexible(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                        child: TextFormField(
                          maxLines: null,
                          readOnly: true,
                          controller: trustedCertificateController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Trusted Certificate',
                            labelText: 'Trusted Certificate',
                          ),
                        )),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: () {
                              pickFile().then((chosenFile) => {
                                    handleTrustedCertificateFile(
                                        chosenFile.$1,
                                        chosenFile.$2,
                                        trustedCertificateController)
                                  });
                            },
                            child: const Icon(Icons.folder_open))),
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: certificateChainController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Certificate Chain',
                          labelText: 'Certificate Chain',
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: () {
                              pickFile().then((chosenFile) => {
                                    handleCertificateChainFile(
                                        chosenFile.$1,
                                        chosenFile.$2,
                                        certificateChainController)
                                  });
                            },
                            child: const Icon(Icons.folder_open))),
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: TextFormField(
                        maxLines: null,
                        readOnly: true,
                        controller: privateKeyController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Private Key',
                          labelText: 'Private Key',
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: () {
                              pickFile().then((chosenFile) => {
                                    handlePrivateKeyFile(chosenFile.$1,
                                        chosenFile.$2, privateKeyController)
                                  });
                            },
                            child: const Icon(Icons.folder_open))),
                  ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Prompts the user to pick a certificate file
  Future<(Uint8List?, String)> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pem'],
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

  bool isTlsConnection() {
    if (natsClient.connected && natsClient.info != null) {
      if (natsClient.info?.tlsRequired != null &&
          natsClient.info?.tlsRequired == true) {
        return true;
      }
    }
    return false;
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        actions: [
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
                      value: scheme,
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
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: (currentStatus == Status.disconnected)
                                ? showSecuritySettingsDialog
                                : null,
                            child: const Icon(Icons.lock))),
                  ),
                  Flexible(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: TextFormField(
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
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 1,
                    child: TextFormField(
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
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: TextFormField(
                        enabled: (currentStatus == Status.disconnected),
                        initialValue: widget.subject,
                        onChanged: (value) {
                          subject = value;
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Subjects',
                          labelText: 'Subjects',
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: (currentStatus == Status.disconnected)
                                ? natsConnect
                                : null,
                            child: const Icon(Icons.check))),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: (currentStatus != Status.disconnected)
                                ? natsDisconnect
                                : null,
                            child: const Icon(Icons.close))),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                return Material(
                  child: ListTile(
                    title: RegexTextHighlight(
                      text: filteredItems[index].string,
                      searchTerm: currentFind,
                      highlightStyle: TextStyle(
                        background: Paint()
                          ..color =
                              Theme.of(context).colorScheme.inversePrimary,
                      ),
                    ),
                    tileColor: selectedIndex == index
                        ? Theme.of(context).colorScheme.inversePrimary
                        : index % 2 == 0
                            ? Theme.of(context).colorScheme.surfaceVariant
                            : null,
                    onTap: () {
                      setState(() {
                        if (index == selectedIndex) {
                          // user tapped the already-selected item.
                          // un-select it
                          selectedIndex = -1;
                        } else {
                          selectedIndex = index;
                        }
                      });
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 450),
                          child: Tooltip(
                            message: filteredItems[index].subject!,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 5, 0),
                              child: Chip(
                                  label: Text(filteredItems[index].subject!,
                                      overflow: TextOverflow.ellipsis)),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          itemBuilder: (context) {
                            return [
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Copy'),
                              ),
                              const PopupMenuItem(
                                value: 'detail',
                                child: Text('Detail'),
                              ),
                              const PopupMenuItem(
                                value: 'replay',
                                child: Text('Replay'),
                              ),
                              const PopupMenuItem(
                                value: 'edit_and_send',
                                child: Text('Edit & Send'),
                              ),
                              const PopupMenuItem(
                                value: 'reply_to',
                                child: Text('Reply To'),
                              )
                            ];
                          },
                          onSelected: (String value) async {
                            switch (value) {
                              case 'copy':
                                await Clipboard.setData(ClipboardData(
                                    text: filteredItems[index].string));
                                showSnackBar('Copied to clipboard!');
                                break;
                              case 'detail':
                                showDetailDialog(filteredItems[index]);
                                break;
                              case 'replay':
                                if (currentStatus == Status.connected) {
                                  natsClient.pubString(
                                      filteredItems[index].subject!,
                                      filteredItems[index].string);
                                } else {
                                  showSnackBar(
                                      'Not connected, cannot replay message');
                                }
                                break;
                              case 'edit_and_send':
                                if (currentStatus == Status.connected) {
                                  showSendMessageDialog(
                                      filteredItems[index].subject!,
                                      null,
                                      filteredItems[index].string);
                                } else {
                                  showSnackBar(
                                      'Not connected, cannot send message');
                                }
                              case 'reply_to':
                                if (currentStatus == Status.connected) {
                                  if (filteredItems[index].replyTo != null &&
                                      filteredItems[index]
                                          .replyTo!
                                          .isNotEmpty) {
                                    showSendMessageDialog(
                                        filteredItems[index].replyTo,
                                        null,
                                        null);
                                  } else {
                                    showSnackBar(
                                        'This message has no replyTo subject');
                                  }
                                } else {
                                  showSnackBar(
                                      'Not connected, cannot send message');
                                }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 5, 10),
                child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                        onPressed: clearMessageList,
                        child: const Icon(
                          Icons.delete,
                          size: 18,
                        ))),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(0, 10, 5, 10),
                child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                        onPressed: currentStatus == Status.connected
                            ? () {
                                showSendMessageDialog(null, null, null);
                              }
                            : null,
                        child: const Icon(
                          Icons.send,
                          size: 18,
                        ))),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                  child: TextFormField(
                    controller: filterBoxController,
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
                if (isTlsConnection())
                  const Padding(
                    padding: EdgeInsets.fromLTRB(5, 2, 0, 0),
                    child: Icon(Icons.lock_outline, size: 15),
                  ),
                const Text('  |  '),
                Text('Status: $connectionStateString'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
