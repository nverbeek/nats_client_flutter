import 'package:flutter/cupertino.dart';

class RegexTextHighlight extends StatelessWidget {
  final String text;
  final String searchTerm;
  final TextStyle highlightStyle;
  final int maxLines = 5;

  const RegexTextHighlight({super.key,
    required this.text,
    required this.searchTerm,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Text("",
          style: DefaultTextStyle.of(context).style);
    }

    if (searchTerm.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          style: DefaultTextStyle.of(context).style);
    }

    List<TextSpan> spans = [];
    int start = 0;
    while (true) {

      var highlightRegex = RegExp('($searchTerm)', caseSensitive: false);

      final String? highlight =
      highlightRegex.stringMatch(text.substring(start));
      if (highlight == null) {
        // no highlight
        spans.add(_normalSpan(text.substring(start)));
        break;
      }

      final int indexOfHighlight = text.indexOf(highlight, start);

      if (indexOfHighlight == start) {
        // starts with highlight
        spans.add(_highlightSpan(highlight));
        start += highlight.length;
      } else {
        // normal + highlight
        spans.add(_normalSpan(text.substring(start, indexOfHighlight)));
        spans.add(_highlightSpan(highlight));
        start = indexOfHighlight + highlight.length;
      }
    }

    return RichText(
      maxLines: maxLines,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
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