import 'dart:ffi';
import 'dart:typed_data';

import 'pak.dart';

typedef _DecompressNative = Int32 Function(
    Pointer<Uint8> src,
    Int32 srcLen,
    Pointer<Uint8> dst,
    Size dstLen,
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Size,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Size,
    Int32);
typedef _Decompress = int Function(
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    int,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    int);

/// Decompressor for Oodle data (Kraken and others) through the DLL built
/// from the open-source ooz (`native/build/ooz.dll`, see `native/build_ooz.sh`).
class Ooz {
  /// Loads the DLL.
  ///
  /// @param dllPath Path of `ooz.dll`.
  Ooz(String dllPath) {
    final crt = DynamicLibrary.open('msvcrt.dll');
    _malloc = crt.lookupFunction<Pointer<Uint8> Function(Size),
        Pointer<Uint8> Function(int)>('malloc');
    _free = crt.lookupFunction<Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)>('free');
    _decompress = DynamicLibrary.open(dllPath)
        .lookupFunction<_DecompressNative, _Decompress>('Ooz_Decompress');
  }

  late final Pointer<Uint8> Function(int) _malloc;
  late final void Function(Pointer<Uint8>) _free;
  late final _Decompress _decompress;

  // ooz writes up to 64 bytes past the end of the target buffer.
  static const _slack = 64;

  /// Decompresses one block. Fits as a [BlockDecoder] for [PakFile.read].
  ///
  /// @param packed Compressed bytes.
  /// @param rawSize Expected size after decompression.
  /// @returns The decompressed bytes.
  /// @throws FormatException If ooz reports a different size.
  Uint8List decode(Uint8List packed, int rawSize) {
    final src = _malloc(packed.length + _slack);
    final dst = _malloc(rawSize + _slack);
    try {
      src.asTypedList(packed.length).setAll(0, packed);
      final n = _decompress(src, packed.length, dst, rawSize, 0, 0, 0, nullptr,
          0, nullptr, nullptr, nullptr, 0, 0);
      if (n != rawSize) {
        throw FormatException(
            'Oodle block cannot be unpacked (returned $n instead of $rawSize)');
      }
      return Uint8List.fromList(dst.asTypedList(rawSize));
    } finally {
      _free(src);
      _free(dst);
    }
  }
}
