import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/subject_chips_row.dart';
import 'package:nats_client_flutter/subscription_info.dart';

void main() {
  Widget buildRow({
    required List<SubscriptionInfo> subscriptions,
    ValueChanged<SubscriptionInfo>? onTapChip,
    ValueChanged<SubscriptionInfo>? onRemoveChip,
    VoidCallback? onAdd,
    VoidCallback? onOpenManager,
    double width = 700,
  }) {
    return MaterialApp(
      home: Scaffold(
        // OverflowBox (rather than a plain SizedBox) so `width` can exceed
        // the test surface's viewport -- a SizedBox would just get clamped
        // back down to the viewport's own width.
        body: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: width,
          minHeight: 0,
          maxHeight: 100,
          child: SizedBox(
            width: width,
            child: SubjectChipsRow(
              subscriptions: subscriptions,
              isDark: false,
              onTapChip: onTapChip ?? (_) {},
              onRemoveChip: onRemoveChip ?? (_) {},
              onAdd: onAdd ?? () {},
              onOpenManager: onOpenManager ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'renders a chip per subscription, with a queue-group badge in the label',
      (tester) async {
    await tester.pumpWidget(buildRow(subscriptions: [
      SubscriptionInfo(
          subject: 'orders.*', queueGroup: 'workers', colorIndex: 0),
      SubscriptionInfo(subject: 'alerts', colorIndex: 1),
    ]));

    expect(find.text('orders.* · workers'), findsOneWidget);
    expect(find.text('alerts'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2));
  });

  testWidgets('shows a "No subscriptions" placeholder when empty',
      (tester) async {
    await tester.pumpWidget(buildRow(subscriptions: []));
    expect(find.text('No subscriptions'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('tapping a chip body calls onTapChip, not onRemoveChip',
      (tester) async {
    SubscriptionInfo? tapped;
    var removedCalled = false;
    final info = SubscriptionInfo(subject: 'orders.*', colorIndex: 0);
    await tester.pumpWidget(buildRow(
      subscriptions: [info],
      onTapChip: (i) => tapped = i,
      onRemoveChip: (_) => removedCalled = true,
    ));

    await tester.tap(find.text('orders.*'));
    await tester.pump();

    expect(tapped, same(info));
    expect(removedCalled, isFalse);
  });

  testWidgets('tapping the delete icon calls onRemoveChip, not onTapChip',
      (tester) async {
    SubscriptionInfo? removed;
    var tappedCalled = false;
    final info = SubscriptionInfo(subject: 'orders.*', colorIndex: 0);
    await tester.pumpWidget(buildRow(
      subscriptions: [info],
      onRemoveChip: (i) => removed = i,
      onTapChip: (_) => tappedCalled = true,
    ));

    // InputChip's default delete icon under Material3 is Icons.clear.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(removed, same(info));
    expect(tappedCalled, isFalse);
  });

  testWidgets('tapping "+" calls onAdd', (tester) async {
    var addCalled = false;
    await tester.pumpWidget(buildRow(
      subscriptions: [SubscriptionInfo(subject: 'orders.*', colorIndex: 0)],
      onAdd: () => addCalled = true,
    ));

    await tester.tap(find.byTooltip('Add subscription'));
    await tester.pump();

    expect(addCalled, isTrue);
  });

  List<SubscriptionInfo> longSubscriptions() => List.generate(
        6,
        (i) => SubscriptionInfo(
            subject: 'a.pretty.long.subject.name.number.$i', colorIndex: i),
      );

  testWidgets('collapses overflow into a single "+N more" chip when narrow',
      (tester) async {
    final subscriptions = longSubscriptions();
    await tester.pumpWidget(buildRow(subscriptions: subscriptions, width: 260));
    await tester.pumpAndSettle();

    final visibleChips = find.byType(InputChip).evaluate().length;
    expect(visibleChips, lessThan(subscriptions.length));
    expect(find.textContaining('more'), findsOneWidget);
  });

  testWidgets('renders every chip with no overflow once widened',
      (tester) async {
    final subscriptions = longSubscriptions();
    await tester.pumpWidget(buildRow(subscriptions: subscriptions, width: 20000));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip).evaluate().length, subscriptions.length);
    expect(find.textContaining('more'), findsNothing);
  });
}
