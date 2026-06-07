// lib/providers/update_provider.dart
// Riverpod provider that fires the cold-start GitHub update check.
//
// D-11: autoDispose is the FutureProvider default — the provider resolves once
// when ScanScreen first subscribes and is disposed when ScanScreen unmounts.
//
// Usage: consumed by ScanScreen via ref.listen (not ref.watch) so the widget
// does not rebuild when the provider transitions through loading → data.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/services/update_service.dart';

/// One-shot update check provider (D-11: autoDispose, fires once per session).
///
/// Resolves to [UpdateInfo] when a newer, non-skipped GitHub release exists,
/// or null when the app is up-to-date, the version was previously skipped, or
/// any network / parse error occurred (D-01: silent fail).
///
/// Fires exactly once per ScanScreen lifecycle (cold-start check).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  return UpdateService.checkForUpdate();
});
