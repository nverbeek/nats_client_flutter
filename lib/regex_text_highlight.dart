//import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';

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
class RegexTextHighlight extends StatelessWidget {
  final String text;
  final String searchTerm;
  final TextStyle highlightStyle;
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  const RegexTextHighlight({
    super.key,
    required this.text,
    required this.searchTerm,
    required this.highlightStyle,
    required this.fontSize,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    var textStyle = DefaultTextStyle.of(context).style;
    textStyle = textStyle.copyWith(fontSize: fontSize);
    if (text.isEmpty) {
      return Text(
        "",
        style: textStyle,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
      );
    }
    if (searchTerm.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          overflow: overflow ?? TextOverflow.clip,
          style: textStyle);
    }
    final RegExp? highlightRegex = _compileSearchTerm(searchTerm);
    if (highlightRegex == null) {
      return Text(text,
          maxLines: maxLines,
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
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: textStyle,
        children: spans,
      ),
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
