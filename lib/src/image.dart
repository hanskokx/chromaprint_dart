import "dart:typed_data";

/// A PNG of [raw] (a fingerprint's 32-bit sub-fingerprints) the way AcoustID
/// draws one on acoustid.org: a column per sub-fingerprint and a row per
/// bit, bit 0 at the top, set bits near-black (#1a1a1a) on white, one pixel
/// each. Show it scaled without smoothing.
///
/// It's a 1-bit palette PNG, so a 2-minute fingerprint is about 4 KB.
/// Throws an [ArgumentError] if [raw] is empty, since a PNG can't be 0
/// pixels wide.
Uint8List fingerprintPng(List<int> raw) {
  if (raw.isEmpty) {
    throw ArgumentError.value(raw, "raw", "A fingerprint image needs a column");
  }
  final int width = raw.length;
  const int height = 32;
  final int stride = (width + 7) >> 3;
  // Each row: filter type 0, then palette indices, leftmost in the high
  // bit. Index 1 is a set bit.
  final Uint8List pixels = Uint8List((stride + 1) * height);
  for (int bit = 0; bit < height; bit++) {
    final int start = bit * (stride + 1) + 1;
    for (int x = 0; x < width; x++) {
      if ((raw[x] >> bit) & 1 != 0) pixels[start + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  final ByteData header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 1) // bit depth
    ..setUint8(9, 3) // palette
    ..setUint8(10, 0) // deflate
    ..setUint8(11, 0) // adaptive filtering
    ..setUint8(12, 0); // no interlace
  return (BytesBuilder(copy: false)
        ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ..add(_chunk("IHDR", header.buffer.asUint8List()))
        ..add(_chunk("PLTE", Uint8List.fromList(_palette)))
        ..add(_chunk("IDAT", _zlibStored(pixels)))
        ..add(_chunk("IEND", Uint8List(0))))
      .takeBytes();
}

/// White for a clear bit, AcoustID's #1a1a1a for a set one.
const List<int> _palette = [0xff, 0xff, 0xff, 0x1a, 0x1a, 0x1a];

Uint8List _chunk(String type, Uint8List data) {
  final ByteData out = ByteData(12 + data.length)..setUint32(0, data.length);
  final Uint8List bytes = out.buffer.asUint8List();
  bytes
    ..setAll(4, type.codeUnits)
    ..setAll(8, data);
  out.setUint32(8 + data.length, _crc32(bytes, 4, 8 + data.length));
  return bytes;
}

/// A zlib stream of uncompressed deflate blocks: no compressor needed, and
/// the 1-bit image is small anyway.
Uint8List _zlibStored(Uint8List data) {
  final BytesBuilder out = BytesBuilder(copy: false)..add(const [0x78, 0x01]);
  int offset = 0;
  do {
    final int length = data.length - offset > 0xffff
        ? 0xffff
        : data.length - offset;
    final bool last = offset + length == data.length;
    out
      ..addByte(last ? 1 : 0)
      ..add([length & 0xff, length >> 8, ~length & 0xff, (~length >> 8) & 0xff])
      ..add(Uint8List.sublistView(data, offset, offset + length));
    offset += length;
  } while (offset < data.length);
  int a = 1;
  int b = 0;
  for (final int byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final int adler = (b << 16) | a;
  out.add([
    adler >> 24 & 0xff,
    adler >> 16 & 0xff,
    adler >> 8 & 0xff,
    adler & 0xff,
  ]);
  return out.takeBytes();
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes, int start, int end) {
  int crc = 0xffffffff;
  for (int i = start; i < end; i++) {
    crc = _crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}
