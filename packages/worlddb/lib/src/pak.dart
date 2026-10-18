import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Entry in the directory of an Unreal pak file.
class PakEntry {
  PakEntry(this.path, this.offset, this.size, this.compressedSize,
      this.compression, this.encrypted, this.blockSizes);

  /// Path relative to the mount point, e.g. `Content/CM_Stages/top_tdf_01_2026.cds`.
  final String path;

  /// Position of the entry in the pak file (points at the entry header).
  final int offset;
  final int size;
  final int compressedSize;

  /// Name of the method (`Oodle`, `Zlib`), or null for uncompressed files.
  final String? compression;
  final bool encrypted;

  /// Packed size of each block.
  final List<int> blockSizes;
}

/// Decompresses one block: packed bytes and expected size in, raw data out.
typedef BlockDecoder = Uint8List Function(Uint8List packed, int rawSize);

/// Reads the directory of an Unreal Engine pak file (version 11, index not
/// encrypted) and extracts single files.
///
/// Layout: the file ends with a 221-byte footer holding the position of the
/// index and the names of the compression methods. The index contains
/// bit-packed entries and points at a directory of all paths.
class PakFile {
  PakFile._(this._file, this.mountPoint, this.entries);

  final RandomAccessFile _file;
  final String mountPoint;
  final List<PakEntry> entries;

  static const _footerSize = 221;
  static const _magic = 0x5A6F12E1;

  /// Opens a pak file and reads its directory.
  ///
  /// @param path File path.
  /// @returns The open file; call [close] when done.
  /// @throws FormatException If the footer is not that of a version 11 pak.
  static PakFile open(String path) {
    final file = File(path).openSync();
    final length = file.lengthSync();
    Uint8List read(int offset, int size) {
      file.setPositionSync(offset);
      return file.readSync(size);
    }

    final footer =
        ByteData.sublistView(read(length - _footerSize, _footerSize));
    if (footer.getUint32(17, Endian.little) != _magic) {
      throw const FormatException('Not an Unreal pak (magic number missing)');
    }
    final version = footer.getUint32(21, Endian.little);
    if (version != 11) {
      throw FormatException('Pak version $version is not supported');
    }
    if (footer.getUint8(16) != 0) {
      throw const FormatException('Encrypted pak index');
    }
    final methods = [
      for (var i = 0; i < 5; i++)
        _cString(
            footer.buffer.asUint8List(footer.offsetInBytes + 61 + i * 32, 32)),
    ];

    final index = _Bytes(read(
      footer.getUint64(25, Endian.little),
      footer.getUint64(33, Endian.little),
    ));
    final mountPoint = index.fstring();
    index.skip(4 + 8); // entry count, seed of the path hashes
    if (index.u32() != 0) index.skip(8 + 8 + 20); // path hash index
    if (index.u32() == 0) {
      throw const FormatException('Pak without an index');
    }
    final dirOffset = index.u64();
    final dirSize = index.u64();
    index.skip(20);
    final encodedSize = index.u32();
    final encoded = _Bytes(index.take(encodedSize));

    final dir = _Bytes(read(dirOffset, dirSize));
    final entries = <PakEntry>[];
    for (var d = dir.u32(); d > 0; d--) {
      final folder = dir.fstring();
      for (var f = dir.u32(); f > 0; f--) {
        final name = dir.fstring();
        final at = dir.i32();
        if (at < 0)
          continue; // entries that are not bit-packed do not occur here
        final path = '$folder$name';
        entries.add(_decodeEntry(encoded, at,
            path.startsWith('/') ? path.substring(1) : path, methods));
      }
    }
    return PakFile._(file, mountPoint, entries);
  }

