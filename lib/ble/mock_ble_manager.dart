import 'dart:async';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

/// Phase 1 compile-target stub.
///
/// All methods throw [UnimplementedError] with a "Phase 2:" prefix except
/// [dispose], which must not throw (called on cleanup regardless of state).
///
/// Phase 2 will replace these stubs with StreamController-based random-walk
/// behaviour, a simulated ~300ms connect delay, and a simulateDisconnect()
/// debug method.
class MockBleManager implements BleManager {
  @override
  Stream<ScannedDevice> get scanResults =>
      throw UnimplementedError('Phase 2: scanResults');

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      throw UnimplementedError('Phase 2: connectionStatus');

  @override
  Stream<List<int>> get statePackets =>
      throw UnimplementedError('Phase 2: statePackets');

  @override
  Future<void> startScan() => throw UnimplementedError('Phase 2: startScan');

  @override
  Future<void> stopScan() => throw UnimplementedError('Phase 2: stopScan');

  @override
  Future<void> connect(String deviceId) =>
      throw UnimplementedError('Phase 2: connect');

  @override
  Future<void> disconnect() => throw UnimplementedError('Phase 2: disconnect');

  @override
  Future<void> sendCommand(int commandByte) =>
      throw UnimplementedError('Phase 2: sendCommand');

  @override
  void dispose() {}
}
