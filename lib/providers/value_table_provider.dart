import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Reads a table of Settings or Calibrations (one GET per row) and writes
/// single rows back. A row the firmware does not have (an `optional` one
/// answering UNKNOWN_RESOURCE) reads as null and the UI hides it.
class ValueTableNotifier extends AsyncNotifier<Map<int, int?>> {
  ValueTableNotifier(this.defs);

  final List<ApiValueDef> defs;

  @override
  Future<Map<int, int?>> build() => _readAll();

  Future<Map<int, int?>> _readAll() async {
    final api = ref.read(instrumentApiProvider);
    final entries = await Future.wait(defs.map((d) async {
      try {
        return MapEntry(d.id, await api.tryReadValue(d));
      } catch (_) {
        return MapEntry<int, int?>(d.id, null);
      }
    }));
    return Map.fromEntries(entries);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_readAll);
  }

  /// Writes [def] and re-reads it (the device clamps / rejects as it sees fit).
  /// Throws `ApiException` if the device refuses.
  Future<void> write(ApiValueDef def, int value) async {
    final api = ref.read(instrumentApiProvider);
    await api.writeValue(def, value);
    final actual = await api.readValue(def);
    final current = state.asData?.value ?? const <int, int?>{};
    state = AsyncData({...current, def.id: actual});
  }
}

final settingsTableProvider =
    AsyncNotifierProvider.autoDispose<ValueTableNotifier, Map<int, int?>>(
  () => ValueTableNotifier(kSettings),
);

final calibrationTableProvider =
    AsyncNotifierProvider.autoDispose<ValueTableNotifier, Map<int, int?>>(
  () => ValueTableNotifier(kCalibrations),
);
