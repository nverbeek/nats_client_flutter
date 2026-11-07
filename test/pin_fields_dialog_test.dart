import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/pin_fields_dialog.dart';

void main() {
  final json = jsonDecode('''
    {"order_id":"ord_1","customer":{"name":"Ada"},
     "items":[{"sku":"A1"},{"sku":"B7"}],"label":"urgent"}''') as Object;

  Future<List<String>?> pump(WidgetTester tester,
      {List<String> pinned = const [],
      Future<void> Function()? edit,
      bool cancel = false}) async {
    List<String>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PinFieldsDialog(
                  subject: 'orders.created',
                  json: json,
                  pinned: pinned,
                  onSave: (sources) => saved = sources,
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
    if (edit != null) await edit();
    if (cancel) {
      await tester.tap(find.text('Cancel'));
    } else {
      await tester.tap(find.byType(FilledButton));
    }
    await tester.pumpAndSettle();
    return saved;
  }

  Finder row(String path) => find.byKey(ValueKey('pinFieldsRow_$path'));

  testWidgets('lists the message fields with sample values', (tester) async {
    await pump(tester, edit: () async {
      expect(row('order_id'), findsOneWidget);
      expect(row('customer.name'), findsOneWidget);
      expect(row('items[*].sku'), findsOneWidget);
      expect(find.text('A1, B7'), findsOneWidget);
      expect(find.text('urgent'), findsOneWidget);
    }, cancel: true);
  });

  testWidgets('checking fields pins them in message order', (tester) async {
    final saved = await pump(tester, edit: () async {
      await tester.tap(row('label'));
      await tester.tap(row('items[*].sku'));
      await tester.pump();
      expect(find.text('Pin 2 Fields'), findsOneWidget);
    });
    expect(saved, ['items[*].sku', 'label']);
  });

  testWidgets('existing pins keep their order and short names', (tester) async {
    final saved = await pump(tester, pinned: ['who=customer.name', 'label'],
        edit: () async {
      expect(
          tester.widget<CheckboxListTile>(row('customer.name')).value, isTrue);
      await tester.tap(row('order_id'));
      await tester.pump();
    });
    expect(saved, ['who=customer.name', 'label', 'order_id']);
  });

  testWidgets('pins missing from this message are listed and can be removed',
      (tester) async {
    final saved =
        await pump(tester, pinned: ['meta.status', 'label'], edit: () async {
      expect(row('meta.status'), findsOneWidget);
      expect(find.text('not in this message'), findsOneWidget);
      await tester.tap(row('meta.status'));
      await tester.pump();
    });
    expect(saved, ['label']);
  });

  testWidgets('search narrows the list', (tester) async {
    await pump(tester, edit: () async {
      await tester.enterText(
          find.byKey(const ValueKey('pinFieldsSearch')), 'sku');
      await tester.pump();
      expect(row('items[*].sku'), findsOneWidget);
      expect(row('label'), findsNothing);
    }, cancel: true);
  });

  testWidgets('unchecking everything offers Clear Pins', (tester) async {
    final saved = await pump(tester, pinned: ['label'], edit: () async {
      await tester.tap(row('label'));
      await tester.pump();
      expect(find.text('Clear Pins'), findsOneWidget);
    });
    expect(saved, isEmpty);
  });

  testWidgets('Cancel saves nothing', (tester) async {
    final saved = await pump(tester, edit: () async {
      await tester.tap(row('label'));
      await tester.pump();
    }, cancel: true);
    expect(saved, isNull);
  });
}
