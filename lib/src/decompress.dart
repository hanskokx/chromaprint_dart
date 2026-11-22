// A port of Chromaprint's fingerprint decompressor and base64 decoder
// (https://github.com/acoustid/chromaprint), Copyright (C) 2010-2016
// Lukas Lalinsky, MIT licensed; see THIRD_PARTY_NOTICES.md.

import "dart:typed_data";

import "algorithm.dart";

/// A fingerprint read back from its encoded form.
class DecodedFingerprint {
  const DecodedFingerprint(this.algorithm, this.raw);

  /// The algorithm that produced the fingerprint.
  final ChromaprintAlgorithm algorithm;

  /// The 32-bit sub-fingerprints, one per 1365 samples at 11025 Hz.
  final Uint32List raw;
}

/// Decodes a fingerprint as `fpcalc` prints it (URL-safe base64, compressed)
/// back to its sub-fingerprints: the inverse of `encodeFingerprint`.
///
/// Throws a [FormatException] if [encoded] isn't a valid fingerprint.
DecodedFingerprint decodeFingerprint(String encoded) =>
    decompressFingerprint(base64UrlNoPaddingDecode(encoded));

/// Decompresses the bytes `compressFingerprint` produces.
DecodedFingerprint decompressFingerprint(Uint8List bytes) {
  if (bytes.length < 4) {
    throw const FormatException("A fingerprint has a 4-byte header");
  }
  final int algorithm = bytes[0];
  final int size = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  final Uint8List body = Uint8List.sublistView(bytes, 4);

  // The 3-bit values: bit-position deltas, each sub-fingerprint ended by 0.
  final List<int> normal = [];
  int pos = 0;
  int ended = 0;
  while (ended < size) {
    if (pos + 3 > body.length * 8) {
      throw const FormatException("The fingerprint is cut short");
    }
    final int value = _bits(body, pos, 3);
    pos += 3;
    normal.add(value);
    if (value == 0) ended++;
  }

  // The 5-bit extensions of each 7, from the next whole byte.
  int exceptionalPos = ((pos + 7) >> 3) * 8;
  final Uint32List raw = Uint32List(size);
  int index = 0;
  int x = 0;
  int lastBit = 0;
  for (int value in normal) {
    if (value == 0) {
      raw[index] = index == 0 ? x : raw[index - 1] ^ x;
      index++;
      x = 0;
      lastBit = 0;
      continue;
    }
    if (value == 7) {
      if (exceptionalPos + 5 > body.length * 8) {
        throw const FormatException("The fingerprint is cut short");
      }
      value += _bits(body, exceptionalPos, 5);
      exceptionalPos += 5;
    }
    lastBit += value;
    if (lastBit > 32) {
      throw const FormatException("A sub-fingerprint has more than 32 bits");
    }
    x |= 1 << (lastBit - 1);
  }
  return DecodedFingerprint(ChromaprintAlgorithm.fromValue(algorithm), raw);
}

int _bits(Uint8List bytes, int pos, int count) {
  int value = 0;
  for (int b = 0; b < count; b++, pos++) {
    if ((bytes[pos >> 3] >> (pos & 7)) & 1 != 0) value |= 1 << b;
  }
  return value;
}

const _alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// Decodes URL-safe base64 with no `=` padding, as Chromaprint writes it.
Uint8List base64UrlNoPaddingDecode(String text) {
  final BytesBuilder out = BytesBuilder(copy: false);
  int acc = 0;
  int bits = 0;
  for (final int unit in text.codeUnits) {
    final int value = _alphabet.indexOf(String.fromCharCode(unit));
    if (value < 0) {
      throw FormatException("Not URL-safe base64", text);
    }
    acc = ((acc << 6) | value) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((acc >> bits) & 255);
    }
  }
  return out.takeBytes();
}
