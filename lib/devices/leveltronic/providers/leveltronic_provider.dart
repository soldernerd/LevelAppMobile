import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/device_state.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_session.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// The Leveltronic the UI is currently focused on, or null if the active
/// device is something else (or nothing).
final leveltronicSessionProvider = Provider<LeveltronicSession?>((ref) {
  final s = ref.watch(activeSessionProvider);
  return s is LeveltronicSession ? s : null;
});

/// The typed API over the active Leveltronic. Everything in this driver talks
/// to the instrument through this. Without one the link fails every request
/// with a `LinkException`, as a dropped connection would.
final instrumentApiProvider = Provider<InstrumentApi>((ref) {
  final session = ref.watch(leveltronicSessionProvider);
  return session?.api ?? const InstrumentApi(DisconnectedLink());
});

/// Live instrument data as [DeviceState?] for the active Leveltronic.
///
/// Null values indicate stale data: no instrument, or the connection ended.
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) async* {
  final session = ref.watch(leveltronicSessionProvider);
  if (session == null) {
    yield null;
    return;
  }
  // A late subscriber (a screen opened mid-session) gets the last merged
  // state at once instead of waiting for the next push.
  yield session.state;
  yield* session.states;
  // The feed ends with the session: the stale sentinel.
  yield null;
});
