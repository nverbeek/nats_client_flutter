import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/exact_extent_list.dart';
import 'package:nats_client_flutter/message_list_layout.dart';

void main() {
  // Mixed heights, like wrapped rows: 1 to 5 lines.
  final random = Random(7);
  final heights = List<double>.generate(
      3000, (_) => 56.0 + random.nextInt(5) * 18.0,
      growable: false);
  final total = heights.fold<double>(0, (a, b) => a + b);
  double topOf(int index) =>
      heights.take(index).fold<double>(0, (a, b) => a + b);

  Future<ScrollController> pumpList(WidgetTester tester,
      {required bool exact}) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget row(BuildContext context, int i) =>
        SizedBox(key: ValueKey(i), child: Text('row $i'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: exact
            ? ExactExtentListView.builder(
                controller: controller,
                itemCount: heights.length,
                itemBuilder: row,
                extentAt: (i) => heights[i],
                extentsToken: 1,
              )
            : ListView.builder(
                controller: controller,
                itemCount: heights.length,
                itemBuilder: row,
                itemExtentBuilder: (i, _) =>
                    i < heights.length ? heights[i] : null,
              ),
      ),
    ));
    return controller;
  }

  testWidgets(
      'the scroll extent is exact and stays put while scrolling (the '
      'scrollbar never jumps)', (tester) async {
    final controller = await pumpList(tester, exact: true);
    final viewport = controller.position.viewportDimension;
    for (final offset in <double>[0, 1234.5, 40000, 90000, 150000, 3000, 0]) {
      controller.jumpTo(min(offset, total - viewport));
      await tester.pump();
      expect(controller.position.maxScrollExtent, total - viewport,
          reason: 'at offset $offset');
    }
  });

  testWidgets(
      'Flutter\'s own itemExtentBuilder list estimates the extent, which is '
      'why the exact list exists', (tester) async {
    final controller = await pumpList(tester, exact: false);
    final extents = <double>{};
    for (final offset in <double>[0, 40000, 90000, 150000]) {
      controller.jumpTo(offset);
      await tester.pump();
      extents.add(controller.position.maxScrollExtent);
    }
    // If this ever starts passing as a single exact value, Flutter fixed it
    // and ExactExtentListView can go.
    expect(extents.length, greaterThan(1));
  });

  testWidgets('rows are placed at their exact offsets deep in the list',
      (tester) async {
    final controller = await pumpList(tester, exact: true);
    const index = 2500;
    controller.jumpTo(topOf(index));
    await tester.pump();
    final listTop = tester.getTopLeft(find.byType(ExactExtentListView)).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey(index))).dy, listTop);
    expect(tester.getSize(find.byKey(const ValueKey(index))).height,
        heights[index]);
  });

  testWidgets('a new extents token rebuilds the sums', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget build(double height, Object token) => MaterialApp(
          home: Scaffold(
            body: ExactExtentListView.builder(
              controller: controller,
              itemCount: 100,
              itemBuilder: (_, i) => Text('$i'),
              extentAt: (_) => height,
              extentsToken: token,
            ),
          ),
        );
    await tester.pumpWidget(build(50, 'a'));
    final viewport = controller.position.viewportDimension;
    expect(controller.position.maxScrollExtent, 5000 - viewport);
    await tester.pumpWidget(build(80, 'b'));
    expect(controller.position.maxScrollExtent, 8000 - viewport);
  });

  group('MessageListLayout.deferJump', () {
    testWidgets('runs after the frame, relative to the offset then',
        (tester) async {
      final controller = await pumpList(tester, exact: true);
      final layout = MessageListLayout(subjectChipMaxWidth: 450);
      controller.jumpTo(1000);
      layout.deferJump(controller, () => controller.offset + 300);
      controller.jumpTo(1100); // the user scrolls before the frame
      await tester.pump();
      expect(controller.offset, 1400);
    });

    testWidgets('Jump to top cancels a jump scheduled before it',
        (tester) async {
      final controller = await pumpList(tester, exact: true);
      final layout = MessageListLayout(subjectChipMaxWidth: 450);
      controller.jumpTo(5000);
      // A flush scheduled "keep the view still"...
      layout.deferJump(controller, () => controller.offset + 300);
      // ...then the user presses Jump to top before the frame.
      layout.userJumped();
      controller.jumpTo(0);
      await tester.pump();
      expect(controller.offset, 0);
    });
  });
}
