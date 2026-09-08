import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

/// Root-level provider for the BLE manager.
///
/// Must be overridden at the ProviderScope root — throws [UnimplementedError]
/// if accessed without an override. WP1 overrides with [MockBleManager];
/// WP2 overrides with RealBleManager.
///
/// Phase 3 adds [ConnectionNotifier], [scanResultsProvider], and
/// [instrumentDataProvider] to this file.
// ARCH: BLE connection provider must survive navigation (CLAUDE.md: keepAlive).
// ref.keepAlive() is called in the ProviderScope.overrideWith body in main.dart
// so that the live BleManager instance is never auto-disposed mid-session.
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});

/// Connection state machine notifier.
///
/// Owns the full [ConnectionStatus] state machine from idle through reconnecting.
/// Accumulates scan results, manages wakelock side-effects, and exposes a
/// shared [StreamController] that emits [StatePacket?] values — including null
/// sentinels on disconnect/error (D-05/D-06).
class ConnectionNotifier extends Notifier<ConnectionStatus> {
  // D-07: Auto-reconnect stub. WP2 activates by setting to true.
  static const bool _autoReconnectEnabled = false;

  // broadcast() — multi-subscriber safe; no "already listened" error
  final _packetController = StreamController<DeviceState?>.broadcast();
  final _scannedDevices = <ScannedDevice>[];

  /// Broadcast stream of merged instrument snapshots.
  ///
  /// Emits null on disconnect/error (stale sentinel per D-05/D-06).
  Stream<DeviceState?> get instrumentStream => _packetController.stream;

  /// Unmodifiable snapshot of accumulated scan results.
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  @override
  ConnectionStatus build() {
    // keepAlive: prevents auto-dispose while BLE session is active (PITFALL-2).
    // Riverpod 3 does not propagate keepAlive through the dependency chain —
    // each provider that must survive navigation must call ref.keepAlive() independently.
    final link = ref.keepAlive();
    ref.onDispose(link.close);

    final manager = ref.read(bleManagerProvider);

    // Subscribe to connection status stream — update state on each event.
    final statusSub = manager.connectionStatus.listen(_handleStatusEvent);

    // Subscribe to scan results stream — accumulate unique devices.
    final scanSub = manager.scanResults.listen((device) {
      if (!_scannedDevices.contains(device)) {
        _scannedDevices.add(device);
        // Increment the scan revision counter so scanResultsProvider rebuilds.
        // `state = state` is suppressed by Riverpod's equality check when the
        // ConnectionStatus value is unchanged (e.g. scanning → scanning).
        // Using a dedicated revision counter avoids this pitfall (BUGFIX: A1).
        ref.read(_scanRevisionProvider.notifier).increment();
      }
    });

    // Forward merged device snapshots (and null stale sentinels) straight
    // through — decoding/merging now lives in the BleManager implementation.
    final packetSub = manager.deviceStream.listen((state) {
      if (!_packetController.isClosed) {
        _packetController.add(state);
      }
    });

    ref.onDispose(() {
      statusSub.cancel();
      scanSub.cancel();
      packetSub.cancel();
      _packetController.close();
      // Safety: release wakelock if provider is torn down unexpectedly.
      // .catchError: async platform channel may throw in test environments.
      WakelockPlus.disable().catchError((_) {});
    });

    return ConnectionStatus.idle;
  }

