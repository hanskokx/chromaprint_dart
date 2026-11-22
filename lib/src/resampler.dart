// audio resampling
// Copyright (c) 2004 Michael Niedermayer <michaelni@gmx.at>
//
// This file is part of FFmpeg.
//
// FFmpeg is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; either
// version 2.1 of the License, or (at your option) any later version.
//
// FFmpeg is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with FFmpeg; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
//
// Ported to Dart by Hans Kokx in 2026 from the av_resample() implementation in
// FFmpeg's libavresample/resample2.c (bundled by Chromaprint as
// src/avresample/resample2.c), in its 16-bit integer configuration. That code
// is LGPL-2.1-or-later; this port is LGPL-2.1. See LICENSE and
// THIRD_PARTY_NOTICES.md.

import "dart:math" as math;
import "dart:typed_data";

const int _filterShift = 15;
const int _windowType = 9;

// The settings Chromaprint's AudioProcessor resamples with.
const int _filterSize = 16;
const int _phaseShift = 8;
const double _cutoff = 0.8;

double _bessel(double x) {
  double v = 1.0;
  double lastV = 0.0;
  double t = 1.0;
  final double xx = x * x / 4;
  for (int i = 1; v != lastV; i++) {
    lastV = v;
    t *= xx / (i * i);
    v += t;
  }
  return v;
}

/// C's lrint() in the default rounding mode: halves go to the even integer.
int _lrint(double x) {
  final double floor = x.floorToDouble();
  final double diff = x - floor;
  if (diff > 0.5) return floor.toInt() + 1;
  if (diff < 0.5) return floor.toInt();
  final int f = floor.toInt();
  return f.isEven ? f : f + 1;
}

/// Resamples 16-bit mono [input] from [inRate] to [outRate] as libchromaprint
/// does when it's fed audio at another rate: a Kaiser-windowed sinc filter
/// (16 taps at the output rate, 256 phases, cutoff 0.8), no interpolation
/// between phases. The input's tail that the filter can't reach is dropped,
/// as Chromaprint does when the stream ends.
///
/// `fpcalc` instead has FFmpeg's swresample convert to 11025 Hz with the
/// same filter, but interpolating between phases. On the test signals both
/// give identical fingerprints.
Int16List resample(Int16List input, int inRate, int outRate) {
  final double factor = math.min(outRate * _cutoff / inRate, 1);
  const int phaseCount = 1 << _phaseShift;
  const int phaseMask = phaseCount - 1;
  final int length = math.max((_filterSize / factor).ceil(), 1);
  final Int16List bank = _buildFilter(factor.toDouble(), length, phaseCount);

  final int srcSize = input.length;
  final int srcIncr = outRate;
  final int dstIncr = inRate * phaseCount;
  final int incrFrac = dstIncr % srcIncr;
  final int incr = dstIncr ~/ srcIncr;
  int index = -phaseCount * ((length - 1) ~/ 2);
  int frac = 0;

  final List<int> out = [];

  if (srcSize == 0) return Int16List(0);

  while (true) {
    final int filter = length * (index & phaseMask);
    final int sampleIndex = index >> _phaseShift;
    int val = 0;
    if (sampleIndex < 0) {
      for (int i = 0; i < length; i++) {
        val += input[(sampleIndex + i).abs() % srcSize] * bank[filter + i];
      }
    } else if (sampleIndex + length > srcSize) {
      break;
    } else {
      for (int i = 0; i < length; i++) {
        val += input[sampleIndex + i] * bank[filter + i];
      }
    }
    // FELEM2 is a 32-bit int in this configuration.
    val = val.toSigned(32);
    val = (val + (1 << (_filterShift - 1))).toSigned(32) >> _filterShift;
    out.add(val.clamp(-32768, 32767));
    frac += incrFrac;
    index += incr;
    if (frac >= srcIncr) {
      frac -= srcIncr;
      index++;
    }
  }
  return Int16List.fromList(out);
}

Int16List _buildFilter(double factor, int tapCount, int phaseCount) {
  const int scale = 1 << _filterShift;
  final Int16List filter = Int16List(tapCount * phaseCount);
  final Float64List tab = Float64List(tapCount);
  final Float32List single = Float32List(1);
  final int center = (tapCount - 1) ~/ 2;
  for (int ph = 0; ph < phaseCount; ph++) {
    double norm = 0.0;
    for (int i = 0; i < tapCount; i++) {
      final double x = math.pi * ((i - center) - ph / phaseCount) * factor;
      double y = x == 0 ? 1.0 : math.sin(x) / x;
      final double w = 2.0 * x / (factor * tapCount * math.pi);
      y *= _bessel(_windowType * math.sqrt(math.max(1 - w * w, 0)));
      tab[i] = y;
      norm += y;
    }
    for (int i = 0; i < tapCount; i++) {
      // lrintf() takes a float, so the value is rounded to one first.
      single[0] = tab[i] * scale / norm;
      filter[ph * tapCount + i] = _lrint(single[0]).clamp(-32768, 32767);
    }
  }
  return filter;
}
