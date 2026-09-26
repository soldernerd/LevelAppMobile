import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';

/// Talks to the Leveltronic instrument over `flutter_blue_plus`.
///
/// The link is an RN4871 Transparent-UART GATT service: requests are written
/// to [kRxCharUuid], responses and subscription pushes arrive as
/// notifications on [kTxCharUuid], both carrying framed API v2 packets
/// ([api_v2.dart]). On connect the manager subscribes to the `Environmental`,
/// `Device status` and `Raw displacement` topic groups plus the `dispOk`
/// measurement, and merges their pushes into a single [DeviceState] stream.
/// One-shot GET/EXECUTE requests (zero calibration, precision measurement)
/// are correlated to their response by opcode via [_request].
class RealBleManager implements BleManager {
  RealBleManager();

  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _deviceController = StreamController<DeviceState?>.broadcast();

  final _reasm = Api2Reassembler();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _notifySub;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  bool _connected = false;
  int _crcErrorCount = 0;

  Api2Environmental? _env;
  Api2DeviceStatus? _status;
  Api2DisplacementRaw? _disp;
  bool _dispOk = false;

  /// Outstanding one-shot GET/EXECUTE requests, keyed by opcode. One-shot
  /// traffic is atomic and non-interleaved per the API spec, so a single
  /// completer per opcode is enough — a new request for the same opcode is
  /// only ever issued after the previous one resolved or timed out.
  final Map<int, Completer<Api2Frame>> _pending = {};

  /// Subscription-push opcodes this manager understands, dispatched before
  /// the one-shot request/response correlation is even considered.
  late final Map<int, void Function(Api2Frame push)> _pushHandlers = {
    opSubscribeTopic(Api2TopicRes.environmental): _onEnvPush,
    opSubscribeTopic(Api2TopicRes.deviceStatus): _onStatusPush,
    opSubscribeTopic(Api2TopicRes.displacementRaw): _onDispPush,
    opSubscribeMeasurement(Api2MeasRes.dispOk): _onDispOkPush,
  };

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<DeviceState?> get deviceStream => _deviceController.stream;

  // --- scanning ---------------------------------------------------------------

