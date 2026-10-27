import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/models/connection.dart';

/// Root-level provider for the BLE manager.
///
/// Must be overridden at the ProviderScope root — throws [UnimplementedError]
/// if accessed without an override. `main.dart` overrides it with
/// `RealBleManager`; tests with [MockBleManager].
// ARCH: BLE connection provider must survive navigation (CLAUDE.md: keepAlive).
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});

/// The device drivers this build knows. Overridden at the root like
/// [bleManagerProvider]; tests and `main.dart` list the drivers they want.
final deviceRegistryProvider = Provider<DeviceRegistry>((ref) {
  throw UnimplementedError('deviceRegistryProvider must be overridden at root');
});

/// Why the last connect / scan failed, for the scan screen. Null when the
/// failure had no more specific cause than "Bluetooth".
final connectionErrorProvider = StateProvider<String?>((ref) => null);

/// The open devices, and which one the UI is focused on.
class OpenSessions {
  const OpenSessions(this.all, this.activeId);

  static const none = OpenSessions([], null);

  final List<DeviceSession> all;
  final String? activeId;

  DeviceSession? get active {
    for (final s in all) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  bool get isEmpty => all.isEmpty;
  bool contains(String id) => all.any((s) => s.id == id);
}

/// Owns the [DeviceSession]s: any number of devices can be connected at once,
/// each running its own feeds; one of them is the *active* one that the
/// device screens show. A session leaves the list when its link goes down.
class SessionsNotifier extends Notifier<OpenSessions> {
  final _sessions = <DeviceSession>[];
  String? _activeId;

  @override
  OpenSessions build() {
    ref.keepAlive();
    ref.onDispose(() {
      for (final s in _sessions) {
        unawaited(s.close());
      }
      _sessions.clear();
    });
    return OpenSessions.none;
  }

  /// Adds a freshly opened session and makes it the active one.
  void add(DeviceSession session) {
    _sessions.removeWhere((s) => s.id == session.id);
    _sessions.add(session);
    _activeId = session.id;
    _publish();
    unawaited(session.closed.then<void>((_) => _drop(session)));
  }

  void activate(String id) {
    if (!_sessions.any((s) => s.id == id) || _activeId == id) return;
    _activeId = id;
    _publish();
  }

  /// Closes the session with [id]; it leaves the list once its link is down.
  Future<void> close(String id) async {
    for (final s in _sessions.toList()) {
      if (s.id != id) continue;
      await s.close();
      _drop(s);
    }
  }

  void _drop(DeviceSession session) {
    // A newer session for the same device may have replaced this one.
    if (!_sessions.remove(session)) return;
    if (_activeId == session.id) {
      _activeId = _sessions.isEmpty ? null : _sessions.last.id;
    }
    _publish();
  }

  void _publish() =>
      state = OpenSessions(List.unmodifiable(_sessions), _activeId);
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, OpenSessions>(SessionsNotifier.new);

/// The session the device screens show, or null. Changes only when the
/// active device changes, not when other sessions come and go.
final activeSessionProvider = Provider<DeviceSession?>((ref) {
  return ref.watch(sessionsProvider.select((s) => s.active));
});

/// Connection state machine notifier.
///
/// Owns the [ConnectionStatus] of the scan / connect flow, accumulates scan
/// results and manages the wakelock. [ConnectionStatus.connected] means at
/// least one device is open and nothing else is going on; the devices
/// themselves are in [sessionsProvider].
class ConnectionNotifier extends Notifier<ConnectionStatus> {
  // Auto-reconnect is a stub: structure in place, not active.
  static const bool _autoReconnectEnabled = false;

  final _scannedDevices = <ScannedDevice>[];

