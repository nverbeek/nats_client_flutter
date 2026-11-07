import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/scroll_anchor.dart';

void main() {
  final items = ['a', 'b', 'c', 'd'];
  final heights = {'a': 56.0, 'b': 100.0, 'c': 56.0, 'd': 200.0};
  double extent(String item) => heights[item]!;

  test('anchorAt finds the item under the offset and the offset into it', () {
    expect(scrollAnchorAt(items, 0, extent), ('a', 0.0));
    expect(scrollAnchorAt(items, 60, extent), ('b', 4.0));
    expect(scrollAnchorAt(items, 156, extent), ('c', 0.0));
    expect(scrollAnchorAt(items, 10000, extent), (null, 0.0));
  });

  test('offsetForAnchor accounts for new rows above and changed heights', () {
    final (anchor, intra) = scrollAnchorAt(items, 170, extent);
    expect(anchor, 'c');
    // Two rows arrive on top and 'b' gets taller.
    final newItems = ['y', 'z', ...items];
    final newHeights = {...heights, 'y': 56.0, 'z': 74.0, 'b': 150.0};
    final offset =
        offsetForAnchor(newItems, anchor!, intra, (i) => newHeights[i]!);
    expect(offset, 56 + 74 + 56 + 150 + intra);
  });

  test('intra is clamped to the anchor\'s new height', () {
    expect(offsetForAnchor(items, 'b', 300, extent), 56 + 99);
  });

  test('a removed anchor gives null', () {
    expect(offsetForAnchor(items, 'gone', 0, extent), isNull);
  });
}
