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
/// ([api_v2.dart]). On connect the manager subscribes to the `Environmental`
/// and `Device status` topic groups and merges their pushes into a single
/// [DeviceState] stream.
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

    _emitStatus(ConnectionStatus.disconnected);
    _emitDevice(null);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _connStateSub?.cancel();
    _notifySub?.cancel();
    _scanController.close();
    _statusController.close();
    _deviceController.close();
  }

  // --- internals ----------------------------------------------------------

  void _handleInvoluntaryDisconnect() {
    _connected = false;
    _notifySub?.cancel();
    _notifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _rxChar = null;
    _device = null;
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
    // Topic-group pushes echo the SUBSCRIBE opcode; the ack that precedes them
    // is status-only (empty data), so a non-empty payload is a real push.
    final envOp = opSubscribeTopic(Api2TopicRes.environmental);
    final statusOp = opSubscribeTopic(Api2TopicRes.deviceStatus);

    if (frame.opcode == envOp || frame.opcode == opGetTopic(Api2TopicRes.environmental)) {
      final push = frame.asPush();
      final env = Api2Environmental.decode(push.data);
      if (env != null) {
        _env = env;
        _emitDevice(_merge());
      }
      return;
    }

    if (frame.opcode == statusOp || frame.opcode == opGetTopic(Api2TopicRes.deviceStatus)) {
      final push = frame.asPush();
      final st = Api2DeviceStatus.decode(push.data);
      if (st != null) {
        _status = st;
        _emitDevice(_merge());
      }
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

  DeviceState _merge() {
    final st = _status;
    final env = _env;
    return DeviceState(
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
