import 'package:flutter/material.dart';

/// Custom syntax highlight theme for HighlightView that matches the app's theme.
/// Call [getCustomHighlightTheme] with the current [BuildContext] and [isDark] flag.
Map<String, TextStyle> getCustomHighlightTheme(BuildContext context, {required bool isDark}) {
  final theme = Theme.of(context);
  final baseTextColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
  final backgroundColor = theme.colorScheme.surface;
  final accentColor = theme.colorScheme.secondary;
  final keywordColor = isDark ? Colors.lightBlue[200]! : Colors.blue[800]!;
  final stringColor = isDark ? Colors.greenAccent[200]! : Colors.green[800]!;
  final commentColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
  final numberColor = isDark ? Colors.orange[200]! : Colors.orange[800]!;
  final functionColor = isDark ? Colors.purple[200]! : Colors.purple[800]!;
  const monoFont = 'monospace';

  return {
    'root': TextStyle(
      backgroundColor: backgroundColor,
      color: baseTextColor,
      fontFamily: monoFont,
    ),
    'keyword': TextStyle(color: keywordColor, fontWeight: FontWeight.bold, fontFamily: monoFont),
    'selector-tag': TextStyle(color: keywordColor, fontWeight: FontWeight.bold, fontFamily: monoFont),
    'literal': TextStyle(color: numberColor, fontFamily: monoFont),
    'section': TextStyle(color: accentColor, fontFamily: monoFont),
    'link': TextStyle(color: accentColor, decoration: TextDecoration.underline, fontFamily: monoFont),
    'subst': TextStyle(color: baseTextColor, fontFamily: monoFont),
    'string': TextStyle(color: stringColor, fontFamily: monoFont),
    'title': TextStyle(color: functionColor, fontWeight: FontWeight.bold, fontFamily: monoFont),
    'name': TextStyle(color: functionColor, fontFamily: monoFont),
    'type': TextStyle(color: accentColor, fontFamily: monoFont),
    'attribute': TextStyle(color: accentColor, fontFamily: monoFont),
    'symbol': TextStyle(color: numberColor, fontFamily: monoFont),
    'bullet': TextStyle(color: numberColor, fontFamily: monoFont),
    'built_in': TextStyle(color: functionColor, fontFamily: monoFont),
    'addition': TextStyle(color: stringColor, fontFamily: monoFont),
    'variable': TextStyle(color: accentColor, fontFamily: monoFont),
    'template-tag': TextStyle(color: accentColor, fontFamily: monoFont),
    'template-variable': TextStyle(color: accentColor, fontFamily: monoFont),
    'comment': TextStyle(color: commentColor, fontStyle: FontStyle.italic, fontFamily: monoFont),
    'quote': TextStyle(color: commentColor, fontStyle: FontStyle.italic, fontFamily: monoFont),
    'deletion': TextStyle(color: Colors.red[400], fontFamily: monoFont),
    'meta': TextStyle(color: accentColor, fontFamily: monoFont),
    'doctag': TextStyle(color: accentColor, fontFamily: monoFont),
    'emphasis': TextStyle(fontStyle: FontStyle.italic, fontFamily: monoFont),
    'strong': TextStyle(fontWeight: FontWeight.bold, fontFamily: monoFont),
  };
}
