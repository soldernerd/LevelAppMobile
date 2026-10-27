import 'package:flutter/foundation.dart';

import 'package:inclinometer/devices/neigmess2/protocol.dart';

/// A live snapshot of the NeigMess2, merged from the topic and measurement
/// subscriptions the app keeps while connected. Any part is null until its
/// first reading arrives.
@immutable
class NeigMessState {
  const NeigMessState({
    this.sensors,
    this.tilt,
    this.plateCapPf,
    this.tiltStatus,
    this.offsets,
  });

  final NmSensors? sensors;

  /// µm/m of the centre sensor, trimmed; 0 unless [tiltStatus] is ok.
  final double? tilt;
  final double? plateCapPf;
  final NmTiltStatus? tiltStatus;
  final NmZeroOffsets? offsets;

  NeigMessState copyWith({
    NmSensors? sensors,
    double? tilt,
    double? plateCapPf,
    NmTiltStatus? tiltStatus,
    NmZeroOffsets? offsets,
  }) =>
      NeigMessState(
        sensors: sensors ?? this.sensors,
        tilt: tilt ?? this.tilt,
        plateCapPf: plateCapPf ?? this.plateCapPf,
        tiltStatus: tiltStatus ?? this.tiltStatus,
        offsets: offsets ?? this.offsets,
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
          identical(offsets, other.offsets);

  @override
  int get hashCode => Object.hash(identityHashCode(sensors), tilt, plateCapPf,
      tiltStatus, identityHashCode(offsets));
}
