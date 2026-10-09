import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/simulated_device.dart';
import 'package:inclinometer/providers/device_provider.dart';

import '../support/app_harness.dart';

String textOf(WidgetTester t, Finder f) => t.widget<Text>(f).data!;

ApiValueDef setting(int id) => kSettings.firstWhere((d) => d.id == id);

/// Scrolls the visible list until [item] is fully on screen.
Future<void> scrollTo(WidgetTester t, Finder item) async {
  await t.dragUntilVisible(
    item,
    find.byType(ListView).hitTestable().first,
    const Offset(0, -250),
  );
  await t.ensureVisible(item);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('precision sheet', () {
    testWidgets('measures and shows S1, S2 and Diff', (tester) async {
      final h = await AppHarness.start(tester);
      await tester.tap(find.byKey(const ValueKey('precision')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('precision-running')), findsOneWidget);
      expect(find.text('Hold still…'), findsOneWidget);

      await h.pump(tester, const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('precision-done')), findsOneWidget);
      final num = RegExp(r'^[+−]\d\.\d{4} mm/m$');
      for (final k in ['S1', 'S2', 'DIFF']) {
        final t = textOf(tester, find.byKey(ValueKey('precision-$k')));
        expect(num.hasMatch(t), isTrue, reason: '$k: $t');
      }

      await tester.tap(find.byKey(const ValueKey('precision-close')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('precision-done')), findsNothing);
      await h.dispose(tester);
    });

    testWidgets('can be repeated', (tester) async {
      final h = await AppHarness.start(tester);
      await tester.tap(find.byKey(const ValueKey('precision')));
      await h.pump(tester, const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('precision-done')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('precision-again')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('precision-running')), findsOneWidget);
      await h.pump(tester, const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('precision-done')), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('tells the user when the table never calms down',
        (tester) async {
      final h = await AppHarness.start(tester,
          device: SimulatedDevice()..precisionNeverClean = true);
      await tester.tap(find.byKey(const ValueKey('precision')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.textContaining('not quiet yet'), findsOneWidget);
      await h.pump(tester, const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('precision-failed')), findsOneWidget);
      expect(find.textContaining('No quiet window'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('precision-close')));
      await h.pump(tester, const Duration(milliseconds: 600));
      await h.dispose(tester);
    });

    testWidgets('cancel stops the measurement on the instrument',
        (tester) async {
      final h = await AppHarness.start(tester);
      await tester.tap(find.byKey(const ValueKey('precision')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('precision-running')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('precision-close')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('precision-running')), findsNothing);
      final st = await _settle(tester, h,
          h.container.read(instrumentApiProvider).precisionStatus());
      expect(st.phase, isNot(PrecisionPhase.running));
      await h.dispose(tester);
    });

    testWidgets('the sheet cannot be swiped away mid-measurement',
        (tester) async {
      final h = await AppHarness.start(tester);
      await tester.tap(find.byKey(const ValueKey('precision')));
      await h.pump(tester, const Duration(seconds: 1));
      await tester.tapAt(const Offset(200, 40)); // the barrier
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('precision-running')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('precision-close')));
      await h.pump(tester, const Duration(seconds: 1));
      await h.dispose(tester);
    });
  });

  group('settings', () {
    const loc = '/instrument/settings';

    testWidgets('lists the settings with their values', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      expect(find.text('Auto power-off'), findsOneWidget);
      expect(find.text('300 s'), findsOneWidget);
      expect(find.text('Charge start voltage'), findsOneWidget);
      expect(find.text('3700 mV'), findsOneWidget);
      // Not in this firmware: hidden, not shown as a dash.
      expect(find.text('Max time at 100 %'), findsNothing);
      await h.dispose(tester);
    });

    testWidgets('shows max-time-at-100 % when the firmware has it',
        (tester) async {
      final h = await AppHarness.start(tester,
          device: SimulatedDevice(supportsChargeFullTimeout: true),
          location: loc);
      expect(find.text('Max time at 100 %'), findsOneWidget);
      expect(find.text('120 min'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('edits a setting', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await tester.tap(find.text('Auto power-off'));
      await h.pump(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const ValueKey('edit-field')), '900');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await h.pump(tester, const Duration(milliseconds: 800));
      expect(find.text('900 s'), findsOneWidget);
      expect(h.sim.setting(setting(0x60)), equals(900));
      await h.dispose(tester);
    });

    testWidgets('rejects a value outside the range before sending it',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await tester.tap(find.text('Charge start voltage'));
      await h.pump(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const ValueKey('edit-field')), '9000');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await h.pump(tester, const Duration(milliseconds: 300));
      expect(find.textContaining('from 3000 to 4200'), findsOneWidget);
      expect(h.sim.setting(setting(0x52)), equals(3700));
      await h.dispose(tester);
    });

    testWidgets("shows the device's refusal (critical must stay below low)",
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await tester.tap(find.text('Battery critical'));
      await h.pump(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const ValueKey('edit-field')), '3600');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await h.pump(tester, const Duration(milliseconds: 800));
      expect(find.textContaining('rejected the value'), findsOneWidget);
      expect(h.sim.setting(setting(0x50)), equals(3400));
      await h.dispose(tester);
    });

    testWidgets('calibration values are read-only until service mode is on',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await tester.tap(find.text('Calibration'));
      await h.pump(tester, const Duration(milliseconds: 800));
      expect(find.text('S1 sensitivity k'), findsOneWidget);
      expect(find.text('45000'), findsOneWidget);

      await scrollTo(tester, find.text('S1 sensitivity k'));
      await tester.tap(find.text('S1 sensitivity k'));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(
          find.text('Writing this value needs service mode.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await h.pump(tester, const Duration(milliseconds: 500));

      h.sim.setServiceMode(true);
      await h.pump(tester, const Duration(seconds: 2));
      await tester.tap(find.text('S1 sensitivity k'));
      await h.pump(tester, const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const ValueKey('edit-field')), '47000');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await h.pump(tester, const Duration(milliseconds: 800));
      expect(h.sim.calibration(kS1K), equals(47000));
      await h.dispose(tester);
    });

    testWidgets('an invert flag is a switch, not a number', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      h.sim.setServiceMode(true);
      await tester.tap(find.text('Calibration'));
      await h.pump(tester, const Duration(seconds: 2));
      await scrollTo(tester, find.text('S1 invert'));
      await tester.tap(find.text('S1 invert'));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('edit-field')), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await h.pump(tester, const Duration(milliseconds: 800));
      expect(h.sim.calibration(kS1Invert), equals(1));
      await h.dispose(tester);
    });
  });

  group('actions', () {
    const loc = '/instrument/settings';

    Future<AppHarness> open(WidgetTester t, {bool service = false}) async {
      final h = await AppHarness.start(t, location: loc);
      if (service) h.sim.setServiceMode(true);
      await t.tap(find.text('Actions'));
      await h.pump(t, const Duration(seconds: 2));
      return h;
    }

    testWidgets('force charge arms when USB power is present', (tester) async {
      final h = await open(tester);
      h.sim.setBattery(usb: true);
      await tester.tap(find.byKey(const ValueKey('action-force-charge')));
      await h.pump(tester, const Duration(seconds: 2));
      expect(find.text('Forced charge is armed'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('charge inhibit is a switch that follows the instrument',
        (tester) async {
      final h = await open(tester);
      bool value() => tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('charge-inhibit')))
          .value;
      expect(value(), isFalse);
      await tester.tap(find.byKey(const ValueKey('charge-inhibit')));
      await h.pump(tester, const Duration(seconds: 2));
      expect(value(), isTrue);
      await h.dispose(tester);
    });

    testWidgets('power off asks first, then the link ends', (tester) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const ValueKey('action-power-off')));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(
          find.textContaining('Power the instrument off?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(h.router.state.matchedLocation, contains('/instrument'));

      await tester.tap(find.byKey(const ValueKey('action-power-off')));
      await h.pump(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await h.pump(tester, const Duration(seconds: 2));
      expect(h.router.state.matchedLocation, equals('/scan'));
      await h.dispose(tester);
    });

    testWidgets('DFU and factory defaults stay disabled without service mode',
        (tester) async {
      final h = await open(tester);
      await scrollTo(tester, find.byKey(const ValueKey('action-factory')));
      for (final k in ['action-dfu', 'action-factory']) {
        expect(tester.widget<ListTile>(find.byKey(ValueKey(k))).enabled,
            isFalse,
            reason: k);
      }
      await h.dispose(tester);
    });

    testWidgets('factory defaults needs service mode and a typed RESET',
        (tester) async {
      final h = await open(tester, service: true);
      h.sim.setCalibration(kS1K, 12345);
      await h.pump(tester, const Duration(seconds: 1));
      await scrollTo(tester, find.byKey(const ValueKey('action-factory')));
      await tester.tap(find.byKey(const ValueKey('action-factory')));
      await h.pump(tester, const Duration(milliseconds: 500));

      FilledButton ok() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirm-ok')));
      expect(ok().onPressed, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('confirm-field')), 'reset');
      await tester.pump();
      expect(ok().onPressed, isNull, reason: 'case matters');
      await tester.enterText(
          find.byKey(const ValueKey('confirm-field')), 'RESET');
      await tester.pump();
      expect(ok().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('confirm-ok')));
      await h.pump(tester, const Duration(seconds: 1));
      expect(h.sim.calibration(kS1K), equals(45000));
      await h.dispose(tester);
    });

    testWidgets('reboot to DFU explains that it sticks', (tester) async {
      final h = await open(tester, service: true);
      await scrollTo(tester, find.byKey(const ValueKey('action-dfu')));
      await tester.tap(find.byKey(const ValueKey('action-dfu')));
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(find.textContaining('stay in the bootloader'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await h.pump(tester, const Duration(milliseconds: 500));
      await h.dispose(tester);
    });
  });
}

/// Resolves a device request under the fake clock.
Future<T> _settle<T>(WidgetTester t, AppHarness h, Future<T> f) async {
  T? out;
  Object? err;
  var done = false;
  f.then((v) {
    out = v;
    done = true;
  }, onError: (Object e) {
    err = e;
    done = true;
  });
  for (var i = 0; i < 30 && !done; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  if (err != null) throw err!;
  expect(done, isTrue, reason: 'request did not complete');
  return out as T;
}
