/// Settings that change how a `Chromaprint` instance fingerprints audio.
class ChromaprintOptions {
  /// Creates options with Chromaprint's default leading-silence threshold.
  ///
  /// Throws an [ArgumentError] if [silenceThreshold] is outside 0–32767.
  ChromaprintOptions({this.silenceThreshold = 50}) {
    if (silenceThreshold < 0 || silenceThreshold > 32767) {
      throw ArgumentError.value(
        silenceThreshold,
        "silenceThreshold",
        "must be between 0 and 32767",
      );
    }
  }

  /// The leading-silence threshold used by `ChromaprintAlgorithm.test4`.
  ///
  /// Like Chromaprint's `silence_threshold` option, this has no effect on the
  /// other algorithms.
  final int silenceThreshold;
}
