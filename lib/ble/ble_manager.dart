import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/models/device_state.dart';

/// Scanning, connecting and the open link to the instrument.
///
/// [RealBleManager] talks to the instrument over `flutter_blue_plus`;
/// [MockBleManager] puts a simulated instrument behind the same interface for
/// tests and for running without hardware. The concrete class is chosen once,
/// in `main.dart`; nothing else in the app imports `flutter_blue_plus`.
///
/// The protocol itself lives above the [DeviceLink] this interface extends:
/// `InstrumentApi` (typed operations) and `LiveFeed` (the always-on
/// subscriptions) work on any link.
abstract class BleManager implements DeviceLink {
  /// Emits [ScannedDevice] entries while a scan is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state for the instrument.
  Stream<ConnectionStatus> get connectionStatus;

  Future<void> startScan();
  Future<void> stopScan();

  /// Connects and verifies the instrument speaks API v3. Throws
  /// `IncompatibleFirmwareException` (after dropping the connection) if not.
  Future<void> connect(String deviceId);
  Future<void> disconnect();

  void dispose();
}
