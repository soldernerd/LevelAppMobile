import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/instrument_api.dart';
import 'package:inclinometer/ble/simulated_device.dart';
import 'package:inclinometer/models/device_state.dart';

/// A [BleManager] with a [SimulatedDevice] behind it, for tests and for
/// running the app without hardware. Scanning finds one fake instrument;
/// connecting takes ~300 ms and verifies the simulated API version exactly
/// like the real manager does.
///
/// [sim] exposes the simulator's test hooks (physical tilt, service mode,
/// battery, a disturbed table, …). [simulateDisconnect] is a debug escape
/// hatch, not part of [BleManager].
class MockBleManager implements BleManager {
  MockBleManager({
    Random? random,
    SimulatedDevice? device,
    this.connectDelay = const Duration(milliseconds: 300),
  }) : sim = device ?? SimulatedDevice(random: random) {
    sim.onLinkDown = _onSimLinkDown;
  }

  /// A mock for running the app by hand: the simulated tilt wanders a little
  /// so the live screen is not frozen. (Tests use the plain constructor, whose
  /// tilt only changes when the test says so.)
  factory MockBleManager.demo() =>
      MockBleManager(device: SimulatedDevice(noise: 0.0004)..wander = true);

  final SimulatedDevice sim;
  final Duration connectDelay;

  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  Timer? _scanTimer;
  bool _connected = false;

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Future<void> startScan() async {
    _scanTimer?.cancel();
    _statusController.add(ConnectionStatus.scanning);
    _scanTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_scanController.isClosed) {
        _scanController.add(const ScannedDevice(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Leveltronic-EEFF',
          rssi: -65,
        ));
      }
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.idle);
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_statusController.isClosed) return;
    _statusController.add(ConnectionStatus.connecting);
    await Future<void>.delayed(connectDelay);
    if (_statusController.isClosed) return;
    _connected = true;
    try {
      await InstrumentApi(this).verifyCompatible();
    } catch (_) {
      _connected = false;
      rethrow;
    }
    _statusController.add(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    if (_statusController.isClosed) return;
    _statusController.add(ConnectionStatus.disconnecting);
    _connected = false;
    sim.linkDown();
    _statusController.add(ConnectionStatus.disconnected);
  }

  /// Debug-only: the link drops without being asked to.
  void simulateDisconnect() {
    // _onSimLinkDown reports the loss while _connected is still true.
    sim.linkDown();
  }

  void _onSimLinkDown() {
    if (_connected && !_statusController.isClosed) {
      _connected = false;
      _statusController.add(ConnectionStatus.disconnected);
    }
  }

  @override
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    if (!_connected) throw const LinkException('not connected');
    return sim.request(opcode, payload, timeout);
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) {
    if (!_connected) {
      return Stream<Uint8List>.error(const LinkException('not connected'));
    }
    return sim.subscribe(subscribeOpcode,
        intervalMs: intervalMs, payload: payload);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    sim.dispose();
    _scanController.close();
    _statusController.close();
  }
}