  /// Unmodifiable snapshot of accumulated scan results.
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  @override
  ConnectionStatus build() {
    // keepAlive: prevents auto-dispose while a BLE session is active. Riverpod
    // 3 does not propagate keepAlive through the dependency chain — each
    // provider that must survive navigation calls ref.keepAlive() itself.
    final link = ref.keepAlive();
    ref.onDispose(link.close);

    final manager = ref.read(bleManagerProvider);

    final scanningSub = manager.scanning.listen((scanning) {
      if (scanning) {
        state = ConnectionStatus.scanning;
      } else if (state == ConnectionStatus.scanning) {
        state = _resting;
      }
    });

    final scanSub = manager.scanResults.listen((device) {
      if (!_scannedDevices.contains(device)) {
        _scannedDevices.add(device);
        // A dedicated revision counter makes scanResultsProvider rebuild even
        // when the ConnectionStatus value is unchanged.
        ref.read(_scanRevisionProvider.notifier).increment();
      }
    });

    ref.listen(sessionsProvider, (prev, next) {
      final had = !(prev?.isEmpty ?? true);
      if (next.isEmpty && had) {
        WakelockPlus.disable().catchError((_) {});
        state = _autoReconnectEnabled
            ? ConnectionStatus.reconnecting
            : ConnectionStatus.disconnected;
      } else if (!next.isEmpty && !had) {
        // .catchError: async platform channel may throw in test environments.
        WakelockPlus.enable().catchError((_) {});
      }
    });

    ref.onDispose(() {
      scanningSub.cancel();
      scanSub.cancel();
      WakelockPlus.disable().catchError((_) {});
    });

    return ConnectionStatus.idle;
  }

  /// What the status is when no scan or connect is in flight.
  ConnectionStatus get _resting => ref.read(sessionsProvider).isEmpty
      ? ConnectionStatus.idle
      : ConnectionStatus.connected;

  /// Clears accumulated scan results and starts a new BLE scan for the
  /// advertised names of the registered drivers.
  Future<void> startScan() async {
    _scannedDevices.clear();
    ref.read(_scanRevisionProvider.notifier).reset();
    ref.read(connectionErrorProvider.notifier).state = null;
    try {
      await ref.read(bleManagerProvider).startScan(
            accept: ref.read(deviceRegistryProvider).acceptsAdvertisedName,
          );
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  Future<void> stopScan() async {
    try {
      await ref.read(bleManagerProvider).stopScan();
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Connects to [deviceId], identifies it and opens its session; the new
  /// device becomes the active one. On failure sets [ConnectionStatus.error]
  /// and, for a device the app cannot use, a specific message in
  /// [connectionErrorProvider].
  Future<void> connect(String deviceId) async {
    ref.read(connectionErrorProvider.notifier).state = null;
    final sessions = ref.read(sessionsProvider.notifier);
    if (ref.read(sessionsProvider).contains(deviceId)) {
      sessions.activate(deviceId);
      state = ConnectionStatus.connected;
      return;
    }
    try {
      final manager = ref.read(bleManagerProvider);
      await manager.stopScan();
      state = ConnectionStatus.connecting;
      final connection = await manager.open(deviceId);
      final session =
          await ref.read(deviceRegistryProvider).openSession(connection);
      sessions.add(session);
      state = ConnectionStatus.connected;
    } on ConnectFailure catch (e) {
      ref.read(connectionErrorProvider.notifier).state = e.message;
      state = ConnectionStatus.error;
    } catch (e) {
      ref.read(connectionErrorProvider.notifier).state =
          'Could not connect to the device.';
      state = ConnectionStatus.error;
    }
  }

  /// Disconnects [deviceId], or the active device.
  Future<void> disconnect({String? deviceId}) async {
    final open = ref.read(sessionsProvider);
    final id = deviceId ?? open.activeId;
    if (id == null) return;
    try {
      if (open.all.length == 1) state = ConnectionStatus.disconnecting;
      await ref.read(sessionsProvider.notifier).close(id);
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Debug-only: simulates an involuntary disconnect via [MockBleManager].
  /// Encapsulates the `is MockBleManager` check so `lib/ui/` never imports
  /// the mock. No-op on the real manager.
  void debugSimulateDisconnect() {
    final mgr = ref.read(bleManagerProvider);
    final id = ref.read(sessionsProvider).activeId;
    if (mgr is MockBleManager) mgr.simulateDisconnect(id);
  }
}

/// Provider for the connection state machine.
final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);

class _ScanRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
  void reset() => state = 0;
}

final _scanRevisionProvider =
    NotifierProvider<_ScanRevisionNotifier, int>(_ScanRevisionNotifier.new);

/// Derived provider exposing accumulated scan results.
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(_scanRevisionProvider);
  return ref.watch(connectionNotifierProvider.notifier).scannedDevices;
});

/// Whether BLE permissions are permanently denied on this device.
final blePermissionPermanentlyDeniedProvider =
    StateProvider<bool>((ref) => false);
