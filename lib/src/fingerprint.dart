// A port of Chromaprint's fingerprinter (https://github.com/acoustid/chromaprint),
// Copyright (C) 2010-2016 Lukas Lalinsky, MIT licensed; see LICENSE.

import "dart:math" as math;
import "dart:typed_data";

import "resampler.dart";

/// The rate Chromaprint fingerprints at.
const int fingerprintSampleRate = 11025;

const int _frameSize = 4096;
const int _frameStep = _frameSize ~/ 3; // 4096 - overlap of 2731
const int _minFreq = 28;
const int _maxFreq = 3520;
const int _bands = 12;
const List<double> _chromaFilter = [0.25, 0.75, 1.0, 0.75, 0.25];

/// Mixes interleaved 16-bit [samples] down to mono the way Chromaprint does:
/// the channels' mean, truncated toward zero.
Int16List downmix(Int16List samples, int channels) {
  if (channels == 1) return samples;
  final int frames = samples.length ~/ channels;
  final Int16List mono = Int16List(frames);
  for (int f = 0, s = 0; f < frames; f++) {
    int sum = 0;
    for (int c = 0; c < channels; c++) {
      sum += samples[s++];
    }
    mono[f] = sum ~/ channels;
  }
  return mono;
}

/// The raw Chromaprint fingerprint (algorithm 2, the default) of
/// interleaved 16-bit [samples]: one 32-bit sub-fingerprint per ~0.124 s.
///
/// Like `fpcalc`, only the first [maxDuration] is used (120 s by default);
/// pass null to use all of it.
Uint32List rawFingerprint(
  Int16List samples, {
  required int sampleRate,
  int channels = 1,
  Duration? maxDuration = const Duration(seconds: 120),
}) {
  if (sampleRate <= 1000) {
    throw ArgumentError.value(sampleRate, "sampleRate", "must be over 1000");
  }
  Int16List input = samples;
  if (maxDuration != null) {
    final int limit = maxDuration.inMicroseconds * sampleRate ~/ 1000000;
    if (input.length > limit * channels) {
      input = Int16List.sublistView(input, 0, limit * channels);
    }
  }
  Int16List mono = downmix(input, channels);
  if (sampleRate != fingerprintSampleRate) {
    mono = resample(mono, sampleRate, fingerprintSampleRate);
  }
  return _Fingerprinter().run(mono);
}

class _Fingerprinter {
  _Fingerprinter() {
    for (int i = 0; i < _frameSize; i++) {
      // vDSP's FFT, which macOS builds use, is scaled by 2, so Chromaprint
      // halves its window there. The float window is kept for exactness.
      _window[i] =
          0.5 /
          32767 *
          (0.54 - 0.46 * math.cos(i * 2.0 * math.pi / (_frameSize - 1)));
    }
    _minIndex = math.max(1, _freqToIndex(_minFreq));
    _maxIndex = math.min(_frameSize ~/ 2, _freqToIndex(_maxFreq));
    for (int i = _minIndex; i < _maxIndex; i++) {
      final double freq = i * fingerprintSampleRate / _frameSize;
      final double octave = math.log(freq / (440.0 / 16.0)) / math.ln2;
      _notes[i] = (_bands * (octave - octave.floorToDouble())).toInt();
    }
  }

  final Float32List _window = Float32List(_frameSize);
  final Int8List _notes = Int8List(_frameSize);
  late final int _minIndex;
  late final int _maxIndex;
  final _Fft _fft = _Fft(_frameSize);
  final Float32List _frame = Float32List(_frameSize);
  final Float64List _re = Float64List(_frameSize);
  final Float64List _im = Float64List(_frameSize);

  static int _freqToIndex(int freq) =>
      (_frameSize * freq / fingerprintSampleRate).round();

  Uint32List run(Int16List mono) {
    final List<Float64List> chromas = <Float64List>[];
    for (
      int start = 0;
      start + _frameSize <= mono.length;
      start += _frameStep
    ) {
      chromas.add(_chroma(mono, start));
    }
    final _IntegralImage image = _IntegralImage();
    final List<int> result = <int>[];
    for (int i = _chromaFilter.length - 1; i < chromas.length; i++) {
      final Float64List row = Float64List(_bands);
      for (int b = 0; b < _bands; b++) {
        for (int j = 0; j < _chromaFilter.length; j++) {
          row[b] +=
              chromas[i - _chromaFilter.length + 1 + j][b] * _chromaFilter[j];
        }
      }
      _normalize(row);
      image.add(row);
      if (image.rows >= _maxFilterWidth) {
        result.add(_subFingerprint(image, image.rows - _maxFilterWidth));
      }
    }
    return Uint32List.fromList(result);
  }

  Float64List _chroma(Int16List mono, int start) {
    for (int i = 0; i < _frameSize; i++) {
      _frame[i] = mono[start + i] * _window[i];
    }
    for (int i = 0; i < _frameSize; i++) {
      _re[i] = _frame[i];
      _im[i] = 0;
    }
    _fft.transform(_re, _im);
    final Float64List features = Float64List(_bands);
    for (int i = _minIndex; i < _maxIndex; i++) {
      final double re = 2 * _re[i];
      final double im = 2 * _im[i];
      features[_notes[i]] += re * re + im * im;
    }
    return features;
  }

  static void _normalize(Float64List row) {
    double squares = 0.0;
    for (final double v in row) {
      squares += v * v;
    }
    final double norm = squares > 0 ? math.sqrt(squares) : 0;
    for (int i = 0; i < row.length; i++) {
      row[i] = norm < 0.01 ? 0 : row[i] / norm;
    }
  }
}

