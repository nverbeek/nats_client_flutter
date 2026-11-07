import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/message_wrap.dart';

void main() {
  group('wrapSegments', () {
    test('short text is one untruncated line', () {
      final r = wrapSegments('hello', 10, 4);
      expect(r.segments, [(0, 5)]);
      expect(r.truncated, isFalse);
      expect(r.lineCount, 1);
    });

    test('empty text is one empty line', () {
      final r = wrapSegments('', 10, 4);
      expect(r.segments, [(0, 0)]);
      expect(r.truncated, isFalse);
    });

    test('a long line is chunked at exactly charsPerLine', () {
      final r = wrapSegments('abcdefghij', 4, 5);
      expect(r.segments, [(0, 4), (4, 8), (8, 10)]);
      expect(r.truncated, isFalse);
    });

    test('an exact multiple of charsPerLine has no empty trailing line', () {
      final r = wrapSegments('abcdefgh', 4, 5);
      expect(r.segments, [(0, 4), (4, 8)]);
      expect(r.truncated, isFalse);
    });

    test('hard newlines start new lines and are not part of a segment', () {
      final r = wrapSegments('ab\ncd\n\nef', 10, 10);
      expect(r.segments, [(0, 2), (3, 5), (6, 6), (7, 9)]);
      expect(r.truncated, isFalse);
    });

    test('a trailing newline yields a final empty line', () {
      final r = wrapSegments('ab\n', 10, 10);
      expect(r.segments, [(0, 2), (3, 3)]);
    });

    test('stops at maxLines and reports truncation', () {
      final r = wrapSegments('a' * 100, 10, 3);
      expect(r.segments, [(0, 10), (10, 20), (20, 30)]);
      expect(r.truncated, isTrue);
    });

    test('hard lines past maxLines also truncate', () {
      final r = wrapSegments('a\nb\nc', 10, 2);
      expect(r.segments, [(0, 1), (2, 3)]);
      expect(r.truncated, isTrue);
    });

    test('never splits a surrogate pair', () {
      // 'a' then an emoji (2 code units) then 'b'.
      const text = 'a\u{1F600}b';
      final r = wrapSegments(text, 2, 5);
      expect(r.segments, [(0, 1), (1, 3), (3, 4)]);
    });

    test('charsPerLine 1 still makes progress over a surrogate pair', () {
      const text = '\u{1F600}x';
      final r = wrapSegments(text, 1, 5);
      expect(r.segments, [(0, 2), (2, 3)]);
    });

    test('work is bounded by maxLines on a huge payload', () {
      final big = 'x' * 5000000;
      final sw = Stopwatch()..start();
      final r = wrapSegments(big, 120, 4);
      sw.stop();
      expect(r.lineCount, 4);
      expect(r.truncated, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('displayTextForWrap', () {
    test('returns the same string when there is nothing to replace', () {
      const text = 'plain {"a":1}\nnext';
      expect(identical(displayTextForWrap(text), text), isTrue);
    });

    test('replaces tabs and carriage returns, keeping length and newlines', () {
      const text = 'a\tb\r\nc';
      final display = displayTextForWrap(text);
      expect(display, 'a b \nc');
      expect(display.length, text.length);
    });
  });

  group('WrapCache', () {
    test('reuses a result until cpl or maxLines changes', () {
      final cache = WrapCache();
      final key = Object();
      final a = cache.wrapFor(key, 'abcdefgh', 4, 3);
      expect(identical(cache.wrapFor(key, 'abcdefgh', 4, 3), a), isTrue);
      final b = cache.wrapFor(key, 'abcdefgh', 2, 3);
      expect(identical(b, a), isFalse);
      expect(b.lineCount, 3);
      expect(b.truncated, isTrue);
    });
  });
}
