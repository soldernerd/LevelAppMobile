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
/// `Environmental` (0x5/0x00) and `Device status` (0x5/0x01).
///
/// **Tilt is not part of this firmware build.** REV B senses tilt through an
/// analog front-end whose angle math is not yet implemented, and the REV A
/// SCL3300 path was removed. [angleX]/[angleY] are therefore always null here
/// and surface in the UI as an explicit "not available" placeholder — the
/// field is kept so a future firmware Measurement resource is a small change.
@immutable
class DeviceState {
  const DeviceState({
    this.angleX,
    this.angleY,
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

  /// Placeholder — never populated by the current firmware (see class doc).
  final double? angleX;
  final double? angleY;

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
          angleX == other.angleX &&
          angleY == other.angleY &&
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
        angleX,
        angleY,
        batteryPercent,
        batteryMillivolts,
        batteryState,
        onboardTempC,
        externalTempC,
        bme280TempC,
        pressurePa,
        humidityPct,
        bme280Fresh,
        usbConnected,
        charging,
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
