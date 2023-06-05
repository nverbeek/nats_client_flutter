import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart';

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
      home: const MyHomePage(title: 'NATS Client'),
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
  String scheme = 'nats://';
  String fullUri = '';
  int selectedIndex = 0;

  // nats stuff
  late Client natsClient;
  bool isConnected = false;

  String testCode = """
  {
  "deploymentId": "SomeTempDeployment",
  "deviceId": "C6565BB1",
  "eventTime": "2023-05-23T15:05:05.003Z",
  "messageType": "MobileDeviceEventFact",
  "userId": "PDV23",
  "eventType": "WORKFLOW_STATE",
  "eventValue": "EngineTester.MainTask.clMainTask.stWelcome"
  }""";

  List<String> items = [];

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
    debugPrint('NVB about to connect to $fullUri');
    try {
      Uri uri = Uri.parse(fullUri);
      await natsClient.connect(uri, retry: false);
      isConnected = true;
      var sub = natsClient.sub('subject1');
      natsClient.pubString('subject1',
          '{"deploymentId":"SomeTempDeployment","deviceId":"C6565BB1","eventTime":"2023-05-23T15:05:05.003Z","messageType":"MobileDeviceEventFact","userId":"PDV23","eventType":"WORKFLOW_STATE","eventValue":"EngineTester.MainTask.clMainTask.stWelcome"}');
      var data = await sub.stream.first;

      debugPrint(data.string);
      setState(() {
        items.insert(0, data.string);
      });
    } on HttpException {
      showSnackBar('Failed to connect!');
    } on Exception {
      showSnackBar('Failed to connect!');
    } catch (_) {
      showSnackBar('Failed to connect!');
    }
  }

  void natsDisconnect() async {
    await natsClient.close();

    setState(() {
      isConnected = false;
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

  @override
  Widget build(BuildContext context) {
    updateFullUri();

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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: <String>['ws://', 'nats://'].map((String value) {
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
                    padding: const EdgeInsets.all(10.0),
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
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                  child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                          onPressed: isConnected ? null : natsConnect,
                          child: const Text('✔️'))),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                  child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                          onPressed: isConnected ? natsDisconnect : null,
                          child: const Text('❌'))),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Material(
                  child: ListTile(
                    title: Text(items[index],
                        style: const TextStyle(fontSize: 14)),
                    tileColor: selectedIndex == index
                        ? Theme.of(context).colorScheme.inversePrimary
                        : null,
                    onTap: () {
                      setState(() {
                        selectedIndex = index;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
            color: isConnected ? Colors.green[700] : const Color(0xff474747),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text('URL: $fullUri'),
                const Text(' | '),
                Text('Status: ${getConnectedString()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Flexible(
//   child: HighlightView(
//     testCode,
//     language: 'json',
//     theme: atomOneDarkTheme,
//     padding: const EdgeInsets.all(10),
//     textStyle: const TextStyle(
//         fontFamily:
//             'SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace'),
//   ),
// ),
