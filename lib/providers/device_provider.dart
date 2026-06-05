import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
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

  /// Broadcast stream of parsed instrument packets.
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
        // state reassignment triggers scanResultsProvider to re-evaluate.
        // ref.notifyListeners() is NOT available on Ref in Riverpod 3.3.1 Notifier
        // (RESOLVED: A1) — use state = state; instead.
        // ignore: invalid_use_of_protected_member, unnecessary_statements
        state = state;
      }
    });

    // Subscribe to raw BLE packets — forward parsed packets to shared controller.
    // try/catch prevents Riverpod retry storm at 10 Hz mock rate (PITFALL-5, T-03-03).
    final packetSub = manager.statePackets.listen((bytes) {
      if (!_packetController.isClosed) {
        try {
          _packetController.add(StatePacket.parse(bytes));
        } catch (e) {
          // Parse error — swallow with debug log; do not rethrow into stream.
          // Prevents Riverpod automatic retry storm (T-03-03).
          assert(() {
            // ignore: avoid_print
            print('[ConnectionNotifier] StatePacket.parse error: $e');
            return true;
          }());
        }
      }
    });

    ref.onDispose(() {
      statusSub.cancel();
      scanSub.cancel();
      packetSub.cancel();
      _packetController.close();
      // Safety: release wakelock if provider is torn down unexpectedly.
      WakelockPlus.disable();
    });

    return ConnectionStatus.idle;
  }

  void _handleStatusEvent(ConnectionStatus status) {
    state = status;

    if (status == ConnectionStatus.connected) {
      // D-09: Acquire screen-on lock when instrument is connected.
      WakelockPlus.enable();
    } else if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      // D-09: Release screen-on lock on disconnect/error.
      WakelockPlus.disable();

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
  Future<void> startScan() async {
    _scannedDevices.clear();
    await ref.read(bleManagerProvider).startScan();
  }

  /// Stops the active BLE scan.
  Future<void> stopScan() async {
    await ref.read(bleManagerProvider).stopScan();
  }

  /// Initiates connection to the device with [deviceId].
  Future<void> connect(String deviceId) async {
    await ref.read(bleManagerProvider).connect(deviceId);
  }

  /// Disconnects from the currently connected device.
  Future<void> disconnect() async {
    await ref.read(bleManagerProvider).disconnect();
  }
}

/// Provider for the connection state machine.
///
/// keepAlive is managed inside [ConnectionNotifier.build()] via [ref.keepAlive()].
final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);

/// Derived provider exposing accumulated scan results.
///
/// Watches [connectionNotifierProvider] as a rebuild trigger — when the notifier
/// reassigns state (e.g., after adding a scanned device), this provider re-evaluates
/// and returns the updated unmodifiable list (D-03).
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(connectionNotifierProvider); // rebuild trigger on state change
  return ref.read(connectionNotifierProvider.notifier).scannedDevices;
});

/// StreamProvider exposing live instrument data as [DeviceState?].
///
/// Null values indicate stale data (disconnect/error sentinel per D-05/D-06).
/// Riverpod manages the stream subscription lifecycle.
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) {
  return ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});
