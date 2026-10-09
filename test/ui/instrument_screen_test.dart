import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/simulated_device.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/tare_provider.dart';
import 'package:inclinometer/ui/widgets/battery_indicator.dart';
import 'package:inclinometer/ui/widgets/vibration_indicator.dart';

import '../support/app_harness.dart';

Finder reading(String label) => find.byKey(ValueKey('reading-$label'));
String textOf(WidgetTester t, Finder f) => t.widget<Text>(f).data!;

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('shows S1, S2 and Diff in mm/m with four decimals', (tester) async {
    final h = await AppHarness.start(tester);

    final s1 = textOf(tester, reading('S1'));
    final s2 = textOf(tester, reading('S2'));
    final diff = textOf(tester, reading('DIFF'));
    final num = RegExp(r'^[+−]\d\.\d{4}$');
    expect(num.hasMatch(s1), isTrue, reason: s1);
    expect(num.hasMatch(s2), isTrue, reason: s2);
    expect(num.hasMatch(diff), isTrue, reason: diff);
    expect(find.text('mm/m'), findsNWidgets(3));
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(find.text('DIFF'), findsOneWidget);

    // Diff really is S1 − S2.
    double v(String t) => double.parse(t.replaceAll('−', '-'));
    expect(v(diff), closeTo(v(s1) - v(s2), 2e-4));
    await h.dispose(tester);
  });

  testWidgets('the readings follow the instrument', (tester) async {
    final h = await AppHarness.start(tester);
    final before = textOf(tester, reading('S1'));
    h.sim.physicalTilt = [3.0, 0.5];
    await h.pump(tester, const Duration(seconds: 1));
    expect(textOf(tester, reading('S1')), isNot(equals(before)));
    await h.dispose(tester);
  });

  testWidgets('battery and on-board temperature sit in the top bar',
      (tester) async {
    final h = await AppHarness.start(tester);
    expect(find.byKey(const ValueKey('battery')), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboard-temp')), findsOneWidget);
    expect(find.text('+24.5 °C'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('the battery indicator shows charging and low states',
      (tester) async {
    final h = await AppHarness.start(tester);
    h.sim.setBattery(soc: 12, mv: 3500, usb: true, charging: true);
    await h.pump(tester, const Duration(seconds: 2));
    final b = tester.widget<BatteryIndicator>(find.byKey(const ValueKey('battery')));
    expect(b.percent, equals(12));
    expect(b.charging, isTrue);
    expect(BatteryIndicator.colorFor(12, BatteryState.normal),
        equals(const Color(0xFFE53935)));
    expect(BatteryIndicator.colorFor(80, BatteryState.normal),
        equals(const Color(0xFF43A047)));
    expect(BatteryIndicator.colorFor(50, BatteryState.low),
        equals(const Color(0xFFFFA000)));
    await h.dispose(tester);
  });

  testWidgets('the vibration indicator turns amber on a disturbed table',
      (tester) async {
    final h = await AppHarness.start(tester);
    var calm = tester.widgetList<VibrationIndicator>(find.byType(VibrationIndicator));
    expect(calm, hasLength(3));
    expect(calm.every((v) => !v.disturbed), isTrue);

    h.sim.disturbed = true;
    await h.pump(tester, const Duration(seconds: 1));
    final bad = tester.widgetList<VibrationIndicator>(find.byType(VibrationIndicator));
    expect(bad.every((v) => v.disturbed), isTrue);
    expect(find.text('disturbed'), findsNWidgets(3));
    await h.dispose(tester);
  });

  group('zero Diff', () {
    testWidgets('sets the displayed Diff to zero and remembers it',
        (tester) async {
      final h = await AppHarness.start(tester);
      final raw = textOf(tester, reading('DIFF'));
      expect(raw, isNot(contains('0.0000')));

      await tester.tap(find.byKey(const ValueKey('zero-diff')));
      await h.pump(tester, const Duration(milliseconds: 600));
      expect(textOf(tester, reading('DIFF')), matches(RegExp(r'^[+−]0\.0000$')));
      expect(h.container.read(tareProvider), isNotNull);
      // S1 and S2 are untouched.
      expect(textOf(tester, reading('S1')), isNot(contains('0.0000')));
      expect(find.text('zeroed'), findsOneWidget);
      expect(find.text('Re-zero Diff'), findsOneWidget);

      // The tilt then changes: Diff moves relative to the zero.
      h.sim.physicalTilt = [h.sim.physicalTilt[0] + 0.5, h.sim.physicalTilt[1]];
      await h.pump(tester, const Duration(seconds: 1));
      expect(textOf(tester, reading('DIFF')), isNot(contains('0.0000')));
      await h.dispose(tester);
    });

    testWidgets('a long-press clears the zero', (tester) async {
      final h = await AppHarness.start(tester);
      await tester.tap(find.byKey(const ValueKey('zero-diff')));
      await h.pump(tester, const Duration(milliseconds: 300));
      expect(h.container.read(tareProvider), isNotNull);
      await tester.longPress(find.byKey(const ValueKey('zero-diff')));
      await h.pump(tester, const Duration(milliseconds: 300));
      expect(h.container.read(tareProvider), isNull);
      expect(find.text('Zero Diff'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('asks first when the table is disturbed', (tester) async {
      final h = await AppHarness.start(tester);
      h.sim.disturbed = true;
      await h.pump(tester, const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('zero-diff')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reading is disturbed'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.container.read(tareProvider), isNull);

      await tester.tap(find.byKey(const ValueKey('zero-diff')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Zero anyway'));
      await h.pump(tester, const Duration(milliseconds: 300));
      expect(h.container.read(tareProvider), isNotNull);
      await h.dispose(tester);
    });

    testWidgets('survives a restart: the zero is stored per instrument',
        (tester) async {
      final h = await AppHarness.start(tester, prefs: {'tare_diff_6DA08073': 0.25});
      await h.pump(tester, const Duration(milliseconds: 500));
      expect(h.container.read(tareProvider), closeTo(0.25, 1e-9));
      expect(find.text('zeroed'), findsOneWidget);
      await h.dispose(tester);
    });
  });

  testWidgets('the menu reaches every other screen', (tester) async {
    final h = await AppHarness.start(tester);
    Future<void> openMenuItem(String label) async {
      await tester.tap(find.byKey(const ValueKey('menu')));
      await h.pump(tester, const Duration(milliseconds: 800));
      await tester.tap(find.text(label).last);
      await h.pump(tester, const Duration(milliseconds: 800));
    }

    for (final entry in {
      'Calibration': 'Phase',
      'Settings': 'Auto power-off',
      'All values': 'BATTERY',
      'Diagnostics': 'Channels in ADC order',
    }.entries) {
      await openMenuItem(entry.key);
      expect(find.textContaining(entry.value, findRichText: true),
          findsWidgets,
          reason: '${entry.key} opens');
      h.router.pop();
      await h.pump(tester, const Duration(milliseconds: 500));
    }
    await h.dispose(tester);
  });

  testWidgets('a lost link greys the readings and goes back to the scan',
      (tester) async {
    final h = await AppHarness.start(tester);
    expect(find.byKey(const ValueKey('reading-S1')), findsOneWidget);
    h.mock.simulateDisconnect();
    await h.pump(tester, const Duration(milliseconds: 600));
    expect(h.router.state.matchedLocation, equals('/scan'));
    await h.dispose(tester);
  });

  testWidgets('shows dashes before the first reading', (tester) async {
    final sim = SimulatedDevice();
    final h = await AppHarness.start(tester, device: sim);
    // The demodulation stops: LIVE flags say "no valid reading".
    final api = h.container.read(instrumentApiProvider);
    await api.setTiltDemod(false);
    await h.pump(tester, const Duration(seconds: 1));
    expect(textOf(tester, reading('S1')), equals('––.––––'));
    await h.dispose(tester);
  });
}
