import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inclinometer/providers/info_provider.dart';

/// "Zero the difference": an offset subtracted from Diff on the live and
/// precision screens. The firmware has no such function — its zero is a
/// per-sensor calibration (flip calibration) and moving that would change
/// S1 and S2 too — so this is app-side and per instrument (keyed by serial).
class TareNotifier extends Notifier<double?> {
  String? _serial;

  @override
  double? build() {
    final serial = ref.watch(identityProvider).asData?.value.serial;
    _serial = serial;
    if (serial != null) _load(serial);
    return null;
  }

  static String _key(String serial) => 'tare_diff_$serial';

  Future<void> _load(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_key(serial));
      if (ref.mounted && _serial == serial) state = v;
    } catch (_) {}
  }

  /// Zero Diff at its current value.
  Future<void> set(double diff) async {
    state = diff;
    final serial = _serial;
    if (serial == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key(serial), diff);
    } catch (_) {}
  }

  Future<void> clear() async {
    state = null;
    final serial = _serial;
    if (serial == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(serial));
    } catch (_) {}
  }
}

final tareProvider =
    NotifierProvider<TareNotifier, double?>(TareNotifier.new);
