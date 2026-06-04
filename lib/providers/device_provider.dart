import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/ble_manager.dart';

/// Root-level provider for the BLE manager.
///
/// Must be overridden at the ProviderScope root — throws [UnimplementedError]
/// if accessed without an override. WP1 overrides with [MockBleManager];
/// WP2 overrides with RealBleManager.
///
/// Phase 3 adds [ConnectionNotifier], [scanResultsProvider], and
/// [deviceStateProvider] to this file.
// ARCH: BLE connection provider must survive navigation (CLAUDE.md: keepAlive).
// ref.keepAlive() is called in the ProviderScope.overrideWith body in main.dart
// so that the live BleManager instance is never auto-disposed mid-session.
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});
