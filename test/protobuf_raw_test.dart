import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nats_client_flutter/protobuf_raw.dart';

/// Tiny protobuf encoder for building test payloads.
class _Pb {
  final BytesBuilder _b = BytesBuilder();

  static List<int> varint(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      final byte = v & 0x7F;
      v = v >>> 7;
      if (v == 0) {
        out.add(byte);
        return out;
      }
      out.add(byte | 0x80);
    }
  }

  void tag(int number, int wireType) =>
      _b.add(varint((number << 3) | wireType));

  _Pb uint(int number, int value) {
    tag(number, 0);
    _b.add(varint(value));
    return this;
  }

  _Pb dbl(int number, double value) {
    tag(number, 1);
    _b.add((ByteData(8)..setFloat64(0, value, Endian.little))
        .buffer
        .asUint8List());
    return this;
  }

  _Pb flt(int number, double value) {
    tag(number, 5);
    _b.add((ByteData(4)..setFloat32(0, value, Endian.little))
        .buffer
        .asUint8List());
    return this;
  }

  _Pb bytes(int number, List<int> value) {
    tag(number, 2);
    _b.add(varint(value.length));
    _b.add(value);
    return this;
  }

  _Pb str(int number, String value) => bytes(number, utf8.encode(value));
  _Pb msg(int number, _Pb value) => bytes(number, value.build());

  Uint8List build() => _b.toBytes();
}

void main() {
  test('decodes scalars, strings and nested messages', () {
    final payload = (_Pb()
          ..uint(1, 1730912345678)
          ..str(2, 'sensor "lobby"')
          ..msg(
              3,
              _Pb()
                ..uint(1, 7)
                ..dbl(13, 21.5))
          ..flt(4, 0.25))
        .build();
    expect(
      decodeProtobufRaw(payload),
      '1: 1730912345678\n'
      '2: "sensor \\"lobby\\""\n'
      '3 {\n'
      '  1: 7\n'
      '  13: 21.5  // fixed64 0x4035800000000000\n'
      '}\n'
      '4: 0.25  // fixed32 0x3e800000',
    );
  });

  test('repeated nested records, like a batch of readings', () {
    final batch = _Pb()..uint(1, 3);
    for (var i = 0; i < 3; i++) {
      batch.msg(
          2,
          _Pb()
            ..uint(2, 700 + i)
            ..uint(3, 1730912345000 + i)
            ..dbl(13, 2.5 + i));
    }
    final text = decodeProtobufRaw(batch.build())!;
    expect('2 {'.allMatches(text).length, 3);
    expect(text, contains('  13: 4.5  // fixed64'));
  });

  test('negative int64 varints also show their signed value', () {
    final text = decodeProtobufRaw((_Pb()..uint(1, -5)).build())!;
    expect(text, '1: 18446744073709551611  // int64 -5');
  });

  test('implausible fixed64 values print as hex only', () {
    final payload = _Pb()..tag(1, 1);
    final b = BytesBuilder()
      ..add(payload.build())
      ..add([1, 0, 0, 0, 0, 0, 0, 0]);
    expect(decodeProtobufRaw(b.toBytes()), '1: 0x0000000000000001  // fixed64');
  });

  test('non-text, non-message bytes print as hex', () {
    final text =
        decodeProtobufRaw((_Pb()..bytes(5, [0xFF, 0x00, 0x13])).build())!;
    expect(text, '5: <ff 00 13>  // 3 bytes');
  });

  test('empty length-delimited field is an empty string', () {
    expect(decodeProtobufRaw((_Pb()..str(1, '')).build()), '1: ""');
  });

  group('rejects what is not protobuf', () {
    test(
        'empty payload', () => expect(decodeProtobufRaw(Uint8List(0)), isNull));

    test('truncated varint', () {
      expect(decodeProtobufRaw(Uint8List.fromList([0xFF, 0xFE])), isNull);
    });

    test('field number 0', () {
      expect(decodeProtobufRaw(Uint8List.fromList([0x00, 0x01])), isNull);
    });

    test('invalid wire type', () {
      expect(decodeProtobufRaw(Uint8List.fromList([0x0F, 0x01])), isNull);
    });

    test('length past the end', () {
      expect(decodeProtobufRaw(Uint8List.fromList([0x0A, 0x05, 0x41])), isNull);
    });

    test('truncated fixed64', () {
      expect(decodeProtobufRaw(Uint8List.fromList([0x09, 1, 2, 3])), isNull);
    });

    test('a plain JSON payload', () {
      expect(decodeProtobufRaw(Uint8List.fromList(utf8.encode('{"a":1}'))),
          isNull);
    });
  });
}
