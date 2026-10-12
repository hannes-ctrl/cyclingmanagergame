import 'dart:math';

/// Random number generator whose state can be saved and restored.
///
/// Dart's own [Random] hides its state, which makes it impossible to store a
/// running career and continue it with the same random sequence. This is a
/// xorshift64* generator; it is only used where the sequence has to survive
/// a save (the career and each stage race), not inside a single stage.
class Rng implements Random {
  /// Creates a generator.
  ///
  /// @param seed Any integer; equal seeds give equal sequences.
  Rng(int seed) : state = _mix(seed);

  /// Restores a generator from a saved [state].
  ///
  /// @param state Value read from [Rng.state] earlier.
  Rng.restore(this.state);

  /// Internal state; never zero. Save this to continue the sequence later.
  int state;

  /// Spreads a small seed over all 64 bits (splitmix64 finaliser).
  ///
  /// @param seed The seed.
  /// @returns A non-zero starting state.
  static int _mix(int seed) {
    var z = seed + 0x9E3779B97F4A7C15;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z ^= z >>> 31;
    return z == 0 ? 1 : z;
  }

  /// @returns The next 64 random bits.
  int _next() {
    var x = state;
    x ^= x << 13;
    x ^= x >>> 7;
    x ^= x << 17;
    state = x;
    return x * 0x2545F4914F6CDD1D;
  }

  @override
  bool nextBool() => _next() < 0;

  @override
  double nextDouble() => (_next() >>> 11) * (1.0 / (1 << 53));

  @override
  int nextInt(int max) => (_next() >>> 1) % max;
}
