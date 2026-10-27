import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/models/connection.dart';

/// Talks to devices over `flutter_blue_plus`.
///
/// Scanning is global; every [open] gives an independent [_BleConnection], so
/// several devices can be connected at once. The link is an RN4871
/// Transparent-UART GATT service: requests are written to [kRxCharUuid],
/// replies and subscription pushes arrive as notifications on [kTxCharUuid],
/// both carrying framed API v3 packets ([api_v3.dart]). This class is only
/// the transport; identifying the device and the typed operations live above.
class RealBleManager implements BleManager {
  RealBleManager();

  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;

  final List<_BleConnection> _open = [];

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<bool> get scanning => _scanningController.stream;

  // --- scanning ---------------------------------------------------------------

  @override
  Future<void> startScan({bool Function(String name)? accept}) async {
    await _scanSub?.cancel();
    await _isScanningSub?.cancel();
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _emitScanning(true);

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (accept != null && !accept(name)) continue;
        if (_scanController.isClosed) return;
        _scanController.add(
          ScannedDevice(id: r.device.remoteId.str, name: name, rssi: r.rssi),
        );
      }
    }, onError: (Object _) {});

    // No service filter: the RN4871 advertises its name but not the 128-bit
    // Transparent-UART service UUID, so results are filtered by name above.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning) {
        _isScanningSub?.cancel();
        _isScanningSub = null;
        _scanSub?.cancel();
        _scanSub = null;
        _emitScanning(false);
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
    _emitScanning(false);
  }

  void _emitScanning(bool v) {
    if (!_scanningController.isClosed) _scanningController.add(v);
  }

  // --- connecting -----------------------------------------------------------

  @override
  Future<DeviceConnection> open(String deviceId) async {
    await stopScan();
    final conn = _BleConnection(BluetoothDevice.fromId(deviceId));
    try {
      await conn.connect();
    } catch (_) {
      await conn.close();
      rethrow;
    }
    _open.add(conn);
    unawaited(conn.closed.then<void>((_) => _open.remove(conn)));
    return conn;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    for (final c in _open.toList()) {
      unawaited(c.close());
    }
    _scanController.close();
    _scanningController.close();
  }
}

/// One open GATT link: owns the byte-stream reassembly, the outstanding
/// requests and the subscriptions of a single device.
class _BleConnection implements DeviceConnection {
  _BleConnection(this._device);

  final BluetoothDevice _device;
  final _reasm = ApiReassembler();
  final _closed = Completer<void>();

  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothCharacteristic? _rxChar;
  bool _up = false;

  /// Outstanding requests by opcode. One-shot traffic is atomic, so one
  /// completer per opcode is enough; a newer request for the same opcode
  /// fails the older one at once instead of orphaning it.
  final Map<int, Completer<ApiFrame>> _pending = {};

  /// Active subscriptions by SUBSCRIBE opcode.
  final Map<int, StreamController<Uint8List>> _subs = {};

  static const _defaultTimeout = Duration(seconds: 3);

  @override
  String get id => _device.remoteId.str;

  @override
  Future<void> get closed => _closed.future;

