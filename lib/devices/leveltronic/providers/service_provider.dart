import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';

/// Whether the instrument currently reports service mode (STATUS topic).
/// Service mode can only be switched on at the instrument itself; the app can
/// only observe it and switch it off (Commands SERVICE_END).
final serviceModeProvider = Provider<bool>((ref) {
  return ref.watch(instrumentDataProvider).asData?.value?.serviceMode ?? false;
});

/// Service mode ends by itself after 10 minutes without an API request. The
/// calibration wizards can sit idle for longer than that (waiting for the
/// user to turn the instrument, place a shim, …), so while one is open this
/// provider sends a cheap request every 30 s. Watch it from the wizard
/// screens.
final serviceKeepAliveProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!ref.read(serviceModeProvider)) return;
    ref.read(instrumentApiProvider).state().then<void>((_) {}, onError: (Object _) {});
  });
  ref.onDispose(timer.cancel);
});
