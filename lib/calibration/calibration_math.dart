/// The arithmetic of the phase and gain calibration wizards, as pure
/// functions so it is unit-tested against the simulator's known truth.
///
/// Model (firmware `Math/math_displacement.c`): per batch and sensor
/// `u = S / D` with `D = A − B`; a real tilt moves `u` along `e^{jφ}`, φ being
/// the sensor's signal phase. The firmware derotates by the stored phase,
/// `x = u·e^{−jφcal}`, and reports `tilt = (Re x − zero) / k`.
library;

import 'dart:math';

/// Running mean / variance of a complex quantity (Welford).
class ComplexStats {
  int n = 0;
  double meanRe = 0, meanIm = 0;
  double _m2Re = 0, _m2Im = 0;

  void reset() {
    n = 0;
    meanRe = 0;
    meanIm = 0;
    _m2Re = 0;
    _m2Im = 0;
  }

  void add(double re, double im) {
    n++;
    final dr = re - meanRe;
    meanRe += dr / n;
    _m2Re += dr * (re - meanRe);
    final di = im - meanIm;
    meanIm += di / n;
    _m2Im += di * (im - meanIm);
  }

  double get varRe => n > 1 ? _m2Re / (n - 1) : 0;
  double get varIm => n > 1 ? _m2Im / (n - 1) : 0;
}

/// `(sr + j·si) / (dr + j·di)`, or null if the divisor is (nearly) zero.
(double, double)? complexDivide(double sr, double si, double dr, double di) {
  final d = dr * dr + di * di;
  if (d < 1e-12) return null;
  return ((sr * dr + si * di) / d, (si * dr - sr * di) / d);
}

/// The result of comparing two captures of `u`: a flat reference and a known
/// tilt step.
class PhaseEstimate {
  const PhaseEstimate({
    required this.angleDeg,
    required this.uncertaintyDeg,
    required this.snr,
    required this.stepMagnitude,
  });

  /// The signal phase, folded to (−90°, 90°].
  final double angleDeg;

  /// 1σ uncertainty of [angleDeg].
  final double uncertaintyDeg;

  /// |Δu| over the standard error perpendicular to it.
  final double snr;

  /// |Δu|, the size of the step in the ratio plane.
  final double stepMagnitude;

  /// The instrument stores the phase in ±45°.
  bool get inRange => angleDeg.abs() <= 45.0;

  /// Stored unit: 0.01°.
  int get centiDegrees => (angleDeg * 100).round().clamp(-4500, 4500);

  /// Good enough to apply without a second thought.
  bool get confident => snr >= 8 && uncertaintyDeg <= 0.5;
}

/// Phase from a tilt step: the direction of `Δu = u_tilted − u_flat`, folded
/// into (−90°, 90°] (the sign of the step is the invert flag's business, not
/// the phase's). Null if either capture is too short or there is no step.
PhaseEstimate? estimatePhase(ComplexStats flat, ComplexStats tilted) {
  if (flat.n < 5 || tilted.n < 5) return null;
  final dRe = tilted.meanRe - flat.meanRe;
  final dIm = tilted.meanIm - flat.meanIm;
  final mag = sqrt(dRe * dRe + dIm * dIm);
  if (mag == 0) return null;

  var a = atan2(dIm, dRe) * 180 / pi;
  while (a > 90) {
    a -= 180;
  }
  while (a <= -90) {
    a += 180;
  }

  final seRe = sqrt(flat.varRe / flat.n + tilted.varRe / tilted.n);
  final seIm = sqrt(flat.varIm / flat.n + tilted.varIm / tilted.n);
  final ux = dRe / mag, uy = dIm / mag;
  // Error component perpendicular to the step direction.
  final sePerp = sqrt(pow(seRe * uy, 2) + pow(seIm * ux, 2));
  final unc = atan2(sePerp, mag) * 180 / pi;
  final snr = sePerp == 0 ? 1e9 : mag / sePerp;
  return PhaseEstimate(
    angleDeg: a,
    uncertaintyDeg: unc,
    snr: snr,
    stepMagnitude: mag,
  );
}

/// The result of a gain (sensitivity k) calibration step.
class GainEstimate {
  const GainEstimate({
    required this.measuredChange,
    required this.trueTilt,
    required this.kOldMicro,
    required this.kNewMicro,
  });

  /// Reading with the known tilt applied minus the baseline reading.
  final double measuredChange;

  /// The known tilt step (mm/m), always positive.
  final double trueTilt;
  final int kOldMicro;

  /// New k in the instrument's unit (1e-6 per mm/m), rounded.
  final int kNewMicro;

  /// kNew / kOld — 1.0 means the old calibration was already right.
  double get factor => kNewMicro / kOldMicro;

  /// Percent change of k.
  double get changePercent => (factor - 1) * 100;

  bool get inRange => kNewMicro >= 100 && kNewMicro <= 1000000;

  /// The measured step has the sign a positive step should have. When it
  /// does not, the invert flag (or the shim direction) is the suspect.
  bool get positive => measuredChange > 0;
}

/// k from a baseline and a known-tilt reading:
/// `reading = (ratio − zero) / k`, so the ratio step is `Δm·kOld`, which the
/// true tilt `T` produces with `kTrue` — `kTrue = kOld·|Δm| / T`.
GainEstimate? estimateGain({
  required int kOldMicro,
  required double baseline,
  required double tilted,
  required double trueTilt,
}) {
  final change = tilted - baseline;
  if (trueTilt <= 0 || change.abs() < 1e-6) return null;
  final kNew = (kOldMicro * change.abs() / trueTilt).round();
  return GainEstimate(
    measuredChange: change,
    trueTilt: trueTilt,
    kOldMicro: kOldMicro,
    kNewMicro: kNew,
  );
}

/// Tilt in mm/m of a shim of [heightMm] under one end of a baseline of
/// [baselineMm] (1000 mm = 1 m → h mm over 1 m is h mm/m).
double shimTilt(double heightMm, double baselineMm) =>
    baselineMm <= 0 ? 0 : heightMm / baselineMm * 1000.0;
