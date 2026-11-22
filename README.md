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
fingerprint.png;            // PNG, drawn the way AcoustID shows it
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

## Verification Mechanism

`test/chromaprint_test.dart` fingerprints deterministic synthetic PCM from `test/signal.dart` and compares it with values recorded from Chromaprint's own `fpcalc` 1.6.2 in `test/fixtures/fpcalc.json`. Re-run `dart run tool/record_fixtures.dart` to regenerate that file: it writes each signal as a WAV, runs `fpcalc` for the raw and encoded fingerprints, and records the native hash.

The cases cover mono and stereo at 11025, 22050, 44100 and 48000 Hz, five-channel input, audio longer than `fpcalc`'s 120-second limit, audio too short to fingerprint, and leading silence. For every case and all five `ChromaprintAlgorithm` values, the tests compare raw sub-fingerprints, encoded strings, and hashes bit for bit.

Separate tests cover compression and decompression, URL-safe unpadded base64, algorithm headers, exceptional bit gaps, rehydration from `Fingerprint(String)`, unmodifiable raw values, hash ties, PNG dimensions, palette, bit order, channel downmix, sample-rate validation, resampling, leading-silence removal, and option/algorithm wiring.

`dart run example/main.dart` was checked too: it writes a valid 59×32 1-bit palette PNG and round-trips its encoded fingerprint. The SimHash implementation was checked against native `chromaprint_hash_fingerprint` on random 32-bit fingerprints.

### Known gaps

For more than two channels, `fpcalc` has FFmpeg's swresample mix down with surround weights, while libchromaprint and this port average the channels. Those fingerprints differ by 17% of bits on the test signal.

Decoding audio files is left to the caller, so files fingerprint exactly only if the decoder gives the same PCM as FFmpeg's. That is always true for 16-bit WAV. Lossy decoders can round differently, which flips a few bits, and AcoustID tolerates that.

During development, the two-minute “Lights” MP3 and AcoustID's `canvas.png` were also compared manually. With the same PCM, this port matched `fpcalc` exactly. Running `fpcalc` directly on the MP3 differed by 10 of 30336 bits (0.033%) because the ffmpeg CLI decodes that MP3 slightly differently from `fpcalc`'s decoder; the canvas differed from `fpcalc` by 384 bits (1.27%) because it was made from a different encoding. Those large fixtures and the one-off test are intentionally not kept in the repository.

## License

LGPL-2.1; see `LICENSE`. Upstream notices for the FFmpeg resampler and Chromaprint's MIT-licensed code are in `THIRD_PARTY_NOTICES.md`.
