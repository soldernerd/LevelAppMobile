import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/ble/api_v2.dart';
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
          expect(s.displacementOk, isTrue);
          expect(s.displacementS1Mm, inInclusiveRange(-5.0, 5.0));
          expect(s.displacementS2Mm, inInclusiveRange(-5.0, 5.0));
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

  group('MockBleManager — zero calibration', () {
    test('step1 -> step1Done -> step2 -> idle (persisted zero)', () {
      fakeAsync((async) {
        final mock = MockBleManager(random: Random(0));

        Api2Status? step1Result;
        mock.zeroCalibrationStep1().then((s) => step1Result = s);
        async.flushMicrotasks();
        expect(step1Result, Api2Status.ok);

        Api2ZeroCalStatus? status;
        mock.pollZeroCalibration().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, ZeroCalPhase.step1Running);

        async.elapse(const Duration(milliseconds: 900)); // 9 ticks @100ms > 8 needed
        mock.pollZeroCalibration().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, ZeroCalPhase.step1Done);
        expect(status!.progress, equals(32));

        Api2Status? step2Result;
        mock.zeroCalibrationStep2().then((s) => step2Result = s);
        async.flushMicrotasks();
        expect(step2Result, Api2Status.ok);

        async.elapse(const Duration(milliseconds: 900));
        mock.pollZeroCalibration().then((s) => status = s);
        async.flushMicrotasks();
        // resultReady is transient on the real device too — idle means success.
        expect(status!.phase, ZeroCalPhase.idle);

        mock.dispose();
      });
    });

    test('step2 before step1 is rejected', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        Api2Status? result;
        mock.zeroCalibrationStep2().then((s) => result = s);
        async.flushMicrotasks();
        expect(result, Api2Status.busyResource);
        mock.dispose();
      });
    });

    test('cancel resets to idle mid-step1', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        mock.zeroCalibrationStep1();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        Api2Status? cancelResult;
        mock.zeroCalibrationCancel().then((s) => cancelResult = s);
        async.flushMicrotasks();
        expect(cancelResult, Api2Status.ok);

        Api2ZeroCalStatus? status;
        mock.pollZeroCalibration().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, ZeroCalPhase.idle);
        expect(status!.progress, equals(0));

        mock.dispose();
      });
    });
  });

  group('MockBleManager — triggered precision measurement', () {
    test('running -> done with a result per sensor', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        Api2Status? startResult;
        mock.startPrecisionMeasurement().then((s) => startResult = s);
        async.flushMicrotasks();
        expect(startResult, Api2Status.ok);

        async.elapse(const Duration(milliseconds: 300));
        Api2PrecisionStatus? status;
        mock.pollPrecisionMeasurement().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, PrecisionPhase.running);
        expect(status!.count1, greaterThan(0));

        async.elapse(const Duration(seconds: 1)); // enough ticks to reach target
        mock.pollPrecisionMeasurement().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, PrecisionPhase.done);
        expect(status!.count1, equals(64));
        expect(status!.count2, equals(64));
        expect(status!.timedOut, isFalse);

        mock.dispose();
      });
    });

    test('cancel resets to idle mid-run', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        mock.startPrecisionMeasurement();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));

        Api2Status? cancelResult;
        mock.cancelPrecisionMeasurement().then((s) => cancelResult = s);
        async.flushMicrotasks();
        expect(cancelResult, Api2Status.ok);

        Api2PrecisionStatus? status;
        mock.pollPrecisionMeasurement().then((s) => status = s);
        async.flushMicrotasks();
        expect(status!.phase, PrecisionPhase.idle);

        mock.dispose();
      });
    });
  });
}
