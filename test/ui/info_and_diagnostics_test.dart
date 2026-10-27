import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/devices/leveltronic/simulated_device.dart';

import '../support/app_harness.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('all values', () {
    const loc = '/leveltronic/info';

    testWidgets('shows battery, temperatures, humidity and pressure',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 2));
      expect(find.text('85 %'), findsOneWidget);
      expect(find.text('4.020 V'), findsOneWidget);
      expect(find.text('+24.50 °C'), findsOneWidget); // on-board
      expect(find.text('+23.80 °C'), findsOneWidget); // BME280
      expect(find.text('not connected'), findsOneWidget); // no LM35
      expect(find.text('41.0 %RH'), findsOneWidget);
      expect(find.text('964.0 hPa'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('shows an external probe when one is connected',
        (tester) async {
      // The simulator reports ext. temp not OK; check the wording instead of
      // a value, then the identity.
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 2));
      expect(find.text('External probe (LM35)'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('shows identity and health', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 2));
      await tester.scrollUntilVisible(find.text('Serial'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('6DA08073'), findsOneWidget);
      expect(find.text('InclinationMeter'), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'API version');
      await tester.scrollUntilVisible(find.text('Uptime'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Uptime'), findsOneWidget);
      expect(find.textContaining('power-on'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('shows the clock and sets it to the phone time',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 2));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('set-clock')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('not set'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('set-clock')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('set-clock')));
      await h.pump(tester, const Duration(seconds: 3));
      expect(find.text('not set'), findsNothing);
      expect(find.text('within 2 s'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('follows the charger', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      h.sim.setBattery(soc: 40, mv: 3800, usb: true, charging: true);
      await h.pump(tester, const Duration(seconds: 3));
      expect(find.text('40 %'), findsOneWidget);
      expect(find.text('3.800 V'), findsOneWidget);
      expect(find.text('Charging'), findsWidgets);
      await h.dispose(tester);
    });
  });

  group('diagnostics', () {
    const loc = '/leveltronic/diagnostics';

    testWidgets('shows RMS, peak-to-peak and phase of all four channels',
        (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 1));
      for (final ch in ['S2', 'B', 'A', 'S1']) {
        expect(find.byKey(ValueKey('diag-$ch')), findsOneWidget, reason: ch);
      }
      expect(find.text('RMS'), findsNWidgets(4));
      expect(find.text('PEAK–PEAK'), findsNWidgets(4));
      expect(find.text('PHASE'), findsNWidgets(4));
      // The simulator: S2 4.10 mV rms, B 310.0, A 309.5, S1 3.80.
      expect(find.text('4.10 mV'), findsOneWidget);
      expect(find.text('310.0 mV'), findsOneWidget);
      expect(find.text('309.5 mV'), findsOneWidget);
      expect(find.text('3.80 mV'), findsOneWidget);
      // A is the phase reference.
      expect(find.text('+0.0°'), findsOneWidget);
      expect(find.text('+180.0°'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('lists the theoretical tilt of each sensor', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 1));
      await tester.scrollUntilVisible(
          find.text('Theoretical tilt from the signal amplitude'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('mm/m'), findsWidgets);
      await h.dispose(tester);
    });

    testWidgets('updates while open and stops when closed', (tester) async {
      final h = await AppHarness.start(tester, location: loc);
      await h.pump(tester, const Duration(seconds: 1));
      h.router.pop();
      await h.pump(tester, const Duration(seconds: 1));
      await h.dispose(tester);
    });
  });

  group('scan screen', () {
    testWidgets('tells the user an API v2 instrument needs a firmware update',
        (tester) async {
      final h = await AppHarness.start(tester,
          device: SimulatedDevice(apiVersion: 2), location: '/scan');
      await h.pump(tester, const Duration(milliseconds: 500));
      final text = tester.widget<Text>(find.byKey(const ValueKey('scan-error')));
      expect(text.data, contains('API v2'));
      expect(text.data, contains('needs API v3'));
      await h.dispose(tester);
    });
  });
}
