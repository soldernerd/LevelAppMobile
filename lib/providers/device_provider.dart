import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/instrument_api.dart';
import 'package:inclinometer/ble/live_feed.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

/// Root-level provider for the BLE manager.
///
/// Must be overridden at the ProviderScope root — throws [UnimplementedError]
/// if accessed without an override. `main.dart` overrides it with
/// `RealBleManager`; tests with [MockBleManager].
// ARCH: BLE connection provider must survive navigation (CLAUDE.md: keepAlive).
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});

/// The typed API over the open link. Everything above the transport talks to
/// the instrument through this.
final instrumentApiProvider = Provider<InstrumentApi>((ref) {
  return InstrumentApi(ref.watch(bleManagerProvider));
});

/// Why the last connect / scan failed, for the scan screen. Null when the
/// failure had no more specific cause than "Bluetooth".
final connectionErrorProvider = StateProvider<String?>((ref) => null);

/// Connection state machine notifier.
///
/// Owns the full [ConnectionStatus] state machine from idle through
/// reconnecting, accumulates scan results, manages the wakelock and — while
/// connected — runs the [LiveFeed], forwarding its merged [DeviceState]s
/// (and a null stale sentinel on disconnect/error) to [instrumentStream].
class ConnectionNotifier extends Notifier<ConnectionStatus> {
  // Auto-reconnect is a stub: structure in place, not active.
  static const bool _autoReconnectEnabled = false;

  // broadcast() — multi-subscriber safe; no "already listened" error
  final _packetController = StreamController<DeviceState?>.broadcast();
  final _scannedDevices = <ScannedDevice>[];

  LiveFeed? _feed;
  StreamSubscription<DeviceState>? _feedSub;

  /// Broadcast stream of merged instrument snapshots.
  ///
  /// Emits null on disconnect/error (stale sentinel).
  Stream<DeviceState?> get instrumentStream => _packetController.stream;

  /// Unmodifiable snapshot of accumulated scan results.
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  /// The last merged state while connected, else null.
  DeviceState? get currentState => _feed?.state;

  @override
  ConnectionStatus build() {
    // keepAlive: prevents auto-dispose while a BLE session is active. Riverpod
    // 3 does not propagate keepAlive through the dependency chain — each
    // provider that must survive navigation calls ref.keepAlive() itself.
    final link = ref.keepAlive();
    ref.onDispose(link.close);

    final manager = ref.read(bleManagerProvider);

    final statusSub = manager.connectionStatus.listen(_handleStatusEvent);

    final scanSub = manager.scanResults.listen((device) {
      if (!_scannedDevices.contains(device)) {
        _scannedDevices.add(device);
        // A dedicated revision counter makes scanResultsProvider rebuild even
        // when the ConnectionStatus value is unchanged.
        ref.read(_scanRevisionProvider.notifier).increment();
      }
    });

    ref.onDispose(() {
      statusSub.cancel();
      scanSub.cancel();
      _stopFeed();
      _packetController.close();
      // .catchError: async platform channel may throw in test environments.
      WakelockPlus.disable().catchError((_) {});
    });

    return ConnectionStatus.idle;
  }

  void _handleStatusEvent(ConnectionStatus status) {
    state = status;

    if (status == ConnectionStatus.connected) {
      WakelockPlus.enable().catchError((_) {});
      _startFeed();
    } else if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      WakelockPlus.disable().catchError((_) {});
      _stopFeed();

      // Stale sentinel: the UI must not show last-known values as live.
      if (!_packetController.isClosed) {
        _packetController.add(null);
      }

      if (_autoReconnectEnabled) {
        state = ConnectionStatus.reconnecting;
      }
    }
  }

  void _startFeed() {
    _stopFeed();
    final feed = LiveFeed(ref.read(instrumentApiProvider));
    _feed = feed;
    _feedSub = feed.stream.listen((s) {
      if (!_packetController.isClosed) _packetController.add(s);
    });
    feed.start();
  }

  void _stopFeed() {
    _feedSub?.cancel();
    _feedSub = null;
    final feed = _feed;
    _feed = null;
    if (feed != null) unawaited(feed.stop());
  }

  /// Clears accumulated scan results and starts a new BLE scan.
  Future<void> startScan() async {
    _scannedDevices.clear();
    ref.read(_scanRevisionProvider.notifier).reset();
    ref.read(connectionErrorProvider.notifier).state = null;
    try {
      await ref.read(bleManagerProvider).startScan();
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

  /// Connects to [deviceId]. On failure sets [ConnectionStatus.error] and, for
  /// an instrument that does not speak API v3, a specific message in
  /// [connectionErrorProvider].
  Future<void> connect(String deviceId) async {
    ref.read(connectionErrorProvider.notifier).state = null;
    try {
      await ref.read(bleManagerProvider).connect(deviceId);
    } on IncompatibleFirmwareException catch (e) {
      ref.read(connectionErrorProvider.notifier).state = e.message;
      state = ConnectionStatus.error;
    } catch (e) {
      ref.read(connectionErrorProvider.notifier).state =
          'Could not connect to the instrument.';
      state = ConnectionStatus.error;
    }
  }

  Future<void> disconnect() async {
    try {
      await ref.read(bleManagerProvider).disconnect();
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  /// Debug-only: simulates an involuntary disconnect via [MockBleManager].
  /// Encapsulates the `is MockBleManager` check so `lib/ui/` never imports
  /// the mock. No-op on the real manager.
  void debugSimulateDisconnect() {
    final mgr = ref.read(bleManagerProvider);
    if (mgr is MockBleManager) mgr.simulateDisconnect();
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

/// StreamProvider exposing live instrument data as [DeviceState?].
///
/// Null values indicate stale data (disconnect/error sentinel).
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) async* {
  final notifier = ref.watch(connectionNotifierProvider.notifier);
  // A late subscriber (a screen opened mid-session) gets the last merged
  // state at once instead of waiting for the next push.
  final current = notifier.currentState;
  if (current != null) yield current;
  yield* notifier.instrumentStream;
});

/// Whether BLE permissions are permanently denied on this device.
final blePermissionPermanentlyDeniedProvider =
    StateProvider<bool>((ref) => false);
