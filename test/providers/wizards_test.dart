import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/devices/leveltronic/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/flip_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/gain_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/phase_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/precision_provider.dart';

import '../support/harness.dart';

/// Keeps an autoDispose provider alive for the test and returns a reader.
T Function() hold<T>(ProviderContainer c, ProviderListenable<T> p) {
  final sub = c.listen<T>(p, (_, _) {});
  addTearDown(sub.close);
  return () => sub.read();
}

void main() {
  group('precision', () {
    test('runs to a result with progress along the way', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, precisionProvider);
        final seen = <PrecisionStage>{};
        var maxProgress = 0.0;
        h.container.listen(precisionProvider, (_, s) {
          seen.add(s.stage);
          if (s.progress > maxProgress) maxProgress = s.progress;
        });

        h.container.read(precisionProvider.notifier).start();
        pass(async, const Duration(milliseconds: 500));
        expect(state().stage, equals(PrecisionStage.running));
        pass(async, const Duration(seconds: 4));

        expect(state().stage, equals(PrecisionStage.done));
        expect(seen, containsAll([PrecisionStage.running, PrecisionStage.done]));
        expect(maxProgress, greaterThan(0.5), reason: 'progress was shown');
        // S1 − S2 of the simulated tilts (0.8 and 0.5) with its cal errors.
        expect(state().tiltDiff, closeTo(state().tiltS1 - state().tiltS2, 1e-5));
        expect(state().tiltS1, greaterThan(0.5));
      });
    });

    test('says so when no quiet window appears', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.precisionNeverClean = true;
        final state = hold(h.container, precisionProvider);
        h.container.read(precisionProvider.notifier).start();
        pass(async, const Duration(seconds: 7));
        expect(state().stage, equals(PrecisionStage.failed));
        expect(state().message, contains('quiet'));
      });
    });

    test('reports a refusal from the device', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        settle(async, h.mock.sim.request(opExecute(CmdRes.tiltDemod), [0]));
        final state = hold(h.container, precisionProvider);
        h.container.read(precisionProvider.notifier).start();
        pass(async, const Duration(seconds: 1));
        expect(state().stage, equals(PrecisionStage.error));
        expect(state().message, contains('busy'));
      });
    });

    test('cancel returns to idle and stops the device', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, precisionProvider);
        final n = h.container.read(precisionProvider.notifier);
        n.start();
        pass(async, const Duration(milliseconds: 600));
        expect(state().stage, equals(PrecisionStage.running));
        settle(async, n.cancel());
        expect(state().stage, equals(PrecisionStage.idle));
        pass(async, const Duration(seconds: 4));
        expect(state().stage, equals(PrecisionStage.idle));
        final s = settle(async, h.mock.sim.request(opGet(ApiCat.procedures, ProcRes.precision)));
        expect(s.data[0], equals(PrecisionPhase.idle.value));
      });
    });

    test('a second measurement is not fooled by the first one\'s result', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, precisionProvider);
        final n = h.container.read(precisionProvider.notifier);
        n.start();
        pass(async, const Duration(seconds: 4));
        expect(state().stage, equals(PrecisionStage.done));
        final first = state().tiltS1;

        // The tilt changes, then a new run is started. The device still holds
        // the old "done" result until the new run replaces it.
        h.sim.physicalTilt = [2.0, 0.5];
        n.start();
        pass(async, const Duration(milliseconds: 300));
        expect(state().stage, equals(PrecisionStage.running));
        pass(async, const Duration(seconds: 4));
        expect(state().stage, equals(PrecisionStage.done));
        expect(state().tiltS1, greaterThan(first + 0.5));
      });
    });
  });

  group('flip calibration wizard', () {
    test('walks both steps and records before / after', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, flipCalProvider);
        final n = h.container.read(flipCalProvider.notifier);
        pass(async, const Duration(milliseconds: 100));
        expect(state().current, isNotNull, reason: 'current values are read');
        final zeroBefore = h.sim.calibration(kS1Zero);

        n.selectSensors(SensorMask.both);
        n.start();
        pass(async, const Duration(milliseconds: 300));
        expect(state().stage, equals(FlipStage.measuring1));
        pass(async, const Duration(seconds: 2));
        expect(state().stage, equals(FlipStage.turn));

        n.confirmTurned();
        pass(async, const Duration(milliseconds: 200));
        expect(state().stage, equals(FlipStage.measuring2));
        pass(async, const Duration(seconds: 3));

        expect(state().stage, equals(FlipStage.result));
        final run = state().lastRun!;
        expect(run.before.zeroPpm[0], equals(zeroBefore));
        expect(run.after.zeroPpm[0], equals(h.sim.calibration(kS1Zero)));
        expect(run.after.zeroPpm[0], isNot(equals(run.before.zeroPpm[0])));
        expect(run.mask, equals(SensorMask.both));
      });
    });

    test('a single sensor leaves the other one\'s zero alone', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, flipCalProvider);
        final n = h.container.read(flipCalProvider.notifier);
        pass(async, const Duration(milliseconds: 100));
        final s2 = h.sim.calibration(kS2Zero);
        n.selectSensors(SensorMask.s1);
        n.start();
        pass(async, const Duration(seconds: 3));
        n.confirmTurned();
        pass(async, const Duration(seconds: 4));
        expect(state().stage, equals(FlipStage.result));
        expect(h.sim.calibration(kS2Zero), equals(s2));
      });
    });

    test('without service mode it ends in an error that asks for it', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, flipCalProvider);
        h.container.read(flipCalProvider.notifier).start();
        pass(async, const Duration(seconds: 1));
        expect(state().stage, equals(FlipStage.error));
        expect(state().needsService, isTrue);
        expect(state().message, contains('Service mode'));
      });
    });

    test('a repeat run is recorded next to the first', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, flipCalProvider);
        final n = h.container.read(flipCalProvider.notifier);
        pass(async, const Duration(milliseconds: 100));
        for (var run = 0; run < 2; run++) {
          n.start();
          pass(async, const Duration(seconds: 3));
          n.confirmTurned();
          pass(async, const Duration(seconds: 4));
          expect(state().stage, equals(FlipStage.result));
          n.backToStart();
          pass(async, const Duration(milliseconds: 200));
        }
        expect(state().runs, hasLength(2));
        // The second run finds (almost) nothing left to correct.
        final second = state().runs[1];
        expect((second.after.zeroPpm[0] - second.before.zeroPpm[0]).abs(),
            lessThanOrEqualTo(1));
      });
    });

    test('cancel returns to the selection and aborts the device', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, flipCalProvider);
        final n = h.container.read(flipCalProvider.notifier);
        n.start();
        pass(async, const Duration(milliseconds: 500));
        settle(async, n.cancel());
        expect(state().stage, equals(FlipStage.select));
        pass(async, const Duration(seconds: 3));
        expect(state().stage, equals(FlipStage.select));
      });
    });
  });

  group('phase calibration wizard', () {
    /// Runs the wizard up to the review stage with a tilt step of [step].
    PhaseCalState runToReview(FakeAsync async, SimHarness h,
        PhaseCalState Function() state,
        {double step = 0.1}) {
      final n = h.container.read(phaseCalProvider.notifier);
      n.begin();
      h.sim.physicalTilt = [0.0, 0.0];
      n.captureReference();
      pass(async, const Duration(seconds: 9));
      expect(state().stage, equals(PhaseStage.tilted));
      h.sim.physicalTilt = [step, step];
      n.captureTilted();
      pass(async, const Duration(seconds: 9));
      return state();
    }

    test('finds the true phase of both sensors and writes it', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, phaseCalProvider);
        pass(async, const Duration(milliseconds: 200));
        final before1 = h.sim.calibration(kS1Phase);

        final s = runToReview(async, h, state);
        expect(s.stage, equals(PhaseStage.review));
        expect(s.estimates[0]!.angleDeg, closeTo(h.sim.truePhaseDeg[0], 0.1));
        expect(s.estimates[1]!.angleDeg, closeTo(h.sim.truePhaseDeg[1], 0.1));
        expect(s.samples, greaterThan(250));

        h.container.read(phaseCalProvider.notifier).apply();
        pass(async, const Duration(seconds: 1));
        final done = state();
        expect(done.stage, equals(PhaseStage.done));
        expect(done.before![0], equals(before1));
        expect(done.after![0], closeTo(h.sim.truePhaseDeg[0] * 100, 10));
        expect(done.after![1], closeTo(h.sim.truePhaseDeg[1] * 100, 10));
        expect(h.sim.calibration(kS1Phase), equals(done.after![0]));
      });
    });

    test('only the selected sensor is written', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        final state = hold(h.container, phaseCalProvider);
        final n = h.container.read(phaseCalProvider.notifier);
        pass(async, const Duration(milliseconds: 200));
        final s2Before = h.sim.calibration(kS2Phase);
        n.selectSensors(SensorMask.s1);
        runToReview(async, h, state);
        n.apply();
        pass(async, const Duration(seconds: 1));
        expect(state().stage, equals(PhaseStage.done));
        expect(h.sim.calibration(kS2Phase), equals(s2Before));
        expect(h.sim.calibration(kS1Phase), closeTo(1200, 10));
      });
    });

    test('works whichever way the step goes', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, phaseCalProvider);
        final s = runToReview(async, h, state, step: -0.2);
        expect(s.estimates[0]!.angleDeg, closeTo(h.sim.truePhaseDeg[0], 0.1));
      });
    });

    test('no step at all gives no estimate', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, phaseCalProvider);
        final s = runToReview(async, h, state, step: 0.0);
        expect(s.estimates[0], isNull,
            reason: 'a zero step has no direction to find');
      });
    });

    test('applying without service mode asks for it', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, phaseCalProvider);
        runToReview(async, h, state);
        h.container.read(phaseCalProvider.notifier).apply();
        pass(async, const Duration(seconds: 1));
        expect(state().stage, equals(PhaseStage.error));
        expect(state().needsService, isTrue);
      });
    });

    test('an out-of-range phase is flagged and not written', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        h.sim.truePhaseDeg = [70.0, 10.5];
        final state = hold(h.container, phaseCalProvider);
        final s = runToReview(async, h, state);
        expect(s.estimates[0]!.inRange, isFalse);
        final stored = h.sim.calibration(kS1Phase);
        h.container.read(phaseCalProvider.notifier).apply();
        pass(async, const Duration(seconds: 1));
        expect(h.sim.calibration(kS1Phase), equals(stored));
        expect(h.sim.calibration(kS2Phase), closeTo(1050, 10));
      });
    });

    test('too few batches is an error', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, phaseCalProvider);
        final n = h.container.read(phaseCalProvider.notifier);
        n.begin();
        // The demodulation is stopped: no usable phasor stream.
        settle(async, h.mock.sim.request(opExecute(CmdRes.tiltDemod), [0]));
        h.sim.linkDown();
        n.captureReference();
        pass(async, const Duration(seconds: 10));
        expect(state().stage, equals(PhaseStage.error));
      });
    });
  });

  group('gain calibration wizard', () {
    GainCalState runToReview(FakeAsync async, SimHarness h,
        GainCalState Function() state,
        {double step = 0.1}) {
      final n = h.container.read(gainCalProvider.notifier);
      n.setShim(heightMm: 0.1, baselineMm: 1000);
      n.begin();
      h.sim.physicalTilt = [0.0, 0.0];
      n.measureBaseline();
      pass(async, const Duration(seconds: 5));
      expect(state().stage, equals(GainStage.shim));
      h.sim.physicalTilt = [step, step];
      n.measureShim();
      pass(async, const Duration(seconds: 5));
      return state();
    }

    test('sets k so that the known step reads as the known tilt', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        // Phase already right, so only k is off.
        h.sim.setCalibration(kS1Phase, 1200);
        h.sim.setCalibration(kS2Phase, 1050);
        final state = hold(h.container, gainCalProvider);
        pass(async, const Duration(milliseconds: 200));

        final s = runToReview(async, h, state);
        expect(s.stage, equals(GainStage.review));
        expect(s.estimates[0]!.kOldMicro, equals(45000));
        expect(s.estimates[0]!.kNewMicro, closeTo(50000, 300));
        expect(s.estimates[1]!.kNewMicro, closeTo(48000, 300));

        h.container.read(gainCalProvider.notifier).apply();
        pass(async, const Duration(seconds: 6));
        final done = state();
        expect(done.stage, equals(GainStage.done));
        expect(done.kBefore![0], equals(45000));
        expect(done.kAfter![0], closeTo(50000, 300));
        expect(h.sim.calibration(kS1K), equals(done.kAfter![0]));
        // The proof: the step now reads as the known 0.1 mm/m.
        expect(done.verifyReading![0], closeTo(0.1, 0.002));
        expect(done.verifyReading![1], closeTo(0.1, 0.002));
      });
    });

    test('a different shim and edge give the same k', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        h.sim.setCalibration(kS1Phase, 1200);
        h.sim.setCalibration(kS2Phase, 1050);
        final state = hold(h.container, gainCalProvider);
        pass(async, const Duration(milliseconds: 200));
        final n = h.container.read(gainCalProvider.notifier);
        n.setShim(heightMm: 0.05, baselineMm: 250); // 0.2 mm/m
        expect(state().knownTilt, closeTo(0.2, 1e-9));
        n.begin();
        h.sim.physicalTilt = [0.0, 0.0];
        n.measureBaseline();
        pass(async, const Duration(seconds: 5));
        h.sim.physicalTilt = [0.2, 0.2];
        n.measureShim();
        pass(async, const Duration(seconds: 5));
        expect(state().estimates[0]!.kNewMicro, closeTo(50000, 300));
      });
    });

    test('only the selected sensor is written', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.setServiceMode(true);
        h.sim.setCalibration(kS1Phase, 1200);
        h.sim.setCalibration(kS2Phase, 1050);
        final state = hold(h.container, gainCalProvider);
        final n = h.container.read(gainCalProvider.notifier);
        pass(async, const Duration(milliseconds: 200));
        n.selectSensors(SensorMask.s2);
        runToReview(async, h, state);
        n.apply();
        pass(async, const Duration(seconds: 6));
        expect(h.sim.calibration(kS1K), equals(45000));
        expect(h.sim.calibration(kS2K), closeTo(48000, 300));
      });
    });

    test('applying without service mode asks for it', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, gainCalProvider);
        runToReview(async, h, state);
        h.container.read(gainCalProvider.notifier).apply();
        pass(async, const Duration(seconds: 1));
        expect(state().stage, equals(GainStage.error));
        expect(state().needsService, isTrue);
      });
    });

    test('a disturbed table sends the user back to measure again', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        h.sim.precisionNeverClean = true;
        final state = hold(h.container, gainCalProvider);
        final n = h.container.read(gainCalProvider.notifier);
        n.begin();
        n.measureBaseline();
        pass(async, const Duration(seconds: 7));
        expect(state().stage, equals(GainStage.baseline));
        expect(state().message, contains('quiet'));
      });
    });

    test('no shim input means no start', () {
      fakeAsync((async) {
        final h = SimHarness()..connect(async);
        final state = hold(h.container, gainCalProvider);
        final n = h.container.read(gainCalProvider.notifier);
        n.setShim(heightMm: 0, baselineMm: 1000);
        n.begin();
        expect(state().stage, equals(GainStage.setup));
      });
    });
  });
}
