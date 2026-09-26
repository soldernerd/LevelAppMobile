import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/measurement_provider.dart';

/// Creates a [ProviderContainer] with the mock BLE manager injected.
ProviderContainer buildContainer(MockBleManager mock) {
  final container = ProviderContainer(
    overrides: [bleManagerProvider.overrideWithValue(mock)],
  );
  addTearDown(container.dispose);
  addTearDown(mock.dispose);
  return container;
}

void main() {
  group('ZeroCalibrationNotifier', () {
    test(
        'start -> runningStep1 -> awaitingRotation -> confirmRotated -> '
        'runningStep2 -> success', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final container = buildContainer(mock);
        final notifier = container.read(zeroCalibrationProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.runningStep1));

        // Mock's step 1 completes after 8 ticks @ 100ms = 800ms.
        async.elapse(const Duration(milliseconds: 1000));
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.awaitingRotation));

        notifier.confirmRotated();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.runningStep2));

        async.elapse(const Duration(milliseconds: 1000));
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.success));
      });
    });

    test('cancel() mid-step1 returns to idle without touching the device '
        'again', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final container = buildContainer(mock);
        final notifier = container.read(zeroCalibrationProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.runningStep1));

        notifier.cancel();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.idle));

        // No further progress after cancel — the poller was stopped.
        async.elapse(const Duration(seconds: 1));
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.idle));
      });
    });

    test('confirmRotated() is a no-op outside awaitingRotation', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final container = buildContainer(mock);
        final notifier = container.read(zeroCalibrationProvider.notifier);

        notifier.confirmRotated();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.idle));
      });
    });
  });

  group('PrecisionMeasurementNotifier', () {
    test('start -> running -> done with a result per sensor', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final container = buildContainer(mock);
        final notifier = container.read(precisionMeasurementProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.running));

        // Mock reaches target (64/64) after 8 ticks @ 100ms = 800ms.
        async.elapse(const Duration(milliseconds: 1000));
        final state = container.read(precisionMeasurementProvider);
        expect(state.phase, equals(PrecisionUiPhase.done));
        expect(state.count1, equals(64));
        expect(state.count2, equals(64));
        expect(state.timedOut, isFalse);
      });
    });

    test('cancel() mid-run returns to idle', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        final container = buildContainer(mock);
        final notifier = container.read(precisionMeasurementProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.running));

        notifier.cancel();
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.idle));
      });
    });

    test('progress is the slower of the two sensor counts, fraction of target',
        () {
      const state = PrecisionUiState(count1: 40, count2: 20, target: 64);
      expect(state.progress, closeTo(20 / 64, 1e-9));
    });
  });
}
