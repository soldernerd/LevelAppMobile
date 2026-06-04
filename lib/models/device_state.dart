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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedDevice &&
          id == other.id &&
          name == other.name &&
          rssi == other.rssi;

  @override
  int get hashCode => Object.hash(id, name, rssi);
}
