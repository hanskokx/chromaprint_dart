// Records the reference fingerprints the tests compare against, using
// Chromaprint's own fpcalc: dart run tool/record_fixtures.dart
import "dart:convert";
import "dart:io";

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
      testSignal(sampleRate: c.rate, channels: c.channels, seconds: c.seconds),
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

    final raw = jsonDecode(run(["-json", "-raw"])) as Map<String, Object?>;
    final encoded = jsonDecode(run(["-json"])) as Map<String, Object?>;
    out[c.name] = {
      "raw": raw["fingerprint"],
      "fingerprint": encoded["fingerprint"],
    };
  }
  dir.deleteSync(recursive: true);
  File("test/fixtures/fpcalc.json").writeAsStringSync(
    const JsonEncoder.withIndent(" ").convert({
      "fpcalc": version.trim(),
      ...out,
    }),
  );
}
