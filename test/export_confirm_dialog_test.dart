import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/export_confirm_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required int count,
    required VoidCallback onConfirm,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => ExportConfirmDialog(
                count: count,
                sourceLabel: 'selected',
                onConfirm: onConfirm,
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

  testWidgets('under threshold shows no warning and Export calls onConfirm',
      (tester) async {
    var confirmed = false;
    await pumpDialog(tester, count: 50, onConfirm: () => confirmed = true);

    expect(find.textContaining('Export 50 selected message(s) to a file?'),
        findsOneWidget);
    expect(find.textContaining('large export'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Export'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
    expect(find.byType(ExportConfirmDialog), findsNothing);
  });

  testWidgets(
      'over threshold shows a warning and still calls onConfirm (warn-and-proceed)',
      (tester) async {
    var confirmed = false;
    await pumpDialog(tester, count: 25000, onConfirm: () => confirmed = true);

    expect(find.textContaining('Export 25000 selected message(s) to a file?'),
        findsOneWidget);
    expect(find.textContaining('large export'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Export'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('Cancel does not call onConfirm', (tester) async {
    var confirmed = false;
    await pumpDialog(tester, count: 10, onConfirm: () => confirmed = true);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.byType(ExportConfirmDialog), findsNothing);
  });
}
