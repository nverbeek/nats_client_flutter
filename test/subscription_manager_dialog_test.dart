import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/subscription_info.dart';
import 'package:nats_client_flutter/subscription_manager_dialog.dart';

void main() {
  group('SubscriptionEditDialog', () {
    Widget buildAddDialog(void Function(String, String?) onSave) {
      return MaterialApp(
        home: Scaffold(
          body: SubscriptionEditDialog(onSave: onSave),
        ),
      );
    }

    testWidgets('add mode: subject field is editable and required',
        (tester) async {
      var saved = false;
      await tester.pumpWidget(buildAddDialog((_, __) => saved = true));

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pump();

      expect(saved, isFalse);
      expect(find.text('Subject is required'), findsOneWidget);

      final subjectField =
          tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Subject'));
      expect(subjectField.enabled, isTrue);
    });

    testWidgets('add mode: Add calls onSave with subject and queue group',
        (tester) async {
      String? subject;
      String? queueGroup;
      await tester.pumpWidget(buildAddDialog((s, q) {
        subject = s;
        queueGroup = q;
      }));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'orders.*');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Queue group (optional)'),
          'workers');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pump();

      expect(subject, 'orders.*');
      expect(queueGroup, 'workers');
    });

    testWidgets('add mode: blank queue group is normalized to null',
        (tester) async {
      String? queueGroup = 'unset';
      await tester.pumpWidget(buildAddDialog((_, q) => queueGroup = q));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'orders.*');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pump();

      expect(queueGroup, isNull);
    });

    testWidgets('edit mode: subject field is disabled, Remove button shown',
        (tester) async {
      var removed = false;
      final existing =
          SubscriptionInfo(subject: 'orders.*', queueGroup: 'workers', colorIndex: 0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubscriptionEditDialog(
            existing: existing,
            onSave: (_, __) {},
            onRemove: () => removed = true,
          ),
        ),
      ));

      final subjectField =
          tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Subject'));
      expect(subjectField.enabled, isFalse);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pump();

      expect(removed, isTrue);
    });

    testWidgets('edit mode: Save reports the (possibly unchanged) subject '
        'and updated queue group', (tester) async {
      String? savedSubject;
      String? savedQueueGroup;
      final existing =
          SubscriptionInfo(subject: 'orders.*', queueGroup: 'workers', colorIndex: 0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubscriptionEditDialog(
            existing: existing,
            onSave: (s, q) {
              savedSubject = s;
              savedQueueGroup = q;
            },
          ),
        ),
      ));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Queue group (optional)'),
          'replicas');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(savedSubject, 'orders.*');
      expect(savedQueueGroup, 'replicas');
    });

    testWidgets('Ctrl+Enter in the Subject field submits without clicking Add',
        (tester) async {
      String? subject;
      await tester.pumpWidget(buildAddDialog((s, __) => subject = s));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'orders.*');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(subject, 'orders.*');
    });

    testWidgets(
        'Ctrl+Enter in the Queue group field submits without clicking Add',
        (tester) async {
      String? subject;
      String? queueGroup;
      await tester.pumpWidget(buildAddDialog((s, q) {
        subject = s;
        queueGroup = q;
      }));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'orders.*');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Queue group (optional)'),
          'workers');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(subject, 'orders.*');
      expect(queueGroup, 'workers');
    });
  });

  group('SubscriptionManagerDialog', () {
    Widget buildManager({
      required List<SubscriptionInfo> subscriptions,
      void Function(String, String?)? onAdd,
      void Function(SubscriptionInfo)? onRemove,
      void Function(SubscriptionInfo, String?)? onQueueGroupChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SubscriptionManagerDialog(
            subscriptions: subscriptions,
            isDark: false,
            onAdd: onAdd ?? (_, __) {},
            onRemove: onRemove ?? (_) {},
            onQueueGroupChanged: onQueueGroupChanged ?? (_, __) {},
          ),
        ),
      );
    }

    testWidgets('renders one row per subscription with a read-only subject',
        (tester) async {
      await tester.pumpWidget(buildManager(subscriptions: [
        SubscriptionInfo(subject: 'orders.*', colorIndex: 0),
        SubscriptionInfo(subject: 'alerts', queueGroup: 'workers', colorIndex: 1),
      ]));

      expect(find.text('orders.*'), findsOneWidget);
      expect(find.text('alerts'), findsOneWidget);
      // subject cells are plain Text, not editable fields -- only one
      // TextFormField per row (the queue-group field).
      expect(find.widgetWithText(TextFormField, 'orders.*'), findsNothing);
    });

    testWidgets('subject chip carries a tooltip with the full subject',
        (tester) async {
      final longSubject = 'a.pretty.long.subject.name.that.would.ellipsize';
      await tester.pumpWidget(buildManager(subscriptions: [
        SubscriptionInfo(subject: longSubject, colorIndex: 0),
      ]));

      expect(find.byTooltip(longSubject), findsOneWidget);
    });

    testWidgets('shows "No subscriptions" when the list is empty',
        (tester) async {
      await tester.pumpWidget(buildManager(subscriptions: []));
      expect(find.text('No subscriptions'), findsOneWidget);
    });

    testWidgets('the remove icon on a row calls onRemove for that row',
        (tester) async {
      SubscriptionInfo? removed;
      final a = SubscriptionInfo(subject: 'orders.*', colorIndex: 0);
      final b = SubscriptionInfo(subject: 'alerts', colorIndex: 1);

      await tester.pumpWidget(buildManager(
        subscriptions: [a, b],
        onRemove: (info) => removed = info,
      ));

      await tester.tap(find.byTooltip('Remove subscription').first);
      await tester.pump();

      expect(removed, same(a));
    });

    testWidgets(
        'editing the queue group field does not commit until submitted',
        (tester) async {
      final calls = <String?>[];
      final info = SubscriptionInfo(subject: 'orders.*', colorIndex: 0);

      await tester.pumpWidget(buildManager(
        subscriptions: [info],
        // Mirrors main.dart's real _updateQueueGroup, which mutates the
        // shared SubscriptionInfo synchronously -- that mutation is what
        // stops a same-value re-commit (e.g. from a submit-then-blur
        // sequence) from firing the callback twice.
        onQueueGroupChanged: (target, newValue) {
          calls.add(newValue);
          target.queueGroup = newValue;
        },
      ));

      await tester.enterText(find.widgetWithText(TextFormField, 'Queue group'),
          'workers');
      await tester.pump();
      expect(calls, isEmpty, reason: 'typing alone must not trigger a resub');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(calls, ['workers']);
    });

    testWidgets("Add button opens the edit dialog and forwards to onAdd",
        (tester) async {
      String? addedSubject;
      await tester.pumpWidget(buildManager(
        subscriptions: const [],
        onAdd: (s, __) => addedSubject = s,
      ));

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'metrics.*');
      // `.last`: the manager dialog's own header "Add" button is still in
      // the tree underneath the newly-opened edit dialog's "Add" action.
      await tester.tap(find.widgetWithText(TextButton, 'Add').last);
      await tester.pumpAndSettle();

      expect(addedSubject, 'metrics.*');
    });
  });
}
