import 'package:inclinometer/models/device_state.dart';

/// Abstract interface for all BLE operations.
///
/// WP1 uses [MockBleManager]; WP2 swaps in RealBleManager via a single
/// ProviderScope.overrides change in main.dart.
///
/// No flutter_blue_plus import — ever. The isolation boundary is here.
abstract class BleManager {
  /// Emits [ScannedDevice] entries while a scan is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state for the paired instrument.
  Stream<ConnectionStatus> get connectionStatus;

  /// Raw 9-byte state packets from the instrument characteristic.
  Stream<List<int>> get statePackets;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendCommand(int commandByte);

  void dispose();
}
