import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

void main() {
  group('MockBleManager', () {
    test('deviceStream emits animated snapshots once connected', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final states = <DeviceState?>[];
        mock.deviceStream.listen(states.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 1)); // 4 ticks at 250 ms

        final snapshots = states.whereType<DeviceState>().toList();
        expect(snapshots.length, greaterThanOrEqualTo(4));
        for (final s in snapshots) {
          expect(s.angleX, isNull, reason: 'tilt is never synthesised');
          expect(s.batteryPercent, inInclusiveRange(0, 100));
          expect(s.onboardTempC, isNotNull);
          expect(s.humidityPct, inInclusiveRange(20, 80));
        }
        mock.dispose();
      });
    });

    test('battery drains over virtual time', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final states = <DeviceState?>[];
        mock.deviceStream.listen(states.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 250)); // first tick
        final initial = states.whereType<DeviceState>().first.batteryPercent;

        async.elapse(const Duration(seconds: 20)); // > 40 ticks -> at least one drain
        final last = states.whereType<DeviceState>().last.batteryPercent;

        expect(last, lessThan(initial));
        mock.dispose();
      });
    });

    test('connect() emits connecting then connected', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final statuses = <ConnectionStatus>[];
        mock.connectionStatus.listen(statuses.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(
          statuses,
          containsAllInOrder(
              [ConnectionStatus.connecting, ConnectionStatus.connected]),
        );
        mock.dispose();
      });
    });

    test('simulateDisconnect() emits disconnected + null sentinel and stops ticking',
        () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final statuses = <ConnectionStatus>[];
        final states = <DeviceState?>[];
        mock.connectionStatus.listen(statuses.add);
        mock.deviceStream.listen(states.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 750)); // a few ticks

        final countBefore = states.whereType<DeviceState>().length;
        expect(countBefore, greaterThanOrEqualTo(2));

        mock.simulateDisconnect();
        async.elapse(const Duration(seconds: 1));

        expect(states.whereType<DeviceState>().length, equals(countBefore));
        expect(states.last, isNull);
        expect(statuses, contains(ConnectionStatus.disconnected));
        mock.dispose();
      });
    });
  });
}
