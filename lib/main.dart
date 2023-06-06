import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atelier-cave-dark.dart';
import 'package:loader_overlay/loader_overlay.dart';

void main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NATS Client',
      theme: ThemeData.dark(useMaterial3: true),
      home: const LoaderOverlay(
        child: MyHomePage(title: 'NATS Client'),
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
  String host = '35.196.236.50';
  String port = '4222';
  String subject = 'dwe.*';
  var availableSchemes = <String>['ws://', 'nats://'];
  String scheme = 'nats://';
  String fullUri = '';
  int selectedIndex = -1;
  List<Message> items = [];

  // nats stuff
  late Client natsClient;
  bool isConnected = false;

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
    context.loaderOverlay.show();
    natsClient = Client();
    debugPrint('About to connect to $fullUri');
    try {
      Uri uri = Uri.parse(fullUri);
      await natsClient.connect(uri, retry: false);
      isConnected = true;
      if (context.mounted) {
        context.loaderOverlay.hide();
      }
      var sub = natsClient.sub('dwe.*');
      natsClient.pubString('dwe.analytics',
          '{"deploymentId":"SomeTempDeployment","deviceId":"C6565BB1","eventTime":"2023-05-23T15:05:05.003Z","messageType":"MobileDeviceEventFact","userId":"PDV23","eventType":"WORKFLOW_STATE","eventValue":"EngineTester.MainTask.clMainTask.stWelcome"}');
      sub.stream.listen((event) {
        debugPrint(event.string);
        setState(() {
          items.insert(0, event);
          selectedIndex += 1;
        });
      });
    } on HttpException {
      showSnackBar('Failed to connect!');
      isConnected = false;
      if (context.mounted) {
        context.loaderOverlay.hide();
      }
    } on Exception {
      showSnackBar('Failed to connect!');
      isConnected = false;
      if (context.mounted) {
        context.loaderOverlay.hide();
      }
    } catch (_) {
      showSnackBar('Failed to connect!');
      isConnected = false;
      if (context.mounted) {
        context.loaderOverlay.hide();
      }
    }
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
                  theme: atelierCaveDarkTheme,
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
                      onChanged: (value) {
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
                        initialValue: host,
                        onChanged: (value) {
                          host = value;
                          updateFullUri();
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Host',
                        ),
                        readOnly: isConnected,
                      ),
                    ),
                  ),
                  Flexible(
                    flex: 1,
                    child: TextFormField(
                      initialValue: port,
                      onChanged: (value) {
                        port = value;
                        updateFullUri();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Port',
                      ),
                      readOnly: isConnected,
                    ),
                  ),
                  Flexible(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                      child: TextFormField(
                        initialValue: subject,
                        onChanged: (value) {
                          subject = value;
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Subject',
                        ),
                        readOnly: isConnected,
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
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Material(
                  child: ListTile(
                    title: Text(
                      items[index].string,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 5,
                    ),
                    tileColor: selectedIndex == index
                        ? Theme.of(context).colorScheme.inversePrimary
                        : index % 2 == 0
                            ? Colors.grey[900]
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
                          child: Chip(label: Text(items[index].subject!)),
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
                                await Clipboard.setData(
                                    ClipboardData(text: items[index].string));
                                showSnackBar('Copied to clipboard!');
                                break;
                              case 'detail':
                                var json = jsonDecode(items[index].string);
                                var encoder =
                                    const JsonEncoder.withIndent("  ");
                                var formattedJson = encoder.convert(json);
                                showDetailDialog(formattedJson);
                                break;
                              case 'replay':
                                if (isConnected) {
                                  natsClient.pubString(items[index].subject!,
                                      items[index].string);
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
            ],
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(5, 2, 5, 4),
            color: isConnected ? Colors.green[700] : const Color(0xff474747),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text('URL: $fullUri'),
                const Text('  |  '),
                Text('Status: ${getConnectedString()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
