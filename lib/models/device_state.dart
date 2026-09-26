import 'package:flutter/foundation.dart';

import 'package:inclinometer/ble/api_v2.dart';

/// Connection state machine for the BLE instrument.
enum ConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnecting,
  disconnected,
  error,
  reconnecting,
}

/// A live snapshot of the instrument, merged from the API v2 topic groups
/// `Environmental` (0x5/0x00), `Device status` (0x5/0x01) and `Raw
/// displacement` (0x5/0x03), plus the `dispOk` measurement (0x4/0x0D).
///
/// The instrument measures displacement at two capacitive sensors (S1/S2),
/// not a single tilt angle — [displacementS1Mm]/[displacementS2Mm] are the
/// live readings. They (and the residuals/quality flags) are only meaningful
/// while [displacementOk] is true; the demod may not be running yet (see
/// [RealBleManager._ensureDemodRunning]).
@immutable
class DeviceState {
  const DeviceState({
    this.displacementS1Mm,
    this.displacementS2Mm,
    this.residualS1,
    this.residualS2,
    this.displacementOk = false,
    this.quality1Ok = true,
    this.quality2Ok = true,
    required this.batteryPercent,
    required this.batteryMillivolts,
    required this.batteryState,
    this.onboardTempC,
    this.externalTempC,
    this.bme280TempC,
    this.pressurePa,
    this.humidityPct,
    this.bme280Fresh = false,
    this.usbConnected = false,
    this.charging = false,
  });

  /// Sensor 1 displacement, mm, pre-moving-average (Topic groups 0x5/0x03).
  /// Null until the first push arrives.
  final double? displacementS1Mm;

  /// Sensor 2 displacement, mm, pre-moving-average.
  final double? displacementS2Mm;

  /// Im(x1)/Im(x2) — should sit near 0; a consistently nonzero value usually
  /// means a Calibrations constant is off. Diagnostic, not shown prominently.
  final double? residualS1;
  final double? residualS2;

  /// Whether the displacement readings are currently meaningful (the demod
  /// is running and healthy — Measurements 0x4/0x0D).
  final bool displacementOk;

  /// False flags the most recent S1/S2 batch as a statistically-likely
  /// glitch — a soft warning, not a hard error.
  final bool quality1Ok;
  final bool quality2Ok;

  /// Battery state of charge, 0–100 %.
  final int batteryPercent;

  /// Battery terminal voltage in millivolts.
  final int batteryMillivolts;

  final BatteryState batteryState;

  /// On-board TMP236 temperature, °C. Null if never reported.
  final double? onboardTempC;

  /// External LM35 probe temperature, °C. Null if absent / out of range.
  final double? externalTempC;

  /// BME280 ambient temperature, °C. Null if never reported.
  final double? bme280TempC;

  /// BME280 barometric pressure, pascals. Null if never reported.
  final int? pressurePa;

  /// BME280 relative humidity, %RH. Null if never reported.
  final double? humidityPct;

  /// Whether the last BME280 reading is current (sensor present and fresh).
  final bool bme280Fresh;

  /// USB power present at the instrument.
  final bool usbConnected;

  /// Charger active (TP4056 CHRG).
  final bool charging;

  /// Barometric pressure in hectopascals (mbar), or null.
  double? get pressureHpa => pressurePa == null ? null : pressurePa! / 100.0;

  DeviceState copyWith({
    double? displacementS1Mm,
    double? displacementS2Mm,
    double? residualS1,
    double? residualS2,
    bool? displacementOk,
    bool? quality1Ok,
    bool? quality2Ok,
    int? batteryPercent,
    int? batteryMillivolts,
    BatteryState? batteryState,
    double? onboardTempC,
    double? externalTempC,
    double? bme280TempC,
    int? pressurePa,
    double? humidityPct,
    bool? bme280Fresh,
    bool? usbConnected,
    bool? charging,
  }) {
    return DeviceState(
      displacementS1Mm: displacementS1Mm ?? this.displacementS1Mm,
      displacementS2Mm: displacementS2Mm ?? this.displacementS2Mm,
      residualS1: residualS1 ?? this.residualS1,
      residualS2: residualS2 ?? this.residualS2,
      displacementOk: displacementOk ?? this.displacementOk,
      quality1Ok: quality1Ok ?? this.quality1Ok,
      quality2Ok: quality2Ok ?? this.quality2Ok,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryMillivolts: batteryMillivolts ?? this.batteryMillivolts,
      batteryState: batteryState ?? this.batteryState,
      onboardTempC: onboardTempC ?? this.onboardTempC,
      externalTempC: externalTempC ?? this.externalTempC,
      bme280TempC: bme280TempC ?? this.bme280TempC,
      pressurePa: pressurePa ?? this.pressurePa,
      humidityPct: humidityPct ?? this.humidityPct,
      bme280Fresh: bme280Fresh ?? this.bme280Fresh,
      usbConnected: usbConnected ?? this.usbConnected,
      charging: charging ?? this.charging,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          displacementS1Mm == other.displacementS1Mm &&
          displacementS2Mm == other.displacementS2Mm &&
          residualS1 == other.residualS1 &&
          residualS2 == other.residualS2 &&
          displacementOk == other.displacementOk &&
          quality1Ok == other.quality1Ok &&
          quality2Ok == other.quality2Ok &&
          batteryPercent == other.batteryPercent &&
          batteryMillivolts == other.batteryMillivolts &&
          batteryState == other.batteryState &&
          onboardTempC == other.onboardTempC &&
          externalTempC == other.externalTempC &&
          bme280TempC == other.bme280TempC &&
          pressurePa == other.pressurePa &&
          humidityPct == other.humidityPct &&
          bme280Fresh == other.bme280Fresh &&
          usbConnected == other.usbConnected &&
          charging == other.charging;

  @override
  int get hashCode => Object.hash(
        Object.hash(displacementS1Mm, displacementS2Mm, residualS1, residualS2),
        Object.hash(displacementOk, quality1Ok, quality2Ok),
        Object.hash(batteryPercent, batteryMillivolts, batteryState),
        Object.hash(onboardTempC, externalTempC, bme280TempC),
        Object.hash(pressurePa, humidityPct, bme280Fresh),
        Object.hash(usbConnected, charging),
      );
}

/// A BLE device discovered during a scan.
@immutable
class ScannedDevice {
  final String id;
  final String name;
  final int rssi;

  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  // Identity is the device's BLE address / peripheral UUID only.
  // name and rssi are mutable attributes — rssi changes on every advertisement,
  // so including it would treat the same physical device as a different device
  // across consecutive scan results.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScannedDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
