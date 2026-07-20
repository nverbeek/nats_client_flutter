import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';

void main() {
  Widget buildHighlight({
    required String text,
    required String searchTerm,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RegexTextHighlight(
          text: text,
          searchTerm: searchTerm,
          fontSize: 14,
          highlightStyle: const TextStyle(backgroundColor: Colors.yellow),
        ),
      ),
    );
  }

  testWidgets('an invalid regex renders plain text instead of crashing',
      (tester) async {
    await tester
        .pumpWidget(buildHighlight(text: 'hello [world]', searchTerm: '['));

    expect(tester.takeException(), isNull);
    expect(find.text('hello [world]'), findsOneWidget);
    expect(
        find.byType(RichText).evaluate().where((e) {
          final richText = e.widget as RichText;
          return (richText.text as TextSpan).children?.isNotEmpty ?? false;
        }),
        isEmpty);
  });

  testWidgets('a zero-width-matching pattern completes without hanging',
      (tester) async {
    await tester.pumpWidget(buildHighlight(text: 'banana', searchTerm: 'a*'));

    expect(tester.takeException(), isNull);
    expect(find.byType(RichText), findsOneWidget);
  });

  testWidgets('a normal pattern highlights the matching portion',
      (tester) async {
    await tester
        .pumpWidget(buildHighlight(text: 'hello world', searchTerm: 'world'));

    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    final texts = span.children!.map((s) => (s as TextSpan).text).toList();
    expect(texts, ['hello ', 'world']);
  });

  testWidgets('an empty search term renders plain text', (tester) async {
    await tester
        .pumpWidget(buildHighlight(text: 'hello world', searchTerm: ''));

    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('empty text renders an empty Text widget', (tester) async {
    await tester.pumpWidget(buildHighlight(text: '', searchTerm: 'anything'));

    expect(find.text(''), findsOneWidget);
  });

  test('isValidRegexPattern accepts empty and valid patterns, rejects invalid',
      () {
    expect(isValidRegexPattern(''), isTrue);
    expect(isValidRegexPattern('a.*b'), isTrue);
    expect(isValidRegexPattern('['), isFalse);
    expect(isValidRegexPattern('('), isFalse);
  });
}
