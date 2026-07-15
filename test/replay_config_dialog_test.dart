import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/message_export.dart';
import 'package:nats_client_flutter/replay_config_dialog.dart';

Uint8List _ndjsonBytes(List<ExportedMessage> messages) =>
    Uint8List.fromList(utf8.encode(encodeExportedMessagesNdjson(messages)));

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required bool isConnected,
    required Future<(Uint8List, String)?> Function() pickFile,
    void Function(List<ExportedMessage>, Duration, int, Duration)? onReplay,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => ReplayConfigDialog(
                isConnected: isConnected,
                onReplay: onReplay ?? (_, __, ___, ____) {},
                pickFile: pickFile,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<ExportedMessage> makeMessages(int count) => List.generate(
        count,
        (i) => ExportedMessage(
          subject: 'subj.$i',
          payload: Uint8List.fromList([i]),
        ),
      );

  testWidgets('disconnected disables Start Replay regardless of file/fields',
      (tester) async {
    final messages = makeMessages(4);
    await pumpDialog(
      tester,
      isConnected: false,
      pickFile: () async => (_ndjsonBytes(messages), 'export.ndjson'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();
    expect(find.text('export.ndjson'), findsOneWidget);

    final startButton = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Start Replay'));
    expect(startButton.onPressed, isNull);
  });

  testWidgets(
      'a valid file shows filename/count, helper text, and a live preview '
      'matching the documented formula (including repeatCount=0)',
      (tester) async {
    final messages = makeMessages(4);
    await pumpDialog(
      tester,
      isConnected: true,
      pickFile: () async => (_ndjsonBytes(messages), 'export.ndjson'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();

    expect(find.text('export.ndjson'), findsOneWidget);
    expect(find.text('4 message(s) parsed.'), findsOneWidget);
    expect(find.text('0 = play once, no repeat'), findsOneWidget);

    // Default fields are all '0': repeatCount=0 -> totalPasses=1,
    // total = 4 * 1 = 4, estimated = 0 -> "<1s".
    expect(find.text('Will send 4 messages over <1s'), findsOneWidget);

    final fields = find.byType(TextFormField);
    // messageInterval=1000ms, repeatCount=2, repeatInterval=5000ms.
    // total = 4 * (2+1) = 12
    // estimated = 1000 * (4-1) * 3 + 5000 * 2 = 9000 + 10000 = 19000ms = ~19s
    await tester.enterText(fields.at(0), '1000');
    await tester.enterText(fields.at(1), '2');
    await tester.enterText(fields.at(2), '5000');
    await tester.pumpAndSettle();

    expect(find.text('Will send 12 messages over ~19s'), findsOneWidget);
  });

  testWidgets(
      'a file with malformed lines surfaces the parse-error count while '
      'valid messages remain usable', (tester) async {
    final content = [
      encodeExportedMessageLine(
          ExportedMessage(subject: 'a', payload: Uint8List.fromList([1]))),
      'not valid json',
      encodeExportedMessageLine(
          ExportedMessage(subject: 'b', payload: Uint8List.fromList([2]))),
    ].join('\n');
    final bytes = Uint8List.fromList(utf8.encode(content));

    await pumpDialog(
      tester,
      isConnected: true,
      pickFile: () async => (bytes, 'partial.ndjson'),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();

    expect(find.text('2 message(s) parsed.'), findsOneWidget);
    expect(
        find.text('1 line(s) could not be parsed and will be skipped.'),
        findsOneWidget);

    final startButton = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Start Replay'));
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets(
      'confirming calls onReplay with the exact parsed messages/durations '
      'and closes the dialog', (tester) async {
    final messages = makeMessages(3);
    List<ExportedMessage>? capturedMessages;
    Duration? capturedMessageInterval;
    int? capturedRepeatCount;
    Duration? capturedRepeatInterval;

    await pumpDialog(
      tester,
      isConnected: true,
      pickFile: () async => (_ndjsonBytes(messages), 'export.ndjson'),
      onReplay: (msgs, msgInterval, repeatCount, repeatInterval) {
        capturedMessages = msgs;
        capturedMessageInterval = msgInterval;
        capturedRepeatCount = repeatCount;
        capturedRepeatInterval = repeatInterval;
      },
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose File'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '10');
    await tester.enterText(fields.at(1), '1');
    await tester.enterText(fields.at(2), '20');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Start Replay'));
    await tester.pumpAndSettle();

    expect(capturedMessages, hasLength(3));
    expect(capturedMessages!.map((m) => m.subject).toList(),
        messages.map((m) => m.subject).toList());
    expect(capturedMessageInterval, const Duration(milliseconds: 10));
    expect(capturedRepeatCount, 1);
    expect(capturedRepeatInterval, const Duration(milliseconds: 20));

    expect(find.byType(ReplayConfigDialog), findsNothing);
  });
}
