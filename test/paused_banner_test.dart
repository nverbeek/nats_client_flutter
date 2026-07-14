import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/paused_banner.dart';

void main() {
  Widget buildBanner({required int pendingCount, VoidCallback? onResume}) {
    return MaterialApp(
      home: Scaffold(
        body: PausedBanner(
          pendingCount: pendingCount,
          onResume: onResume ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows a singular count for exactly one buffered message',
      (tester) async {
    await tester.pumpWidget(buildBanner(pendingCount: 1));
    expect(find.text('Paused — 1 new message buffered'), findsOneWidget);
  });

  testWidgets('shows a plural count for more than one buffered message',
      (tester) async {
    await tester.pumpWidget(buildBanner(pendingCount: 95));
    expect(find.text('Paused — 95 new messages buffered'), findsOneWidget);
  });

  testWidgets('uses the compact "1.2k"-style count for a large backlog',
      (tester) async {
    await tester.pumpWidget(buildBanner(pendingCount: 1200));
    expect(find.text('Paused — 1.2k new messages buffered'), findsOneWidget);
  });

  testWidgets('shows a neutral message when nothing is buffered yet',
      (tester) async {
    await tester.pumpWidget(buildBanner(pendingCount: 0));
    expect(find.text('Paused — no new messages yet'), findsOneWidget);
  });

  testWidgets('the Resume button calls onResume', (tester) async {
    var resumed = false;
    await tester.pumpWidget(buildBanner(
      pendingCount: 3,
      onResume: () => resumed = true,
    ));
    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    expect(resumed, isTrue);
  });
}
