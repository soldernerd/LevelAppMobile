import 'package:inclinometer/models/device_state.dart';

/// Abstract interface for all BLE operations.
///
/// [RealBleManager] talks to the instrument over `flutter_blue_plus`;
/// [MockBleManager] drives the UI with synthetic data for tests and for
/// running without hardware. The concrete class is chosen once, in
/// `main.dart`, via a `ProviderScope` override — nothing else in the app
/// imports `flutter_blue_plus`. That import isolation boundary lives here.
abstract class BleManager {
  /// Emits [ScannedDevice] entries while a scan is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state for the instrument.
  Stream<ConnectionStatus> get connectionStatus;

  /// Live merged instrument snapshots. Emits `null` as a stale-data sentinel
  /// on disconnect/error so the UI never shows last-known values as live.
  Stream<DeviceState?> get deviceStream;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();

  void dispose();
}
