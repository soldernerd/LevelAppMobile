import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_v2.dart';
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

/// A [MockBleManager] whose zero-cal poll never resolves on its own — the
/// test completes [pendingPoll] manually to control exactly when a
/// (possibly stale) response lands.
class _StallingZeroCalManager extends MockBleManager {
  Completer<Api2ZeroCalStatus?>? pendingPoll;

  @override
  Future<Api2ZeroCalStatus?> pollZeroCalibration() {
    final c = Completer<Api2ZeroCalStatus?>();
    pendingPoll = c;
    return c.future;
  }
}

/// Same idea for the precision-measurement poll.
class _StallingPrecisionManager extends MockBleManager {
  Completer<Api2PrecisionStatus?>? pendingPoll;

  @override
  Future<Api2PrecisionStatus?> pollPrecisionMeasurement() {
    final c = Completer<Api2PrecisionStatus?>();
    pendingPoll = c;
    return c.future;
  }
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

    // Regression test: a poll that was already in flight when the user hit
    // Cancel must not be allowed to land its (possibly stale, possibly
    // error-shaped) result on top of the state cancel() already set.
    test('a stale poll response arriving after cancel() is discarded', () {
      fakeAsync((async) {
        final mock = _StallingZeroCalManager();
        final container = buildContainer(mock);
        final notifier = container.read(zeroCalibrationProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.runningStep1));

        // First poll tick fires and stalls — response deliberately withheld.
        async.elapse(const Duration(milliseconds: 200));
        final stalled = mock.pendingPoll!;
        expect(stalled.isCompleted, isFalse);

        notifier.cancel();
        async.flushMicrotasks();
        expect(container.read(zeroCalibrationProvider).phase,
            equals(ZeroCalUiPhase.idle));

        // The stale request finally resolves — must be ignored, not resurrect
        // progress or (if it had been a comms-failure null) an error.
        stalled.complete(
          const Api2ZeroCalStatus(
              phase: ZeroCalPhase.step1Running, progress: 16, target: 32),
        );
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

    // Regression test for the reported bug: a "done" result for a poll that
    // was already in flight when the user cancelled must not resurrect a
    // result (or a manufactured "lost contact" error) after cancel() already
    // reset the screen to idle.
    test('a stale "done" poll response arriving after cancel() is discarded',
        () {
      fakeAsync((async) {
        final mock = _StallingPrecisionManager();
        final container = buildContainer(mock);
        final notifier = container.read(precisionMeasurementProvider.notifier);

        notifier.start();
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.running));

        async.elapse(const Duration(milliseconds: 200));
        final stalled = mock.pendingPoll!;
        expect(stalled.isCompleted, isFalse);

        notifier.cancel();
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.idle));

        stalled.complete(const Api2PrecisionStatus(
          phase: PrecisionPhase.done,
          target: 64,
          count1: 64,
          count2: 64,
          elapsedMs: 3000,
          timedOut: false,
          delta1Mm: 1.0,
          delta2Mm: 2.0,
        ));
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.idle));
      });
    });

    // Same guard, other branch: a stale poll *failure* (comms hiccup, not a
    // real device response) must not manufacture a "lost contact" error
    // after the screen already moved on.
    test('a stale comms-failure poll arriving after cancel() does not '
        'manufacture an error', () {
      fakeAsync((async) {
        final mock = _StallingPrecisionManager();
        final container = buildContainer(mock);
        final notifier = container.read(precisionMeasurementProvider.notifier);

        notifier.start();
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 200));
        final stalled = mock.pendingPoll!;

        notifier.cancel();
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.idle));

        // Simulates RealBleManager's internal poll timeout finally firing —
        // must not surface as an error now that the run was cancelled.
        stalled.complete(null);
        async.flushMicrotasks();
        expect(container.read(precisionMeasurementProvider).phase,
            equals(PrecisionUiPhase.idle));
      });
    });
  });
}
