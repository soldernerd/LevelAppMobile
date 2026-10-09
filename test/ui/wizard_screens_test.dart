import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ui/widgets/instrument_diagram.dart';

import '../support/app_harness.dart';

String textOf(WidgetTester t, Finder f) => t.widget<Text>(f).data!;

/// Taps a segment of the S1 / S2 / Both selector.
Future<void> pickSensor(WidgetTester t, String label) => t.tap(find.descendant(
    of: find.byType(SegmentedButton<int>), matching: find.text(label)));

bool enabled(WidgetTester t, String key) {
  final w = t.widget(find.byKey(ValueKey(key)));
  return switch (w) {
    FilledButton() => w.onPressed != null,
    OutlinedButton() => w.onPressed != null,
    _ => throw StateError('not a button: $w'),
  };
}

Future<void> turnServiceOn(WidgetTester t, AppHarness h) async {
  h.sim.setServiceMode(true);
  await h.pump(t, const Duration(seconds: 2));
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('calibration hub', () {
    testWidgets('lists the three wizards in order and the service state',
        (tester) async {
      final h = await AppHarness.start(tester,
          location: '/instrument/calibration');
      expect(find.text('Phase'), findsOneWidget);
      expect(find.text('Gain (sensitivity)'), findsOneWidget);
      expect(find.text('Zero (flip)'), findsOneWidget);
      expect(find.text('Service mode is off'), findsOneWidget);
      await turnServiceOn(tester, h);
      expect(find.text('Service mode is on'), findsOneWidget);
      expect(find.text('Leave service mode'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('opens each wizard', (tester) async {
      final h = await AppHarness.start(tester,
          location: '/instrument/calibration');
      await tester.tap(find.byKey(const ValueKey('cal-phase')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.text('Phase calibration'), findsOneWidget);
      h.router.pop();
      await h.pump(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('cal-gain')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.text('Gain calibration'), findsOneWidget);
      h.router.pop();
      await h.pump(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('cal-flip')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.text('Zero (flip) calibration'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('can end service mode from the hub', (tester) async {
      final h = await AppHarness.start(tester,
          location: '/instrument/calibration');
      await turnServiceOn(tester, h);
      await tester.tap(find.text('Leave service mode'));
      await h.pump(tester, const Duration(seconds: 2));
      expect(h.sim.serviceMode, isFalse);
      expect(find.text('Service mode is off'), findsOneWidget);
      await h.dispose(tester);
    });
  });

  group('flip calibration screen', () {
    const loc = '/instrument/calibration/flip';

    testWidgets('cannot start until service mode is on, and says how',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      expect(enabled(tester, 'flip-start'), isFalse);
      expect(find.textContaining('SETTINGS > Service mode'), findsOneWidget);
      await turnServiceOn(tester, h);
      expect(enabled(tester, 'flip-start'), isTrue);
      await h.dispose(tester);
    });

    testWidgets('shows the stored level point before starting', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      // 500 ppm / 45000 = +0.0111 mm/m for S1.
      expect(find.textContaining('+0.0111 mm/m'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('leads through both steps to a before / after table',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await turnServiceOn(tester, h);

      await tester.tap(find.byKey(const ValueKey('flip-start')));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(find.text('Measure in the starting position'), findsOneWidget);
      expect(find.byKey(const ValueKey('flip-progress')), findsOneWidget);
      expect(find.textContaining('batches'), findsOneWidget);

      await h.pump(tester, const Duration(seconds: 2));
      expect(find.text('Turn the instrument 180°'), findsOneWidget);
      final diagram = tester.widget<InstrumentDiagram>(
          find.byType(InstrumentDiagram));
      expect(diagram.pose, equals(DiagramPose.rotated));

      await tester.tap(find.byKey(const ValueKey('flip-continue')));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(find.text('Measure in the turned position'), findsOneWidget);

      await h.pump(tester, const Duration(seconds: 3));
      expect(find.text('New zero stored'), findsOneWidget);
      expect(find.byKey(const ValueKey('flip-result')), findsOneWidget);
      expect(find.text('Before'), findsNWidgets(2));
      expect(find.text('After'), findsNWidgets(2));
      expect(find.text('S1'), findsWidgets);
      expect(find.text('S2'), findsWidgets);
      expect(find.text('+500'), findsOneWidget, reason: 'S1 zero before, ppm');

      await tester.tap(find.byKey(const ValueKey('flip-done')));
      await h.pump(tester, const Duration(milliseconds: 600));
      await h.dispose(tester);
    });

    testWidgets('one sensor only shows one row', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await turnServiceOn(tester, h);
      await pickSensor(tester, 'S1');
      await h.pump(tester, const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('flip-start')));
      await h.pump(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('flip-continue')));
      await h.pump(tester, const Duration(seconds: 4));
      expect(find.text('New zero stored'), findsOneWidget);
      expect(find.text('S2'), findsNothing);
      await h.dispose(tester);
    });

    testWidgets('cancel returns to the start', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await turnServiceOn(tester, h);
      await tester.tap(find.byKey(const ValueKey('flip-start')));
      await h.pump(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text('Cancel'));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('flip-start')), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('losing service mode between the steps blocks step 2',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await turnServiceOn(tester, h);
      await tester.tap(find.byKey(const ValueKey('flip-start')));
      await h.pump(tester, const Duration(seconds: 3));
      expect(find.text('Turn the instrument 180°'), findsOneWidget);
      h.sim.setServiceMode(false);
      await h.pump(tester, const Duration(seconds: 2));
      expect(enabled(tester, 'flip-continue'), isFalse);
      expect(find.text('Service mode is off'), findsOneWidget);
      await h.dispose(tester);
    });
  });

  group('phase calibration screen', () {
    const loc = '/instrument/calibration/phase';

    testWidgets('leads through reference, tilt step and result',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      expect(find.text('Stored phase'), findsOneWidget);
      expect(find.text('+10.00°'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('phase-begin')));
      await h.pump(tester, const Duration(milliseconds: 400));
      expect(find.text('Reference'), findsOneWidget);

      h.sim.physicalTilt = [0.0, 0.0];
      await tester.tap(find.byKey(const ValueKey('phase-capture-ref')));
      await h.pump(tester, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('phase-progress')), findsOneWidget);
      await h.pump(tester, const Duration(seconds: 8));
      expect(find.text('Tilt step'), findsOneWidget);

      h.sim.physicalTilt = [0.15, 0.15];
      await tester.tap(find.byKey(const ValueKey('phase-capture-tilt')));
      await h.pump(tester, const Duration(seconds: 10));

      expect(find.text('Result'), findsOneWidget);
      expect(textOf(tester, find.byKey(const ValueKey('phase-angle-S1'))),
          startsWith('+12.0'));
      expect(textOf(tester, find.byKey(const ValueKey('phase-angle-S2'))),
          startsWith('+10.5'));
      expect(find.text('Good.'), findsNWidgets(2));
      expect(enabled(tester, 'phase-apply'), isFalse,
          reason: 'service mode is off');
      expect(find.text('Service mode is off'), findsOneWidget);

      await turnServiceOn(tester, h);
      expect(enabled(tester, 'phase-apply'), isTrue);
      await tester.tap(find.byKey(const ValueKey('phase-apply')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.text('Phase stored'), findsOneWidget);
      expect(find.byKey(const ValueKey('phase-result')), findsOneWidget);
      expect(h.sim.calibration(kS1Phase), closeTo(1200, 10));
      expect(h.sim.calibration(kS2Phase), closeTo(1050, 10));
      await h.dispose(tester);
    });

    testWidgets('warns when there was no tilt step', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await tester.tap(find.byKey(const ValueKey('phase-begin')));
      await h.pump(tester, const Duration(milliseconds: 400));
      h.sim.physicalTilt = [0.0, 0.0];
      await tester.tap(find.byKey(const ValueKey('phase-capture-ref')));
      await h.pump(tester, const Duration(seconds: 10));
      await tester.tap(find.byKey(const ValueKey('phase-capture-tilt')));
      await h.pump(tester, const Duration(seconds: 10));
      expect(find.textContaining('No usable step'), findsWidgets);
      await turnServiceOn(tester, h);
      expect(enabled(tester, 'phase-apply'), isFalse);
      await h.dispose(tester);
    });

    testWidgets('one sensor: only its card is shown', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await pickSensor(tester, 'S2');
      await h.pump(tester, const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('phase-begin')));
      await h.pump(tester, const Duration(milliseconds: 400));
      h.sim.physicalTilt = [0.0, 0.0];
      await tester.tap(find.byKey(const ValueKey('phase-capture-ref')));
      await h.pump(tester, const Duration(seconds: 10));
      h.sim.physicalTilt = [0.15, 0.15];
      await tester.tap(find.byKey(const ValueKey('phase-capture-tilt')));
      await h.pump(tester, const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('phase-estimate-S2')), findsOneWidget);
      expect(find.byKey(const ValueKey('phase-estimate-S1')), findsNothing);
      await h.dispose(tester);
    });
  });

  group('gain calibration screen', () {
    const loc = '/instrument/calibration/gain';

    testWidgets('computes the known tilt from shim and edge', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      expect(textOf(tester, find.byKey(const ValueKey('gain-known-tilt'))),
          equals('Known tilt step: 0.1000 mm/m'));
      await tester.enterText(find.byKey(const ValueKey('gain-height')), '0.25');
      await tester.enterText(find.byKey(const ValueKey('gain-length')), '500');
      await tester.pump();
      expect(textOf(tester, find.byKey(const ValueKey('gain-known-tilt'))),
          equals('Known tilt step: 0.5000 mm/m'));
      await tester.enterText(find.byKey(const ValueKey('gain-length')), '');
      await tester.pump();
      expect(enabled(tester, 'gain-begin'), isFalse);
      await h.dispose(tester);
    });

    testWidgets('leads through baseline, shim and result', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      h.sim.setCalibration(kS1Phase, 1200);
      h.sim.setCalibration(kS2Phase, 1050);
      expect(find.text('45000'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gain-begin')));
      await h.pump(tester, const Duration(milliseconds: 400));
      expect(find.text('Baseline'), findsOneWidget);

      h.sim.physicalTilt = [0.0, 0.0];
      await tester.tap(find.byKey(const ValueKey('gain-measure-baseline')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('gain-progress')), findsOneWidget);
      await h.pump(tester, const Duration(seconds: 4));
      expect(find.text('With the shim'), findsOneWidget);

      h.sim.physicalTilt = [0.1, 0.1];
      await tester.tap(find.byKey(const ValueKey('gain-measure-shim')));
      await h.pump(tester, const Duration(seconds: 5));
      expect(find.text('Result'), findsOneWidget);
      expect(textOf(tester, find.byKey(const ValueKey('gain-k-S1'))),
          matches(RegExp(r'^k 45000 to (4[89]|50)\d{3}$')));
      expect(enabled(tester, 'gain-apply'), isFalse,
          reason: 'service mode is off');

      await turnServiceOn(tester, h);
      await tester.tap(find.byKey(const ValueKey('gain-apply')));
      await h.pump(tester, const Duration(seconds: 6));
      expect(find.text('Sensitivity stored'), findsOneWidget);
      expect(find.byKey(const ValueKey('gain-result')), findsOneWidget);
      expect(find.byKey(const ValueKey('gain-verify')), findsOneWidget);
      expect(h.sim.calibration(kS1K), closeTo(50000, 300));
      await h.dispose(tester);
    });

    testWidgets('warns when the reading moves the wrong way', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      h.sim.setCalibration(kS1Phase, 1200);
      h.sim.setCalibration(kS2Phase, 1050);
      await tester.tap(find.byKey(const ValueKey('gain-begin')));
      await h.pump(tester, const Duration(milliseconds: 400));
      h.sim.physicalTilt = [0.0, 0.0];
      await tester.tap(find.byKey(const ValueKey('gain-measure-baseline')));
      await h.pump(tester, const Duration(seconds: 5));
      h.sim.physicalTilt = [-0.1, -0.1];
      await tester.tap(find.byKey(const ValueKey('gain-measure-shim')));
      await h.pump(tester, const Duration(seconds: 5));
      expect(find.textContaining('moved the other way'), findsWidgets);
      await h.dispose(tester);
    });
  });
}