  Future<void> connect() async {
    _connStateSub = _device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && _up) {
        unawaited(close());
      }
    });

    // License.nonprofit: this is a personal / hobby project. A commercial
    // FlutterBluePlus license is required for for-profit use (see the package
    // LICENSE). `mtu: 512` negotiates a larger ATT MTU during connect so
    // pushes arrive in one notification.
    await _device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
      mtu: 512,
    );

    final services = await _device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == Guid(kServiceUuid),
      orElse: () => throw StateError('Transparent UART service not found'),
    );

    _rxChar = service.characteristics
        .firstWhere((c) => c.uuid == Guid(kRxCharUuid));
    final txChar = service.characteristics
        .firstWhere((c) => c.uuid == Guid(kTxCharUuid));

    await txChar.setNotifyValue(true);
    _notifySub = txChar.onValueReceived.listen(_onBytes, onError: (Object _) {});
    _device.cancelWhenDisconnected(_notifySub!);

    _up = true;
  }

  @override
  Future<void> close() async {
    final wasUp = _up || _rxChar != null;
    _up = false;
    _rxChar = null;
    final notify = _notifySub;
    _notifySub = null;
    final conn = _connStateSub;
    _connStateSub = null;
    unawaited(notify?.cancel());
    unawaited(conn?.cancel());
    _teardownLink();
    if (wasUp || !_closed.isCompleted) {
      try {
        await _device.disconnect();
      } catch (_) {}
    }
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Ends every outstanding request and subscription (the device clears its
  /// subscriptions on disconnect anyway).
  void _teardownLink() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const LinkException('disconnected'));
    }
    _pending.clear();
    final subs = _subs.values.toList();
    _subs.clear();
    for (final c in subs) {
      if (!c.isClosed) c.close();
    }
  }

  // --- DeviceLink ----------------------------------------------------------

  @override
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    if (_rxChar == null) throw const LinkException('not connected');

    final superseded = _pending[opcode];
    if (superseded != null && !superseded.isCompleted) {
      superseded.completeError(const LinkException('superseded'));
    }
    final completer = Completer<ApiFrame>();
    _pending[opcode] = completer;

    try {
      await _send(buildPacket(opcode, payload));
      final frame = await completer.future.timeout(
        timeout ?? _defaultTimeout,
        onTimeout: () => throw const LinkException('timeout'),
      );
      return ApiReply(frame.status, frame.data);
    } on LinkException {
      rethrow;
    } catch (e) {
      throw LinkException('$e');
    } finally {
      // Only clear our own entry; a newer request may have replaced it.
      if (identical(_pending[opcode], completer)) _pending.remove(opcode);
    }
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) {
    final existing = _subs[subscribeOpcode];
    if (existing != null && !existing.isClosed) return existing.stream;

    final body = payload ?? u32le(intervalMs);
    late final StreamController<Uint8List> c;
    c = StreamController<Uint8List>.broadcast(
      onListen: () => _beginSubscription(subscribeOpcode, body, c),
      onCancel: () => _endSubscription(subscribeOpcode, c),
    );
    _subs[subscribeOpcode] = c;
    return c.stream;
  }

  Future<void> _beginSubscription(
    int op,
    List<int> body,
    StreamController<Uint8List> c,
  ) async {
    try {
      final reply = await request(op, body);
      if (!reply.ok) {
        _failSubscription(op, c, ApiException(reply.status, 'subscribe'));
      }
    } catch (e) {
      _failSubscription(op, c, e);
    }
  }

  void _failSubscription(int op, StreamController<Uint8List> c, Object e) {
    if (identical(_subs[op], c)) _subs.remove(op);
    if (!c.isClosed) {
      c.addError(e);
      c.close();
    }
  }

  void _endSubscription(int op, StreamController<Uint8List> c) {
    final active = identical(_subs[op], c);
    if (active) _subs.remove(op);
    if (active && _rxChar != null) {
      // Fire and forget; NOT_SUBSCRIBED is fine.
      unawaited(request(withVerb(op, ApiVerb.unsubscribe), const [],
              const Duration(seconds: 1))
          .then<void>((_) {}, onError: (Object _) {}));
    }
  }

  // --- internals ----------------------------------------------------------

  /// Writes [bytes] in pieces that fit one GATT write (the ATT MTU less its
  /// 3-byte header; 20 bytes at the default MTU): some devices only accept
  /// that much per write and reassemble the packet themselves.
  Future<void> _send(List<int> bytes) async {
    final rx = _rxChar;
    if (rx == null) throw const LinkException('not connected');
    final chunk = (_device.mtuNow - 3).clamp(20, 244);
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = i + chunk < bytes.length ? i + chunk : bytes.length;
      await rx.write(bytes.sublist(i, end), withoutResponse: true);
    }
  }

  void _onBytes(List<int> chunk) {
    final crcBefore = _reasm.crcErrors;
    for (final frame in _reasm.addBytes(chunk)) {
      _dispatch(frame);
    }
    assert(() {
      if (_reasm.crcErrors != crcBefore) {
        debugPrint('[RealBleManager $id] dropped '
            '${_reasm.crcErrors - crcBefore} CRC-bad candidate(s), total '
            '${_reasm.crcErrors}');
      }
      return true;
    }());
  }

  void _dispatch(ApiFrame frame) {
    // A push is only ever sent for an active subscription; the ack that
    // precedes the pushes (and any error) carries no data after the status.
    final sub = _subs[frame.opcode];
    if (sub != null && frame.looksLikePush) {
      if (!sub.isClosed) sub.add(frame.pushData);
      return;
    }
    final pending = _pending.remove(frame.opcode);
    if (pending != null && !pending.isCompleted) {
      pending.complete(frame);
    }
  }
}
