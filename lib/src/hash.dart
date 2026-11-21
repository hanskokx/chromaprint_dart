/// The 32-bit SimHash of a raw fingerprint, as computed by Chromaprint's
/// `chromaprint_hash_fingerprint`.
///
/// Each output bit is set when more than half of the sub-fingerprints have
/// that bit set. Returns 0 for an empty fingerprint.
int fingerprintHash(List<int> raw) {
  final List<int> counts = List<int>.filled(32, 0);
  for (final int value in raw) {
    for (int bit = 0; bit < 32; bit++) {
      counts[bit] += (value >> bit) & 1;
    }
  }
  final int threshold = raw.length ~/ 2;
  int hash = 0;
  for (int bit = 0; bit < 32; bit++) {
    if (counts[bit] > threshold) {
      hash |= 1 << bit;
    }
  }
  return hash;
}
