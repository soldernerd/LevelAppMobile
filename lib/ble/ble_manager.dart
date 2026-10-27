import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/models/connection.dart';

/// Scanning, and opening links to devices.
///
/// [RealBleManager] talks to devices over `flutter_blue_plus`;
/// [MockBleManager] puts simulated devices behind the same interface for
/// tests and for running without hardware. The concrete class is chosen once,
/// in `main.dart`; nothing else in the app imports `flutter_blue_plus`.
///
/// This layer knows nothing about what a device *is*: it finds advertisers and
/// opens one [DeviceConnection] per device, any number at a time. Identifying
/// the device and choosing a driver for it is `DeviceRegistry`'s job, on top
/// of the connection.
abstract class BleManager {
  /// Emits [ScannedDevice] entries while a scan is active.
  Stream<ScannedDevice> get scanResults;

  /// Whether a scan is running (false again when it times out or is stopped).
  Stream<bool> get scanning;

  /// Starts a scan. Only advertisers whose name satisfies [accept] are
  /// reported (all named ones if null).
  Future<void> startScan({bool Function(String name)? accept});
  Future<void> stopScan();

  /// Connects to [deviceId] at the transport level (GATT, notifications) and
  /// returns the open link. Several can be open at once.
  Future<DeviceConnection> open(String deviceId);

  void dispose();
}