  void _handleStatusEvent(ConnectionStatus status) {
    state = status;

    if (status == ConnectionStatus.connected) {
      // D-09: Acquire screen-on lock when instrument is connected.
      // .catchError: WakelockPlus returns a Future — the platform channel error
      // arrives asynchronously so try/catch alone is insufficient. Use .catchError
      // to swallow PlatformException from test environments without a platform binding.
      // Platform side-effect is verified by code inspection (RESEARCH.md: static API).
      WakelockPlus.enable().catchError((_) {});
    } else if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      // D-09: Release screen-on lock on disconnect/error.
      WakelockPlus.disable().catchError((_) {});

      // D-05/D-06: Emit null sentinel — signals stale data to instrumentDataProvider.
      if (!_packetController.isClosed) {
        _packetController.add(null);
      }

      // D-07/D-08: Auto-reconnect stub — gated by _autoReconnectEnabled.
      // WP2 activates by setting _autoReconnectEnabled = true.
      if (_autoReconnectEnabled) {
        state = ConnectionStatus.reconnecting;
        // backoff/retry logic goes here (WP2 activates)
      }
    }
  }

  /// Clears accumulated scan results and starts a new BLE scan.
  ///
  /// Sets [ConnectionStatus.error] if the underlying BLE manager throws,
  /// so callers do not need to handle the error themselves.
  Future<void> startScan() async {
    _scannedDevices.clear();
    // Reset revision counter so scanResultsProvider correctly shows empty list.
    ref.read(_scanRevisionProvider.notifier).reset();
    try {
      await ref.read(bleManagerProvider).startScan();
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Stops the active BLE scan.
  ///
  /// Sets [ConnectionStatus.error] if the underlying BLE manager throws.
  Future<void> stopScan() async {
    try {
      await ref.read(bleManagerProvider).stopScan();
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Initiates connection to the device with [deviceId].
  ///
  /// Sets [ConnectionStatus.error] if the underlying BLE manager throws,
  /// so callers do not need to handle the error themselves.
  Future<void> connect(String deviceId) async {
    try {
      await ref.read(bleManagerProvider).connect(deviceId);
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Disconnects from the currently connected device.
  ///
  /// Sets [ConnectionStatus.error] if the underlying BLE manager throws,
  /// consistent with [connect] and [startScan] error handling (WR-03).
  Future<void> disconnect() async {
    try {
      await ref.read(bleManagerProvider).disconnect();
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Debug-only: simulates an involuntary disconnect via [MockBleManager].
  ///
  /// This method encapsulates the [is MockBleManager] check so that
  /// [lib/ui/] never needs to import [MockBleManager] directly, preserving
  /// the architecture constraint from CLAUDE.md. No-op on non-mock managers.
  void debugSimulateDisconnect() {
    final mgr = ref.read(bleManagerProvider);
    if (mgr is MockBleManager) mgr.simulateDisconnect();
  }
}

/// Provider for the connection state machine.
///
/// keepAlive is managed inside [ConnectionNotifier.build()] via [ref.keepAlive()].
final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);

/// Internal revision counter incremented whenever a new scan result arrives.
///
/// Watching this provider triggers [scanResultsProvider] to re-evaluate even
/// when [ConnectionStatus] hasn't changed (which Riverpod would suppress via
/// equality — see BUGFIX: A1 in [ConnectionNotifier.build]).
class _ScanRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
  void reset() => state = 0;
}

final _scanRevisionProvider =
    NotifierProvider<_ScanRevisionNotifier, int>(_ScanRevisionNotifier.new);

/// Derived provider exposing accumulated scan results.
///
/// Watches [_scanRevisionProvider] as the rebuild trigger — incremented by
/// [ConnectionNotifier] whenever a new device is added to the scan list.
/// Uses ref.watch (not ref.read) on the notifier to establish a proper
/// Riverpod dependency, avoiding stale reads if the notifier is recreated.
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(_scanRevisionProvider); // rebuild trigger on each new scan result
  return ref.watch(connectionNotifierProvider.notifier).scannedDevices;
});

/// StreamProvider exposing live instrument data as [DeviceState?].
///
/// Null values indicate stale data (disconnect/error sentinel per D-05/D-06).
/// Riverpod manages the stream subscription lifecycle.
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) {
  return ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});

/// Whether BLE permissions are permanently denied on this device.
///
/// Set by main() on cold start (Android only) and updated by ScanScreen
/// after a permission request resolves to permanentlyDenied.
/// Watched by ScanScreen to show the inline "Open Settings" message (D-02).
final blePermissionPermanentlyDeniedProvider = StateProvider<bool>((ref) => false);
