import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A `ListView` whose rows have different but known heights, with an exact
/// scroll extent.
///
/// Flutter's own `ListView(itemExtentBuilder:)` knows each row's height, but
/// reports the list's total height as an *estimate* (the average of the rows
/// currently laid out times the row count), and finds row positions by
/// summing heights from row 0 on every lookup. With mixed heights the
/// estimate changes as different rows scroll into view, so the scrollbar
/// thumb jumps, and the summing gets slow deep into a long list.
///
/// This list keeps a running total (prefix sums) of the row heights instead:
/// the scroll extent is exact, a row's position is a lookup and the row at
/// an offset is a binary search. The sums are rebuilt only when
/// [extentsToken] changes, so callers pass a value that changes whenever any
/// row height may have (see `MessageListLayout.buildList`).
class ExactExtentListView extends ListView {
  ExactExtentListView.builder({
    super.key,
    super.controller,
    required super.itemBuilder,
    required int super.itemCount,
    required this.extentAt,
    required this.extentsToken,
  })  : _itemCount = itemCount,
        super.builder(
          itemExtentBuilder: (index, _) =>
              index < itemCount ? extentAt(index) : null,
        );

  /// Height of row [index], for `0 <= index < itemCount`.
  final double Function(int index) extentAt;

  /// Equal to the previous build's token exactly when no row height changed.
  final Object? extentsToken;

  final int _itemCount;

  @override
  Widget buildChildLayout(BuildContext context) => ExactExtentSliverList(
        delegate: childrenDelegate,
        itemCount: _itemCount,
        extentAt: extentAt,
        extentsToken: extentsToken,
      );
}

/// The sliver behind [ExactExtentListView].
class ExactExtentSliverList extends SliverMultiBoxAdaptorWidget {
  const ExactExtentSliverList({
    super.key,
    required super.delegate,
    required this.itemCount,
    required this.extentAt,
    required this.extentsToken,
  });

  final int itemCount;
  final double Function(int index) extentAt;
  final Object? extentsToken;

  @override
  RenderExactExtentSliverList createRenderObject(BuildContext context) =>
      RenderExactExtentSliverList(
        childManager: context as SliverMultiBoxAdaptorElement,
        itemCount: itemCount,
        extentAt: extentAt,
        extentsToken: extentsToken,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderExactExtentSliverList renderObject) {
    renderObject.update(
        itemCount: itemCount, extentAt: extentAt, extentsToken: extentsToken);
  }
}

/// Lays out rows of known, varied heights from prefix sums: `_offsets[i]` is
/// the top of row `i`, `_offsets[itemCount]` the total height.
class RenderExactExtentSliverList extends RenderSliverVariedExtentList {
  RenderExactExtentSliverList({
    required super.childManager,
    required int itemCount,
    required double Function(int index) extentAt,
    required Object? extentsToken,
  })  : _itemCount = itemCount,
        _extentAt = extentAt,
        _token = extentsToken,
        super(itemExtentBuilder: _unused) {
    itemExtentBuilder = _extentOrNull;
  }

  // The superclass needs a builder at construction, before `this` exists.
  static double? _unused(int index, SliverLayoutDimensions dimensions) => null;

  int _itemCount;
  double Function(int index) _extentAt;
  Object? _token;
  Float64List? _offsets;

  double? _extentOrNull(int index, SliverLayoutDimensions dimensions) =>
      index >= 0 && index < _itemCount ? _extentAt(index) : null;

  void update({
    required int itemCount,
    required double Function(int index) extentAt,
    required Object? extentsToken,
  }) {
    _extentAt = extentAt;
    if (itemCount == _itemCount && extentsToken == _token) return;
    _itemCount = itemCount;
    _token = extentsToken;
    _offsets = null;
    markNeedsLayout();
  }

  Float64List get _sums {
    final cached = _offsets;
    if (cached != null && cached.length == _itemCount + 1) return cached;
    final sums = Float64List(_itemCount + 1);
    var total = 0.0;
    for (var i = 0; i < _itemCount; i++) {
      sums[i] = total;
      total += _extentAt(i);
    }
    sums[_itemCount] = total;
    return _offsets = sums;
  }

  /// The row containing [scrollOffset]: the smallest `i` with
  /// `sums[i + 1] >= scrollOffset`, matching the superclass's linear scan
  /// (an offset exactly on a boundary belongs to the row above it).
  int _indexAt(double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    final sums = _sums;
    if (_itemCount == 0) return -1;
    if (scrollOffset > sums[_itemCount]) return _itemCount - 1;
    var lo = 1, hi = _itemCount;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sums[mid] >= scrollOffset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo - 1;
  }

  @override
  double indexToLayoutOffset(double itemExtent, int index) {
    final sums = _sums;
    if (index <= 0) return 0.0;
    return sums[index > _itemCount ? _itemCount : index];
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _indexAt(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _indexAt(scrollOffset);

  @override
  double computeMaxScrollOffset(
          SliverConstraints constraints, double itemExtent) =>
      _sums[_itemCount];

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) =>
      _sums[_itemCount];
}
