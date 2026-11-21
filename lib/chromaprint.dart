/// A pure-Dart port of Chromaprint's default audio fingerprint, the one
/// AcoustID looks up.
///
/// ```dart
/// final raw = rawFingerprint(pcm, sampleRate: 44100, channels: 2);
/// final fingerprint = encodeFingerprint(raw); // what `fpcalc` prints
/// ```
library;

export "src/compress.dart";
export "src/decompress.dart";
export "src/fingerprint.dart"
    show downmix, fingerprintSampleRate, rawFingerprint;
export "src/image.dart";
export "src/resampler.dart" show resample;
