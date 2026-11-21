import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:chromaprint_dart/chromaprint.dart";
import "package:chromaprint_dart/src/compress.dart" as codec;
import "package:chromaprint_dart/src/decompress.dart" as decoder;
import "package:chromaprint_dart/src/fingerprinter.dart" as fingerprinter;
import "package:chromaprint_dart/src/hash.dart" as hashing;
import "package:chromaprint_dart/src/resampler.dart" as resampler;
import "package:test/test.dart";

import "cases.dart";
import "signal.dart";

/// Reference output from Chromaprint's own fpcalc for every algorithm,
/// recorded in test/fixtures/fpcalc.json by tool/record_fixtures.dart.
final Map<String, Object?> reference =
    jsonDecode(File("test/fixtures/fpcalc.json").readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> expectedFor(String name, ChromaprintAlgorithm algorithm) {
  final Map<String, Object?> cases =
      reference["cases"]! as Map<String, Object?>;
  final Map<String, Object?> byAlgorithm = cases[name]! as Map<String, Object?>;
  return byAlgorithm["${algorithm.value}"]! as Map<String, Object?>;
}

/// The share of bits that differ, over the longer of the two.
double bitErrorRate(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  var errors = ((a.length - b.length).abs()) * 32;
  for (var i = 0; i < n; i++) {
    var x = (a[i] ^ b[i]) & 0xffffffff;
    while (x != 0) {
      errors += x & 1;
      x >>= 1;
    }
  }
  final total = (a.length > b.length ? a.length : b.length) * 32;
  return total == 0 ? 0 : errors / total;
}

/// fpcalc has FFmpeg's swresample mix more than two channels down with
/// surround weights; libchromaprint, and this port, average them. On the
/// 5-channel test signal 17% of the bits differ.
const surroundGap =
    "Known gap: swresample's surround downmix isn't emulated yet.";

void main() {
  group("against fpcalc", () {
    for (final c in cases) {
      group(c.name, () {
        late Map<ChromaprintAlgorithm, Fingerprint> fingerprints;
        setUpAll(() {
          final Int16List audio = testSignal(
            sampleRate: c.rate,
            channels: c.channels,
            seconds: c.seconds,
            leadingSilence: c.leadingSilence,
          );
          fingerprints = {
            for (final algorithm in ChromaprintAlgorithm.values)
              algorithm: Chromaprint(algorithm: algorithm).fingerprint(
                audio,
                sampleRate: c.rate,
                channels: c.channels,
              ),
          };
        });

        for (final algorithm in ChromaprintAlgorithm.values) {
          final Map<String, Object?> expected = expectedFor(c.name, algorithm);
          final List<int> expectedRaw = [
            ...?(expected["raw"] as List<Object?>?),
          ].cast<int>();

          group(algorithm.name, () {
            test("matches the raw fingerprint", () {
              final List<int> raw = fingerprints[algorithm]!.raw;
              expect(raw.length, expectedRaw.length);
              expect(bitErrorRate(raw, expectedRaw), 0);
            }, skip: c.channels > 2 ? surroundGap : false);

            test("encodes as fpcalc does", () {
              expect(
                expectedRaw.isEmpty
                    ? null
                    : fingerprints[algorithm]!.toString(),
                expected["fingerprint"],
              );
            }, skip: c.channels > 2 ? surroundGap : false);

            test("hashes as fpcalc does", () {
              expect(fingerprints[algorithm]!.hash, expected["hash"]);
            }, skip: c.channels > 2 ? surroundGap : false);
          });
        }
      });
    }
  });

  group("Fingerprint", () {
    late String encoded;
    late Fingerprint fingerprint;
    setUpAll(() {
      final expected = expectedFor("mono_11025", ChromaprintAlgorithm.test2);
      encoded = expected["fingerprint"]! as String;
      fingerprint = Fingerprint(encoded);
    });

    test("decodes an encoded string", () {
      expect(fingerprint.decode.algorithm, ChromaprintAlgorithm.test2);
      final expected = expectedFor("mono_11025", ChromaprintAlgorithm.test2);
      expect(fingerprint.raw, expected["raw"] as List<Object?>);
      expect(fingerprint.hash, expected["hash"]);
    });

    test("round-trips through toString", () {
      expect(fingerprint.toString(), encoded);
    });

    test("exposes an unmodifiable raw list", () {
      expect(
        () => fingerprint.raw[0] = 0,
        throwsUnsupportedError,
      );
    });

    test("rejects text that isn't a fingerprint", () {
      expect(() => Fingerprint("not a fingerprint!"), throwsFormatException);
      expect(() => Fingerprint("AQ"), throwsFormatException);
    });

    test("an empty fingerprint hashes to zero", () {
      expect(hashing.fingerprintHash(const <int>[]), 0);
    });

    test("ties leave every hash bit clear", () {
      expect(hashing.fingerprintHash(const [1, 2]), 0);
    });
  });

  group("compression", () {
    test("encodes fpcalc's raw fingerprints byte for byte", () {
      for (final c in cases) {
        for (final algorithm in ChromaprintAlgorithm.values) {
          final expected = expectedFor(c.name, algorithm);
          final List<int>? raw = (expected["raw"] as List<Object?>?)
              ?.cast<int>();
          if (raw == null) continue;
          expect(
            codec.encodeFingerprint(raw, algorithm: algorithm),
            expected["fingerprint"],
            reason: "${c.name} ${algorithm.name}",
          );
        }
      }
    });

    test("writes the algorithm into the header", () {
      final bytes = codec.compressFingerprint(
        [1],
        algorithm: ChromaprintAlgorithm.test5,
      );
      expect(bytes.sublist(0, 4), [4, 0, 0, 1]);
    });

    test("large bit gaps go to the exceptional stream", () {
      // Bits 1 and 32: a gap of 31, over the 3-bit maximum of 7.
      final bytes = codec.compressFingerprint([0x80000001]);
      expect(bytes.sublist(0, 4), [1, 0, 0, 1]);
      // Normal values 1, 7, 0 in 3 bits each; exceptional 31 - 7 = 24.
      expect(bytes.sublist(4), [0x39, 0x00, 24]);
    });

    test("base64 is URL-safe and unpadded", () {
      expect(codec.base64UrlNoPadding([0xfb, 0xff]), "-_8");
      expect(codec.base64UrlNoPadding([1]), "AQ");
      expect(codec.base64UrlNoPadding([]), "");
    });
  });

  group("decoding", () {
    test("decodes fpcalc's fingerprints to its raw ones", () {
      for (final c in cases) {
        for (final algorithm in ChromaprintAlgorithm.values) {
          final expected = expectedFor(c.name, algorithm);
          final List<int>? raw = (expected["raw"] as List<Object?>?)
              ?.cast<int>();
          if (raw == null) continue;
          final decoded = decoder.decodeFingerprint(
            expected["fingerprint"]! as String,
          );
          expect(
            decoded.algorithm,
            algorithm,
            reason: "${c.name} ${algorithm.name}",
          );
          expect(decoded.raw, raw, reason: "${c.name} ${algorithm.name}");
        }
      }
    });

    test("round-trips exceptional gaps and every bit", () {
      const raw = [0x80000001, 0xffffffff, 0, 0x40000000, 0x12345678];
      for (final algorithm in ChromaprintAlgorithm.values) {
        final encoded = codec.encodeFingerprint(raw, algorithm: algorithm);
        final decoded = decoder.decodeFingerprint(encoded);
        expect(decoded.algorithm, algorithm);
        expect(decoded.raw, raw);
      }
    });

    test("base64 decodes what it encodes", () {
      for (final bytes in [
        <int>[],
        [1],
        [0xfb, 0xff],
        [1, 2, 3, 250],
      ]) {
        expect(
          decoder.base64UrlNoPaddingDecode(codec.base64UrlNoPadding(bytes)),
          bytes,
        );
      }
    });

    test("rejects text that isn't a fingerprint", () {
      expect(
        () => decoder.decodeFingerprint("not a fingerprint!"),
        throwsFormatException,
      );
      expect(() => decoder.decodeFingerprint("AQ"), throwsFormatException);
      // The header promises 5 sub-fingerprints; the body has none.
      expect(
        () => decoder.decodeFingerprint(
          codec.base64UrlNoPadding([1, 0, 0, 5]),
        ),
        throwsFormatException,
      );
    });
  });

  group("image", () {
    /// The PNG's chunks by type, checking each one's CRC.
    Map<String, Uint8List> chunks(Uint8List png) {
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final out = <String, Uint8List>{};
      final data = ByteData.sublistView(png);
      var o = 8;
      while (o < png.length) {
        final length = data.getUint32(o);
        final type = String.fromCharCodes(png.sublist(o + 4, o + 8));
        final body = png.sublist(o + 8, o + 8 + length);
        final crc = data.getUint32(o + 8 + length);
        expect(crc, _crc32([...type.codeUnits, ...body]), reason: type);
        out[type] = body;
        o += 12 + length;
      }
      return out;
    }

    Uint8List pngOf(List<int> raw) =>
        Fingerprint(codec.encodeFingerprint(raw)).image;

    test("draws a column per sub-fingerprint, bit 0 at the top", () {
      // Column 0: bits 0 and 1; column 1: none; ... column 8: all.
      final raw = [0x00000003, 0, 0, 0, 0, 0, 0, 0, 0xffffffff];
      final parts = chunks(pngOf(raw));
      expect(parts.keys, ["IHDR", "PLTE", "IDAT", "IEND"]);
      final header = ByteData.sublistView(parts["IHDR"]!);
      expect(header.getUint32(0), 9);
      expect(header.getUint32(4), 32);
      // 1-bit palette, deflate, no filter, no interlace.
      expect(parts["IHDR"]!.sublist(8), [1, 3, 0, 0, 0]);
      // Clear bits white, set bits AcoustID's #1a1a1a.
      expect(parts["PLTE"], [255, 255, 255, 0x1a, 0x1a, 0x1a]);

      final pixels = zlib.decode(parts["IDAT"]!);
      const stride = 2; // 9 pixels in 1-bit rows
      expect(pixels, hasLength((stride + 1) * 32));
      bool set(int x, int y) {
        final byte = pixels[y * (stride + 1) + 1 + (x >> 3)];
        return (byte >> (7 - (x & 7))) & 1 == 1;
      }

      for (var y = 0; y < 32; y++) {
        expect(pixels[y * (stride + 1)], 0, reason: "filter byte");
        expect(set(0, y), y <= 1, reason: "column 0, row $y");
        expect(set(1, y), isFalse);
        expect(set(8, y), isTrue);
      }
    });

    test("a 2-minute fingerprint fits in a few kilobytes", () {
      final raw = List<int>.generate(950, (i) => (i * 2654435761) & 0xffffffff);
      final png = pngOf(raw);
      expect(png.length, lessThan(5000));
      expect(zlib.decode(chunks(png)["IDAT"]!), hasLength(32 * (1 + 119)));
    });

    test("needs at least one column", () {
      expect(() => pngOf(const []), throwsArgumentError);
    });
  });

  group("input and options", () {
    test("channels are averaged, truncating toward zero", () {
      expect(
        fingerprinter.downmix(
          Int16List.fromList([3, 4, -3, -4, 32767, 32767]),
          2,
        ),
        [3, -3, 32767],
      );
      expect(
        fingerprinter.downmix(
          Int16List.fromList([1, 1, 1, -5, 0, 0]),
          3,
        ),
        [1, -1],
      );
    });

    test("a rate of 1000 Hz or less is refused", () {
      expect(
        () => Chromaprint().fingerprint(Int16List(10), sampleRate: 1000),
        throwsArgumentError,
      );
    });

    test("resampling 44.1 kHz gives a quarter of the samples", () {
      final out = resampler.resample(Int16List(44100), 44100, 11025);
      expect(out.length, closeTo(11025, 64));
      expect(out.every((s) => s == 0), isTrue);
    });

    test("leading silence is skipped starting at the crossing sample", () {
      final samples = Int16List.fromList([
        0,
        0,
        0,
        0,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
        100,
      ]);
      expect(
        fingerprinter.removeLeadingSilence(samples, 40),
        [100, 100, 100, 100, 100, 100, 100],
      );
    });

    test("the silence threshold is validated", () {
      expect(
        () => ChromaprintOptions(silenceThreshold: -1),
        throwsArgumentError,
      );
      expect(
        () => ChromaprintOptions(silenceThreshold: 32768),
        throwsArgumentError,
      );
    });

    test("options are exposed on the instance", () {
      final options = ChromaprintOptions(silenceThreshold: 40);
      final chromaprint = Chromaprint(
        algorithm: ChromaprintAlgorithm.test4,
        options: options,
      );
      expect(chromaprint.algorithm, ChromaprintAlgorithm.test4);
      expect(chromaprint.options, same(options));
    });

    test("the silence threshold only affects test4", () {
      final audio = testSignal(
        sampleRate: 11025,
        channels: 1,
        seconds: 12,
        leadingSilence: 1,
      );
      Fingerprint fingerprintFor(int threshold) => Chromaprint(
        algorithm: ChromaprintAlgorithm.test2,
        options: ChromaprintOptions(silenceThreshold: threshold),
      ).fingerprint(audio, sampleRate: 11025);
      expect(fingerprintFor(0).toString(), fingerprintFor(32767).toString());
    });

    test("changing the silence threshold changes test4's fingerprint", () {
      final audio = testSignal(
        sampleRate: 11025,
        channels: 1,
        seconds: 12,
        leadingSilence: 1,
      );
      Fingerprint fingerprintFor(int threshold) => Chromaprint(
        algorithm: ChromaprintAlgorithm.test4,
        options: ChromaprintOptions(silenceThreshold: threshold),
      ).fingerprint(audio, sampleRate: 11025);
      expect(
        fingerprintFor(0).toString(),
        isNot(fingerprintFor(5000).toString()),
      );
    });
  });

  group("algorithm", () {
    test("maps to and from the C library's ids", () {
      for (final algorithm in ChromaprintAlgorithm.values) {
        expect(
          ChromaprintAlgorithm.fromValue(algorithm.value),
          same(algorithm),
        );
      }
      expect(
        () => ChromaprintAlgorithm.fromValue(5),
        throwsFormatException,
      );
    });

    test("defaults to test2", () {
      expect(Chromaprint().algorithm, ChromaprintAlgorithm.test2);
    });
  });
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
