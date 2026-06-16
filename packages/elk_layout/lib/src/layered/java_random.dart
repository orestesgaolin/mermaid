/// Faithful port of `java.util.Random` (the linear-congruential generator ELK
/// uses via `InternalProperties.RANDOM`).
///
/// ELK's crossing minimization is *deliberately* randomized — the barycenter
/// heuristic perturbs barycenters and permutes the first layer so that the
/// `thoroughness` restarts explore different solutions, and the driver keeps
/// the order with the fewest crossings. To reproduce that algorithm
/// deterministically (and as close to elkjs — itself GWT-transpiled Java — as
/// possible) we replicate `java.util.Random`'s exact 48-bit LCG rather than use
/// Dart's `math.Random`, whose sequence differs.
///
/// Reference: `java.util.Random` (OpenJDK) — multiplier `0x5DEECE66D`,
/// addend `0xB`, modulus `2^48`.
///
/// Runs on the native VM (the CLI / `dart test` / SVG backend) where ints are
/// 64-bit; the modular arithmetic below is exact under 64-bit two's-complement
/// wraparound because we mask to 48 bits after every step.
library;

class JavaRandom {
  JavaRandom(int seed) : _seed = (seed ^ _multiplier) & _mask;

  static const int _multiplier = 0x5DEECE66D;
  static const int _addend = 0xB;
  static const int _mask = (1 << 48) - 1;

  int _seed;

  /// Mirrors `Random.setSeed(long)`.
  void setSeed(int seed) {
    _seed = (seed ^ _multiplier) & _mask;
  }

  /// Mirrors `Random.next(int bits)`. Returns the top [bits] bits of the
  /// advanced 48-bit state (an unsigned value in `[0, 2^bits)`).
  int _next(int bits) {
    _seed = (_seed * _multiplier + _addend) & _mask;
    return _seed >> (48 - bits);
  }

  /// Mirrors `Random.next(32)` reinterpreted as a signed 32-bit `int`.
  int _next32Signed() {
    final v = _next(32);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// Mirrors `Random.nextBoolean()`.
  bool nextBoolean() => _next(1) != 0;

  /// Mirrors `Random.nextDouble()` — 53 bits of precision.
  double nextDouble() =>
      ((_next(26) << 27) + _next(27)) / (1 << 53).toDouble();

  /// Mirrors `Random.nextFloat()` — 24 bits of precision.
  double nextFloat() => _next(24) / (1 << 24).toDouble();

  /// Mirrors `Random.nextLong()`.
  int nextLong() => (_next32Signed() << 32) + _next32Signed();
}
