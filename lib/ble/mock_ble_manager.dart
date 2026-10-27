import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/simulated_peripheral.dart';
import 'package:inclinometer/devices/leveltronic/simulated_device.dart';
import 'package:inclinometer/models/connection.dart';

/// A simulated device in range: what a scan finds and what [open] connects to.
class MockPeripheral {
  const MockPeripheral({
    required this.id,
    required this.name,
    required this.sim,
    this.rssi = -65,
  });

  final String id;
  final String name;
  final int rssi;
  final SimulatedPeripheral sim;
}

/// A [BleManager] with simulated devices behind it, for tests and for running
/// the app without hardware. A scan finds every peripheral (after ~500 ms);
/// opening one takes ~300 ms. Any number can be open at once.
///
/// The default constructor is the common case — one Leveltronic, reachable
/// under any id — and [sim] exposes its test hooks (physical tilt, service
/// mode, battery, a disturbed table, …). [withPeripherals] sets up several
/// devices, of any family. [simulateDisconnect] is a debug escape hatch, not
/// part of [BleManager].
class MockBleManager implements BleManager {
  MockBleManager({
    Random? random,
    SimulatedDevice? device,
    Duration connectDelay = const Duration(milliseconds: 300),
  }) : this.withPeripherals(
          [
            MockPeripheral(
              id: 'AA:BB:CC:DD:EE:FF',
              name: 'Leveltronic-EEFF',
              sim: device ?? SimulatedDevice(random: random),
            ),
          ],
          connectDelay: connectDelay,
        );

  MockBleManager.withPeripherals(
    this.peripherals, {
    this.connectDelay = const Duration(milliseconds: 300),
  }) : assert(peripherals.isNotEmpty);

  /// A mock for running the app by hand: the simulated tilt wanders a little
  /// so the live screen is not frozen. (Tests use the plain constructor, whose
  /// tilt only changes when the test says so.)
  factory MockBleManager.demo() =>
      MockBleManager(device: SimulatedDevice(noise: 0.0004)..wander = true);

  final List<MockPeripheral> peripherals;
  final Duration connectDelay;

  /// The first peripheral's simulator (the one of the default constructor).
  SimulatedDevice get sim => peripherals.first.sim as SimulatedDevice;

  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  final List<_MockConnection> _open = [];

  Timer? _scanTimer;

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<bool> get scanning => _scanningController.stream;

  @override
  Future<void> startScan({bool Function(String name)? accept}) async {
    _scanTimer?.cancel();
    _scanningController.add(true);
    _scanTimer = Timer(const Duration(milliseconds: 500), () {
      if (_scanController.isClosed) return;
      for (final p in peripherals) {
        if (accept != null && !accept(p.name)) continue;
        _scanController.add(ScannedDevice(id: p.id, name: p.name, rssi: p.rssi));
      }
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (!_scanningController.isClosed) _scanningController.add(false);
  }

  /// Opens the peripheral with [deviceId]; an unknown id reaches the first
  /// one, so tests can connect with any string.
  @override
  Future<DeviceConnection> open(String deviceId) async {
    await Future<void>.delayed(connectDelay);
    final p = peripherals.firstWhere((p) => p.id == deviceId,
        orElse: () => peripherals.first);
    final conn = _MockConnection(p);
    _open.add(conn);
    unawaited(conn.closed.then<void>((_) => _open.remove(conn)));
    return conn;
  }

  /// Debug-only: the link to [deviceId] (default: the first peripheral) drops
  /// without being asked to.
  void simulateDisconnect([String? deviceId]) {
    final p = peripherals.firstWhere((p) => p.id == deviceId,
        orElse: () => peripherals.first);
    p.sim.linkDown();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    for (final p in peripherals) {
      p.sim.dispose();
    }
    _scanController.close();
    _scanningController.close();
  }
}

class _MockConnection implements DeviceConnection {
  _MockConnection(this._peripheral) {
    _peripheral.sim.onLinkDown = _onSimLinkDown;
  }

  final MockPeripheral _peripheral;
  final _closed = Completer<void>();
  bool _up = true;

  @override
  String get id => _peripheral.id;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() async {
    if (!_up) return;
    _up = false;
    _peripheral.sim.onLinkDown = null;
    _peripheral.sim.linkDown();
    _closed.complete();
  }

  void _onSimLinkDown() {
    if (!_up) return;
    _up = false;
    _closed.complete();
  }

  @override
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    if (!_up) throw const LinkException('not connected');
    return _peripheral.sim.request(opcode, payload, timeout);
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) {
    if (!_up) {
      return Stream<Uint8List>.error(const LinkException('not connected'));
    }
    return _peripheral.sim.subscribe(subscribeOpcode,
        intervalMs: intervalMs, payload: payload);
  }
}
