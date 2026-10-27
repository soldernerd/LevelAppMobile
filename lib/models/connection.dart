import 'package:flutter/foundation.dart';

/// What the app is doing over BLE: scanning, connecting, holding at least one
/// open device, or having lost the last one.
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

  // Identity is the device's BLE address / peripheral UUID only; name and
  // rssi change on every advertisement.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScannedDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
