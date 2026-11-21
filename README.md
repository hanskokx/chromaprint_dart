# chromaprint_dart

A pure-Dart port of [Chromaprint](https://github.com/acoustid/chromaprint)'s default fingerprint (algorithm 2), the one AcoustID looks up.

```dart
final raw = rawFingerprint(pcm, sampleRate: 44100, channels: 2);
final fingerprint = encodeFingerprint(raw); // the string fpcalc prints

final decoded = decodeFingerprint(fingerprint); // back to the raw values
final png = fingerprintPng(decoded.raw); // drawn the way AcoustID shows it
```

Input is interleaved 16-bit PCM. As with `fpcalc`, only the first 120 s are used.

## How exact it is

`dart test` compares the output with fpcalc 1.6.2's, recorded in `test/fixtures/fpcalc.json` by `dart run tool/record_fixtures.dart`, for generated signals: mono and stereo, at 11025, 22050, 44100 and 48000 Hz, longer than 120 s, and too short to fingerprint. The raw and encoded fingerprints match bit for bit.

Known gap: for more than two channels, `fpcalc` has FFmpeg's swresample mix down with surround weights, while libchromaprint and this port average the channels. Those fingerprints differ (17% of bits on the test signal).

Decoding is left to the caller, so files fingerprint exactly only if the decoder gives the same PCM as FFmpeg's. That's always true for 16-bit WAV. Lossy decoders can round differently, which flips a few bits, and AcoustID tolerates that.

## License

LGPL-2.1; see `LICENSE`. The resampler ports LGPL-2.1-or-later FFmpeg code bundled with Chromaprint. The rest ports Chromaprint's own MIT-licensed code, and its notice is kept in `LICENSE`.
