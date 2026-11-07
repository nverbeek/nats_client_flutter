import 'package:flutter/material.dart';

import 'message_wrap.dart';

RegExp? _cachedRegex;
String? _cachedTerm;

/// Compiles [searchTerm] into a case-insensitive [RegExp], memoizing the last
/// compiled term/pattern pair so repeated builds (e.g. once per list row per
/// frame) don't recompile the same pattern. Returns null if [searchTerm] is
/// not a valid regex.
RegExp? _compileSearchTerm(String searchTerm) {
  if (_cachedTerm == searchTerm) {
    return _cachedRegex;
  }
  RegExp? regex;
  try {
    regex = RegExp(searchTerm, caseSensitive: false);
  } on FormatException {
    regex = null;
  }
  _cachedTerm = searchTerm;
  _cachedRegex = regex;
  return regex;
}

/// Widget that applies [highlightStyle] to the provided [text] when any portion
/// of the text matches the [searchTerm]. Text is limited to [maxLines].
///
/// With [wrap] set, the text is drawn as exactly those pre-computed lines
/// (see `message_wrap.dart`) with soft wrap off, and a `…` replaces the last
/// character when [WrapResult.truncated]. Matches are found on the original
/// text and split at line boundaries, so a highlight that spans a break
/// still shows on both lines.
class RegexTextHighlight extends StatelessWidget {
  final String text;
  final String searchTerm;
  final TextStyle highlightStyle;
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Merged over the ambient text style (e.g. the monospace payload style).
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final WrapResult? wrap;

  const RegexTextHighlight({
    super.key,
    required this.text,
    required this.searchTerm,
    required this.highlightStyle,
    required this.fontSize,
    this.maxLines,
    this.overflow,
    this.style,
    this.strutStyle,
    this.wrap,
  });

  @override
  Widget build(BuildContext context) {
    var textStyle = DefaultTextStyle.of(context).style.merge(style);
    textStyle = textStyle.copyWith(fontSize: fontSize);
    final wrap = this.wrap;
    if (wrap != null) return _buildWrapped(textStyle, wrap);
    if (text.isEmpty) {
      return Text(
        "",
        style: textStyle,
        strutStyle: strutStyle,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
      );
    }
    if (searchTerm.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          strutStyle: strutStyle,
          overflow: overflow ?? TextOverflow.clip,
          style: textStyle);
    }
    final RegExp? highlightRegex = _compileSearchTerm(searchTerm);
    if (highlightRegex == null) {
      return Text(text,
          maxLines: maxLines,
          strutStyle: strutStyle,
          overflow: overflow ?? TextOverflow.clip,
          style: textStyle);
    }
    List<TextSpan> spans = [];
    int cursor = 0;
    for (final Match match in highlightRegex.allMatches(text)) {
      if (match.start == match.end) {
        // Zero-width match (e.g. `a*` between non-`a` characters): skip so we
        // don't emit an empty highlight span; allMatches still advances.
        continue;
      }
      if (match.start > cursor) {
        spans.add(_normalSpan(text.substring(cursor, match.start)));
      }
      spans.add(_highlightSpan(text.substring(match.start, match.end)));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(_normalSpan(text.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(_normalSpan(text));
    }
    return RichText(
      maxLines: maxLines,
      strutStyle: strutStyle,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: textStyle,
        children: spans,
      ),
    );
  }

  Widget _buildWrapped(TextStyle textStyle, WrapResult wrap) {
    final segments = wrap.segments;
    final shownEnd = segments.isEmpty ? 0 : segments.last.$2;
    final display = displayTextForWrap(text.substring(0, shownEnd));

    // Matches on the shown prefix only: a payload can be megabytes, the row
    // shows at most a few hundred characters of it.
    final matches = <(int, int)>[];
    if (searchTerm.isNotEmpty) {
      final regex = _compileSearchTerm(searchTerm);
      if (regex != null) {
        for (final m in regex.allMatches(text.substring(0, shownEnd))) {
          if (m.start != m.end) matches.add((m.start, m.end));
        }
      }
    }

    final spans = <TextSpan>[];
    for (var s = 0; s < segments.length; s++) {
      var (start, end) = segments[s];
      final isLast = s == segments.length - 1;
      final ellipsize = isLast && wrap.truncated;
      // Make room for the ellipsis inside the line's character budget.
      if (ellipsize && end > start) end--;
      var cursor = start;
      for (final (ms, me) in matches) {
        if (me <= cursor || ms >= end) continue;
        final hs = ms < cursor ? cursor : ms;
        final he = me > end ? end : me;
        if (hs > cursor) spans.add(_normalSpan(display.substring(cursor, hs)));
        spans.add(_highlightSpan(display.substring(hs, he)));
        cursor = he;
      }
      if (cursor < end) spans.add(_normalSpan(display.substring(cursor, end)));
      if (ellipsize) spans.add(_normalSpan('…'));
      if (!isLast) spans.add(_normalSpan('\n'));
    }

    return RichText(
      softWrap: false,
      maxLines: segments.isEmpty ? 1 : segments.length,
      strutStyle: strutStyle,
      overflow: TextOverflow.clip,
      text: TextSpan(style: textStyle, children: spans),
    );
  }

  TextSpan _highlightSpan(String content) {
    return TextSpan(text: content, style: highlightStyle);
  }

  TextSpan _normalSpan(String content) {
    return TextSpan(text: content);
  }
}

/// Returns true if [pattern] is a valid regex, used by callers to surface a
/// "Invalid regex" error in Find fields without duplicating the try/compile.
bool isValidRegexPattern(String pattern) {
  if (pattern.isEmpty) return true;
  try {
    RegExp(pattern);
    return true;
  } on FormatException {
    return false;
  }
}
