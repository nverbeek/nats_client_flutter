/// Deterministic line wrapping for message payloads in the multi-line
/// message lists.
///
/// The lists give every row an exact height up front (`itemExtentBuilder`)
/// so prepend compensation, the scrollbar and "at the top" detection stay
/// exact. That only works if a row's line count is a cheap, pure function of
/// its text and the available width, never a text layout. Payloads render in
/// a monospace font, so the app breaks lines itself at a fixed character
/// count ([wrapSegments]) and renders each segment with soft wrap off. The
/// height assigned is then always the height drawn. Glyphs wider than one
/// cell (CJK, emoji) only clip inside the row; they can't throw the scroll
/// math off.
library;

/// The visual lines of a wrapped payload: `[start, end)` code-unit ranges
/// into the original text, plus whether more text follows the last line.
class WrapResult {
  final List<(int, int)> segments;
  final bool truncated;

  const WrapResult(this.segments, this.truncated);

  int get lineCount => segments.length;
}

/// Splits [text] into at most [maxLines] visual lines of at most
/// [charsPerLine] UTF-16 code units each. Hard `\n` breaks are respected; a
/// `\r` before a `\n` stays on its line (rendered as a blank cell by
/// [displayTextForWrap]). A surrogate pair is never split across lines.
///
/// Stops as soon as [maxLines] lines exist, so the cost is bounded by about
/// `maxLines * charsPerLine` characters however large the payload is.
WrapResult wrapSegments(String text, int charsPerLine, int maxLines) {
  assert(maxLines >= 1);
  final cpl = charsPerLine < 1 ? 1 : charsPerLine;
  final segments = <(int, int)>[];
  var i = 0;
  while (segments.length < maxLines) {
    final newline = text.indexOf('\n', i);
    final lineEnd = newline < 0 ? text.length : newline;
    if (lineEnd - i <= cpl) {
      segments.add((i, lineEnd));
      if (newline < 0) return WrapResult(segments, false);
      i = newline + 1;
    } else {
      var end = i + cpl;
      // Don't end a line between the two halves of a surrogate pair. With
      // cpl == 1 that would make no progress, so take the whole pair.
      if (_isHighSurrogate(text.codeUnitAt(end - 1))) {
        end = end - 1 > i ? end - 1 : end + 1;
      }
      segments.add((i, end));
      i = end;
    }
  }
  return WrapResult(segments, true);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

/// [text] with every control character other than `\n` swapped for a space.
///
/// Tabs, `\r` and other C0 controls don't render as one monospace cell, which
/// would break the one-code-unit-per-cell assumption [wrapSegments] relies
/// on. The replacement keeps the length, so match offsets computed on the
/// original text still line up.
String displayTextForWrap(String text) {
  var needsReplace = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if ((c < 0x20 && c != 0x0A) || c == 0x7F) {
      needsReplace = true;
      break;
    }
  }
  if (!needsReplace) return text;
  final units = text.codeUnits.toList(growable: false);
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if ((c < 0x20 && c != 0x0A) || c == 0x7F) units[i] = 0x20;
  }
  return String.fromCharCodes(units);
}

/// Caches each message's [WrapResult] until its characters-per-line or the
/// max-lines setting changes (a resize, a font size change, a Settings
/// change). Keyed by object identity, so it never keeps a message alive.
class WrapCache {
  final Expando<_CachedWrap> _cache = Expando<_CachedWrap>('wrap');

  WrapResult wrapFor(
      Object message, String text, int charsPerLine, int maxLines) {
    final cached = _cache[message];
    if (cached != null &&
        cached.charsPerLine == charsPerLine &&
        cached.maxLines == maxLines) {
      return cached.result;
    }
    final result = wrapSegments(text, charsPerLine, maxLines);
    _cache[message] = _CachedWrap(charsPerLine, maxLines, result);
    return result;
  }
}

class _CachedWrap {
  final int charsPerLine;
  final int maxLines;
  final WrapResult result;

  _CachedWrap(this.charsPerLine, this.maxLines, this.result);
}