/// A radix-2 complex FFT, in place.
class _Fft {
  _Fft(this.size)
    : _cos = Float64List(size ~/ 2),
      _sin = Float64List(size ~/ 2),
      _reverse = Int32List(size) {
    for (int i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / size);
      _sin[i] = -math.sin(2 * math.pi * i / size);
    }
    final bits = size.bitLength - 1;
    for (int i = 0; i < size; i++) {
      int r = 0;
      for (int b = 0; b < bits; b++) {
        r |= ((i >> b) & 1) << (bits - 1 - b);
      }
      _reverse[i] = r;
    }
  }

  final int size;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _reverse;

  void transform(Float64List re, Float64List im) {
    for (int i = 0; i < size; i++) {
      final int j = _reverse[i];
      if (j > i) {
        final double tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final double ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (int len = 2; len <= size; len <<= 1) {
      final int half = len >> 1;
      final int step = size ~/ len;
      for (int i = 0; i < size; i += len) {
        for (int k = 0; k < half; k++) {
          final double wr = _cos[k * step];
          final double wi = _sin[k * step];
          final int a = i + k;
          final int b = a + half;
          final double xr = re[b] * wr - im[b] * wi;
          final double xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}

class _IntegralImage {
  final List<Float64List> _data = <Float64List>[];

  int get rows => _data.length;

  void add(Float64List row) {
    final Float64List sums = Float64List(_bands);
    double running = 0.0;
    for (int i = 0; i < _bands; i++) {
      running += row[i];
      sums[i] = running;
    }
    if (_data.isNotEmpty) {
      final Float64List last = _data.last;
      for (int i = 0; i < _bands; i++) {
        sums[i] = last[i] + sums[i];
      }
    }
    _data.add(sums);
  }

  /// The sum over rows [r1, r2) and columns [c1, c2).
  double area(int r1, int c1, int r2, int c2) {
    if (r1 == r2 || c1 == c2) return 0;
    final Float64List row2 = _data[r2 - 1];
    if (r1 == 0) return c1 == 0 ? row2[c2 - 1] : row2[c2 - 1] - row2[c1 - 1];
    final Float64List row1 = _data[r1 - 1];
    if (c1 == 0) return row2[c2 - 1] - row1[c2 - 1];
    return row2[c2 - 1] - row1[c2 - 1] - row2[c1 - 1] + row1[c1 - 1];
  }
}

/// Classifier(Filter(type, y, height, width), Quantizer(t0, t1, t2)), from
/// Chromaprint's kClassifiersTest2.
const _classifiers = <(int, int, int, int, double, double, double)>[
  (0, 4, 3, 15, 1.98215, 2.35817, 2.63523),
  (4, 4, 6, 15, -1.03809, -0.651211, -0.282167),
  (1, 0, 4, 16, -0.298702, 0.119262, 0.558497),
  (3, 8, 2, 12, -0.105439, 0.0153946, 0.135898),
  (3, 4, 4, 8, -0.142891, 0.0258736, 0.200632),
  (4, 0, 3, 5, -0.826319, -0.590612, -0.368214),
  (1, 2, 2, 9, -0.557409, -0.233035, 0.0534525),
  (2, 7, 3, 4, -0.0646826, 0.00620476, 0.0784847),
  (2, 6, 2, 16, -0.192387, -0.029699, 0.215855),
  (2, 1, 3, 2, -0.0397818, -0.00568076, 0.0292026),
  (5, 10, 1, 15, -0.53823, -0.369934, -0.190235),
  (3, 6, 2, 10, -0.124877, 0.0296483, 0.139239),
  (2, 1, 1, 14, -0.101475, 0.0225617, 0.231971),
  (3, 5, 6, 4, -0.0799915, -0.00729616, 0.063262),
  (1, 9, 2, 12, -0.272556, 0.019424, 0.302559),
  (3, 4, 2, 14, -0.164292, -0.0321188, 0.0846339),
];

final int _maxFilterWidth = _classifiers.map((c) => c.$4).reduce(math.max);

const List<int> _grayCode = [0, 1, 3, 2];

int _subFingerprint(_IntegralImage image, int x) {
  int bits = 0;
  for (final (int type, int y, int h, int w, double t0, double t1, double t2)
      in _classifiers) {
    final double value = _filter(image, type, x, y, w, h);
    final int q = value < t1 ? (value < t0 ? 0 : 1) : (value < t2 ? 2 : 3);
    bits = ((bits << 2) | _grayCode[q]) & 0xffffffff;
  }
  return bits;
}

double _filter(_IntegralImage im, int type, int x, int y, int w, int h) {
  double a;
  double b;
  switch (type) {
    case 0:
      a = im.area(x, y, x + w, y + h);
      b = 0;
    case 1:
      final h2 = h ~/ 2;
      a = im.area(x, y + h2, x + w, y + h);
      b = im.area(x, y, x + w, y + h2);
    case 2:
      final w2 = w ~/ 2;
      a = im.area(x + w2, y, x + w, y + h);
      b = im.area(x, y, x + w2, y + h);
    case 3:
      final w2 = w ~/ 2;
      final h2 = h ~/ 2;
      a = im.area(x, y + h2, x + w2, y + h) + im.area(x + w2, y, x + w, y + h2);
      b = im.area(x, y, x + w2, y + h2) + im.area(x + w2, y + h2, x + w, y + h);
    case 4:
      final h3 = h ~/ 3;
      a = im.area(x, y + h3, x + w, y + 2 * h3);
      b = im.area(x, y, x + w, y + h3) + im.area(x, y + 2 * h3, x + w, y + h);
    case 5:
      final w3 = w ~/ 3;
      a = im.area(x + w3, y, x + 2 * w3, y + h);
      b = im.area(x, y, x + w3, y + h) + im.area(x + 2 * w3, y, x + w, y + h);
    default:
      return 0;
  }
  return math.log((1.0 + a) / (1.0 + b));
}
