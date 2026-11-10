import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Names the user gave to known instruments, keyed by BLE id (the address the
/// scan list and the connection both know, so a name shows before connecting
/// too). Kept in SharedPreferences; shown in addition to the technical
/// identifier, never instead of it.
class DeviceNamesNotifier extends Notifier<Map<String, String>> {
  static const _key = 'device_names';

  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || !ref.mounted) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      // A rename made before the load finished wins.
      state = {for (final e in m.entries) e.key: '${e.value}', ...state};
    } catch (_) {}
  }

  /// Gives [id] the [name]; an empty name removes it.
  Future<void> rename(String id, String name) async {
    final n = name.trim();
    final next = Map<String, String>.of(state);
    if (n.isEmpty) {
      next.remove(id);
    } else {
      next[id] = n;
    }
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next));
    } catch (_) {}
  }
}

final deviceNamesProvider =
    NotifierProvider<DeviceNamesNotifier, Map<String, String>>(
  DeviceNamesNotifier.new,
);
