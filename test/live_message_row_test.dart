import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/live_message_row.dart';
import 'package:nats_client_flutter/message_font.dart';
import 'package:nats_client_flutter/message_row_metrics.dart';
import 'package:nats_client_flutter/message_wrap.dart';
import 'package:nats_client_flutter/pinned_fields.dart';
import 'package:nats_client_flutter/regex_text_highlight.dart';

/// Guards the contract the multi-line Live Messages list depends on: the
/// height and text width worked out by `message_row_metrics.dart` (without a
/// layout) are exactly what the row then draws. If they drifted apart, the
/// list's prepend compensation and scrollbar would be off, or text would be
/// clipped mid-line.
void main() {
  const subject = 'orders.created.eu-west-1';
  const fontSize = 14.0;
  final longJson = jsonEncode({
    'order_id': 'ord_4812',
    'customer': {'name': 'Ada Lovelace', 'tier': 'gold'},
    'items': [
      {'sku': 'A1-RED', 'qty': 2},
      {'sku': 'B7-BLU', 'qty': 1},
    ],
    'note': 'x' * 400,
    'label': 'urgent',
  });

  Message<dynamic> msg(String text) => Message<dynamic>(
      subject, 1, Uint8List.fromList(utf8.encode(text)), Client());

  /// Pumps one row the way main.dart builds it, at [rowWidth], and returns
  /// the layout main.dart would have computed for it.
  Future<({WrapResult? wrap, double extent, double titleWidth})> pumpRow(
    WidgetTester tester, {
    required String text,
    required double rowWidth,
    required int maxLines,
    bool showTimestamp = true,
    bool showSubject = true,
    bool showColorBar = true,
    List<String> pins = const [],
    String findTerm = '',
  }) async {
    late ({WrapResult? wrap, double extent, double titleWidth}) result;
    final message = msg(text);
    // The default 800px test surface would squeeze the wider rows.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final theme = Theme.of(context);
          final pinned = PinnedFields()
            ..setPaths(
              [for (final p in pins) parsePinnedPath(p)!],
              [message],
              (label) => measureTextWidth(label, pinCaptionStyle(theme)),
            );
          final chipStyle = (theme.textTheme.labelLarge ?? const TextStyle())
              .copyWith(fontSize: fontSize);
          final tsStyle = timestampTextStyle(
              theme.textTheme.bodyMedium ?? const TextStyle());
          // The same function main.dart's list uses.
          final layout = layoutMessageRow(
            wrapKey: message,
            wrapCache: WrapCache(),
            text: text,
            subject: subject,
            hasTimestamp: showTimestamp,
            rowWidth: rowWidth,
            fontSize: fontSize,
            maxLines: maxLines,
            showColorBar: showColorBar,
            showSubject: showSubject,
            pinAreaWidth: pinned.areaWidth(message),
            timestampStyle: tsStyle,
            chipLabelStyle: chipStyle,
          );
          final values =
              layout.pinAreaWidth > 0 ? pinned.valuesFor(message) : null;
          final trailingWidth = layout.trailingWidth;
          final titleWidth = messageTitleWidth(
            rowWidth: rowWidth,
            showColorBar: showColorBar,
            pinAreaWidth: layout.pinAreaWidth,
            trailingWidth: trailingWidth,
          );
          final wrap = maxLines > 1 ? layout.wrap : null;
          final extent = messageRowExtent(wrap?.lineCount ?? 1, fontSize);
          result = (wrap: wrap, extent: extent, titleWidth: titleWidth);
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: rowWidth,
              height: extent,
              child: LiveMessageRow(
                text: text,
                subject: subject,
                findTerm: findTerm,
                fontSize: fontSize,
                extent: extent,
                tileColor: Colors.white,
                barColor: Colors.blue,
                showColorBar: showColorBar,
                timestamp: showTimestamp ? '10:15:02.114 PM' : null,
                showSubject: showSubject,
                wrap: wrap,
                trailingWidth: wrap == null ? null : trailingWidth,
                pins: values == null
                    ? null
                    : RowPins(pinned.paths, values, [
                        for (var k = 0; k < values.length; k++)
                          pinned.columnWidth(k),
                      ]),
                onTap: () {},
                menuButton: PopupMenuButton<String>(
                  itemBuilder: (_) => const [],
                ),
                onPinTap: (_, __) {},
              ),
            ),
          );
        }),
      ),
    ));
    await tester.pump();
    return result;
  }

  RenderParagraph titleParagraph(WidgetTester tester) {
    final finder = find.descendant(
        of: find.byType(RegexTextHighlight), matching: find.byType(RichText));
    return tester.renderObject<RenderParagraph>(finder.first);
  }

  for (final width in [520.0, 900.0, 1400.0]) {
    for (final maxLines in [2, 4, 8]) {
      testWidgets(
          'a $maxLines-line row at width $width draws exactly the computed '
          'height and title width', (tester) async {
        final layout = await pumpRow(tester,
            text: longJson, rowWidth: width, maxLines: maxLines);
        expect(tester.takeException(), isNull);

        final paragraph = titleParagraph(tester);
        expect(paragraph.size.width, closeTo(layout.titleWidth, 0.01));
        final lines = layout.wrap!.lineCount;
        expect(paragraph.size.height,
            closeTo(monoTextBlockHeight(fontSize, lines), 0.01));
        // Every wrapped line fits in the title without being clipped.
        expect(paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(layout.titleWidth + 0.01));
        expect(tester.getSize(find.byType(ListTile)).height, layout.extent);
      });
    }
  }

  testWidgets('the subject chip gets the room the metrics reserve for it',
      (tester) async {
    await pumpRow(tester, text: longJson, rowWidth: 900, maxLines: 4);
    final chipLabel = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.byType(Chip), matching: find.byType(RichText)));
    expect(chipLabel.didExceedMaxLines, isFalse);
    expect(chipLabel.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(chipLabel.size.width + 0.01));
  });

  testWidgets('pins and a hidden subject still give an exact title width',
      (tester) async {
    final layout = await pumpRow(tester,
        text: longJson,
        rowWidth: 1000,
        maxLines: 4,
        showSubject: false,
        pins: ['label', 'items[*].sku', 'fc=customer.tier']);
    expect(tester.takeException(), isNull);
    expect(titleParagraph(tester).size.width, closeTo(layout.titleWidth, 0.01));
    expect(find.byType(Chip), findsNothing);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('A1-RED, B7-BLU'), findsOneWidget);
    expect(find.text('fc'), findsOneWidget);
  });

  testWidgets('a row with none of the pinned fields shows no pin area',
      (tester) async {
    final layout = await pumpRow(tester,
        text: 'heartbeat', rowWidth: 1000, maxLines: 4, pins: ['label']);
    expect(find.byType(PinnedFieldCells), findsNothing);
    expect(layout.wrap!.lineCount, 1);
    expect(layout.extent, MessageRowGeometry.minRowExtent);
  });

  testWidgets('short messages in multi-line mode keep the single-line height',
      (tester) async {
    final layout =
        await pumpRow(tester, text: '{"ok":true}', rowWidth: 900, maxLines: 6);
    expect(layout.extent, messageRowExtent(1, fontSize));
  });

  testWidgets('single-line rows keep the long-standing layout', (tester) async {
    await pumpRow(tester, text: longJson, rowWidth: 900, maxLines: 1);
    expect(tester.takeException(), isNull);
    final paragraph = titleParagraph(tester);
    expect(paragraph.didExceedMaxLines, isTrue); // ellipsized on one line
    expect(tester.getSize(find.byType(ListTile)).height,
        messageRowExtent(1, fontSize));
  });

  testWidgets('a truncated row ends in an ellipsis', (tester) async {
    await pumpRow(tester, text: longJson, rowWidth: 600, maxLines: 2);
    final text = titleParagraph(tester).text.toPlainText();
    expect(text, endsWith('…'));
    expect('\n'.allMatches(text).length, 1);
  });

  testWidgets('Find highlights survive a line break inside the match',
      (tester) async {
    // 'abcdef' split across the two lines of a narrow row.
    final layout = await pumpRow(tester,
        text: '${'x' * 400}abcdef',
        rowWidth: 520,
        maxLines: 20,
        showTimestamp: false,
        findTerm: 'abcdef');
    final cpl = layout.wrap!.segments.first.$2;
    // Re-pump with the match straddling the first break.
    await pumpRow(tester,
        text: '${'x' * (cpl - 3)}abcdef',
        rowWidth: 520,
        maxLines: 20,
        showTimestamp: false,
        findTerm: 'abcdef');
    final root = titleParagraph(tester).text as TextSpan;
    final highlighted = <String>[];
    root.visitChildren((span) {
      if (span is TextSpan && span.style?.background != null) {
        highlighted.add(span.text!);
      }
      return true;
    });
    expect(highlighted, ['abc', 'def']);
  });
}
