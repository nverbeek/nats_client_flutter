import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/replay_banner.dart';

void main() {
  Widget buildBanner({
    required int sentCount,
    required int totalCount,
    int currentPass = 1,
    int totalPasses = 1,
    VoidCallback? onStop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReplayBanner(
          sentCount: sentCount,
          totalCount: totalCount,
          currentPass: currentPass,
          totalPasses: totalPasses,
          onStop: onStop ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows exact grouped progress and repeat pass', (tester) async {
    await tester.pumpWidget(buildBanner(
      sentCount: 340,
      totalCount: 4210,
      currentPass: 2,
      totalPasses: 5,
    ));
    expect(find.text('Replaying 340/4,210 (repeat 2/5)'), findsOneWidget);
  });

  testWidgets('shows repeat 1/1 for a no-repeat run', (tester) async {
    await tester.pumpWidget(buildBanner(
      sentCount: 10,
      totalCount: 25,
    ));
    expect(find.text('Replaying 10/25 (repeat 1/1)'), findsOneWidget);
  });

  testWidgets('the Stop button calls onStop', (tester) async {
    var stopped = false;
    await tester.pumpWidget(buildBanner(
      sentCount: 1,
      totalCount: 10,
      onStop: () => stopped = true,
    ));
    await tester.tap(find.widgetWithText(TextButton, 'Stop'));
    expect(stopped, isTrue);
  });
}
