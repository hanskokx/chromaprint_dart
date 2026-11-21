/// A pure-Dart port of Chromaprint's audio fingerprints, including the one
/// AcoustID looks up.
///
/// ```dart
/// final chromaprint = Chromaprint();
/// final fingerprint = chromaprint.fingerprint(
///   pcm,
///   sampleRate: 44100,
///   channels: 2,
/// );
/// print(fingerprint); // the string fpcalc prints
/// ```
library;

export "src/algorithm.dart";
export "src/chromaprint.dart";
export "src/decompress.dart" show DecodedFingerprint;
export "src/fingerprint.dart";
export "src/options.dart";
