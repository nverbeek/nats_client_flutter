import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/main.dart' show ThemeModel;
import 'package:nats_client_flutter/message_detail_dialog.dart';
import 'package:provider/provider.dart';

/// Wraps [child] with the `ThemeModel` provider that `MessageDetailDialog`
/// needs whenever it renders a non-empty payload (its JSON syntax
/// highlighter reads the current theme via `Provider.of<ThemeModel>`).
Widget withThemeModel(Widget child) {
  return ChangeNotifierProvider<ThemeModel>(
    create: (_) => ThemeModel('dark'),
    child: child,
  );
}

void main() {
  testWidgets(
      'renders header version and headers as a table row when present',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: 'NATS/1.0',
          headers: {'X-Trace-Id': 'abc123'},
          formattedJson: '',
        ),
      ),
    ));

    expect(find.text('Header Version'), findsOneWidget);
    expect(find.text('NATS/1.0'), findsOneWidget);
    expect(find.text('Headers'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    // Key and value are separate, individually-selectable cells now, not a
    // single flattened "key: value" block.
    expect(find.text('X-Trace-Id'), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
    expect(find.textContaining('X-Trace-Id: abc123'), findsNothing);
  });

  testWidgets('multiple headers each render as their own table row',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: '',
          headers: {'X-Trace-Id': 'abc123', 'X-Request-Id': 'req-456'},
          formattedJson: '',
        ),
      ),
    ));

    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(2));
    expect(find.text('X-Trace-Id'), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
    expect(find.text('X-Request-Id'), findsOneWidget);
    expect(find.text('req-456'), findsOneWidget);
  });

  testWidgets(
      'tapping the headers copy button copies raw key: value text and shows feedback',
      (tester) async {
    final copiedData = <ClipboardData>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(ClipboardData(text: call.arguments['text'] as String));
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: '',
          headers: {'X-Trace-Id': 'abc123', 'X-Request-Id': 'req-456'},
          formattedJson: '',
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copiedData.single.text, 'X-Trace-Id: abc123\nX-Request-Id: req-456');
    expect(find.text('Copied!'), findsOneWidget);
  });

  testWidgets('shows the formatted payload and a copy button when non-empty',
      (tester) async {
    await tester.pumpWidget(withThemeModel(
      const MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: {},
            formattedJson: '{\n    "a": 1\n}',
          ),
        ),
      ),
    ));

    expect(find.text('Payload'), findsOneWidget);
    // HighlightView renders syntax-highlighted JSON as a RichText with many
    // small TextSpans, so `findRichText` is needed to see the joined text.
    expect(find.textContaining('"a": 1', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.textContaining('no payload'), findsNothing);
  });

  testWidgets('no Text/Hex toggle when payloadBytes is not provided',
      (tester) async {
    await tester.pumpWidget(withThemeModel(
      const MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: {},
            formattedJson: '{"a":1}',
          ),
        ),
      ),
    ));

    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets(
      'defaults to Text view and shows a manual Hex toggle for a valid UTF-8 payload',
      (tester) async {
    await tester.pumpWidget(withThemeModel(
      MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: const {},
            formattedJson: '{\n    "a": 1\n}',
            payloadBytes: Uint8List.fromList('{"a":1}'.codeUnits),
          ),
        ),
      ),
    ));

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.textContaining('"a": 1', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();

    expect(find.textContaining('7b 22 61'), findsOneWidget); // `{"a`
  });

  testWidgets('auto-selects Hex view for a payload that is not valid UTF-8',
      (tester) async {
    await tester.pumpWidget(withThemeModel(
      MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: const {},
            formattedJson: '��',
            payloadBytes: Uint8List.fromList([0xFF, 0xFE]),
          ),
        ),
      ),
    ));

    expect(find.textContaining('ff fe'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ff fe'), findsNothing);
  });

  testWidgets(
      'Hex view background matches the Text/JSON view background (HighlightView\'s theme paints colorScheme.surface behind the code, so a bare/transparent Hex view would look inconsistent)',
      (tester) async {
    await tester.pumpWidget(withThemeModel(
      MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: const {},
            formattedJson: '��',
            payloadBytes: Uint8List.fromList([0xFF, 0xFE]),
          ),
        ),
      ),
    ));

    final context = tester.element(find.byType(MessageDetailDialog));
    final expectedBackground = Theme.of(context).colorScheme.surface;

    final container = tester
        .widget<Container>(find.byKey(const Key('hexPayloadBackground')));

    expect(container.color, expectedBackground);
  });

  testWidgets('copy button copies the hex dump while the Hex view is active',
      (tester) async {
    final copiedData = <ClipboardData>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(ClipboardData(text: call.arguments['text'] as String));
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(withThemeModel(
      MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: const {},
            formattedJson: 'Hi!',
            payloadBytes: Uint8List.fromList('Hi!'.codeUnits),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copiedData.single.text, contains('48 69 21'));
  });

  testWidgets('tapping copy copies the payload and shows "Copied!" feedback',
      (tester) async {
    final copiedData = <ClipboardData>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData.add(ClipboardData(text: call.arguments['text'] as String));
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(withThemeModel(
      const MaterialApp(
        home: Scaffold(
          body: MessageDetailDialog(
            headerVersion: '',
            headers: {},
            formattedJson: '{"a":1}',
          ),
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copiedData.single.text, '{"a":1}');
    expect(find.text('Copied!'), findsOneWidget);
  });

  testWidgets('shows a "no payload" panel and no copy button when empty',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: '',
          headers: {},
          formattedJson: '',
        ),
      ),
    ));

    expect(find.textContaining('no payload'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);
  });

  testWidgets('shows a Received row with the full timestamp when capturedAt is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: '',
          headers: const {},
          formattedJson: '',
          capturedAt: DateTime(2026, 3, 5, 14, 7, 9, 42),
        ),
      ),
    ));

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('2026-03-05 02:07:09.042 PM'), findsOneWidget);
  });

  testWidgets('shows no Received row when capturedAt is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageDetailDialog(
          headerVersion: '',
          headers: {},
          formattedJson: '',
        ),
      ),
    ));

    expect(find.text('Received'), findsNothing);
  });

  testWidgets('close icon and Close button both pop the dialog',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => const MessageDetailDialog(
                  headerVersion: '',
                  headers: {},
                  formattedJson: '',
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(MessageDetailDialog), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageDetailDialog), findsNothing);
  });
}
