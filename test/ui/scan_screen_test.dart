// test/ui/scan_screen_test.dart
// Widget tests for ScanScreen — SCAN-01 through SCAN-05.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/scan_screen.dart';

/// Wraps [ScanScreen] in a ProviderScope with a [MockBleManager] override.
Widget buildHarness(MockBleManager ble) {
  return ProviderScope(
    overrides: [bleManagerProvider.overrideWithValue(ble)],
    child: const MaterialApp(home: ScanScreen()),
  );
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('ScanScreen — scaffold', () {
    test('placeholder — replaced in plan 04', () {
      expect(true, isTrue);
    });
  });

  group('ScanScreen — FAB icon toggle (SCAN-01)', () {
    testWidgets('FAB shows bluetooth_searching icon when idle', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
    });

    testWidgets('FAB shows stop icon when scanning', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      // Tap FAB to start scanning.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.stop), findsOneWidget);
    });
  });

  group('ScanScreen — scan state chip (SCAN-04)', () {
    testWidgets('chip label is Idle when status is idle', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('chip label is Scanning when scanning', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Scanning'), findsOneWidget);
    });
  });

  group('ScanScreen — device list (SCAN-02 / SCAN-03)', () {
    testWidgets('named device appears with name and dBm trailing text', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      // Start scanning — MockBleManager emits named 'Inclinometer' after 500 ms.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Inclinometer'), findsOneWidget);
      expect(find.text('-65 dBm'), findsOneWidget);
    });
  });

  group('ScanScreen — connect on tap (SCAN-05)', () {
    testWidgets('tapping a device tile calls connect and transitions to Connecting', (tester) async {
      await tester.pumpWidget(buildHarness(MockBleManager()));
      await tester.pump();

      // Trigger scan so device appears.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Inclinometer'), findsOneWidget);

      // Tap device row — triggers connect().
      await tester.tap(find.text('Inclinometer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // connect() sets status to connecting (MockBleManager always does this).
      expect(find.text('Connecting…'), findsOneWidget);
    });
  });
}
