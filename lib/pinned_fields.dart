import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_nats/dart_nats.dart' hide Consumer;

import 'format_utils.dart';
import 'message_font.dart';

/// One step of a [PinnedPath]: an object key, an array index, or `[*]`.
sealed class PinnedPathSegment {
  const PinnedPathSegment();
}

class PinnedKey extends PinnedPathSegment {
  final String key;
  const PinnedKey(this.key);
}

class PinnedIndex extends PinnedPathSegment {
  final int index;
  const PinnedIndex(this.index);
}

class PinnedWildcard extends PinnedPathSegment {
  const PinnedWildcard();
}

/// A parsed pinned field: a JSON path, plus the short name shown above its
/// values in each row.
///
/// Syntax: `label`, `meta.status`, `items[0].sku`, `items[*].sku` (every
/// element), `items.sku` (same: a key applied to an array applies to each
/// element), `["key.with.dots"]`, and an optional short name in front:
/// `fc=fulfillment_center_identifier`.
class PinnedPath {
  /// Exactly what the user entered, including any `name=` prefix. This is
  /// what's persisted.
  final String source;

  /// The path without the `name=` prefix.
  final String path;

  /// The caption shown above values: the short name, or the path's last key.
  final String label;

  final List<PinnedPathSegment> segments;

  const PinnedPath(this.source, this.path, this.label, this.segments);
}

final RegExp _aliasPattern = RegExp(r'^([A-Za-z_][\w -]{0,30}?)\s*=\s*(.+)$');

/// Parses [source] into a [PinnedPath], or returns null if it isn't a valid
/// path (the Settings field shows an error for those).
PinnedPath? parsePinnedPath(String source) {
  final full = source.trim();
  if (full.isEmpty) return null;
  final aliasMatch = _aliasPattern.firstMatch(full);
  final alias = aliasMatch?.group(1)!.trim();
  final s = aliasMatch != null ? aliasMatch.group(2)!.trim() : full;

  final segments = <PinnedPathSegment>[];
  var i = 0;
  bool readKey() {
    var j = i;
    while (j < s.length && s[j] != '.' && s[j] != '[') {
      // `]` and `"` only belong inside brackets; a key with them needs the
      // `["..."]` form.
      if (s[j] == ']' || s[j] == '"') return false;
      j++;
    }
    if (j == i) return false;
    segments.add(PinnedKey(s.substring(i, j)));
    i = j;
    return true;
  }

  if (s.isEmpty) return null;
  if (s[0] != '[' && !readKey()) return null;
  while (i < s.length) {
    if (s[i] == '.') {
      i++;
      if (!readKey()) return null;
    } else if (s[i] == '[') {
      final close = s.indexOf(']', i);
      if (close < 0) return null;
      final inner = s.substring(i + 1, close).trim();
      if (inner == '*') {
        segments.add(const PinnedWildcard());
      } else if (RegExp(r'^\d+$').hasMatch(inner)) {
        segments.add(PinnedIndex(int.parse(inner)));
      } else if (inner.length >= 2 &&
          inner.startsWith('"') &&
          inner.endsWith('"')) {
        segments.add(PinnedKey(inner.substring(1, inner.length - 1)));
      } else {
        return null;
      }
      i = close + 1;
    } else {
      return null;
    }
  }
  if (segments.isEmpty) return null;
  final lastKey = segments.whereType<PinnedKey>().lastOrNull?.key;
  return PinnedPath(full, s, alias ?? lastKey ?? s, segments);
}

/// A pinned field's value in one message: [display] is what the row shows
/// (multi-element values abbreviated as `a, b, c +2`), [full] is the
/// untruncated text for the tooltip and "Copy value".
class PinnedValue {
  final String display;
  final String full;

  const PinnedValue(this.display, this.full);
}

const int _maxJsonValueChars = 40;
const int _maxListedValues = 3;
const int _maxTooltipChars = 2000;

String _formatValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  if (value is Map || value is List) {
    final encoded = jsonEncode(value);
    return encoded.length > _maxJsonValueChars
        ? '${encoded.substring(0, _maxJsonValueChars - 1)}…'
        : encoded;
  }
  return value.toString();
}

/// Looks [path] up in a decoded JSON value. Returns null when the path
/// matches nothing.
PinnedValue? extractPinned(Object? json, PinnedPath path) {
  var values = <Object?>[json];
  var multi = false;
  for (final segment in path.segments) {
    final next = <Object?>[];
    for (final v in values) {
      switch (segment) {
        case PinnedKey(:final key):
          if (v is List) {
            multi = true;
            for (final e in v) {
              if (e is Map && e.containsKey(key)) next.add(e[key]);
            }
          } else if (v is Map && v.containsKey(key)) {
            next.add(v[key]);
          }
        case PinnedIndex(:final index):
          if (v is List && index < v.length) next.add(v[index]);
        case PinnedWildcard():
          multi = true;
          if (v is List) {
            next.addAll(v);
          } else if (v is Map) {
            next.addAll(v.values);
          }
      }
    }
    values = next;
  }
  if (values.isEmpty) return null;
  if (!multi) {
    final text = _formatValue(values.first);
    return PinnedValue(text, text);
  }
  final formatted = values.map(_formatValue).toList(growable: false);
  final head = formatted.take(_maxListedValues).join(', ');
  final extra = formatted.length - _maxListedValues;
  var full = formatted.join(', ');
  if (full.length > _maxTooltipChars) {
    full = '${full.substring(0, _maxTooltipChars)}…';
  }
  return PinnedValue(extra > 0 ? '$head +$extra' : head, full);
}

