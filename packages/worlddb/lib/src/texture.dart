import 'dart:io';
import 'dart:typed_data';

/// A decoded texture: width, height and pixels as RGBA bytes.
class Texture {
  Texture(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  /// Reads the largest mip of a cooked Unreal `Texture2D` from its `.uexp`
  /// file. Only uncompressed `PF_B8G8R8A8` textures are supported, which is
  /// what the WorldDB uses for mini jerseys and race logos.
  ///
  /// The pixel data is followed by its dimensions (width, height, depth 1),
  /// 12 zero bytes and the package tag. That trailer is used to find the
  /// data, which avoids parsing the property block in front of it.
  ///
  /// @param uexp Contents of the `.uexp` file.
  /// @returns The texture, or null if the file has another layout or format.
  static Texture? fromUexp(Uint8List uexp) {
    final b = ByteData.sublistView(uexp);
    if (!String.fromCharCodes(uexp.take(512)).contains('PF_B8G8R8A8')) {
      return null;
    }
    // Trailer: width, height, 1, three zero ints, package tag.
    final end = uexp.length - 28;
    if (end < 0) return null;
    final w = b.getUint32(end, Endian.little);
    final h = b.getUint32(end + 4, Endian.little);
    if (b.getUint32(end + 8, Endian.little) != 1 ||
        w == 0 ||
        h == 0 ||
        w > 4096 ||
        h > 4096) {
      return null;
    }
    final start = end - w * h * 4;
    if (start < 0) return null;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final p = start + i * 4;
      rgba[i * 4] = uexp[p + 2];
      rgba[i * 4 + 1] = uexp[p + 1];
      rgba[i * 4 + 2] = uexp[p];
      rgba[i * 4 + 3] = uexp[p + 3];
    }
    return Texture(w, h, rgba);
  }

  /// Halves the texture [times] times by averaging 2×2 pixels.
  ///
  /// @param times Number of halvings.
  /// @returns The smaller texture.
  Texture shrink(int times) {
    var t = this;
    for (var k = 0; k < times && t.width > 1 && t.height > 1; k++) {
      final w = t.width ~/ 2, h = t.height ~/ 2;
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < 4; c++) {
            final a = (y * 2 * t.width + x * 2) * 4 + c;
            final below = a + t.width * 4;
            out[(y * w + x) * 4 + c] = (t.rgba[a] +
                    t.rgba[a + 4] +
                    t.rgba[below] +
                    t.rgba[below + 4]) ~/
                4;
          }
        }
      }
      t = Texture(w, h, out);
    }
    return t;
  }

  /// @returns The texture as the bytes of a PNG file.
  Uint8List toPng() {
    // Each scanline is prefixed with filter type 0 (none).
    final raw = Uint8List(height * (width * 4 + 1));
    for (var y = 0; y < height; y++) {
      raw.setRange(y * (width * 4 + 1) + 1, (y + 1) * (width * 4 + 1), rgba,
          y * width * 4);
    }
    final out = BytesBuilder()
      ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    void chunk(String type, List<int> data) {
      final body = [...type.codeUnits, ...data];
      final head = ByteData(4)..setUint32(0, data.length);
      final crc = ByteData(4)..setUint32(0, _crc32(body));
      out
        ..add(head.buffer.asUint8List())
        ..add(body)
        ..add(crc.buffer.asUint8List());
    }

    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6); // colour type RGBA
    chunk('IHDR', header.buffer.asUint8List());
    chunk('IDAT', zlib.encode(raw));
    chunk('IEND', const []);
    return out.takeBytes();
  }

  static final _table = [
    for (var n = 0; n < 256; n++)
      () {
        var c = n;
        for (var k = 0; k < 8; k++) {
          c = c & 1 != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
        }
        return c;
      }(),
  ];

  /// @param bytes Data of a PNG chunk including its type.
  /// @returns The CRC-32 checksum PNG requires.
  static int _crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
