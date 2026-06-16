/// Faithful port of `java.util.Random`'s 48-bit linear-congruential generator,
/// which ELK uses (via `InternalProperties.RANDOM`) to drive the deliberate
/// randomization in crossing minimization (randomized first layer + barycenter
/// perturbation, explored across the `thoroughness` restarts and kept-best).
///
/// ELK's barycenter heuristic is non-deterministic by design; reproducing it
/// faithfully means using the same generator. We replicate `java.util.Random`'s
/// LCG (multiplier `0x5DEECE66D`, addend `0xB`, modulus `2^48`).
///
/// IMPORTANT — web safety: this runs on Dart **web** (the Flutter/Jaspr site)
/// as well as the native VM. On web, Dart `int`s are 53-bit doubles and bitwise
/// operators are 32-bit, so the naïve `seed * 0x5DEECE66D & ((1<<48)-1)` and
/// `>> 32` would silently overflow/truncate. All arithmetic here is therefore
/// done with float-safe 24-bit splitting so every intermediate stays below
/// `2^53` and no shift exceeds 32 bits — the generator produces identical
/// results on web and native.
library;

class JavaRandom {
  JavaRandom(int seed) {
    setSeed(seed);
  }

  // java.util.Random constants, as doubles.
  static const double _multHi = 1502.0; //  floor(0x5DEECE66D / 2^24)
  static const double _multLo = 15525485.0; // 0x5DEECE66D % 2^24
  static const double _mult = 25214903917.0; // 0x5DEECE66D
  static const double _addend = 11.0; // 0xB
  static const double _two24 = 16777216.0; // 2^24
  static const double _two48 = 281474976710656.0; // 2^48

  /// Current 48-bit state, held as an exact double in [0, 2^48).
  double _seed = 0;

  /// Mirrors `Random.setSeed`: `(seed ^ 0x5DEECE66D) & ((1<<48)-1)`.
  void setSeed(int seed) {
    var s = seed.toDouble() % _two48;
    if (s < 0) s += _two48;
    _seed = _xor48(s, _mult);
  }

  /// Bitwise XOR of two values in `[0, 2^48)`, split into 24-bit halves so each
  /// `^` operates on a value below `2^24` (well within 32-bit-safe range).
  static double _xor48(double a, double b) {
    final aL = (a % _two24).toInt(), aH = (a ~/ _two24).toInt();
    final bL = (b % _two24).toInt(), bH = (b ~/ _two24).toInt();
    return (aH ^ bH) * _two24 + (aL ^ bL);
  }

  /// Advances the state: `_seed = (_seed * 0x5DEECE66D + 0xB) mod 2^48`, with
  /// the multiplication done in 24-bit pieces (all partials < 2^53).
  void _advance() {
    final sH = (_seed ~/ _two24).toDouble(); // < 2^24
    final sL = _seed % _two24; // < 2^24
    // Middle term, reduced mod 2^24: (sH*Mlo + sL*Mhi) each < 2^48 / 2^35.
    final mid = (sH * _multLo + sL * _multHi) % _two24;
    final low = sL * _multLo; // < 2^48
    _seed = (mid * _two24 + low + _addend) % _two48;
  }

  /// Mirrors `Random.next(bits)`: the top [bits] bits of the advanced state,
  /// extracted by division (not a >32-bit shift). Returns `[0, 2^bits)`.
  int _next(int bits) {
    _advance();
    var divisor = 1.0;
    for (var i = 0; i < 48 - bits; i++) {
      divisor *= 2;
    }
    return (_seed / divisor).floor();
  }

  /// Mirrors `Random.nextBoolean()`.
  bool nextBoolean() => _next(1) != 0;

  /// Mirrors `Random.nextDouble()` — 53 bits of precision.
  double nextDouble() =>
      (_next(26) * 134217728.0 /* 2^27 */ + _next(27)) /
      9007199254740992.0 /* 2^53 */;

  /// Mirrors `Random.nextFloat()` — 24 bits of precision.
  double nextFloat() => _next(24) / _two24;
}
