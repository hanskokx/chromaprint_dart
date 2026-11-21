import "dart:typed_data";

import "decompress.dart";
import "hash.dart";
import "image.dart";

/// An audio fingerprint, in the form `fpcalc` prints and AcoustID accepts.
class Fingerprint {
  /// Creates a fingerprint from its encoded form.
  ///
  /// Decodes immediately, throwing a [FormatException] if [encoded] isn't a
  /// valid fingerprint.
  Fingerprint(String encoded)
    : _encoded = encoded,
      _decoded = decodeFingerprint(encoded);

  final String _encoded;
  final DecodedFingerprint _decoded;

  /// The 32-bit sub-fingerprints, one per frame of audio.
  ///
  /// The list is unmodifiable so the other getters stay consistent.
  List<int> get raw => List<int>.unmodifiable(_decoded.raw);

  /// The 32-bit SimHash of this fingerprint.
  int get hash => fingerprintHash(_decoded.raw);

  /// A PNG drawn the way AcoustID shows fingerprints, with one column per
  /// sub-fingerprint and one row per bit.
  Uint8List get png => fingerprintPng(_decoded.raw);

  /// The fingerprint's decoded form, including its algorithm.
  DecodedFingerprint get decode => _decoded;

  @override
  String toString() => _encoded;
}
