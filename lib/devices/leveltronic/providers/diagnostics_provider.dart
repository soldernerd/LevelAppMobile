import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';

/// Topics SIGNAL_DIAG: RMS, peak-to-peak and phase of the four ADC channels
/// (S2, B, A, S1). Only subscribed while a screen watches it.
final signalDiagProvider = StreamProvider.autoDispose<ApiSignalDiag>((ref) {
  return ref.watch(instrumentApiProvider).signalDiagUpdates(intervalMs: 500);
});
