import 'dart:typed_data';

/// FNV-1a 64-bit. Dart int là 64-bit wrap-around trên VM nên nhân tràn số
/// cho kết quả đúng theo modulo 2^64.
int fnv1a64(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash ^= b;
    hash *= 0x100000001b3;
  }
  return hash;
}
