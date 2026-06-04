import 'dart:async';
import 'dart:math';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';

/// WP1 mock implementation of [BleManager].
///
/// Produces animated random-walk angle and battery streams behind the
/// [BleManager] interface. All behaviour is testable without a device.
///
/// Inject a seeded [Random] via the constructor for deterministic tests:
/// ```dart
/// final mock = MockBleManager(random: Random(0));
/// ```
///
/// [simulateDisconnect] is a WP1-only debug escape hatch. It is NOT part of
/// the [BleManager] interface — only code with a concrete [MockBleManager]
/// reference may call it (e.g. a debug button in Phase 4 or a test).
class MockBleManager implements BleManager {
  // --- streams (eager-initialized broadcast controllers) ---
  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _packetController = StreamController<List<int>>.broadcast();

  // --- mutable state ---
  double _angleX = 0.0;
  double _angleY = 0.0;
  int _battery = 85;
  int _tickCount = 0;

  Timer? _ticker;
  Timer? _scanTimer;

  final Random _rng;

  MockBleManager({Random? random}) : _rng = random ?? Random();

  // --- BleManager interface ---

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<List<int>> get statePackets => _packetController.stream;

  @override
  Future<void> startScan() async {
    _scanTimer?.cancel(); // WR-01: cancel any in-flight scan timer
    _scanTimer = null;
    _statusController.add(ConnectionStatus.scanning);
    _scanTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_scanController.isClosed) {
        _scanController.add(const ScannedDevice(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Inclinometer',
          rssi: -65,
        ));
      }
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<void> connect(String deviceId) async {
    _stopTicker(); // CR-01: cancel any in-flight ticker before reconnecting
    if (_statusController.isClosed) return; // CR-02: guard async gap
    _statusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 300)); // D-05; CLAUDE.md constraint
    _angleX = 0.0; // reset on reconnect (Claude's discretion, D-12)
    _angleY = 0.0;
    _tickCount = 0;
    if (!_statusController.isClosed) { // CR-02: guard after async gap
      _statusController.add(ConnectionStatus.connected);
      _startTicker();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_statusController.isClosed) return; // CR-02: guard against post-dispose call
    _statusController.add(ConnectionStatus.disconnecting); // D-13
    _stopTicker();
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> sendCommand(int commandByte) async {
    if (commandByte == kCmdZeroX) _angleX = 0.0; // D-09
    if (commandByte == kCmdZeroY) _angleY = 0.0; // D-09
    // unknown commands: silent no-op (D-10)
  }

  /// WP1-only debug escape hatch. Simulates involuntary disconnect.
  /// NOT part of [BleManager] — only [MockBleManager] callers may call this
  /// (e.g. a debug button in Phase 4 or a test).
  void simulateDisconnect() {
    _stopTicker();
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.disconnected); // D-11
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _scanTimer?.cancel();
    _scanController.close();
    _statusController.close();
    _packetController.close();
  }

  // --- internal helpers ---

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_packetController.isClosed) return; // T-02-02: guard against post-dispose tick
      _angleX = (_angleX + (_rng.nextDouble() - 0.5) * 0.2).clamp(-45.0, 45.0); // D-02, D-03
      _angleY = (_angleY + (_rng.nextDouble() - 0.5) * 0.2).clamp(-45.0, 45.0); // D-02, D-03
      _tickCount++;
      if (_tickCount % 100 == 0) {
        _battery = (_battery - 1).clamp(0, 100); // D-04
      }
      _packetController.add(StatePacket.encode(_angleX, _angleY, _battery));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null; // null after cancel — prevents stale isActive checks
  }
}
