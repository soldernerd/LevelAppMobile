import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_api.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_session.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';
import 'package:inclinometer/devices/neigmess2/simulated_neigmess.dart';
import 'package:inclinometer/devices/neigmess2/ui/neigmess_screen.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/router.dart';

import '../support/harness.dart';
import '../support/registry.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('NeigMess2 protocol', () {
    test('the Sensors topic group round-trips (20 bytes)', () {
      const s = NmSensors(
        units: [1.5, 2.5, -3.5, 171.25],
        angleXCdeg: -123,
        angleYCdeg: 4567,
      );
      final d = NmSensors.decode(s.encode())!;
      expect(d.units, equals(s.units));
      expect(d.angleXDeg, closeTo(-1.23, 1e-9));
      expect(d.angleYDeg, closeTo(45.67, 1e-9));
      expect(NmSensors.decode(Uint8List(19)), isNull);
    });

    test('zero offsets and trim round-trip', () {
      const z = NmZeroOffsets([1, 2, 3, 4]);
      expect(NmZeroOffsets.decode(z.encode())!.units, equals([1, 2, 3, 4]));
      const t = NmTiltTrim(multiplierX1000: 1010, offsetTenthUmPerM: -25);
      final r = NmTiltTrim.decode(t.encode())!;
      expect(r.multiplierX1000, equals(1010));
      expect(r.offsetTenthUmPerM, equals(-25));
    });

    test('one sensor unit is about 0.0954 pF', () {
      expect(kUnitToPf, closeTo(0.09537, 1e-5));
    });

    test('the tilt status maps the four codes', () {
      expect(NmTiltStatus.fromByte(0), equals(NmTiltStatus.ok));
      expect(NmTiltStatus.fromByte(1), equals(NmTiltStatus.over));
      expect(NmTiltStatus.fromByte(2), equals(NmTiltStatus.under));
      expect(NmTiltStatus.fromByte(9), equals(NmTiltStatus.invalid));
    });
  });

  group('NeigMess2 over the shared stack', () {
    test('the 19-byte IDENTITY is claimed by its driver', () {
      fakeAsync((async) {
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(
            id: 'NM:01',
            name: 'NeigMess2',
            sim: SimulatedNeigMess(),
          ),
        ]);
        addTearDown(mock.dispose);
        final conn = settle(async, mock.open('NM:01'));
        final session =
            settle(async, testRegistry.openSession(conn)) as NeigMessSession;
        expect(session.driver, isA<NeigMessDriver>());
        expect(session.identity.product, equals('NeigMess2'));
        expect(session.identity.firmware, equals('0.1.0'));
        expect(session.label, contains('NeigMess2'));
        settle(async, session.close());
      });
    });

    test('the feed is seeded at once, then follows the pushes', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess();
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final session =
            settle(
                  async,
                  testRegistry.openSession(settle(async, mock.open('NM:01'))),
                )
                as NeigMessSession;

        pass(async, const Duration(milliseconds: 100));
        var s = session.state;
        expect(s.hasTilt, isTrue);
        expect(s.tilt, closeTo(12.5, 1e-4));
        expect(s.plateCapPf, closeTo(16.4, 1e-4));
        expect(s.angleXDeg, closeTo(0.12, 1e-9));
        expect(s.sensorPf(3), closeTo(171.5 * kUnitToPf, 1e-4));

        sim.tilt = -3.0;
        pass(async, const Duration(seconds: 1));
        s = session.state;
        expect(s.tilt, closeTo(-3.0, 1e-4));
        settle(async, session.close());
      });
    });

    test('zeroing stores the offsets, and the feed shows the zeroed pF', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess();
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final session =
            settle(
                  async,
                  testRegistry.openSession(settle(async, mock.open('NM:01'))),
                )
                as NeigMessSession;
        pass(async, const Duration(milliseconds: 100));

        settle(async, session.zeroSensors());
        expect(sim.zeroOffsets, equals(sim.sensorUnits));
        expect(sim.eepromWrites, equals(1));
        pass(async, const Duration(milliseconds: 600));
        for (var i = 0; i < 4; i++) {
          expect(session.state.sensorPf(i), closeTo(0, 1e-9));
        }

        settle(async, session.clearZero());
        expect(sim.zeroOffsets, equals([0, 0, 0, 0]));
        settle(async, session.close());
      });
    });

    test('capturing the neutral is refused while the alignment is not OK', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess()..tiltStatus = NmTiltStatus.over;
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final conn = settle(async, mock.open('NM:01'));
        final api = NeigMessApi(conn);
        expect(
          () => settle(async, api.captureNeutral()),
          throwsA(
            isA<ApiException>().having(
              (e) => e.status,
              'status',
              ApiStatus.invalidParameter,
            ),
          ),
        );
        expect(
          settle(async, api.tilt()),
          equals(0),
          reason: 'tilt reads 0 unless the status is OK',
        );
        sim.tiltStatus = NmTiltStatus.ok;
        settle(async, api.captureNeutral());
        expect(sim.neutralCapPf, closeTo(16.4, 1e-4));
      });
    });

    test('a bad SET is refused before it touches the EEPROM', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess();
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final conn = settle(async, mock.open('NM:01'));
        final r = settle(
          async,
          conn.request(
            opSet(ApiCat.calibrations, NmCal.neutralCap),
            encodeFloat(500),
          ),
        );
        expect(r.status, equals(ApiStatus.invalidParameter));
        expect(sim.eepromWrites, equals(0));
      });
    });
  });

  group('NeigMess2 flip zero and calibration', () {
    test('the zero routine status round-trips (14 bytes)', () {
      const r = NmZeroRoutine(
        state: NmZeroState.readyPos2,
        progress: 40,
        pos1Valid: true,
        unsteady: true,
        pos1: 103.5,
        pos2: -96.25,
        offsetTenth: -30,
      );
      final d = NmZeroRoutine.decode(r.encode())!;
      expect(d, equals(r));
      expect(d.offsetUmPerM, closeTo(-3.0, 1e-9));
      expect(NmZeroRoutine.decode(Uint8List(13)), isNull);
    });

    test('the flip zero finds the instrument zero error and stores it', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess()..flipBias = 3.0;
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final session =
            settle(
                  async,
                  testRegistry.openSession(settle(async, mock.open('NM:01'))),
                )
                as NeigMessSession;
        pass(async, const Duration(milliseconds: 100));
        NmZeroState st() => session.state.zeroRoutine!.state;
        expect(st(), equals(NmZeroState.idle));

        settle(async, session.zeroRoutineNext());
        pass(async, const Duration(milliseconds: 300));
        expect(st(), equals(NmZeroState.readyPos1));

        settle(async, session.zeroRoutineNext());
        pass(async, const Duration(seconds: 2));
        expect(st(), equals(NmZeroState.measuring1));
        expect(session.state.zeroRoutine!.progress, inInclusiveRange(1, 99));
        pass(async, const Duration(seconds: 4));
        expect(st(), equals(NmZeroState.readyPos2));

        settle(async, session.zeroRoutineNext());
        pass(async, const Duration(seconds: 6));
        expect(st(), equals(NmZeroState.done));
        expect(session.state.zeroRoutine!.offsetUmPerM, closeTo(-3.0, 1e-9));
        expect(sim.trimOffsetTenth, equals(-30));
        expect(sim.eepromWrites, equals(1));
        expect(
          session.state.trim!.offsetTenthUmPerM,
          equals(-30),
          reason: 'the session re-reads the trim when the routine is done',
        );

        settle(async, session.zeroRoutineNext());
        pass(async, const Duration(milliseconds: 300));
        expect(st(), equals(NmZeroState.idle));
        settle(async, session.close());
      });
    });

    test('quitting abandons the routine without touching the EEPROM', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess();
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final session =
            settle(
                  async,
                  testRegistry.openSession(settle(async, mock.open('NM:01'))),
                )
                as NeigMessSession;
        settle(async, session.zeroRoutineNext());
        settle(async, session.zeroRoutineNext());
        pass(async, const Duration(seconds: 1));
        settle(async, session.zeroRoutineQuit());
        pass(async, const Duration(seconds: 7));
        expect(session.state.zeroRoutine!.state, equals(NmZeroState.idle));
        expect(sim.eepromWrites, equals(0));
        settle(async, session.close());
      });
    });

    test('trim and neutral are set; a capture stays in RAM until stored or '
        'recalled', () {
      fakeAsync((async) {
        final sim = SimulatedNeigMess();
        final mock = MockBleManager.withPeripherals([
          MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
        ]);
        addTearDown(mock.dispose);
        final session =
            settle(
                  async,
                  testRegistry.openSession(settle(async, mock.open('NM:01'))),
                )
                as NeigMessSession;
        pass(async, const Duration(milliseconds: 100));

        settle(
          async,
          session.setTiltTrim(
            const NmTiltTrim(multiplierX1000: 1010, offsetTenthUmPerM: -25),
          ),
        );
        expect(sim.eepromWrites, equals(1));
        expect(session.state.trim!.multiplierX1000, equals(1010));

        sim.plateCapPf = 17.0;
        settle(async, session.captureNeutral());
        expect(session.state.neutralCapPf, closeTo(17.0, 1e-4));
        expect(sim.eepromWrites, equals(1), reason: 'capture is RAM only');

        settle(async, session.recallCalibration());
        expect(session.state.neutralCapPf, closeTo(16.38, 1e-4));
        expect(
          session.state.trim!.multiplierX1000,
          equals(1010),
          reason: 'the trim had been stored',
        );

        settle(async, session.captureNeutral());
        settle(async, session.storeCalibration());
        settle(async, session.recallCalibration());
        expect(session.state.neutralCapPf, closeTo(17.0, 1e-4));
        settle(async, session.close());
      });
    });
  });

  group('NeigMess2 screen', () {
    testWidgets('shows tilt and sensors, and says why when there is no tilt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sim = SimulatedNeigMess();
      final mock = MockBleManager.withPeripherals([
        MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
      ]);
      final container = ProviderContainer(
        overrides: [
          bleManagerProvider.overrideWithValue(mock),
          deviceRegistryProvider.overrideWithValue(testRegistry),
        ],
      );
      final router = buildRouter(
        registry: testRegistry,
        readActive: () => container.read(activeSessionProvider),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData.dark(),
          ),
        ),
      );
      container.read(connectionNotifierProvider.notifier).connect('NM:01');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      router.go('/neigmess2');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(NeigMessScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('tilt')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('tilt'))).data,
        equals('12.5'),
      );
      expect(find.text('16.40 pF'), findsOneWidget);

      sim.tiltStatus = NmTiltStatus.over;
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('tilt'))).data,
        equals('—'),
      );
      expect(find.textContaining('Over range'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      mock.dispose();
      await tester.pump();
    });

    testWidgets('the app alone can run the flip zero and set the trim', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sim = SimulatedNeigMess();
      final mock = MockBleManager.withPeripherals([
        MockPeripheral(id: 'NM:01', name: 'NeigMess2', sim: sim),
      ]);
      final container = ProviderContainer(
        overrides: [
          bleManagerProvider.overrideWithValue(mock),
          deviceRegistryProvider.overrideWithValue(testRegistry),
        ],
      );
      final router = buildRouter(
        registry: testRegistry,
        readActive: () => container.read(activeSessionProvider),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData.dark(),
          ),
        ),
      );
      container.read(connectionNotifierProvider.notifier).connect('NM:01');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      router.go('/neigmess2/zero');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      String title() =>
          tester.widget<Text>(find.byKey(const ValueKey('zero-title'))).data!;
      expect(title(), equals('Flip zero'));
      await tester.tap(find.byKey(const ValueKey('zero-next')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(title(), equals('Position 1'));
      await tester.tap(find.byKey(const ValueKey('zero-next')));
      await tester.pump(const Duration(seconds: 2));
      expect(title(), equals('Measuring position 1'));
      expect(find.byKey(const ValueKey('zero-progress')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(title(), equals('Position 2'));

      router.go('/neigmess2/calibration');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byKey(const ValueKey('trim-mul')), '1.020');
      await tester.enterText(find.byKey(const ValueKey('trim-ofs')), '-2.5');
      await tester.tap(find.byKey(const ValueKey('trim-apply')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(sim.trimMultiplierX1000, equals(1020));
      expect(sim.trimOffsetTenth, equals(-25));
      expect(sim.eepromWrites, equals(1));

      await tester.tap(find.byKey(const ValueKey('neutral-capture')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('neutral-unsaved')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      mock.dispose();
      await tester.pump();
    });
  });
}
