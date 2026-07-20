import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/kv_put_dialog.dart';

void main() {
  testWidgets('create mode: Key field is enabled and revision is not shown',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          onSave: (_, __, ___) {},
        ),
      ),
    ));

    // `find.widgetWithText(TextFormField, 'Key')` is ambiguous here: both
    // the label and hint use the same "Key" text and both remain in the
    // tree (same issue noted in send_message_dialog_test.dart). The Key
    // field is the first of the two, so target it positionally instead.
    final keyField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    expect(keyField.enabled, isTrue);
    expect(find.textContaining('Revision #'), findsNothing);
    expect(find.text('Put Value'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Put'), findsOneWidget);
  });

  testWidgets('shows a validation error and blocks save for an empty key',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          onSave: (_, __, ___) => saved = true,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Put'));
    await tester.pump();

    expect(saved, isFalse);
    expect(find.text('A key is required.'), findsOneWidget);
  });

  testWidgets('Put calls onSave with key, value, and a null expected revision',
      (tester) async {
    String? savedKey;
    String? savedValue;
    int? savedRevision;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          onSave: (k, v, r) {
            savedKey = k;
            savedValue = v;
            savedRevision = r;
          },
        ),
      ),
    ));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Key'), 'db.port');
    await tester.enterText(find.widgetWithText(TextFormField, 'Value'), '5432');
    await tester.tap(find.widgetWithText(TextButton, 'Put'));
    await tester.pump();

    expect(savedKey, 'db.port');
    expect(savedValue, '5432');
    expect(savedRevision, isNull);
  });

  testWidgets(
      'edit mode: Key field is locked, prefilled, and shows the revision hint',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          initialKey: 'db.port',
          initialValue: '5432',
          existingRevision: 3,
          onSave: (_, __, ___) {},
        ),
      ),
    ));

    final keyField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    expect(keyField.enabled, isFalse);
    expect(keyField.controller?.text, 'db.port');
    expect(find.text('Edit Value'), findsOneWidget);
    expect(find.textContaining('Revision #3'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
  });

  testWidgets('Save in edit mode passes the existing revision through',
      (tester) async {
    int? savedRevision;
    String? savedValue;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          initialKey: 'db.port',
          initialValue: '5432',
          existingRevision: 3,
          onSave: (_, v, r) {
            savedValue = v;
            savedRevision = r;
          },
        ),
      ),
    ));

    await tester.enterText(find.widgetWithText(TextFormField, 'Value'), '5433');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();

    expect(savedValue, '5433');
    expect(savedRevision, 3);
  });

  testWidgets('Ctrl+Enter saves the value', (tester) async {
    String? savedKey;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KvPutValueDialog(
          bucket: 'app-config',
          onSave: (k, _, __) => savedKey = k,
        ),
      ),
    ));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Key'), 'db.port');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(savedKey, 'db.port');
  });

  testWidgets('close icon and Cancel button both pop without saving',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => KvPutValueDialog(
                  bucket: 'app-config',
                  onSave: (_, __, ___) {},
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
    expect(find.byType(KvPutValueDialog), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(KvPutValueDialog), findsNothing);
  });
}
