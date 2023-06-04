import 'package:flutter/material.dart';
import 'package:dart_nats/dart_nats.dart';

void main() {
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

  void natsConnect() async {
    var client = Client();
    debugPrint('NVB about to connect to $fullUri');
    try {
      await client.connect(Uri.parse(fullUri), retry: false);
    } on NatsException {
      debugPrint('Failed to connect');
    }
    var sub = client.sub('subject1');
    client.pubString('subject1',
        '{"deploymentId":"SomeTempDeployment","deviceId":"C6565BB1","eventTime":"2023-05-23T15:05:05.003Z","messageType":"MobileDeviceEventFact","userId":"PDV23","eventType":"WORKFLOW_STATE","eventValue":"EngineTester.MainTask.clMainTask.stWelcome"}');
    var data = await sub.stream.first;

    debugPrint(data.string);
    setState(() {
      items.insert(0, data.string);
    });
    client.unSub(sub);
    await client.close();
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
                    onChanged: (value) {
                      scheme = value!;
                      updateFullUri();
                    },
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
                          onPressed: natsConnect, child: const Text('✔️'))),
                ),
              ],
            ),
          ),
          Text(
            fullUri,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(items[index]),
                  tileColor: selectedIndex == index ? Theme.of(context).colorScheme.inversePrimary : null,
                  onTap: () {
                    setState(() {
                      selectedIndex = index;
                    });
                  },
                );
              },
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