import "dart:typed_data";

import "algorithm.dart";
import "compress.dart";
import "fingerprint.dart";
import "fingerprinter.dart";
import "options.dart";

/// Computes Chromaprint fingerprints from 16-bit PCM audio.
class Chromaprint {
  /// Creates a fingerprinter with the given [algorithm] and [options].
  Chromaprint({
    this.algorithm = ChromaprintAlgorithm.test2,
    ChromaprintOptions? options,
  }) : options = options ?? ChromaprintOptions();

  /// The algorithm used to fingerprint audio.
  final ChromaprintAlgorithm algorithm;

  /// The options used to fingerprint audio.
  final ChromaprintOptions options;

  /// Fingerprints interleaved 16-bit [audio].
  ///
  /// Like `fpcalc`, only the first [maxDuration] is used (120 s by default);
  /// pass null to use all of it.
  Fingerprint fingerprint(
    Int16List audio, {
    required int sampleRate,
    int channels = 1,
    Duration? maxDuration = const Duration(seconds: 120),
  }) {
    final Uint32List raw = rawFingerprint(
      audio,
      sampleRate: sampleRate,
      channels: channels,
      maxDuration: maxDuration,
      algorithm: algorithm,
      silenceThreshold: algorithm == ChromaprintAlgorithm.test4
          ? options.silenceThreshold
          : null,
    );
    return Fingerprint(encodeFingerprint(raw, algorithm: algorithm));
  }
}
