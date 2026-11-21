// Records the reference fingerprints the tests compare against, using
// Chromaprint's own fpcalc: dart run tool/record_fixtures.dart
import "dart:convert";
import "dart:io";

import "package:chromaprint_dart/src/algorithm.dart";
import "package:chromaprint_dart/src/hash.dart";

import "../test/cases.dart";
import "../test/signal.dart";

void main() {
  final dir = Directory.systemTemp.createTempSync("chromaprint");
  final out = <String, Object>{};
  final version = Process.runSync("fpcalc", ["-version"]).stdout as String;
  for (final c in cases) {
    final wav = File("${dir.path}/${c.name}.wav");
    writeWav(
      wav,
      testSignal(
        sampleRate: c.rate,
        channels: c.channels,
        seconds: c.seconds,
        leadingSilence: c.leadingSilence,
      ),
      c.rate,
      c.channels,
    );

    String run(List<String> args) {
      final result = Process.runSync("fpcalc", [...args, wav.path]);
      if ("${result.stderr}".contains("Empty fingerprint")) {
        return '{"fingerprint": null}';
      }
      if (result.exitCode != 0) throw StateError("${c.name}: ${result.stderr}");
      return result.stdout as String;
    }

    final byAlgorithm = <String, Object>{};
    for (final algorithm in ChromaprintAlgorithm.values) {
      final number = "${algorithm.value + 1}";
      final raw =
          jsonDecode(run(["-a", number, "-json", "-raw"]))
              as Map<String, Object?>;
      final encoded =
          jsonDecode(run(["-a", number, "-json"])) as Map<String, Object?>;
      final List<int>? values = (raw["fingerprint"] as List<Object?>?)
          ?.cast<int>();
      byAlgorithm["${algorithm.value}"] = <String, Object?>{
        "raw": raw["fingerprint"],
        "fingerprint": encoded["fingerprint"],
        "hash": values == null ? 0 : fingerprintHash(values),
      };
    }
    out[c.name] = byAlgorithm;
  }
  dir.deleteSync(recursive: true);
  File("test/fixtures/fpcalc.json").writeAsStringSync(
    const JsonEncoder.withIndent(" ").convert({
      "fpcalc": version.trim(),
      "cases": out,
    }),
  );
}
