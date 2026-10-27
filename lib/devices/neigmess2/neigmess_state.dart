import 'package:flutter/foundation.dart';

import 'package:inclinometer/devices/neigmess2/protocol.dart';

/// A live snapshot of the NeigMess2, merged from the topic and measurement
/// subscriptions the app keeps while connected, plus the calibrations as last
/// read. Any part is null until its first reading arrives.
@immutable
class NeigMessState {
  const NeigMessState({
    this.sensors,
    this.tilt,
    this.plateCapPf,
    this.tiltStatus,
    this.offsets,
    this.trim,
    this.neutralCapPf,
    this.zeroRoutine,
  });

  final NmSensors? sensors;

  /// µm/m of the centre sensor, trimmed; 0 unless [tiltStatus] is ok.
  final double? tilt;
  final double? plateCapPf;
  final NmTiltStatus? tiltStatus;
  final NmZeroOffsets? offsets;
  final NmTiltTrim? trim;

  /// Calibrations 0x03, pF.
  final double? neutralCapPf;

  /// The flip-test zero routine (idle when it is not running).
  final NmZeroRoutine? zeroRoutine;

  NeigMessState copyWith({
    NmSensors? sensors,
    double? tilt,
    double? plateCapPf,
    NmTiltStatus? tiltStatus,
    NmZeroOffsets? offsets,
    NmTiltTrim? trim,
    double? neutralCapPf,
    NmZeroRoutine? zeroRoutine,
  }) => NeigMessState(
    sensors: sensors ?? this.sensors,
    tilt: tilt ?? this.tilt,
    plateCapPf: plateCapPf ?? this.plateCapPf,
    tiltStatus: tiltStatus ?? this.tiltStatus,
    offsets: offsets ?? this.offsets,
    trim: trim ?? this.trim,
    neutralCapPf: neutralCapPf ?? this.neutralCapPf,
    zeroRoutine: zeroRoutine ?? this.zeroRoutine,
  );

  bool get hasTilt => tiltStatus == NmTiltStatus.ok && tilt != null;

  /// Sensor [i] above its zero position, in pF (nominal Cref).
  double? sensorPf(int i) {
    final s = sensors;
    if (s == null) return null;
    final off = offsets?.units[i] ?? 0;
    return (s.units[i] - off) * kUnitToPf;
  }

  double? get angleXDeg => sensors?.angleXDeg;
  double? get angleYDeg => sensors?.angleYDeg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NeigMessState &&
          identical(sensors, other.sensors) &&
          tilt == other.tilt &&
          plateCapPf == other.plateCapPf &&
          tiltStatus == other.tiltStatus &&
          identical(offsets, other.offsets) &&
          identical(trim, other.trim) &&
          neutralCapPf == other.neutralCapPf &&
          zeroRoutine == other.zeroRoutine;

  @override
  int get hashCode => Object.hash(
    identityHashCode(sensors),
    tilt,
    plateCapPf,
    tiltStatus,
    identityHashCode(offsets),
    identityHashCode(trim),
    neutralCapPf,
    zeroRoutine,
  );
}
