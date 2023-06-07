import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atelier-cave-dark.dart';
import 'package:flutter_highlighter/themes/atelier-cave-light.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:provider/provider.dart';

void main() async {
  runApp(const MyApp());
}

class ThemeModel with ChangeNotifier {
  ThemeMode _mode;
  ThemeMode get mode => _mode;
  ThemeModel({ThemeMode mode = ThemeMode.dark}) : _mode = mode;

  void toggleMode() {
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  bool isDark() {
    if (_mode == ThemeMode.dark) {
      return true;
    }
    return false;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeModel>(
      create: (_) => ThemeModel(),
      child: Consumer<ThemeModel>(
        builder: (_, model, __) {
          return MaterialApp(
            title: 'NATS Client',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(useMaterial3: true),
            darkTheme: ThemeData.dark(useMaterial3: true),
            themeMode: model.mode,
            home: const LoaderOverlay(
              child: MyHomePage(title: 'NATS Client'),
            ),
          );
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //String host = '35.196.236.50';
  String host = '10.0.0.38';
  String port = '4222';
  String subject = 'dwe.*';
  var availableSchemes = <String>['ws://', 'nats://'];
  String scheme = 'nats://';
  String fullUri = '';
  int selectedIndex = -1;
  String currentFilter = '';
  List<Message> filteredItems = [];
  List<Message> items = [];

  // nats stuff
  late Client natsClient;
  bool isConnected = false;
  String connectionStateString = '';

  var filterBoxController = TextEditingController();
  var matchBoxController = TextEditingController();

  @override
  initState() {
    filteredItems = items;
    super.initState();
  }

  void _runFilter() {
    List<Message<dynamic>> results = [];
    if (currentFilter.isEmpty) {
      // if the search field is empty or only contains white-space, we'll display all items
      results = items;
    } else {
      results = items
          .where((message) => message.string
              .toLowerCase()
              .contains(currentFilter.toLowerCase()))
          .toList();
      // we use the toLowerCase() method to make it case-insensitive
    }

    // Refresh the UI
    setState(() {
      filteredItems = results;
    });
  }

  // ignore: unused_element
  void _runMatch() {}

  void updateFullUri() {
    setState(() {
      fullUri = '$scheme$host:$port';
    });
  }

  String getConnectedString() {
    if (isConnected) {
      return 'Connected';
    }
    return 'Disconnected';
  }

  void natsConnect() async {
    natsClient = Client();

    showLoadingSpinner();
    debugPrint('About to connect to $fullUri');
    try {
      Uri uri = Uri.parse(fullUri);
      natsClient.statusStream.listen((Status event) {
        debugPrint('Connection status event $event');
        String stateString = '';

        switch(event) {
          case Status.connected:
            setStateConnected();
            stateString = 'Connected';
            break;
          case Status.closed:
          case Status.disconnected:
            setStateDisconnected();
            stateString = 'Disconnected';
            break;
          case Status.tlsHandshake:
            stateString = 'TLS Handshake';
            break;
          case Status.infoHandshake:
            stateString = 'Info Handshake';
            break;
          case Status.reconnecting:
            stateString = 'Reconnecting';
            break;
          case Status.connecting:
            stateString = 'Connecting';
            break;
        }

        setState(() {
          connectionStateString = stateString;
        });
      });
      await natsClient.connect(uri, retry: false);
      var sub = natsClient.sub('dwe.*');
      sub.stream.listen((event) {
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
      });
    } on HttpException {
      showSnackBar('Failed to connect!');
      setStateDisconnected();
    } on Exception {
      showSnackBar('Failed to connect!');
      setStateDisconnected();
    } catch (_) {
      showSnackBar('Failed to connect!');
      setStateDisconnected();
    }
  }

  void showLoadingSpinner() {
    setState(() {
      context.loaderOverlay.show();
    });
  }

  void hideLoadingSpinner() {
    setState(() {
      context.loaderOverlay.hide();
    });
  }

  void setStateConnected() {
    setState(() {
      isConnected = true;
      if (context.mounted) {
        hideLoadingSpinner();
      }
    });
  }

  void setStateDisconnected() {
    setState(() {
      isConnected = false;
      connectionStateString = 'Disconnected';
      if (context.mounted) {
        hideLoadingSpinner();
      }
    });
  }

  void natsDisconnect() async {
    await natsClient.close();

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

  Future<void> showDetailDialog(String json) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Message Detail'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                HighlightView(
                  json,
                  language: 'json',
                  theme: Provider.of<ThemeModel>(context, listen: false).isDark()
                      ? atelierCaveDarkTheme
                      : atelierCaveLightTheme,
                  padding: const EdgeInsets.all(10),
                  textStyle: const TextStyle(
                      fontSize: 14,
                      fontFamily:
                          'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
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
              onPressed: () =>
                  Provider.of<ThemeModel>(context, listen: false).toggleMode()),
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
                        border: OutlineInputBorder(),
                      ),
                      items: availableSchemes.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      value: scheme,
                      onChanged: isConnected
                          ? null
                          : (value) {
                              scheme = value!;
                              updateFullUri();
                            },
                      hint: const Text('Scheme'),
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: TextFormField(
                        enabled: !isConnected,
                        initialValue: host,
                        onChanged: (value) {
                          host = value;
                          updateFullUri();
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Host',
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 1,
                    child: TextFormField(
                      enabled: !isConnected,
                      initialValue: port,
                      onChanged: (value) {
                        port = value;
                        updateFullUri();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Port',
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: TextFormField(
                        enabled: !isConnected,
                        initialValue: subject,
                        onChanged: (value) {
                          subject = value;
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Subject',
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: isConnected ? null : natsConnect,
                            child: const Icon(Icons.check))),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                            onPressed: isConnected ? natsDisconnect : null,
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
                    title: Text(
                      filteredItems[index].string,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 5,
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
                        Tooltip(
                          message: 'Subject',
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 5, 0),
                            child: Chip(
                                label: Text(filteredItems[index].subject!)),
                          ),
                        ),
                        PopupMenuButton(
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
                                var json =
                                    jsonDecode(filteredItems[index].string);
                                var encoder =
                                    const JsonEncoder.withIndent("  ");
                                var formattedJson = encoder.convert(json);
                                showDetailDialog(formattedJson);
                                break;
                              case 'replay':
                                if (isConnected) {
                                  natsClient.pubString(
                                      filteredItems[index].subject!,
                                      filteredItems[index].string);
                                } else {
                                  showSnackBar(
                                      'Not connected, cannot replay message');
                                }
                                break;
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
                padding: const EdgeInsets.all(5),
                child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                        onPressed: clearMessageList,
                        child: const Icon(
                          Icons.delete,
                          size: 18,
                        ))),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
                  child: TextFormField(
                    controller: filterBoxController,
                    onChanged: (value) {
                      currentFilter = value;
                      _runFilter();
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Filter',
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
                  padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
                  child: TextFormField(
                    controller: matchBoxController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Match',
                      prefixIcon: const Icon(Icons.highlight),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            matchBoxController.clear();
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
            color: Provider.of<ThemeModel>(context, listen: false).isDark() ? isConnected ? Colors.green[700] : const Color(0xff474747) : isConnected ? Colors.green[400] : Colors.grey[400],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                    'Total Messages: ${items.length}, Showing: ${filteredItems.length}  |  '),
                Text('URL: $fullUri'),
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
