import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/devices/leveltronic/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';
import 'package:inclinometer/devices/leveltronic/simulated_device.dart';

import '../support/harness.dart';

/// The simulator is what every other test stands on, so it gets its own
/// tests: the protocol rules it enforces, and the physics (a flip calibration
/// must really remove the zero error).
void main() {
  group('protocol rules', () {
    test('IDENTITY reports API v3 and passes the compatibility check', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        final id = settle(async, api.verifyCompatible());
        expect(id.apiVersion, equals(3));
        expect(id.serial, equals('6DA08073'));
      });
    });

    test('an API v2 instrument is refused with IncompatibleFirmware', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice(apiVersion: 2));
        expect(
          () => settle(async, api.verifyCompatible()),
          throwsA(isA<IncompatibleFirmwareException>()
              .having((e) => e.apiVersion, 'apiVersion', 2)),
        );
      });
    });

    test('a verb that does not exist for a resource is VERB_NOT_VALID', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final r = settle(
            async, sim.request(opSet(ApiCat.system, SysRes.identity)));
        expect(r.status, equals(ApiStatus.verbNotValid));
      });
    });

    test('an unknown resource is UNKNOWN_RESOURCE', () {
      fakeAsync((async) {
        final r = settle(
            async, SimulatedDevice().request(opGet(ApiCat.system, 0x7E)));
        expect(r.status, equals(ApiStatus.unknownResource));
      });
    });
  });

  group('settings and calibrations', () {
    test('a setting round-trips; out of range is INVALID_PARAMETER', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        final autoOff = kSettings.firstWhere((d) => d.id == 0x60);
        settle(async, api.writeValue(autoOff, 600));
        expect(settle(async, api.readValue(autoOff)), equals(600));

        final charge = kSettings.firstWhere((d) => d.id == 0x52);
        expect(
          () => settle(async, api.writeValue(charge, 2000)),
          throwsA(isA<ApiException>()
              .having((e) => e.status, 's', ApiStatus.invalidParameter)),
        );
      });
    });

    test('battery critical must stay below battery low', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        final critical = kSettings.firstWhere((d) => d.id == 0x50);
        expect(
          () => settle(async, api.writeValue(critical, 3550)), // low is 3600
          returnsNormally,
        );
        expect(
          () => settle(async, api.writeValue(critical, 3600)),
          throwsA(isA<ApiException>()),
        );
      });
    });

    test('a calibration write needs service mode', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        expect(
          () => settle(async, api.writeValue(kS1Phase, 1234)),
          throwsA(isA<ApiException>()
              .having((e) => e.isServiceModeRequired, 'service', isTrue)),
        );
        sim.setServiceMode(true);
        settle(async, api.writeValue(kS1Phase, 1234));
        expect(settle(async, api.readValue(kS1Phase)), equals(1234));
      });
    });

    test('reading a calibration never needs service mode', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        expect(settle(async, api.readValue(kS1K)), isPositive);
      });
    });

    test('the optional charge timeout exists only when supported', () {
      fakeAsync((async) {
        final charge = kSettings.firstWhere((d) => d.id == 0x53);
        expect(
          settle(async,
              InstrumentApi(SimulatedDevice()).tryReadValue(charge)),
          isNull,
        );
        expect(
          settle(
              async,
              InstrumentApi(SimulatedDevice(supportsChargeFullTimeout: true))
                  .tryReadValue(charge)),
          equals(120),
        );
      });
    });

    test('service mode ends by itself after 10 minutes of silence', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..setServiceMode(true);
        expect(sim.serviceMode, isTrue);
        pass(async, const Duration(minutes: 9));
        expect(sim.serviceMode, isTrue);
        // A request restarts the timer.
        settle(async, InstrumentApi(sim).state());
        pass(async, const Duration(minutes: 9));
        expect(sim.serviceMode, isTrue);
        pass(async, const Duration(minutes: 2));
        expect(sim.serviceMode, isFalse);
      });
    });
  });

  group('commands', () {
    test('factory defaults need service mode and the 0xA5 confirm byte', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        expect(() => settle(async, api.factoryDefaults()),
            throwsA(isA<ApiException>()));
        sim.setServiceMode(true);
        sim.setCalibration(kS1K, 12345);
        settle(async, api.factoryDefaults());
        expect(sim.calibration(kS1K), equals(45000));
        final bad = settle(
            async, sim.request(opExecute(CmdRes.factoryDefaults), [0x00]));
        expect(bad.status, equals(ApiStatus.invalidParameter));
      });
    });

    test('power off acks, then the link goes down', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        var down = false;
        sim.onLinkDown = () => down = true;
        settle(async, InstrumentApi(sim).powerOff());
        pass(async, const Duration(milliseconds: 50));
        expect(down, isTrue);
      });
    });

    test('stopping the demodulation is refused while the phasor stream runs',
        () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        final sub = api.phasorStream().listen((_) {});
        pass(async, const Duration(milliseconds: 200));
        expect(() => settle(async, api.setTiltDemod(false)),
            throwsA(isA<ApiException>()));
        sub.cancel();
        pass(async, const Duration(milliseconds: 100));
        settle(async, api.setTiltDemod(false));
      });
    });
  });

  group('subscriptions', () {
    test('LIVE pushes once per reading and ends when the last listener leaves',
        () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        final seqs = <int>[];
        final sub = api.liveUpdates().listen((l) => seqs.add(l.seq));
        pass(async, const Duration(seconds: 2));
        expect(seqs.length, inInclusiveRange(6, 9)); // ~4.07 / s
        expect(seqs, equals(List.generate(seqs.length, (i) => seqs.first + i)));
        sub.cancel();
        pass(async, const Duration(milliseconds: 100));
        final n = seqs.length;
        pass(async, const Duration(seconds: 2));
        expect(seqs.length, equals(n));
      });
    });

    test('two listeners share one subscription', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        final a = <int>[], b = <int>[];
        final s1 = api.liveUpdates().listen((l) => a.add(l.seq));
        final s2 = api.liveUpdates().listen((l) => b.add(l.seq));
        pass(async, const Duration(seconds: 1));
        expect(a, isNotEmpty);
        expect(b, equals(a));
        s1.cancel();
        s2.cancel();
      });
    });

    test('the phasor stream arrives at ~40 batches per second', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        var n = 0;
        final sub = api.phasorStream().listen((_) => n++);
        pass(async, const Duration(seconds: 1));
        expect(n, inInclusiveRange(38, 42));
        sub.cancel();
      });
    });

    test('linkDown completes every subscription', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        var done = false;
        api.liveUpdates().listen((_) {}, onDone: () => done = true);
        pass(async, const Duration(milliseconds: 500));
        sim.linkDown();
        async.flushMicrotasks();
        expect(done, isTrue);
      });
    });
  });

  group('flip calibration physics', () {
    test('after a flip calibration the zero error is gone', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..setServiceMode(true);
        final api = InstrumentApi(sim);

        double sumAt(double t) {
          sim.physicalTilt = [t, t];
          final a = settle(async, api.live());
          sim.physicalTilt = [-t, -t];
          final b = settle(async, api.live());
          return a.tiltS1 + b.tiltS1; // 0 when there is no zero error
        }

        final before = sumAt(0.6).abs();
        expect(before, greaterThan(0.01),
            reason: 'the stored zero starts out wrong');

        settle(async, api.zeroCalStep1(3));
        pass(async, const Duration(seconds: 2));
        expect(settle(async, api.zeroCalStatus()).phase,
            equals(ZeroCalPhase.step1Done));
        settle(async, api.zeroCalStep2());
        pass(async, const Duration(seconds: 2));
        expect(settle(async, api.zeroCalStatus()).phase,
            equals(ZeroCalPhase.idle));

        expect(sumAt(0.6).abs(), lessThan(1e-4));
      });
    });

    test('a single-sensor run leaves the other sensor alone', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..setServiceMode(true);
        final api = InstrumentApi(sim);
        final s2Before = sim.calibration(kS2Zero);
        settle(async, api.zeroCalStep1(1)); // S1 only
        pass(async, const Duration(seconds: 2));
        settle(async, api.zeroCalStep2());
        pass(async, const Duration(seconds: 2));
        expect(sim.calibration(kS2Zero), equals(s2Before));
        expect(sim.calibration(kS1Zero), isNot(equals(500)));
      });
    });

    test('step 2 before step 1 is BUSY_RESOURCE', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..setServiceMode(true);
        expect(
          () => settle(async, InstrumentApi(sim).zeroCalStep2()),
          throwsA(isA<ApiException>()
              .having((e) => e.status, 's', ApiStatus.busyResource)),
        );
      });
    });

    test('without service mode the flip calibration is refused', () {
      fakeAsync((async) {
        expect(
          () => settle(async, InstrumentApi(SimulatedDevice()).zeroCalStep1(3)),
          throwsA(isA<ApiException>()
              .having((e) => e.isServiceModeRequired, 's', isTrue)),
        );
      });
    });
  });

  group('precision measurement', () {
    test('delivers one result close to the true tilt, via pushes', () {
      fakeAsync((async) {
        final sim = SimulatedDevice();
        final api = InstrumentApi(sim);
        final phases = <PrecisionPhase>[];
        final sub = api.precisionUpdates().listen((s) => phases.add(s.phase));
        pass(async, const Duration(milliseconds: 100));
        settle(async, api.precisionStart());
        pass(async, const Duration(seconds: 3));
        final s = settle(async, api.precisionStatus());
        expect(s.phase, equals(PrecisionPhase.done));
        expect(s.failed, isFalse);
        expect(s.tiltDiff, closeTo(s.tiltS1 - s.tiltS2, 1e-6));
        expect(phases, contains(PrecisionPhase.running));
        expect(phases.last, equals(PrecisionPhase.done));
        sub.cancel();
      });
    });

    test('a disturbed table ends in failed after 5 s', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..precisionNeverClean = true;
        final api = InstrumentApi(sim);
        settle(async, api.precisionStart());
        pass(async, const Duration(seconds: 6));
        final s = settle(async, api.precisionStatus());
        expect(s.phase, equals(PrecisionPhase.done));
        expect(s.failed, isTrue);
      });
    });

    test('is refused (BUSY_RESOURCE) during a flip calibration', () {
      fakeAsync((async) {
        final sim = SimulatedDevice()..setServiceMode(true);
        final api = InstrumentApi(sim);
        settle(async, api.zeroCalStep1(3));
        expect(() => settle(async, api.precisionStart()),
            throwsA(isA<ApiException>()));
      });
    });
  });

  group('clock', () {
    test('SET then GET', () {
      fakeAsync((async) {
        final api = InstrumentApi(SimulatedDevice());
        expect(settle(async, api.rtc()).isSet, isFalse);
        settle(async, api.setRtc(DateTime(2026, 10, 9, 14, 30, 0)));
        final r = settle(async, api.rtc());
        expect(r.isSet, isTrue);
        expect(r.year, equals(2026));
        expect(r.month, equals(10));
        expect(r.hour, equals(14));
      });
    });
  });

  test('ApiException messages are readable', () {
    expect(const ApiException(ApiStatus.serviceModeRequired, 'x').message,
        contains('Service mode'));
    expect(const ApiException(ApiStatus.unknownResource, 'foo').message,
        contains('foo'));
  });
}
