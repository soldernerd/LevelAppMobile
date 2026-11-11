import 'dart:math';

import 'package:test/test.dart';

import 'package:inclinometer/devices/leveltronic/calibration/calibration_math.dart';

/// A capture of `u = (zero + tilt·k)·e^{jφ}` with a little noise.
ComplexStats capture(double tilt,
    {double k = 0.05,
    double zero = 0.001,
    double phaseDeg = 12,
    double noise = 1e-5,
    int n = 300,
    int seed = 1}) {
  final rng = Random(seed);
  final s = ComplexStats();
  final mag = zero + tilt * k;
  final ph = phaseDeg * pi / 180;
  for (var i = 0; i < n; i++) {
    s.add(mag * cos(ph) + (rng.nextDouble() - 0.5) * noise,
        mag * sin(ph) + (rng.nextDouble() - 0.5) * noise);
  }
  return s;
}

void main() {
  group('ComplexStats', () {
    test('mean and variance', () {
      final s = ComplexStats();
      for (final v in [1.0, 2.0, 3.0, 4.0]) {
        s.add(v, -v);
      }
      expect(s.n, equals(4));
      expect(s.meanRe, closeTo(2.5, 1e-12));
      expect(s.meanIm, closeTo(-2.5, 1e-12));
      expect(s.varRe, closeTo(5 / 3, 1e-12));
    });

    test('reset clears everything', () {
      final s = ComplexStats()..add(3, 4)..add(5, 6);
      s.reset();
      expect(s.n, equals(0));
      expect(s.varRe, equals(0));
      s.add(1, 1);
      expect(s.meanRe, equals(1));
    });
  });

  test('complexDivide', () {
    final (re, im) = complexDivide(1, 1, 0, 1)!; // (1+j)/j = 1 - j
    expect(re, closeTo(1, 1e-12));
    expect(im, closeTo(-1, 1e-12));
    expect(complexDivide(1, 1, 0, 0), isNull);
  });

  group('estimatePhaseFromTilts', () {
    for (final truth in [-170.0, -90.0, -40.0, -12.5, 0.0, 3.0, 12.0, 44.0, 135.0, 180.0]) {
      test('recovers $truth° from a positive and a negative tilt', () {
        final e = estimatePhaseFromTilts(
            positive: capture(0.1, phaseDeg: truth, seed: 1),
            negative: capture(-0.1, phaseDeg: truth, seed: 2))!;
        expect(wrapDegrees(e.angleDeg - truth).abs(), lessThan(0.1));
        expect(e.confident, isTrue);
        expect(e.singleSided, isFalse);
      });

      test('recovers $truth° from a positive tilt alone', () {
        final e = estimatePhaseFromTilts(
            positive: capture(0.1, phaseDeg: truth, seed: 1))!;
        expect(wrapDegrees(e.angleDeg - truth).abs(), lessThan(0.5));
        expect(e.singleSided, isTrue);
      });

      test('recovers $truth° from a negative tilt alone', () {
        final e = estimatePhaseFromTilts(
            negative: capture(-0.1, phaseDeg: truth, seed: 2))!;
        expect(wrapDegrees(e.angleDeg - truth).abs(), lessThan(0.5));
        expect(e.singleSided, isTrue);
      });
    }

    test('two tilts cancel the zero offset, one does not', () {
      final both = estimatePhaseFromTilts(
          positive: capture(0.1, zero: 0.001, phaseDeg: 30, seed: 1),
          negative: capture(-0.1, zero: 0.001, phaseDeg: 30, seed: 2))!;
      expect(both.angleDeg, closeTo(30, 0.1));
      // An offset that is not along the signal (e.g. a crosstalk term).
      ComplexStats offset(double tilt, int seed) {
        final s = capture(tilt, zero: 0, phaseDeg: 30, seed: seed);
        final r = ComplexStats();
        for (var i = 0; i < 300; i++) {
          r.add(s.meanRe + 0.002, s.meanIm - 0.002);
        }
        return r;
      }

      final withOffsetBoth =
          estimatePhaseFromTilts(positive: offset(0.1, 1), negative: offset(-0.1, 2))!;
      final withOffsetOne = estimatePhaseFromTilts(positive: offset(0.1, 1))!;
      expect((withOffsetBoth.angleDeg - 30).abs(),
          lessThan((withOffsetOne.angleDeg - 30).abs()));
      expect(withOffsetBoth.angleDeg, closeTo(30, 0.1));
    });

    test('does not depend on the tilt size', () {
      final small = estimatePhaseFromTilts(
          positive: capture(0.02, seed: 1), negative: capture(-0.02, seed: 2))!;
      final large = estimatePhaseFromTilts(
          positive: capture(1.0, seed: 1), negative: capture(-1.0, seed: 2))!;
      expect(small.angleDeg, closeTo(large.angleDeg, 0.3));
    });

    test('a tilt buried in noise has low confidence and a wide error', () {
      final e = estimatePhaseFromTilts(
        positive: capture(0.01, noise: 5e-3, n: 40, seed: 1),
        negative: capture(-0.01, noise: 5e-3, n: 40, seed: 2),
      )!;
      expect(e.confident, isFalse);
      expect(e.uncertaintyDeg, greaterThan(1));
    });

    test('uncertainty shrinks with a bigger tilt', () {
      final a = estimatePhaseFromTilts(
          positive: capture(0.02, noise: 1e-4, seed: 1),
          negative: capture(-0.02, noise: 1e-4, seed: 2))!;
      final b = estimatePhaseFromTilts(
          positive: capture(0.5, noise: 1e-4, seed: 1),
          negative: capture(-0.5, noise: 1e-4, seed: 2))!;
      expect(b.uncertaintyDeg, lessThan(a.uncertaintyDeg));
      expect(b.snr, greaterThan(a.snr));
    });

    test('too few samples, nothing or no signal gives null', () {
      expect(estimatePhaseFromTilts(), isNull);
      expect(estimatePhaseFromTilts(positive: capture(0.1, n: 3)), isNull);
      expect(
          estimatePhaseFromTilts(
              positive: capture(0.1), negative: capture(-0.1, n: 3)),
          isNull);
      final zero = ComplexStats();
      for (var i = 0; i < 10; i++) {
        zero.add(0, 0);
      }
      expect(estimatePhaseFromTilts(positive: zero), isNull);
      expect(estimatePhaseFromTilts(positive: zero, negative: zero), isNull);
    });

    test('rotated keeps the estimate in (−180°, 180°]', () {
      final e = estimatePhaseFromTilts(
          positive: capture(0.1, phaseDeg: 100, seed: 1))!;
      expect(e.rotated(180).angleDeg, closeTo(-80, 0.1));
      expect(e.rotated(-180).angleDeg, closeTo(-80, 0.1));
      expect(wrapDegrees(540), closeTo(180, 1e-9));
      expect(wrapDegrees(-180), closeTo(180, 1e-9));
    });
  });

  group('estimateGain', () {
    test('k scales with the measured over the true step', () {
      // Reads 0.0900 for a true 0.1000 step: the old k is 10 % too large.
      final g = estimateGain(
          kOldMicro: 50000, baseline: 0.01, tilted: 0.10, trueTilt: 0.1)!;
      expect(g.measuredChange, closeTo(0.09, 1e-12));
      expect(g.kNewMicro, equals(45000));
      expect(g.changePercent, closeTo(-10, 1e-9));
      expect(g.positive, isTrue);
      expect(g.inRange, isTrue);
    });

    test('a negative step still gives k from the magnitude, flagged', () {
      final g = estimateGain(
          kOldMicro: 50000, baseline: 0.0, tilted: -0.1, trueTilt: 0.1)!;
      expect(g.kNewMicro, equals(50000));
      expect(g.positive, isFalse);
    });

    test('no change or no known tilt gives null', () {
      expect(
          estimateGain(
              kOldMicro: 50000, baseline: 0.1, tilted: 0.1, trueTilt: 0.1),
          isNull);
      expect(
          estimateGain(
              kOldMicro: 50000, baseline: 0, tilted: 0.1, trueTilt: 0),
          isNull);
    });

    test('flags a k outside the instrument range', () {
      final g = estimateGain(
          kOldMicro: 900000, baseline: 0, tilted: 0.5, trueTilt: 0.1)!;
      expect(g.kNewMicro, greaterThan(1000000));
      expect(g.inRange, isFalse);
    });
  });

  test('shimTilt: 0.1 mm under a 1 m edge is 0.1 mm/m', () {
    expect(shimTilt(0.1, 1000), closeTo(0.1, 1e-12));
    expect(shimTilt(0.1, 500), closeTo(0.2, 1e-12));
    expect(shimTilt(0.1, 0), equals(0));
  });
}
