/// Keeping a variable-height list's viewport on the same item when row
/// heights above it change (a resize, a settings change, a pinned column
/// widening). Pure functions over the item list and a height function, so
/// the list's own scroll math stays testable.
library;

/// The item at scroll [offset], and how far into that item the offset is.
/// Returns `(null, 0)` if [offset] is past the end.
(T?, double) scrollAnchorAt<T>(
    List<T> items, double offset, double Function(T item) extentOf) {
  var top = 0.0;
  for (final item in items) {
    final height = extentOf(item);
    if (top + height > offset) return (item, offset - top);
    top += height;
  }
  return (null, 0);
}

/// The scroll offset that puts [anchor] back where [scrollAnchorAt] found it,
/// [intra] pixels into it (clamped to its new height), or null if [anchor]
/// is no longer in [items].
double? offsetForAnchor<T extends Object>(
    List<T> items, T anchor, double intra, double Function(T item) extentOf) {
  var top = 0.0;
  for (final item in items) {
    final height = extentOf(item);
    if (identical(item, anchor)) {
      return top + (intra < height ? intra : height - 1);
    }
    top += height;
  }
  return null;
}
