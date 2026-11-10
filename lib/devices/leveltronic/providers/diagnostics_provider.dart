import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/api_catalog.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';

/// Topics SIGNAL_DIAG: RMS, peak-to-peak and phase of the four ADC channels
/// (ch0..ch3 = S2, B, A, S1). Only subscribed while a screen watches it.
final signalDiagProvider = StreamProvider.autoDispose<ApiSignalDiag>((ref) {
  return ref.watch(instrumentApiProvider).signalDiagUpdates(intervalMs: 500);
});

/// The ADC PGA gain of S1 and S2 (index 0 = S1, 1 = S2), read once per visit;
/// null where the firmware (before 0.11.8) does not have the resource.
final sensorPgaProvider = FutureProvider.autoDispose<List<int?>>((ref) async {
  final api = ref.watch(instrumentApiProvider);
  return [for (final d in kSensorPga) await api.tryReadValue(d)];
});