/// Payloads larger than this aren't parsed for pinned fields: decoding a
/// multi-megabyte JSON document for every message would cost more than the
/// pins are worth. Such rows show no pinned values.
const int pinnedJsonMaxBytes = 256 * 1024;

/// Decodes [text] as a JSON object or array, or returns null if it isn't
/// one. Checks the first non-blank character before attempting a decode, so
/// non-JSON payloads cost almost nothing.
Object? decodeJsonPayload(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) continue;
    if (c != 0x7B && c != 0x5B) return null; // '{' or '['
    try {
      final decoded = jsonDecode(text);
      return decoded is Map || decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }
  return null;
}

final RegExp _plainKey = RegExp(r'^[A-Za-z_$][\w$-]*$');
const int _maxFlattenDepth = 6;
const int _maxFlattenPaths = 500;
const int _maxSampledElements = 10;

/// Every leaf path in [json], for the "Pin Fields" picker. Arrays of objects
/// are merged into one `[*]` path per key (sampling the first few elements),
/// so an order with five items lists `items[*].sku` once, not five times.
List<String> flattenJsonPaths(Object? json) {
  final out = <String>{};

  String join(String prefix, String key) {
    if (_plainKey.hasMatch(key)) return prefix.isEmpty ? key : '$prefix.$key';
    return '$prefix["$key"]';
  }

  bool hasNested(Object? v) => v is Map
      ? v.isNotEmpty
      : v is List && v.any((e) => e is Map && e.isNotEmpty);

  void walk(Object? value, String prefix, int depth) {
    if (out.length >= _maxFlattenPaths) return;
    if (value is List) {
      final objects = value.whereType<Map>().take(_maxSampledElements).toList();
      if (objects.isEmpty || depth >= _maxFlattenDepth) {
        if (prefix.isNotEmpty) out.add(prefix);
        return;
      }
      final merged = <String, Object?>{};
      for (final o in objects) {
        for (final entry in o.entries) {
          merged.putIfAbsent('${entry.key}', () => entry.value);
        }
      }
      walk(merged, '$prefix[*]', depth + 1);
    } else if (value is Map) {
      if (value.isEmpty || depth >= _maxFlattenDepth) {
        if (prefix.isNotEmpty) out.add(prefix);
        return;
      }
      for (final entry in value.entries) {
        final key = '${entry.key}';
        if (key.contains('"')) continue; // not expressible as a path
        final path = join(prefix, key);
        if (hasNested(entry.value)) {
          walk(entry.value, path, depth + 1);
        } else {
          out.add(path);
        }
        if (out.length >= _maxFlattenPaths) return;
      }
    } else if (prefix.isNotEmpty) {
      out.add(prefix);
    }
  }

  walk(json, '', 0);
  return out.toList(growable: false);
}

/// Pin cell geometry (see `PinnedFieldCells`): a cell is wide enough for its
/// value, and for its caption up to [pinCaptionMaxWidth], capped at
/// the width cap (see [pinCellWidthCap]).
///
/// [pinCellMaxWidth] is the cap on a wide window. Narrower windows cap
/// cells lower, so pins can't crowd out the message text.
const double pinCellMaxWidth = 280;
const double pinCellMinCap = 120;
const double pinCellWidthFraction = 0.2;

/// The widest a pinned cell may be in a list [rowWidth] wide: a fifth of
/// the row, between [pinCellMinCap] and [pinCellMaxWidth]. A row width of 0
/// (not laid out yet) gets the full [pinCellMaxWidth].
double pinCellWidthCap(double rowWidth) {
  if (rowWidth <= 0) return pinCellMaxWidth;
  final cap = rowWidth * pinCellWidthFraction;
  return cap < pinCellMinCap
      ? pinCellMinCap
      : (cap > pinCellMaxWidth ? pinCellMaxWidth : cap.floorToDouble());
}

const double pinCaptionMaxWidth = 96;
const double pinCellHorizontalPadding = 18;
const double pinCellGap = 8;
const double pinAreaStartPadding = 16;

/// The pinned fields for a message list: the parsed paths, each message's
/// values (cached per message), and per-column widths.
///
/// Column widths only grow, from the widest value seen, until the paths
/// change or the list is cleared. A column that shrank as messages scrolled
/// away would rewrap the rows on screen.
class PinnedFields {
  List<PinnedPath> _paths = const [];
  int _version = 0;
  // Each column's wanted width (fits its widest value, up to
  // pinCellMaxWidth); drawn at most _widthCap wide.
  List<double> _columnWidths = const [];
  double _widthCap = pinCellMaxWidth;

