import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/connection.dart';
import 'package:inclinometer/providers/device_provider.dart';
import '../support/registry.dart';

/// Creates a [ProviderContainer] with the mock BLE manager injected.
///
/// Always registers [container.dispose] and [mock.dispose] as teardowns so
/// tests don't need to clean up manually.
ProviderContainer buildContainer(MockBleManager mock) {
  final container = ProviderContainer(
    overrides: [
      bleManagerProvider.overrideWithValue(mock),
      deviceRegistryProvider.overrideWithValue(testRegistry),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(mock.dispose);
  return container;
}

void main() {
  // WakelockPlus.enable/disable are static Flutter platform calls. They require a
  // Flutter binding to be initialized. We initialize it here so wakelock calls in
  // ConnectionNotifier succeed (they become no-ops in the test environment via the
  // platform channel mock). The try/catch in _handleStatusEvent is a secondary guard.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('ConnectionNotifier — state machine', () {
    test('starts in idle state', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        final status = container.read(connectionNotifierProvider);
        expect(status, equals(ConnectionStatus.idle));
      });
    });

    test('idle → scanning after startScan', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        container.read(connectionNotifierProvider.notifier).startScan();
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider),
          equals(ConnectionStatus.scanning),
        );
      });
    });

    test('scanning → connecting → connected after connect', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        // Subscribe BEFORE triggering transitions (broadcast streams don't buffer)
        final statuses = <ConnectionStatus>[];
        container.listen(
          connectionNotifierProvider,
          (_, next) => statuses.add(next),
        );

        container.read(connectionNotifierProvider.notifier).startScan();
        async.flushMicrotasks();

        container
            .read(connectionNotifierProvider.notifier)
            .connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider),
          equals(ConnectionStatus.connected),
        );
        expect(
          statuses,
          containsAllInOrder([
            ConnectionStatus.connecting,
            ConnectionStatus.connected,
          ]),
        );
      });
    });

    test('connected → disconnected after disconnect', () {
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

        container.read(connectionNotifierProvider.notifier).disconnect();
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider),
          equals(ConnectionStatus.disconnected),
        );
      });
    });

    test('connected → disconnected after simulateDisconnect', () {
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
      });
    });
  });

  group('ConnectionNotifier — scan results accumulation', () {
    test('scannedDevices accumulates devices during scan', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final container = buildContainer(mock);

        container.read(connectionNotifierProvider.notifier).startScan();
        // MockBleManager emits a scan result after 500ms (see mock_ble_manager.dart)
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(
          container.read(connectionNotifierProvider.notifier).scannedDevices,
          isNotEmpty,
          reason: 'scannedDevices must accumulate at least one device from mock scan',
        );
        expect(
          container.read(scanResultsProvider),
          isNotEmpty,
          reason: 'scanResultsProvider must reflect accumulated scanned devices',
        );
      });
    });
  });
}
