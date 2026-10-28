/// A small, portable 32-bit PRNG (mulberry32).
///
/// `dart:math`'s `Random` does not promise the same sequence across SDK
/// releases, so the workloads use this generator instead: the same seed yields
/// the same sequence on every machine and SDK.
class SeededRandom {
  /// Creates a generator seeded with the low 32 bits of [seed].
  SeededRandom(int seed) : _state = seed & _mask;

  static const int _mask = 0xFFFFFFFF;

  int _state;

  static int _imul(int a, int b) => (a * b) & _mask;

  /// Returns the next value in `[0, 2^32)`.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & _mask)) & _mask;
    return (t ^ (t >> 14)) & _mask;
  }

  /// Returns a value in `[0, max)`. [max] must be positive.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return nextUint32() % max;
  }

  /// Returns a value in `[min, max]` (both inclusive).
  int range(int min, int max) => min + nextInt(max - min + 1);

  /// Returns a value in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Returns true with probability [p].
  bool chance(double p) => nextDouble() < p;

  /// Picks an element of [items] uniformly.
  T pick<T>(List<T> items) => items[nextInt(items.length)];
}
