# chromaprint_dart

A pure-Dart port of [Chromaprint](https://github.com/acoustid/chromaprint)'s audio fingerprints. No native code or external program. The default algorithm is `test2`, the one AcoustID looks up.

```dart
final chromaprint = Chromaprint();
final fingerprint = chromaprint.fingerprint(
  pcm,
  sampleRate: 44100,
  channels: 2,
);

print(fingerprint);         // the string fpcalc prints
fingerprint.raw;            // the 32-bit sub-fingerprints (unmodifiable)
fingerprint.hash;           // the 32-bit SimHash of the fingerprint
fingerprint.png;          // PNG, drawn the way AcoustID shows it
fingerprint.decode;         // the algorithm and raw values

// Rehydrate a fingerprint saved earlier.
final restored = Fingerprint(savedString);
```

Input is interleaved 16-bit PCM. As with `fpcalc`, only the first 120 s are used; pass `maxDuration` to change that.

## Algorithms and options

All five algorithms from the C library are available through `ChromaprintAlgorithm`:

| Algorithm | What changes                          |
| --------- | ------------------------------------- |
| `test1`   | The original classifier set           |
| `test2`   | Default, and the one AcoustID accepts |
| `test3`   | No overlap between frames             |
| `test4`   | `test2` plus leading-silence removal  |
| `test5`   | Twice the frame rate                  |

Options are set when the instance is created:

```dart
final custom = Chromaprint(
  algorithm: ChromaprintAlgorithm.test4,
  options: ChromaprintOptions(silenceThreshold: 40),
);
```

`silenceThreshold` (0–32767, default 50) is Chromaprint's `silence_threshold` option. Like the C library, it only affects `test4`; other algorithms ignore it. Only `test2` fingerprints are meant for AcoustID.

## Example

Run the self-contained example, which synthesizes a tone and writes a PNG:

```sh
dart run example/main.dart [output.png]
```

## How exact it is

`dart test` compares the output with fpcalc 1.6.2's, recorded in `test/fixtures/fpcalc.json` by `dart run tool/record_fixtures.dart`, for generated signals: mono and stereo, at 11025, 22050, 44100 and 48000 Hz, longer than 120 s, too short to fingerprint, and with leading silence. All five algorithms are checked bit for bit, including their raw values, encoded strings and hashes.

Known gap: for more than two channels, `fpcalc` has FFmpeg's swresample mix down with surround weights, while libchromaprint and this port average the channels. Those fingerprints differ (17% of bits on the test signal).

Decoding audio files is left to the caller, so files fingerprint exactly only if the decoder gives the same PCM as FFmpeg's. That's always true for 16-bit WAV. Lossy decoders can round differently, which flips a few bits, and AcoustID tolerates that.

## License

LGPL-2.1; see `LICENSE`. The resampler ports LGPL-2.1-or-later FFmpeg code bundled with Chromaprint. The rest ports Chromaprint's own MIT-licensed code, and its notice is kept in `LICENSE`.
