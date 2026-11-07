import 'dart:convert';
import 'dart:typed_data';

/// Decodes [bytes] as a Protocol Buffers message without its schema, the way
/// `protoc --decode_raw` does: field numbers and values, but no names.
/// Returns the readable text, or null if [bytes] isn't a well-formed
/// protobuf message (so the Message Detail dialog only offers the view when
/// it applies).
///
/// Wire types: varints print as unsigned integers (plus the signed int64
/// reading when the top bit is set); 64- and 32-bit fixed fields print as a
/// double/float when that reading looks like a real number, followed by
/// their raw hex; length-delimited fields print as a nested message, a
/// string, or hex bytes, whichever fits. Groups (deprecated) aren't
/// supported and make the decode fail.
///
/// A schema-less decode is a guess: a length-delimited field can be a
/// nested message, a string, raw bytes or a packed repeated field, and the
/// bytes alone don't say which.
String? decodeProtobufRaw(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > protobufDecodeMaxBytes) return null;
  final fields = _parseMessage(bytes, 0, bytes.length, 0);
  if (fields == null || fields.isEmpty) return null;
  final out = StringBuffer();
  _render(fields, out, 0);
  return out.toString().trimRight();
}

/// Payloads bigger than this aren't decoded; the dialog falls back to Hex.
const int protobufDecodeMaxBytes = 1024 * 1024;

const int _maxDepth = 32;
const int _maxFieldNumber = (1 << 29) - 1;
const int _maxBytesShown = 64;

class _Field {
  final int number;
  BigInt? varint;
  Uint8List? fixed; // 8 or 4 bytes, little-endian
  List<_Field>? nested;
  String? string;
  Uint8List? bytes;

  _Field(this.number);
}

class _Varint {
  final BigInt value;
  final int next;
  _Varint(this.value, this.next);
}

_Varint? _readVarint(Uint8List b, int pos, int end) {
  var value = BigInt.zero;
  var shift = 0;
  for (var i = 0; i < 10; i++) {
    if (pos >= end) return null;
    final byte = b[pos++];
    value |= BigInt.from(byte & 0x7F) << shift;
    if (byte & 0x80 == 0) return _Varint(value, pos);
    shift += 7;
  }
  return null; // more than 10 bytes: not a valid varint
}

List<_Field>? _parseMessage(Uint8List b, int start, int end, int depth) {
  if (depth > _maxDepth) return null;
  final fields = <_Field>[];
  var pos = start;
  while (pos < end) {
    final key = _readVarint(b, pos, end);
    if (key == null || key.value.bitLength > 32) return null;
    pos = key.next;
    final tag = key.value.toInt();
    final number = tag >> 3;
    final wireType = tag & 0x7;
    if (number < 1 || number > _maxFieldNumber) return null;
    final field = _Field(number);
    switch (wireType) {
      case 0:
        final v = _readVarint(b, pos, end);
        if (v == null) return null;
        field.varint = v.value;
        pos = v.next;
      case 1:
        if (pos + 8 > end) return null;
        field.fixed = Uint8List.fromList(b.sublist(pos, pos + 8));
        pos += 8;
      case 5:
        if (pos + 4 > end) return null;
        field.fixed = Uint8List.fromList(b.sublist(pos, pos + 4));
        pos += 4;
      case 2:
        final len = _readVarint(b, pos, end);
        if (len == null || len.value > BigInt.from(end - len.next)) {
          return null;
        }
        pos = len.next;
        final length = len.value.toInt();
        final chunk = Uint8List.sublistView(b, pos, pos + length);
        final text = _printableUtf8(chunk);
        if (text != null) {
          field.string = text;
        } else {
          final nested = length == 0
              ? null
              : _parseMessage(b, pos, pos + length, depth + 1);
          if (nested != null && nested.isNotEmpty) {
            field.nested = nested;
          } else {
            field.bytes = Uint8List.fromList(chunk);
          }
        }
        pos += length;
      default:
        return null; // groups (3, 4) and invalid wire types 6, 7
    }
    fields.add(field);
  }
  return fields;
}

/// [chunk] as text if it's valid UTF-8 made of printable characters (tabs
/// and newlines allowed), else null. Empty counts as the empty string.
String? _printableUtf8(Uint8List chunk) {
  final String text;
  try {
    text = utf8.decode(chunk);
  } on FormatException {
    return null;
  }
  for (final rune in text.runes) {
    if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
      return null;
    }
    if (rune == 0x7F) return null;
  }
  return text;
}

final BigInt _twoTo63 = BigInt.one << 63;
final BigInt _twoTo64 = BigInt.one << 64;

String _hex(Uint8List littleEndian) {
  final buffer = StringBuffer('0x');
  for (var i = littleEndian.length - 1; i >= 0; i--) {
    buffer.write(littleEndian[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Whether a decoded float looks like a real measurement rather than
/// integer bits that happen to be read as a float.
bool _plausibleFloat(double v) {
  if (!v.isFinite) return false;
  if (v == 0) return true;
  final magnitude = v.abs();
  return magnitude >= 1e-9 && magnitude <= 1e15;
}

String _formatFloat(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(1);
  return v.toString();
}

String _quote(String s) {
  final buffer = StringBuffer('"');
  for (final rune in s.runes) {
    switch (rune) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        buffer.writeCharCode(rune);
    }
  }
  buffer.write('"');
  return buffer.toString();
}

void _render(List<_Field> fields, StringBuffer out, int depth) {
  final indent = '  ' * depth;
  for (final f in fields) {
    final nested = f.nested;
    if (nested != null) {
      out.writeln('$indent${f.number} {');
      _render(nested, out, depth + 1);
      out.writeln('$indent}');
      continue;
    }
    out.write('$indent${f.number}: ');
    final varint = f.varint;
    final fixed = f.fixed;
    final bytes = f.bytes;
    if (varint != null) {
      out.write(varint);
      if (varint >= _twoTo63) out.write('  // int64 ${varint - _twoTo64}');
    } else if (fixed != null) {
      final data = ByteData.sublistView(fixed);
      final isDouble = fixed.length == 8;
      final value = isDouble
          ? data.getFloat64(0, Endian.little)
          : data.getFloat32(0, Endian.little);
      final kind = isDouble ? 'fixed64' : 'fixed32';
      if (_plausibleFloat(value)) {
        out.write('${_formatFloat(value)}  // $kind ${_hex(fixed)}');
      } else {
        out.write('${_hex(fixed)}  // $kind');
      }
    } else if (bytes != null) {
      final shown = bytes.length > _maxBytesShown
          ? bytes.sublist(0, _maxBytesShown)
          : bytes;
      final hex =
          shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      out.write('<$hex${bytes.length > _maxBytesShown ? ' …' : ''}>');
      out.write('  // ${bytes.length} bytes');
    } else {
      out.write(_quote(f.string ?? ''));
    }
    out.writeln();
  }
}