  /// The widest a cell is drawn, from [pinCellWidthCap] for the list's
  /// current width. Changing it changes row layouts, so it bumps
  /// [layoutVersion].
  double get widthCap => _widthCap;
  set widthCap(double value) {
    if (value == _widthCap) return;
    _widthCap = value;
    _layoutVersion++;
  }

  double Function(String label) _captionWidth = (_) => 0;
  final Expando<_PinnedEntry> _entries = Expando<_PinnedEntry>('pinned');

  List<PinnedPath> get paths => _paths;
  bool get isEmpty => _paths.isEmpty;

  /// Changes whenever anything that affects a row's pin area does (the
  /// paths, or a column width), so cached row heights know to refresh.
  int get layoutVersion => _layoutVersion;
  int _layoutVersion = 0;

  /// Replaces the pinned paths, then re-measures every message in
  /// [messages]. [captionWidth] measures a caption in its rendered style.
  void setPaths(List<PinnedPath> paths, Iterable<Message<dynamic>> messages,
      double Function(String label) captionWidth) {
    _paths = List.unmodifiable(paths);
    _captionWidth = captionWidth;
    _version++;
    resetWidths(messages);
  }

  /// Shrinks columns back to their captions, then grows them over
  /// [messages]. Called when the list is cleared or the paths change.
  void resetWidths(Iterable<Message<dynamic>> messages) {
    _layoutVersion++;
    _columnWidths = [
      for (final p in _paths)
        math.min(
            pinCellMaxWidth,
            (pinCellHorizontalPadding +
                    math.min(_captionWidth(p.label), pinCaptionMaxWidth))
                .ceilToDouble()),
    ];
    for (final m in messages) {
      noteMessage(m);
    }
  }

  /// [message]'s pinned values (null where a path matched nothing), or null
  /// if none of the paths matched, in which case the row shows no pin area.
  List<PinnedValue?>? valuesFor(Message<dynamic> message) {
    if (_paths.isEmpty) return null;
    final cached = _entries[message];
    if (cached != null && cached.version == _version) return cached.values;
    final text = decodeMessageTextFor(message);
    final json = message.byte.length > pinnedJsonMaxBytes
        ? null
        : decodeJsonPayload(text);
    List<PinnedValue?>? values;
    if (json != null) {
      final found = [for (final p in _paths) extractPinned(json, p)];
      if (found.any((v) => v != null)) values = found;
    }
    _entries[message] = _PinnedEntry(_version, values);
    return values;
  }

  /// Grows the columns to fit [message]'s values. Returns whether any column
  /// grew. Value widths are pure arithmetic (monospace), not a text layout.
  bool noteMessage(Message<dynamic> message) => _grow(message, apply: true);

  /// Whether noting [messages] would widen any column, without changing
  /// anything. Lets a caller record the scroll position under the current
  /// widths before applying the change.
  bool wouldGrow(Iterable<Message<dynamic>> messages) =>
      messages.any((m) => _grow(m, apply: false));

  /// Grows column wants to fit [message]. Returns whether a column's drawn
  /// width (its want, capped at [widthCap]) grew; a want growing past the
  /// cap changes nothing on screen until the cap rises.
  bool _grow(Message<dynamic> message, {required bool apply}) {
    final values = valuesFor(message);
    if (values == null) return false;
    final charWidth = monoCharWidth(pinValueFontSize);
    var visibleGrowth = false;
    for (var k = 0; k < values.length; k++) {
      final chars = values[k]?.display.length ?? 1;
      final width = math.min(pinCellMaxWidth,
          (pinCellHorizontalPadding + chars * charWidth).ceilToDouble());
      final old = _columnWidths[k];
      if (width <= old) continue;
      final drawnGrows = math.min(width, _widthCap) > math.min(old, _widthCap);
      if (!apply) {
        if (drawnGrows) return true;
        continue;
      }
      _columnWidths[k] = width;
      if (drawnGrows) {
        visibleGrowth = true;
        _layoutVersion++;
      }
    }
    return visibleGrowth;
  }

  /// Column [index]'s drawn width.
  double columnWidth(int index) => math.min(_columnWidths[index], _widthCap);

  /// Horizontal space [message]'s pin area takes in its row: 0 when it has
  /// none of the pinned fields.
  double areaWidth(Message<dynamic> message) {
    if (valuesFor(message) == null) return 0;
    var width = pinAreaStartPadding + pinCellGap * (_paths.length - 1);
    for (var k = 0; k < _columnWidths.length; k++) {
      width += columnWidth(k);
    }
    return width;
  }
}

class _PinnedEntry {
  final int version;
  final List<PinnedValue?>? values;

  _PinnedEntry(this.version, this.values);
}
