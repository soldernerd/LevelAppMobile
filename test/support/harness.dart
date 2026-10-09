import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/ble/simulated_device.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Runs [f] to completion inside a [FakeAsync] zone by advancing the virtual
/// clock in [step]s; returns its value or rethrows its error. The simulator
/// and the wizards are timer driven, so this is how a test "waits".
T settle<T>(
  FakeAsync async,
  Future<T> f, {
  Duration max = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 50),
}) {
  T? value;
  Object? error;
  StackTrace? stack;
  var done = false;
  f.then<void>((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    stack = s;
    done = true;
  });
  async.flushMicrotasks();
  var elapsed = Duration.zero;
  while (!done && elapsed < max) {
    async.elapse(step);
    elapsed += step;
  }
  if (!done) throw TimeoutException('did not complete in $max');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

/// Advances virtual time by [d] in small steps (so chained timers and
/// microtasks interleave as they do in real life).
void pass(FakeAsync async, Duration d,
    {Duration step = const Duration(milliseconds: 50)}) {
  var elapsed = Duration.zero;
  while (elapsed < d) {
    async.elapse(step);
    elapsed += step;
  }
  async.flushMicrotasks();
}

/// A container wired to a [MockBleManager] (and so a simulated instrument).
class SimHarness {
  SimHarness({SimulatedDevice? device, MockBleManager? manager})
      : mock = manager ?? MockBleManager(device: device ?? SimulatedDevice()) {
    container = ProviderContainer(
      overrides: [bleManagerProvider.overrideWithValue(mock)],
    );
    addTearDown(container.dispose);
    addTearDown(mock.dispose);
  }

  final MockBleManager mock;
  late final ProviderContainer container;

  SimulatedDevice get sim => mock.sim;

  /// Connects through the notifier and lets the live feed seed itself.
  void connect(FakeAsync async) {
    settle(async,
        container.read(connectionNotifierProvider.notifier).connect('id'));
    pass(async, const Duration(milliseconds: 600));
  }
}
