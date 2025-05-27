//import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';

/// Widget that applies [highlightStyle] to the provided [text] when any portion
/// of the text matches the [searchTerm]. Text is limited to [maxLines].
class RegexTextHighlight extends StatelessWidget {
  final String text;
  final String searchTerm;
  final TextStyle highlightStyle;
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  const RegexTextHighlight({super.key,
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
      return Text("",
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
    List<TextSpan> spans = [];
    int start = 0;
    while (true) {
      var highlightRegex = RegExp('($searchTerm)', caseSensitive: false);
      final String? highlight =
      highlightRegex.stringMatch(text.substring(start));
      if (highlight == null) {
        spans.add(_normalSpan(text.substring(start)));
        break;
      }
      final int indexOfHighlight = text.indexOf(highlight, start);
      if (indexOfHighlight == start) {
        spans.add(_highlightSpan(highlight));
        start += highlight.length;
      } else {
        spans.add(_normalSpan(text.substring(start, indexOfHighlight)));
        spans.add(_highlightSpan(highlight));
        start = indexOfHighlight + highlight.length;
      }
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