import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes a ZIP archive with deflated entries, enough for a bug report.
/// Dart has a deflate codec but no ZIP writer, and the format is small.
class ZipWriter {
  final _entries =
      <({String name, Uint8List data, Uint8List packed, int crc})>[];

  /// Adds a file.
  ///
  /// @param name Path inside the archive, with forward slashes.
  /// @param data Its content.
  void add(String name, List<int> data) {
    final bytes = Uint8List.fromList(data);
    final packed = Uint8List.fromList(ZLibCodec(raw: true).encode(bytes));
    _entries.add((name: name, data: bytes, packed: packed, crc: _crc32(bytes)));
  }

  /// Adds a text file in UTF-8.
  ///
  /// @param name Path inside the archive.
  /// @param text Its content.
  void addText(String name, String text) => add(name, utf8.encode(text));

  /// @returns The archive.
  Uint8List bytes() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    for (final e in _entries) {
      final name = utf8.encode(e.name);
      final offset = out.length;
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x0800, Endian.little) // names in UTF-8
        ..setUint16(8, 8, Endian.little) // deflate
        ..setUint32(14, e.crc, Endian.little)
        ..setUint32(18, e.packed.length, Endian.little)
        ..setUint32(22, e.data.length, Endian.little)
        ..setUint16(26, name.length, Endian.little);
      out
        ..add(local.buffer.asUint8List())
        ..add(name)
        ..add(e.packed);
      final entry = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint16(10, 8, Endian.little)
        ..setUint32(16, e.crc, Endian.little)
        ..setUint32(20, e.packed.length, Endian.little)
        ..setUint32(24, e.data.length, Endian.little)
        ..setUint16(28, name.length, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central
        ..add(entry.buffer.asUint8List())
        ..add(name);
    }
    final start = out.length;
    final dir = central.toBytes();
    out.add(dir);
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, _entries.length, Endian.little)
      ..setUint16(10, _entries.length, Endian.little)
      ..setUint32(12, dir.length, Endian.little)
      ..setUint32(16, start, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }

  static final _table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
