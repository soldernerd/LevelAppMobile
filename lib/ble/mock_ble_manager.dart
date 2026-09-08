import 'dart:async';
import 'dart:math';

import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

/// Synthetic [BleManager] for tests and for running the app without hardware.
///
/// Produces an animated random-walk [DeviceState] behind the [BleManager]
/// interface: battery slowly drains, temperatures / humidity / pressure
/// wander. Tilt is left null — the real firmware has no tilt output either,
/// so the UI placeholder path is exercised identically.
///
/// Inject a seeded [Random] for deterministic tests:
/// ```dart
/// final mock = MockBleManager(random: Random(0));
/// ```
///
/// [simulateDisconnect] is a debug escape hatch, not part of [BleManager] —
/// only code holding a concrete [MockBleManager] reference may call it.
class MockBleManager implements BleManager {
  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _deviceController = StreamController<DeviceState?>.broadcast();

  double _onboardTemp = 24.5;
  double _externalTemp = 22.0;
  double _bmeTemp = 23.8;
  double _humidity = 41.0;
  int _pressurePa = 96_400;
  int _batteryPct = 85;
  int _batteryMv = 4020;
  int _tickCount = 0;

  Timer? _ticker;
  Timer? _scanTimer;

  final Random _rng;

  MockBleManager({Random? random}) : _rng = random ?? Random();

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<DeviceState?> get deviceStream => _deviceController.stream;

  @override
  Future<void> startScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
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
    _stopTicker();
    if (_statusController.isClosed) return;
    _statusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 300));
    _tickCount = 0;
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.connected);
      _startTicker();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_statusController.isClosed) return;
    _statusController.add(ConnectionStatus.disconnecting);
    _stopTicker();
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.disconnected);
    }
    if (!_deviceController.isClosed) {
      _deviceController.add(null); // stale sentinel
    }
  }

  /// Debug-only: simulates an involuntary disconnect.
  void simulateDisconnect() {
    _stopTicker();
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.disconnected);
    }
    if (!_deviceController.isClosed) {
      _deviceController.add(null);
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _scanTimer?.cancel();
    _scanController.close();
    _statusController.close();
    _deviceController.close();
  }

  // --- internals ---------------------------------------------------------

  double _walk(double v, double step, double lo, double hi) =>
      (v + (_rng.nextDouble() - 0.5) * step).clamp(lo, hi);

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_deviceController.isClosed) return;
      _onboardTemp = _walk(_onboardTemp, 0.15, 15, 40);
      _externalTemp = _walk(_externalTemp, 0.2, -10, 45);
      _bmeTemp = _walk(_bmeTemp, 0.15, 15, 40);
      _humidity = _walk(_humidity, 0.6, 20, 80);
      _pressurePa = (_pressurePa + (_rng.nextInt(21) - 10)).clamp(94_000, 99_000);
      _tickCount++;
      if (_tickCount % 40 == 0) {
        _batteryPct = (_batteryPct - 1).clamp(0, 100);
        _batteryMv = (_batteryMv - 4).clamp(3300, 4200);
      }
      _deviceController.add(DeviceState(
        batteryPercent: _batteryPct,
        batteryMillivolts: _batteryMv,
        batteryState:
            _batteryPct <= 10 ? BatteryState.low : BatteryState.normal,
        onboardTempC: _onboardTemp,
        externalTempC: _externalTemp,
        bme280TempC: _bmeTemp,
        pressurePa: _pressurePa,
        humidityPct: _humidity,
        bme280Fresh: true,
        usbConnected: false,
        charging: false,
      ));
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
