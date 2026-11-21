import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

/// A deterministic test signal: a chord that changes every half second,
/// a little noise, and a different chord in each channel, so mixing the
/// channels down matters. Interleaved 16-bit PCM.
Int16List testSignal({
  required int sampleRate,
  required int channels,
  required double seconds,
  double leadingSilence = 0,
}) {
  final frames = (sampleRate * seconds).round();
  final silentFrames = (sampleRate * leadingSilence).round();
  final out = Int16List((frames + silentFrames) * channels);
  var seed = 12345;
  double noise() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff * 2 - 1;
  }

  // Semitones above A3 (220 Hz) for each step's chord.
  const chords = [
    [0, 4, 7], [5, 9, 12], [7, 11, 14], [3, 7, 10], //
    [2, 5, 9], [8, 12, 15], [10, 14, 17], [1, 4, 8],
  ];
  for (var f = 0; f < frames; f++) {
    final t = f / sampleRate;
    final step = (t * 2).floor();
    for (var c = 0; c < channels; c++) {
      final chord = chords[(step * 3 + c * 5) % chords.length];
      var v = 0.0;
      for (final semitone in chord) {
        final freq = 220 * math.pow(2, semitone / 12);
        v += math.sin(2 * math.pi * freq * t);
      }
      v = v / chord.length * 0.6 + noise() * 0.05;
      out[(f + silentFrames) * channels + c] = (v * 32767).round().clamp(
        -32768,
        32767,
      );
    }
  }
  return out;
}

/// Writes [samples] as a 16-bit PCM WAV file.
void writeWav(File file, Int16List samples, int sampleRate, int channels) {
  final data = samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  );
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + data.length, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * channels * 2, Endian.little)
    ..setUint16(32, channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, data.length, Endian.little);
  file.writeAsBytesSync([...header.buffer.asUint8List(), ...data]);
}
