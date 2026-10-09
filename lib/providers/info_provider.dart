import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Identity (firmware, serial, build) of the connected instrument.
final identityProvider = FutureProvider.autoDispose<ApiIdentity>((ref) {
  // Re-read when the connection changes (a different instrument).
  ref.watch(connectionNotifierProvider);
  return ref.watch(instrumentApiProvider).identity();
});

/// A value together with the phone time it was read at.
class Timed<T> {
  const Timed(this.value, this.at);
  final T value;
  final DateTime at;
}

/// Polls [read] every [every] while someone listens. A read still in flight
/// when the next tick comes is not doubled up; a failed read is skipped.
Stream<Timed<T>> _poll<T>(
  Duration every,
  Future<T> Function() read,
) {
  late final StreamController<Timed<T>> controller;
  Timer? timer;
  var busy = false;

  Future<void> tick() async {
    if (busy) return;
    busy = true;
    try {
      final v = await read();
      if (!controller.isClosed) controller.add(Timed(v, DateTime.now()));
    } catch (_) {
      // Try again on the next tick.
    } finally {
      busy = false;
    }
  }

  controller = StreamController<Timed<T>>(
    onListen: () {
      tick();
      timer = Timer.periodic(every, (_) => tick());
    },
    onCancel: () => timer?.cancel(),
  );
  return controller.stream;
}

/// System HEALTH, refreshed every 5 s while a screen watches it.
final healthProvider = StreamProvider.autoDispose<Timed<ApiHealth>>((ref) {
  final api = ref.watch(instrumentApiProvider);
  return _poll(const Duration(seconds: 5), api.health);
});

/// System RTC, refreshed every second while a screen watches it (the clock
/// has no subscription).
final rtcProvider = StreamProvider.autoDispose<Timed<ApiRtc>>((ref) {
  final api = ref.watch(instrumentApiProvider);
  return _poll(const Duration(seconds: 1), api.rtc);
});
