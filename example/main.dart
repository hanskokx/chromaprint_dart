import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

import "package:chromaprint_dart/chromaprint.dart";

void main(List<String> args) {
  // A ten-second 440 Hz tone as interleaved 16-bit PCM.
  const int sampleRate = 44100;
  final Int16List pcm = Int16List(sampleRate * 10);
  for (int i = 0; i < pcm.length; i++) {
    pcm[i] = (math.sin(2 * math.pi * 440 * i / sampleRate) * 20000).round();
  }

  final chromaprint = Chromaprint();
  final Fingerprint fingerprint = chromaprint.fingerprint(
    pcm,
    sampleRate: sampleRate,
  );

  print("Algorithm: ${chromaprint.algorithm.name}");
  print("Fingerprint: $fingerprint");
  print("Sub-fingerprints: ${fingerprint.raw.length}");
  print("Hash: ${fingerprint.hash}");

  final File output = File(args.isEmpty ? "fingerprint.png" : args.first);
  output.writeAsBytesSync(fingerprint.image);
  print("Wrote ${output.path}");

  final Fingerprint restored = Fingerprint(fingerprint.toString());
  print("Rehydrated hash matches: ${restored.hash == fingerprint.hash}");

  // Other algorithms and options are available too:
  // final custom = Chromaprint(
  //   algorithm: ChromaprintAlgorithm.test4,
  //   options: ChromaprintOptions(silenceThreshold: 40),
  // );
}
