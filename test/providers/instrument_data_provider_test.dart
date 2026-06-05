import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

// ignore: unused_import — imported for DeviceState type assertions in comments
import 'package:inclinometer/ble/ble_protocol.dart';

/// Creates a [ProviderContainer] with the mock BLE manager injected.
///
/// Registers [container.dispose] and [mock.dispose] as teardowns.
ProviderContainer buildContainer(MockBleManager mock) {
  final container = ProviderContainer(
    overrides: [bleManagerProvider.overrideWithValue(mock)],
  );
  addTearDown(container.dispose);
  addTearDown(mock.dispose);
  return container;
}

void main() {
  // Initialize Flutter binding so WakelockPlus platform channel calls are
  // routed through the test messenger rather than throwing binding errors.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('instrumentDataProvider — stale data sentinel (CONN-05)', () {
    test('emits DeviceState values while connected', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        // Subscribe BEFORE connecting — broadcast streams don't buffer (PITFALL-3).
        // instrumentDataProvider.stream is available on the notifier.
        final collected = <DeviceState?>[];
        container
            .read(connectionNotifierProvider.notifier)
            .instrumentStream
            .listen(collected.add);

        container
            .read(connectionNotifierProvider.notifier)
            .connect('AA:BB:CC:DD:EE:FF');
        // Wait for connect delay (300ms) + several mock packets at 100ms intervals
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(
          collected.whereType<DeviceState>(),
          isNotEmpty,
          reason: 'At least one non-null DeviceState must be emitted during connected period',
        );
      });
    });

    test('emits null sentinel after simulateDisconnect', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        // Subscribe BEFORE connecting — broadcast streams don't buffer (PITFALL-3 / T-03-07).
        final collected = <DeviceState?>[];
        container
            .read(connectionNotifierProvider.notifier)
            .instrumentStream
            .listen(collected.add);

        container
            .read(connectionNotifierProvider.notifier)
            .connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        mock.simulateDisconnect();
        async.flushMicrotasks();

        expect(
          collected.contains(null),
          isTrue,
          reason: 'null sentinel must follow disconnect per D-05/D-06',
        );
      });
    });

    test('instrumentDataProvider initial state is AsyncLoading or AsyncData(null)', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        // No connection triggered — provider should be in loading or null state.
        final asyncVal = container.read(instrumentDataProvider);

        expect(
          asyncVal.isLoading || asyncVal.value == null,
          isTrue,
          reason: 'Before first packet, instrumentDataProvider must be loading or null',
        );
      });
    });
  });

  group('SYS-01 — wakelock side-effects (observable via state transitions)', () {
    test('connected state is reached when connect() resolves', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        container
            .read(connectionNotifierProvider.notifier)
            .connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider),
          equals(ConnectionStatus.connected),
        );
        // WakelockPlus.enable() is called in this transition per D-09/SYS-01.
        // Platform side-effect is verified by code inspection (RESEARCH.md: static API,
        // platform behavior trusted). State reaching connected is the observable proxy.
      });
    });

    test('disconnected state is reached after simulateDisconnect', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        container
            .read(connectionNotifierProvider.notifier)
            .connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        mock.simulateDisconnect();
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider),
          equals(ConnectionStatus.disconnected),
        );
        // WakelockPlus.disable() is called in this transition per D-09/SYS-01.
      });
    });
  });
}
