import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Data type of a column as stored in the .cdb file.
enum CdbType {
  integer(0),
  float(1),
  text(2),
  floatList(10),
  intList(11);

  const CdbType(this.code);
  final int code;

  /// Maps the type code of the file to a [CdbType].
  ///
  /// @param code Type code from the column header.
  /// @returns The matching type.
  /// @throws FormatException For an unknown code.
  static CdbType fromCode(int code) => values.firstWhere(
        (t) => t.code == code,
        orElse: () => throw FormatException('Unbekannter Spaltentyp $code'),
      );
}

/// One column of a table, stored column-wise.
class CdbColumn {
  CdbColumn(this.name, this.type, this.values);

  final String name;
  final CdbType type;

  /// One value per row: int, double, String, `List<double>` or `List<int>`.
  final List<Object> values;
}

/// A table of the database with its columns.
class CdbTable {
  CdbTable(this.name, this.rowCount, this.columns)
      : _byName = {for (final c in columns) c.name: c};

  final String name;
  final int rowCount;
  final List<CdbColumn> columns;
  final Map<String, CdbColumn> _byName;

  /// Looks up a column.
  ///
  /// @param name Column name.
  /// @returns The column, or null if the table has none of that name.
  CdbColumn? column(String name) => _byName[name];

  /// Assembles one row from the columns.
  ///
  /// @param index Zero-based row index.
  /// @returns Column name to value.
  Map<String, Object> row(int index) =>
      {for (final c in columns) c.name: c.values[index]};

  /// All rows in file order.
  Iterable<Map<String, Object>> get rows => Iterable.generate(rowCount, row);
}

/// A Cyanide database (.cdb) from Pro Cycling Manager.
///
/// File layout: `FF FF FF FF`, unpacked size, packed size, then a zlib
/// stream. Unpacked it is a tree of chunks of the form
/// `AA AA AA AA | size | type | 0 | hasName | [name] | BB BB BB BB | body | CC CC CC CC`.
/// Lists of child chunks start with `DD DD DD DD | count`.
/// Data is stored column-wise: chunk 0x22 holds 4 bytes per row (integer,
/// float or length), chunk 0x23 the texts or list elements that go with it.
class CdbDatabase {
  CdbDatabase(this.tables) : _byName = {for (final t in tables) t.name: t};

  final List<CdbTable> tables;
  final Map<String, CdbTable> _byName;

  /// Looks up a table.
  ///
  /// @param name Table name, e.g. `DYN_team`.
  /// @returns The table, or null if it does not exist.
  CdbTable? table(String name) => _byName[name];

  /// Reads and parses a .cdb file.
  ///
  /// @param path File path.
  /// @returns The parsed database.
  static CdbDatabase readFile(String path) =>
      parse(File(path).readAsBytesSync());

  /// Parses the bytes of a .cdb file.
  ///
  /// @param file Complete file contents, still compressed.
  /// @returns The parsed database.
  /// @throws FormatException If the header is not that of a .cdb file.
  static CdbDatabase parse(Uint8List file) {
    final head = ByteData.sublistView(file);
    final Uint8List raw;
    if (head.getUint32(0, Endian.little) == 0xFFFFFFFF) {
      raw = Uint8List.fromList(zlib.decode(Uint8List.sublistView(file, 12)));
    } else {
      raw = file;
    }
    return _Reader(raw).read();
  }
}

const _begin = 0xAAAAAAAA;
const _bodyMark = 0xBBBBBBBB;
const _listMark = 0xDDDDDDDD;

// Chunk types
const _tTableList = 0x01;
const _tRowCount = 0x11;
const _tColumnList = 0x12;
const _tColumnType = 0x21;
const _tColumnData = 0x22;
const _tColumnBlob = 0x23;

/// A chunk of the unpacked tree with the position of its body.
class _Chunk {
  _Chunk(this.type, this.name, this.body, this.end);
  final int type;
  final String? name;

  /// First byte of the body.
  final int body;

  /// First byte after the chunk (including `CC CC CC CC`).
  final int end;
}

