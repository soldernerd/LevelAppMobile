import 'dart:async';
import 'dart:math';

import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

/// Synthetic [BleManager] for tests and for running the app without hardware.
///
/// Produces an animated random-walk [DeviceState] behind the [BleManager]
/// interface: battery slowly drains, temperatures / humidity / pressure and
/// the two displacement sensors wander. Zero calibration and precision
/// measurement are simulated with the same phase machine the firmware uses
/// (see `docs/api-reference.md`), just compressed in time.
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

  double _s1Mm = 0.12;
  double _s2Mm = -0.08;

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
    _resetZeroCal();
    _resetPrecision();
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
    _resetZeroCal();
    _resetPrecision();
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
    _resetZeroCal();
    _resetPrecision();
    _scanController.close();
    _statusController.close();
    _deviceController.close();
  }

  // --- zero calibration (simulated) ---------------------------------------

  ZeroCalPhase _zeroCalPhase = ZeroCalPhase.idle;
  int _zeroCalProgress = 0;
  Timer? _zeroCalTimer;
  static const _zeroCalTarget = 32;

  @override
  Future<Api2Status> zeroCalibrationStep1() async {
    if (_zeroCalPhase != ZeroCalPhase.idle) return Api2Status.busyResource;
    _zeroCalPhase = ZeroCalPhase.step1Running;
    _zeroCalProgress = 0;
    _zeroCalTimer?.cancel();
    _zeroCalTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _zeroCalProgress = (_zeroCalProgress + 4).clamp(0, _zeroCalTarget);
      if (_zeroCalProgress >= _zeroCalTarget) {
        _zeroCalPhase = ZeroCalPhase.step1Done;
        _zeroCalTimer?.cancel();
      }
    });
    return Api2Status.ok;
  }

  @override
  Future<Api2Status> zeroCalibrationStep2() async {
    if (_zeroCalPhase != ZeroCalPhase.step1Done) return Api2Status.busyResource;
    _zeroCalPhase = ZeroCalPhase.step2Running;
    _zeroCalProgress = 0;
    _zeroCalTimer?.cancel();
    _zeroCalTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _zeroCalProgress = (_zeroCalProgress + 4).clamp(0, _zeroCalTarget);
      if (_zeroCalProgress >= _zeroCalTarget) {
        _zeroCalTimer?.cancel();
        _s1Mm = 0.0; // "persisted" zero offset — future readings settle near 0
        _s2Mm = 0.0;
        // Mirrors the real device: phase 4 (resultReady) is transient,
        // applied within one tick, then back to idle.
        _zeroCalPhase = ZeroCalPhase.idle;
      }
    });
    return Api2Status.ok;
  }

  @override
  Future<Api2Status> zeroCalibrationCancel() async {
    _resetZeroCal();
    return Api2Status.ok;
  }

  @override
  Future<Api2ZeroCalStatus?> pollZeroCalibration() async {
    return Api2ZeroCalStatus(
      phase: _zeroCalPhase,
      progress: _zeroCalProgress,
      target: _zeroCalTarget,
    );
  }

  void _resetZeroCal() {
    _zeroCalTimer?.cancel();
    _zeroCalTimer = null;
    _zeroCalPhase = ZeroCalPhase.idle;
    _zeroCalProgress = 0;
  }

  // --- triggered precision measurement (simulated) ------------------------

  PrecisionPhase _precisionPhase = PrecisionPhase.idle;
  int _precisionCount1 = 0;
  int _precisionCount2 = 0;
  int _precisionElapsedMs = 0;
  Timer? _precisionTimer;
  static const _precisionTarget = 64;

  @override
  Future<Api2Status> startPrecisionMeasurement() async {
    _precisionTimer?.cancel();
    _precisionPhase = PrecisionPhase.running;
    _precisionCount1 = 0;
    _precisionCount2 = 0;
    _precisionElapsedMs = 0;
    _precisionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _precisionElapsedMs += 100;
      _precisionCount1 = (_precisionCount1 + 8).clamp(0, _precisionTarget);
      _precisionCount2 = (_precisionCount2 + 8).clamp(0, _precisionTarget);
      if (_precisionCount1 >= _precisionTarget &&
          _precisionCount2 >= _precisionTarget) {
        _precisionPhase = PrecisionPhase.done;
        _precisionTimer?.cancel();
      }
    });
    return Api2Status.ok;
  }

  @override
  Future<Api2Status> cancelPrecisionMeasurement() async {
    _resetPrecision();
    return Api2Status.ok;
  }

  @override
  Future<Api2PrecisionStatus?> pollPrecisionMeasurement() async {
    return Api2PrecisionStatus(
      phase: _precisionPhase,
      target: _precisionTarget,
      count1: _precisionCount1,
      count2: _precisionCount2,
      elapsedMs: _precisionElapsedMs,
      timedOut: false,
      delta1Mm: _s1Mm,
      delta2Mm: _s2Mm,
    );
  }

  void _resetPrecision() {
    _precisionTimer?.cancel();
    _precisionTimer = null;
    _precisionPhase = PrecisionPhase.idle;
    _precisionCount1 = 0;
    _precisionCount2 = 0;
    _precisionElapsedMs = 0;
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
      // Displacement stays quiet while a zero-cal/precision run is in
      // flight so the simulated result matches whatever the walk settled at.
      if (_zeroCalPhase == ZeroCalPhase.idle &&
          _precisionPhase != PrecisionPhase.running) {
        _s1Mm = _walk(_s1Mm, 0.03, -5.0, 5.0);
        _s2Mm = _walk(_s2Mm, 0.03, -5.0, 5.0);
      }
      _tickCount++;
      if (_tickCount % 40 == 0) {
        _batteryPct = (_batteryPct - 1).clamp(0, 100);
        _batteryMv = (_batteryMv - 4).clamp(3300, 4200);
      }
      _deviceController.add(DeviceState(
        displacementS1Mm: _s1Mm,
        displacementS2Mm: _s2Mm,
        residualS1: 0.0,
        residualS2: 0.0,
        displacementOk: true,
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
