/// The fingerprint algorithms Chromaprint supports.
///
/// `test2` is the default and the one AcoustID looks up. The others are
/// experimental variants kept for compatibility with the C library.
enum ChromaprintAlgorithm {
  test1(0),
  test2(1),
  test3(2),
  test4(3),
  test5(4);

  const ChromaprintAlgorithm(this.value);

  /// The id the C library stores in a fingerprint's compressed header.
  final int value;

  /// The algorithm with the given [value].
  ///
  /// Throws a [FormatException] if [value] is not a known algorithm.
  static ChromaprintAlgorithm fromValue(int value) =>
      ChromaprintAlgorithm.values.firstWhere(
        (ChromaprintAlgorithm algorithm) => algorithm.value == value,
        orElse: () =>
            throw FormatException("Unknown fingerprint algorithm", value),
      );
}