/// Walks the unpacked chunk tree and builds tables from it.
class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  int _u32(int o) => data.getUint32(o, Endian.little);

  /// Reads the chunk header at an offset.
  ///
  /// @param o Offset of the `AA AA AA AA` marker.
  /// @returns The chunk with name, type and extent.
  _Chunk _chunk(int o) {
    if (_u32(o) != _begin) {
      throw FormatException('Blockanfang erwartet', null, o);
    }
    final size = _u32(o + 4);
    final type = _u32(o + 8);
    var p = o + 20;
    String? name;
    if (_u32(o + 16) != 0) {
      final len = _u32(p);
      var end = p + 4;
      while (end < p + 4 + len && bytes[end] != 0) {
        end++;
      }
      name = latin1.decode(Uint8List.sublistView(bytes, p + 4, end));
      p += 4 + ((len + 3) & ~3);
    }
    if (_u32(p) != _bodyMark) {
      throw FormatException('Inhaltsmarke erwartet', null, p);
    }
    return _Chunk(type, name, p + 4, o + size);
  }

  /// Lists the direct children of a chunk.
  ///
  /// @param parent Chunk whose body starts with a `DD DD DD DD` list.
  /// @returns The child chunks in file order.
  List<_Chunk> _children(_Chunk parent) {
    var p = parent.body;
    if (_u32(p) == _listMark) p += 8;
    final out = <_Chunk>[];
    while (p < parent.end - 4 && _u32(p) == _begin) {
      final c = _chunk(p);
      out.add(c);
      p = c.end;
    }
    return out;
  }

  _Chunk _child(List<_Chunk> chunks, int type) =>
      chunks.firstWhere((c) => c.type == type);

  /// Reads the whole database.
  ///
  /// @returns All tables.
  CdbDatabase read() {
    final tableList = _child(_children(_chunk(0)), _tTableList);
    return CdbDatabase([for (final t in _children(tableList)) _table(t)]);
  }

  /// Builds a table from its chunk.
  ///
  /// @param t Table chunk.
  /// @returns The table with all columns.
  CdbTable _table(_Chunk t) {
    final parts = _children(t);
    final rows = _u32(_child(parts, _tRowCount).body);
    final columns = [
      for (final c in _children(_child(parts, _tColumnList))) _column(c, rows),
    ];
    return CdbTable(t.name!, rows, columns);
  }

  /// Builds a column from its chunk.
  ///
  /// @param c Column chunk.
  /// @param rows Number of rows of the table.
  /// @returns The column with one value per row.
  CdbColumn _column(_Chunk c, int rows) {
    final parts = _children(c);
    // The type chunk repeats the column name; the value sits right before the end marker.
    final type = CdbType.fromCode(_u32(_child(parts, _tColumnType).end - 8));
    final d = _child(parts, _tColumnData).body;
    final blobs = parts.where((p) => p.type == _tColumnBlob);
    // The blob starts with its own length.
    var p = blobs.isEmpty ? 0 : blobs.first.body + 4;

    final values = List<Object>.generate(rows, (i) {
      final o = d + i * 4;
      switch (type) {
        case CdbType.integer:
          return data.getInt32(o, Endian.little);
        case CdbType.float:
          return data.getFloat32(o, Endian.little);
        case CdbType.text:
          final len = _u32(o); // including the null byte
          if (len == 0) return '';
          final s = utf8.decode(
            Uint8List.sublistView(bytes, p, p + len - 1),
            allowMalformed: true,
          );
          p += len;
          return s;
        case CdbType.intList:
          final n = _u32(o);
          final list = [
            for (var k = 0; k < n; k++) data.getInt32(p + k * 4, Endian.little),
          ];
          p += n * 4;
          return list;
        case CdbType.floatList:
          final n = _u32(o);
          final list = [
            for (var k = 0; k < n; k++)
              data.getFloat32(p + k * 4, Endian.little).toDouble(),
          ];
          p += n * 4;
          return list;
      }
    }, growable: false);
    return CdbColumn(c.name!, type, values);
  }
}