  @override
  Future<void> startScan() async {
    await _scanSub?.cancel();
    await _isScanningSub?.cancel();
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _emitStatus(ConnectionStatus.scanning);

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (!name.startsWith(kDeviceNamePrefix)) continue;
        if (_scanController.isClosed) return;
        _scanController.add(
          ScannedDevice(id: r.device.remoteId.str, name: name, rssi: r.rssi),
        );
      }
    }, onError: (Object _) {});

    // No service filter: the RN4871 advertises its name but not the 128-bit
    // Transparent-UART service UUID, so results are filtered by name above.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    // Now that scanning is live, fold its end (timeout or external stop) back
    // into the state machine. The first event is the current `true`.
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning) {
        _isScanningSub?.cancel();
        _isScanningSub = null;
        _scanSub?.cancel();
        _scanSub = null;
        _emitStatus(ConnectionStatus.idle);
      }
    });
  }

  @override
  Future<void> stopScan() async {
    await _isScanningSub?.cancel();
    _isScanningSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _emitStatus(ConnectionStatus.idle);
  }

  // --- connecting -----------------------------------------------------------

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    _emitStatus(ConnectionStatus.connecting);

    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    _reasm.reset();
    _env = null;
    _status = null;
    _disp = null;
    _dispOk = false;
    _failPendingRequests();

    await _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && _connected) {
        _handleInvoluntaryDisconnect();
      }
    });

    // License.nonprofit: this is a personal / hobby project. A commercial
    // FlutterBluePlus license is required for for-profit use (see the package
    // LICENSE). `mtu: 512` negotiates a larger ATT MTU during connect so
    // topic-group pushes arrive in one notification.
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
      mtu: 512,
    );

    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == Guid(kServiceUuid),
      orElse: () => throw StateError('Transparent UART service not found'),
    );

    _rxChar = service.characteristics
        .firstWhere((c) => c.uuid == Guid(kRxCharUuid));
    final txChar = service.characteristics
        .firstWhere((c) => c.uuid == Guid(kTxCharUuid));

    await txChar.setNotifyValue(true);
    await _notifySub?.cancel();
    _notifySub = txChar.onValueReceived.listen(_onBytes, onError: (Object _) {});
    device.cancelWhenDisconnected(_notifySub!);

    _connected = true;
    _emitStatus(ConnectionStatus.connected);

    // Kick the topic-group subscriptions and a one-off identity read.
    final intervalMs = kSubscriptionInterval.inMilliseconds;
    await _send(buildPacket(opGetIdentity()));
    await _send(buildPacket(
        opSubscribeTopic(Api2TopicRes.environmental), _u32le(intervalMs)));
    await _send(buildPacket(
        opSubscribeTopic(Api2TopicRes.deviceStatus), _u32le(intervalMs)));
    await _send(buildPacket(
        opSubscribeTopic(Api2TopicRes.displacementRaw), _u32le(intervalMs)));
    await _send(buildPacket(
        opSubscribeMeasurement(Api2MeasRes.dispOk), _u32le(intervalMs)));

    // Worked-example step 1 (docs/api-reference.md): the demod usually
    // auto-starts at firmware boot, but confirm and start it if not — zero
    // calibration and precision measurement both need it running.
    unawaited(_ensureDemodRunning());
  }

  @override
  Future<void> disconnect() async {
    _emitStatus(ConnectionStatus.disconnecting);
    _connected = false;

    final device = _device;
    final rx = _rxChar;
    if (device != null && rx != null) {
      try {
        await _send(
            buildPacket(opUnsubscribeTopic(Api2TopicRes.environmental)));
        await _send(
            buildPacket(opUnsubscribeTopic(Api2TopicRes.deviceStatus)));
        await _send(
            buildPacket(opUnsubscribeTopic(Api2TopicRes.displacementRaw)));
        await _send(
            buildPacket(opUnsubscribeMeasurement(Api2MeasRes.dispOk)));
      } catch (_) {
        // best effort — we're tearing down anyway
      }
    }

    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    try {
      await device?.disconnect();
    } catch (_) {}
    _rxChar = null;
    _device = null;
    _failPendingRequests();

    _emitStatus(ConnectionStatus.disconnected);
    _emitDevice(null);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _connStateSub?.cancel();
    _notifySub?.cancel();
    _failPendingRequests();
    _scanController.close();
    _statusController.close();
    _deviceController.close();
  }

  // --- zero calibration (Commands 0x1/0x06) --------------------------------

  @override
  Future<Api2Status> zeroCalibrationStep1() async {
    await _ensureDemodRunning();
    return _executeCommand(Api2CmdRes.zeroCalibration, const [0x01]);
  }

  @override
  Future<Api2Status> zeroCalibrationStep2() =>
      _executeCommand(Api2CmdRes.zeroCalibration, const [0x02]);

  @override
  Future<Api2Status> zeroCalibrationCancel() =>
      _executeCommand(Api2CmdRes.zeroCalibration, const [0x00]);

  @override
  Future<Api2ZeroCalStatus?> pollZeroCalibration() async {
    final frame = await _tryRequest(opGetRaw(Api2RawRes.zeroCalStatus));
    if (frame == null || !frame.isOk) return null;
    return Api2ZeroCalStatus.decode(frame.data);
  }

  // --- triggered precision measurement (Commands 0x1/0x07) -----------------

  @override
  Future<Api2Status> startPrecisionMeasurement() async {
    await _ensureDemodRunning();
    return _executeCommand(Api2CmdRes.precisionMeasurement, const [0x00]);
  }

  @override
  Future<Api2Status> cancelPrecisionMeasurement() =>
      _executeCommand(Api2CmdRes.precisionMeasurement, const [0x01]);

  @override
  Future<Api2PrecisionStatus?> pollPrecisionMeasurement() async {
    final frame = await _tryRequest(opGetRaw(Api2RawRes.precisionStatus));
    if (frame == null || !frame.isOk) return null;
    return Api2PrecisionStatus.decode(frame.data);
  }

  // --- internals ----------------------------------------------------------

  /// `GET 0x4/0x0D` (dispOk); if false, `EXECUTE 0x1/0x01` payload `1` to
  /// start the demod. Best-effort — failures surface as BUSY_RESOURCE on the
  /// zero-cal/precision EXECUTE that follows, so errors here are swallowed.
  Future<void> _ensureDemodRunning() async {
    try {
      final frame = await _tryRequest(opGetMeasurement(Api2MeasRes.dispOk));
      final ok = frame != null && frame.isOk && frame.data.isNotEmpty && frame.data[0] != 0;
      if (!ok) {
        await _executeCommand(Api2CmdRes.displacementDemod, const [0x01]);
      }
    } catch (_) {
      // Swallowed — the subsequent EXECUTE reports BUSY_RESOURCE if this
      // didn't actually get the demod running.
    }
  }

  Future<Api2Status> _executeCommand(int resource, List<int> payload) async {
    final frame = await _tryRequest(opExecuteCommand(resource), payload: payload);
    if (frame == null) return Api2Status.unknown;
    return frame.crcOk ? frame.status : Api2Status.unknown;
  }

  /// Like [_request] but never throws — returns null on timeout, a missing
  /// connection, or any other comms failure, so pollers can just retry.
  Future<Api2Frame?> _tryRequest(int opcode, {List<int> payload = const []}) async {
    try {
      return await _request(opcode, payload: payload);
    } catch (_) {
      return null;
    }
  }

  Future<Api2Frame> _request(
    int opcode, {
    List<int> payload = const [],
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_rxChar == null) {
      throw StateError('not connected');
    }
    final completer = Completer<Api2Frame>();
    _pending[opcode] = completer;
    await _send(buildPacket(opcode, payload));
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending.remove(opcode);
    }
  }

  void _failPendingRequests() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('disconnected'));
    }
    _pending.clear();
  }

  void _handleInvoluntaryDisconnect() {
    _connected = false;
    _notifySub?.cancel();
    _notifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _rxChar = null;
    _device = null;
    _failPendingRequests();
    _emitStatus(ConnectionStatus.disconnected);
    _emitDevice(null);
  }

  Future<void> _send(List<int> bytes) async {
    final rx = _rxChar;
    if (rx == null) return;
    await rx.write(bytes, withoutResponse: true);
  }

  void _onBytes(List<int> chunk) {
    for (final frame in _reasm.addBytes(chunk)) {
      if (!frame.crcOk) {
        _crcErrorCount++;
        assert(() {
          debugPrint('[RealBleManager] dropped CRC-bad frame ($_crcErrorCount)');
          return true;
        }());
        continue;
      }
      _dispatch(frame);
    }
  }

  void _dispatch(Api2Frame frame) {
    // Subscription pushes echo the SUBSCRIBE opcode; the ack that precedes
    // them is status-only (empty data), so a non-empty payload is a real
    // push — a matching handler here always wins over request correlation
    // below, since a SUBSCRIBE opcode is never awaited via [_request].
    final pushHandler = _pushHandlers[frame.opcode];
    if (pushHandler != null) {
      final push = frame.asPush();
      if (push.data.isNotEmpty) pushHandler(push);
      return;
    }

    final pending = _pending.remove(frame.opcode);
    if (pending != null && !pending.isCompleted) {
      pending.complete(frame);
      return;
    }

    if (frame.opcode == opGetIdentity() && frame.isOk) {
      final id = Api2Identity.decode(frame.data);
      if (id != null) {
        assert(() {
          debugPrint('[RealBleManager] ${id.product} fw ${id.version} '
              'serial ${id.serial}');
          return true;
        }());
      }
    }
  }

  void _onEnvPush(Api2Frame push) {
    final env = Api2Environmental.decode(push.data);
    if (env != null) {
      _env = env;
      _emitDevice(_merge());
    }
  }

  void _onStatusPush(Api2Frame push) {
    final st = Api2DeviceStatus.decode(push.data);
    if (st != null) {
      _status = st;
      _emitDevice(_merge());
    }
  }

  void _onDispPush(Api2Frame push) {
    final disp = Api2DisplacementRaw.decode(push.data);
    if (disp != null) {
      _disp = disp;
      _emitDevice(_merge());
    }
  }

  void _onDispOkPush(Api2Frame push) {
    _dispOk = push.data[0] != 0;
    _emitDevice(_merge());
  }

  DeviceState _merge() {
    final st = _status;
    final env = _env;
    final disp = _disp;
    return DeviceState(
      displacementS1Mm: disp?.delta1MmRaw,
      displacementS2Mm: disp?.delta2MmRaw,
      residualS1: disp?.residual1,
      residualS2: disp?.residual2,
      displacementOk: _dispOk,
      quality1Ok: disp?.quality1Ok ?? true,
      quality2Ok: disp?.quality2Ok ?? true,
      batteryPercent: st?.batterySocPct ?? 0,
      batteryMillivolts: st?.batteryMv ?? 0,
      batteryState: st?.batteryState ?? BatteryState.unknown,
      onboardTempC: env?.onboardTempC,
      externalTempC:
          (env?.externalTempOk ?? false) ? env?.externalTempC : null,
      bme280TempC: env?.bme280TempC,
      pressurePa: env?.pressurePa,
      humidityPct: env?.humidityPct,
      bme280Fresh: env?.bme280Ok ?? false,
      usbConnected: st?.usbConnected ?? false,
      charging: st?.charging ?? false,
    );
  }

  void _emitStatus(ConnectionStatus s) {
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void _emitDevice(DeviceState? d) {
    if (!_deviceController.isClosed) _deviceController.add(d);
  }

  static List<int> _u32le(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
}
