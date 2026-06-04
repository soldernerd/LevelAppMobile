import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

void main() {
  group('MockBleManager', () {
    // MOCK-01: Packet rate and angle bounds
    test('statePackets emits at least 10 packets in 1s and angles stay within bounds', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final packets = <List<int>>[];

        // Subscribe BEFORE connect (broadcast streams don't buffer)
        mock.statePackets.listen(packets.add);

        // Trigger connect (no await inside fakeAsync — use elapse + flushFutures)
        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300)); // fires connect delay
        async.flushMicrotasks(); // resolves the Future.delayed continuation

        // Elapse 1000ms — 10 ticks at 100ms each
        async.elapse(const Duration(milliseconds: 1000));

        expect(packets.length, greaterThanOrEqualTo(10));

        for (final packet in packets) {
          final state = StatePacket.parse(packet);
          expect(
            state.angleX,
            inInclusiveRange(-45.0, 45.0),
            reason: 'angleX ${state.angleX} must be within [-45.0, 45.0]',
          );
          expect(
            state.angleY,
            inInclusiveRange(-45.0, 45.0),
            reason: 'angleY ${state.angleY} must be within [-45.0, 45.0]',
          );
        }

        mock.dispose();
      });
    });

    // MOCK-02: Battery drift — decrements by at least 1 in 10 seconds virtual time
    test('battery decrements by at least 1 after 10 seconds of virtual time', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final packets = <List<int>>[];

        mock.statePackets.listen(packets.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Capture initial battery from first packet
        async.elapse(const Duration(milliseconds: 100)); // 1 tick
        final initialBattery = StatePacket.parse(packets.first).battery;

        // Elapse 10000ms — 100 ticks — one battery drain cycle (100 ticks → -1%)
        async.elapse(const Duration(milliseconds: 10000));

        final finalBattery = StatePacket.parse(packets.last).battery;
        expect(
          finalBattery,
          lessThan(initialBattery),
          reason: 'Battery should have decremented: initial=$initialBattery, final=$finalBattery',
        );

        mock.dispose();
      });
    });

    // MOCK-03: connect() emits connecting then connected
    test('connect() emits ConnectionStatus.connecting then .connected', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final statuses = <ConnectionStatus>[];

        // Subscribe BEFORE connect (PITFALL-2: expectLater must precede emission)
        mock.connectionStatus.listen(statuses.add);

        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(
          statuses,
          containsAllInOrder([ConnectionStatus.connecting, ConnectionStatus.connected]),
        );

        mock.dispose();
      });
    });

    // MOCK-04: simulateDisconnect() emits disconnected and silences statePackets
    test('simulateDisconnect() emits .disconnected and statePackets goes silent', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));
        final statusEmitted = <ConnectionStatus>[];

        // Subscribe to connectionStatus BEFORE triggering emissions (PITFALL-2)
        mock.connectionStatus.listen(statusEmitted.add);

        // Connect and wait until connected
        mock.connect('AA:BB:CC:DD:EE:FF');
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Listen to statePackets and count events
        var count = 0;
        mock.statePackets.listen((_) => count++);

        // Elapse 500ms — 5 ticks
        async.elapse(const Duration(milliseconds: 500));
        final countAtDisconnect = count;
        expect(countAtDisconnect, greaterThanOrEqualTo(5));

        // Disconnect — statePackets must go silent
        mock.simulateDisconnect();

        // Elapse another 500ms — no new ticks should fire
        async.elapse(const Duration(milliseconds: 500));

        expect(
          count,
          equals(countAtDisconnect),
          reason: 'No new statePackets should be emitted after simulateDisconnect()',
        );
        expect(
          statusEmitted,
          contains(ConnectionStatus.disconnected),
          reason: 'simulateDisconnect() must emit ConnectionStatus.disconnected',
        );

        mock.dispose();
      });
    });
  });
}
