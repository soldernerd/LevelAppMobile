import 'package:flutter/foundation.dart';

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

/// Live angle and battery reading from the instrument.
@immutable
class DeviceState {
  final double angleX;
  final double angleY;
  final int battery;

  const DeviceState({
    required this.angleX,
    required this.angleY,
    required this.battery,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          angleX == other.angleX &&
          angleY == other.angleY &&
          battery == other.battery;

  @override
  int get hashCode => Object.hash(angleX, angleY, battery);
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
