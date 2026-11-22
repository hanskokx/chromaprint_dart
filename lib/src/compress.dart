// A port of Chromaprint's fingerprint compressor and base64 encoder
// (https://github.com/acoustid/chromaprint), Copyright (C) 2010-2016
// Lukas Lalinsky, MIT licensed; see THIRD_PARTY_NOTICES.md.

import "dart:typed_data";

import "algorithm.dart";

const int _normalBits = 3;
const int _maxNormalValue = (1 << _normalBits) - 1;

/// Compresses a raw fingerprint the way `chromaprint_get_fingerprint` does
/// and encodes it as URL-safe base64 without padding: the form `fpcalc`
/// prints and AcoustID accepts.
String encodeFingerprint(
  List<int> raw, {
  ChromaprintAlgorithm algorithm = ChromaprintAlgorithm.test2,
}) => base64UrlNoPadding(compressFingerprint(raw, algorithm: algorithm));

/// The compressed bytes, before base64.
Uint8List compressFingerprint(
  List<int> raw, {
  ChromaprintAlgorithm algorithm = ChromaprintAlgorithm.test2,
}) {
  final List<int> normal = [];
  final List<int> exceptional = [];
  void add(int x) {
    int bit = 1;
    int lastBit = 0;
    while (x != 0) {
      if (x & 1 != 0) {
        final int value = bit - lastBit;
        if (value >= _maxNormalValue) {
          normal.add(_maxNormalValue);
          exceptional.add(value - _maxNormalValue);
        } else {
          normal.add(value);
        }
        lastBit = bit;
      }
      x >>= 1;
      bit++;
    }
    normal.add(0);
  }

  for (int i = 0; i < raw.length; i++) {
    add(i == 0 ? raw[0] : (raw[i] ^ raw[i - 1]) & 0xffffffff);
  }
  final int size = raw.length;
  return Uint8List.fromList([
    algorithm.value & 255,
    (size >> 16) & 255,
    (size >> 8) & 255,
    size & 255,
    ..._pack(normal, 3),
    ..._pack(exceptional, 5),
  ]);
}

/// Packs [values] [bits] bits each, least significant bit first.
List<int> _pack(List<int> values, int bits) {
  final Uint8List out = Uint8List((values.length * bits + 7) ~/ 8);
  int pos = 0;
  for (final int value in values) {
    for (int b = 0; b < bits; b++, pos++) {
      if ((value >> b) & 1 != 0) out[pos >> 3] |= 1 << (pos & 7);
    }
  }
  return out;
}

const _alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// URL-safe base64 with no `=` padding, as Chromaprint writes it.
String base64UrlNoPadding(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    final int n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out
      ..write(_alphabet[(n >> 18) & 63])
      ..write(_alphabet[(n >> 12) & 63])
      ..write(_alphabet[(n >> 6) & 63])
      ..write(_alphabet[n & 63]);
  }
  final int rest = bytes.length - i;
  if (rest == 1) {
    final int n = bytes[i] << 16;
    out
      ..write(_alphabet[(n >> 18) & 63])
      ..write(_alphabet[(n >> 12) & 63]);
  } else if (rest == 2) {
    final int n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out
      ..write(_alphabet[(n >> 18) & 63])
      ..write(_alphabet[(n >> 12) & 63])
      ..write(_alphabet[(n >> 6) & 63]);
  }
  return out.toString();
}