  /// Decodes one bit-packed directory entry.
  ///
  /// @param encoded Buffer with all encoded entries.
  /// @param at Offset of this entry in the buffer.
  /// @param path Path the entry belongs to.
  /// @param methods Compression method names from the footer.
  /// @returns The decoded entry.
  static PakEntry _decodeEntry(
      _Bytes encoded, int at, String path, List<String> methods) {
    encoded.pos = at;
    final flags = encoded.u32();
    if (flags & 0x3f == 0x3f) encoded.skip(4); // block size written out in full
    final blockCount = (flags >> 6) & 0xffff;
    final encrypted = (flags >> 22) & 1 == 1;
    final method = (flags >> 23) & 0x3f;
    int sized(int bit) =>
        (flags >> bit) & 1 == 1 ? encoded.u32() : encoded.u64();
    final offset = sized(31);
    final size = sized(30);
    final compressedSize = method == 0 ? size : sized(29);
    final blocks = <int>[];
    if (blockCount == 1 && !encrypted) {
      blocks.add(compressedSize);
    } else {
      for (var i = 0; i < blockCount; i++) {
        blocks.add(encoded.u32());
      }
    }
    return PakEntry(path, offset, size, compressedSize,
        method == 0 ? null : methods[method - 1], encrypted, blocks);
  }

  /// Reads one file.
  ///
  /// @param e Directory entry of the file.
  /// @param decoder Needed for compressed entries.
  /// @returns The file contents.
  /// @throws StateError If the entry is compressed and no decoder was given.
  Uint8List read(PakEntry e, {BlockDecoder? decoder}) {
    if (e.encrypted) {
      throw UnsupportedError('${e.path} is encrypted');
    }
    // The data is preceded by the entry header: 3 × 8 bytes of position and
    // sizes, method (4), checksum (20), with compression a block list (4 + 16
    // per block), then the encryption flag (1) and the block size (4).
    final compressed = e.compression != null;
    var p = e.offset + 53 + (compressed ? 4 + 16 * e.blockSizes.length : 0);
    if (!compressed) {
      _file.setPositionSync(p);
      return _file.readSync(e.size);
    }
    if (decoder == null) {
      throw UnsupportedError(
          '${e.path} is compressed with ${e.compression}, and no decompressor was given');
    }
    final out = BytesBuilder(copy: false);
    // Uncompressed size of a full block: the last field of the entry header.
    _file.setPositionSync(p - 4);
    final head = _file.readSync(4);
    final declared = head[0] | head[1] << 8 | head[2] << 16 | head[3] << 24;
    final blockRaw = declared > 0 && declared * e.blockSizes.length >= e.size
        ? declared
        : (e.size / e.blockSizes.length).ceil();
    var left = e.size;
    for (final packedSize in e.blockSizes) {
      _file.setPositionSync(p);
      final raw = left < blockRaw ? left : blockRaw;
      out.add(decoder(_file.readSync(packedSize), raw));
      p += packedSize;
      left -= raw;
    }
    return out.takeBytes();
  }

  /// Closes the underlying file.
  void close() => _file.closeSync();

  /// Reads a null-terminated ASCII string.
  ///
  /// @param bytes Buffer starting at the string.
  /// @returns The text up to the first null byte.
  static String _cString(Uint8List bytes) {
    final end = bytes.indexOf(0);
    return latin1.decode(end < 0 ? bytes : bytes.sublist(0, end));
  }
}

/// Little-endian reader over a byte buffer.
class _Bytes {
  _Bytes(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  int pos = 0;

  /// Advances the read position.
  ///
  /// @param n Number of bytes to skip.
  void skip(int n) => pos += n;

  /// @returns The next unsigned 32-bit integer.
  int u32() {
    final v = data.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }

  /// @returns The next signed 32-bit integer.
  int i32() {
    final v = data.getInt32(pos, Endian.little);
    pos += 4;
    return v;
  }

  /// @returns The next unsigned 64-bit integer.
  int u64() {
    final v = data.getUint64(pos, Endian.little);
    pos += 8;
    return v;
  }

  /// Reads raw bytes.
  ///
  /// @param n Number of bytes.
  /// @returns A view of the next [n] bytes.
  Uint8List take(int n) {
    final v = Uint8List.sublistView(bytes, pos, pos + n);
    pos += n;
    return v;
  }

  /// Reads an Unreal string: length including the null byte; a negative length
  /// means UTF-16.
  ///
  /// @returns The decoded text.
  String fstring() {
    final len = i32();
    if (len < 0) {
      final units = take(-len * 2);
      return String.fromCharCodes(
          Uint16List.sublistView(Uint8List.fromList(units), 0, -len - 1));
    }
    final s = latin1.decode(Uint8List.sublistView(bytes, pos, pos + len - 1));
    pos += len;
    return s;
  }
}
