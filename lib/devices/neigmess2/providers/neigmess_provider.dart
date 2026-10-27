import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/neigmess2/neigmess_session.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// The NeigMess2 the UI is currently focused on, or null if the active device
/// is something else (or nothing).
final neigmessSessionProvider = Provider<NeigMessSession?>((ref) {
  final s = ref.watch(activeSessionProvider);
  return s is NeigMessSession ? s : null;
});

/// Live data of the active NeigMess2. Null values indicate stale data: no
/// device, or the connection ended.
final neigmessDataProvider = StreamProvider<NeigMessState?>((ref) async* {
  final session = ref.watch(neigmessSessionProvider);
  if (session == null) {
    yield null;
    return;
  }
  yield session.state;
  yield* session.states;
  yield null;
});
