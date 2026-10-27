import 'package:flutter/foundation.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';

/// A live snapshot of the instrument, merged from the three topics the app
/// keeps subscribed while connected: LIVE (the tilt reading and its quality
/// flags), STATUS (battery, charging, rails, activities, service mode) and
/// ENV (temperatures, humidity, pressure). Any part is null until its first
/// push arrives.
@immutable
class DeviceState {
  const DeviceState({this.live, this.status, this.env});

  final ApiLive? live;
  final ApiSystemState? status;
  final ApiEnvironmental? env;

  DeviceState copyWith({
    ApiLive? live,
    ApiSystemState? status,
    ApiEnvironmental? env,
  }) =>
      DeviceState(
        live: live ?? this.live,
        status: status ?? this.status,
        env: env ?? this.env,
      );

  // --- tilt ---
  /// A reading exists and the demodulation is delivering (LIVE flags bit0).
  bool get hasReading => live?.valid ?? false;
  double? get tiltS1 => live?.tiltS1;
  double? get tiltS2 => live?.tiltS2;
  double? get tiltDiff => live?.tiltDiff;
  bool get s1Doubtful => live?.s1Doubtful ?? false;
  bool get s2Doubtful => live?.s2Doubtful ?? false;

  /// The difference is only as good as both sensors.
  bool get diffDoubtful => s1Doubtful || s2Doubtful;

  // --- power ---
  int? get batteryPercent => status?.batterySocPct;
  int? get batteryMv => status?.batteryMv;
  BatteryState get batteryState =>
      status?.batteryState ?? BatteryState.unknown;
  bool get charging => status?.charging ?? false;
  bool get usbConnected => status?.usbConnected ?? false;
  bool get serviceMode => status?.serviceMode ?? false;
  bool get demodRunning => status?.demodRunning ?? true;

  // --- environment ---
  double? get onboardTempC => env?.onboardTempC;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          identical(live, other.live) &&
          identical(status, other.status) &&
          identical(env, other.env);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(live), identityHashCode(status),
          identityHashCode(env));
}
