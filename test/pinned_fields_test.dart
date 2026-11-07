import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/message_font.dart';
import 'package:nats_client_flutter/pinned_fields.dart';

Message<dynamic> _msg(String text) => Message<dynamic>(
    'subj', 1, Uint8List.fromList(utf8.encode(text)), Client());

void main() {
  group('parsePinnedPath', () {
    test('plain and dotted keys', () {
      final p = parsePinnedPath('meta.status')!;
      expect(p.path, 'meta.status');
      expect(p.label, 'status');
      expect(p.segments, hasLength(2));
    });

    test('index, wildcard and quoted keys', () {
      final p = parsePinnedPath('items[0].tags[*]["a.b"]')!;
      expect(p.segments[0], isA<PinnedKey>());
      expect((p.segments[1] as PinnedIndex).index, 0);
      expect(p.segments[2], isA<PinnedKey>());
      expect(p.segments[3], isA<PinnedWildcard>());
      expect((p.segments[4] as PinnedKey).key, 'a.b');
      expect(p.label, 'a.b');
    });

    test('a leading bracket path', () {
      final p = parsePinnedPath('[*].make')!;
      expect(p.segments.first, isA<PinnedWildcard>());
      expect(p.label, 'make');
    });

    test('short name prefix sets the label and keeps the source', () {
      final p = parsePinnedPath('fc = fulfillment_center_identifier')!;
      expect(p.label, 'fc');
      expect(p.path, 'fulfillment_center_identifier');
      expect(p.source, 'fc = fulfillment_center_identifier');
    });

    test('invalid paths return null', () {
      for (final bad in [
        '',
        '  ',
        'a.',
        'a..b',
        'a[',
        'a[x]',
        'a]',
        '.a',
        'a[1]b',
        'a"b',
      ]) {
        expect(parsePinnedPath(bad), isNull, reason: bad);
      }
    });
  });

  group('extractPinned', () {
    final json = jsonDecode('''
      {"label":"urgent","n":3,"ok":true,"none":null,
       "meta":{"status":"open"},
       "items":[{"sku":"A1"},{"sku":"B7"},{"sku":"C3"},{"sku":"D9"},{"x":1}],
       "nested":{"deep":{"a":[1,2,3],"long":"${'x' * 60}"}},
       "multi":"line\\none"}''');

    String? show(String path) =>
        extractPinned(json, parsePinnedPath(path)!)?.display;

    test('scalars', () {
      expect(show('label'), 'urgent');
      expect(show('n'), '3');
      expect(show('ok'), 'true');
      expect(show('none'), 'null');
      expect(show('meta.status'), 'open');
    });

    test('missing paths are null', () {
      expect(show('nope'), isNull);
      expect(show('meta.nope'), isNull);
      expect(show('items[99].sku'), isNull);
    });

    test('array index', () {
      expect(show('items[1].sku'), 'B7');
    });

    test('wildcard and implicit wildcard list up to three values plus +N', () {
      expect(show('items[*].sku'), 'A1, B7, C3 +1');
      expect(show('items.sku'), 'A1, B7, C3 +1');
      final full = extractPinned(json, parsePinnedPath('items.sku')!)!.full;
      expect(full, 'A1, B7, C3, D9');
    });

    test('objects and arrays show compact, truncated JSON', () {
      expect(show('nested.deep.a'), '[1,2,3]');
      expect(show('nested.deep')!.length, 40);
      expect(show('nested.deep'), endsWith('…'));
    });

    test('newlines in string values become spaces', () {
      expect(show('multi'), 'line one');
    });
  });

  group('decodeJsonPayload', () {
    test('objects and arrays decode', () {
      expect(decodeJsonPayload(' {"a":1}'), {'a': 1});
      expect(decodeJsonPayload('[1]'), [1]);
    });

    test('non-JSON and scalars are null', () {
      expect(decodeJsonPayload('hello'), isNull);
      expect(decodeJsonPayload('42'), isNull);
      expect(decodeJsonPayload('{broken'), isNull);
      expect(decodeJsonPayload(''), isNull);
    });
  });

  group('flattenJsonPaths', () {
    test('lists leaf paths and merges arrays of objects as [*]', () {
      final json = jsonDecode('''
        {"id":1,"customer":{"name":"a","address":{"city":"x"}},
         "items":[{"sku":"A","qty":1},{"sku":"B","price":2}],
         "tags":["a","b"],"empty":{},"weird key":1}''');
      expect(
        flattenJsonPaths(json),
        [
          'id',
          'customer.name',
          'customer.address.city',
          'items[*].sku',
          'items[*].qty',
          'items[*].price',
          'tags',
          'empty',
          '["weird key"]',
        ],
      );
    });

    test('a root array of objects', () {
      expect(flattenJsonPaths(jsonDecode('[{"make":"a"},{"model":"b"}]')),
          ['[*].make', '[*].model']);
    });

    test('every listed path parses and resolves', () {
      final json = jsonDecode(
          '{"a":{"b.c":1},"items":[{"x":{"y":2}}],"q":"\\"quoted\\""}');
      for (final path in flattenJsonPaths(json)) {
        final parsed = parsePinnedPath(path);
        expect(parsed, isNotNull, reason: path);
        expect(extractPinned(json, parsed!), isNotNull, reason: path);
      }
    });
  });

  group('PinnedFields', () {
    PinnedFields fields(List<String> sources, List<Message<dynamic>> msgs) =>
        PinnedFields()
          ..setPaths(
              [for (final s in sources) parsePinnedPath(s)!], msgs, (_) => 30);

    test('rows with none of the fields have no values and no area', () {
      final heartbeat = _msg('heartbeat');
      final other = _msg('{"x":1}');
      final f = fields(['label'], [heartbeat, other]);
      expect(f.valuesFor(heartbeat), isNull);
      expect(f.valuesFor(other), isNull);
      expect(f.areaWidth(heartbeat), 0);
    });

    test('rows with some of the fields keep a null slot for the missing one',
        () {
      final m = _msg('{"label":"urgent"}');
      final f = fields(['label', 'sku'], [m]);
      final values = f.valuesFor(m)!;
      expect(values[0]!.display, 'urgent');
      expect(values[1], isNull);
      expect(f.areaWidth(m), greaterThan(0));
    });

    test('columns start at the caption width and only grow', () {
      final short = _msg('{"label":"a"}');
      final f = fields(['label'], [short]);
      final start = f.columnWidth(0);
      expect(start, pinCellHorizontalPadding + 30);

      final long = _msg('{"label":"zzzzzz"}');
      expect(f.noteMessage(long), isTrue);
      final grown = f.columnWidth(0);
      expect(
          grown,
          (pinCellHorizontalPadding + 6 * monoCharWidth(pinValueFontSize))
              .ceilToDouble());
      expect(f.noteMessage(short), isFalse);
      expect(f.columnWidth(0), grown);
    });

    test('columns are capped at the width cap, which tracks the list width',
        () {
      final f = fields(['label'], [_msg('{"label":"${'z' * 500}"}')]);
      expect(f.columnWidth(0), pinCellMaxWidth);
      f.widthCap = pinCellWidthCap(700); // a narrow window
      expect(f.columnWidth(0), 140);
      f.widthCap = pinCellWidthCap(2000);
      expect(f.columnWidth(0), pinCellMaxWidth);
    });

    test('pinCellWidthCap is a fifth of the row, within its bounds', () {
      expect(pinCellWidthCap(0), pinCellMaxWidth);
      expect(pinCellWidthCap(400), pinCellMinCap);
      expect(pinCellWidthCap(1000), 200);
      expect(pinCellWidthCap(3000), pinCellMaxWidth);
    });

    test('a want growing past the cap does not count as visible growth', () {
      final f = fields(['label'], [_msg('{"label":"${'z' * 100}"}')]);
      f.widthCap = 140;
      final before = f.layoutVersion;
      expect(f.noteMessage(_msg('{"label":"${'y' * 200}"}')), isFalse);
      expect(f.layoutVersion, before);
    });

    test('resetWidths shrinks back to the captions', () {
      final f = fields(['label'], [_msg('{"label":"${'z' * 30}"}')]);
      expect(f.columnWidth(0), greaterThan(pinCellHorizontalPadding + 30));
      f.resetWidths(const []);
      expect(f.columnWidth(0), pinCellHorizontalPadding + 30);
    });

    test('changing paths invalidates cached values', () {
      final m = _msg('{"a":1,"b":2}');
      final f = fields(['a'], [m]);
      expect(f.valuesFor(m)!.single!.display, '1');
      f.setPaths([parsePinnedPath('b')!], [m], (_) => 30);
      expect(f.valuesFor(m)!.single!.display, '2');
    });

    test('payloads over the size cap are not parsed', () {
      final big = _msg('{"label":"a","pad":"${'x' * pinnedJsonMaxBytes}"}');
      final f = fields(['label'], [big]);
      expect(f.valuesFor(big), isNull);
    });
  });
}
