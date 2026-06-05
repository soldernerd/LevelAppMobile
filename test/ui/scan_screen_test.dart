// test/ui/scan_screen_test.dart
// Widget tests for ScanScreen — SCAN-01 through SCAN-05 and INST-01.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/instrument_screen.dart';
import 'package:inclinometer/ui/scan_screen.dart';

/// A fixed-status notifier for testing specific connection states.
class _FixedStatusNotifier extends ConnectionNotifier {
  _FixedStatusNotifier(this._status);
  final ConnectionStatus _status;

  @override
  ConnectionStatus build() => _status;
}

/// Wraps [ScanScreen] in a ProviderScope with a [MockBleManager] override.
///
/// Registers [ble.dispose] as a teardown so the mock's periodic ticker is
/// cancelled before the test framework checks for pending timers.
Widget buildHarness(MockBleManager ble) {
  addTearDown(ble.dispose);
  return ProviderScope(
    overrides: [bleManagerProvider.overrideWithValue(ble)],
    child: const MaterialApp(home: ScanScreen()),
  );
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('SCAN-01: FAB icon toggle — startScan and stopScan', () {
    testWidgets('SCAN-01: FAB shows bluetooth_searching icon when idle',
        (tester) async {
      final ble = MockBleManager();
      await tester.pumpWidget(buildHarness(ble));
      await tester.pump();

      expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);
    });

    testWidgets('SCAN-01: FAB shows stop icon when scanning', (tester) async {
      final ble = MockBleManager();
      await tester.pumpWidget(buildHarness(ble));
      await tester.pump();

      // Tap FAB to start scanning.
      await tester.tap(find.byType(FloatingActionButton));
      // Advance past the scan-result timer (500 ms) so no pending timer remains.
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byIcon(Icons.stop), findsOneWidget);
    });
  });

  group('SCAN-02: Device list renders name and RSSI', () {
    testWidgets('SCAN-02: named device appears with name and dBm trailing text',
        (tester) async {
      final ble = MockBleManager();
      await tester.pumpWidget(buildHarness(ble));
      await tester.pump();

      // Start scanning — MockBleManager emits named 'Inclinometer' after 500 ms.
      await tester.tap(find.byType(FloatingActionButton));
      // Advance past the 500ms scan timer so the device is emitted.
      await tester.pump(const Duration(milliseconds: 600));
      // Extra frame so Riverpod state = state triggers scanResultsProvider rebuild.
      await tester.pump();

      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Inclinometer'), findsOneWidget);
      expect(find.text('-65 dBm'), findsOneWidget);
    });
  });

  group('SCAN-03: Unnamed devices are filtered from the list', () {
    testWidgets('SCAN-03: only named devices appear in the list', (tester) async {
      final ble = MockBleManager();
      addTearDown(ble.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleManagerProvider.overrideWithValue(ble),
            scanResultsProvider.overrideWith(
              (ref) => [
                const ScannedDevice(id: 'id1', name: '', rssi: -70),
                const ScannedDevice(id: 'id2', name: 'Test Device', rssi: -65),
              ],
            ),
          ],
          child: const MaterialApp(home: ScanScreen()),
        ),
      );
      await tester.pump();

      // Only 1 ListTile should appear (unnamed filtered out).
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Test Device'), findsOneWidget);
    });
  });

  group('SCAN-04: Scan state chip shows correct label', () {
    testWidgets('SCAN-04: chip label is Idle when status is idle', (tester) async {
      final ble = MockBleManager();
      await tester.pumpWidget(buildHarness(ble));
      await tester.pump();

      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('SCAN-04: chip label is Scanning when scanning', (tester) async {
      final ble = MockBleManager();
      addTearDown(ble.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleManagerProvider.overrideWithValue(ble),
            connectionNotifierProvider.overrideWith(
              () => _FixedStatusNotifier(ConnectionStatus.scanning),
            ),
          ],
          child: const MaterialApp(home: ScanScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Scanning'), findsOneWidget);
    });
  });

  group('SCAN-05: Tapping a device tile calls connect()', () {
    testWidgets('SCAN-05: tapping a device tile calls connect and transitions to Connecting',
        (tester) async {
      final ble = MockBleManager();
      // Note: do NOT use buildHarness here — we need explicit control over ble.dispose
      // timing to avoid pending-timer assertion failures.
      await tester.pumpWidget(ProviderScope(
        overrides: [bleManagerProvider.overrideWithValue(ble)],
        child: const MaterialApp(home: ScanScreen()),
      ));
      await tester.pump();

      // Trigger scan so device appears.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Extra frame for Riverpod scanResultsProvider rebuild.

      expect(find.text('Inclinometer'), findsOneWidget);

      // Tap device row — triggers connect().
      await tester.tap(find.text('Inclinometer'));
      // Pump to deliver connecting status from stream.
      await tester.pump(const Duration(milliseconds: 50));

      // connect() sets status to connecting (MockBleManager always does this).
      expect(find.text('Connecting…'), findsOneWidget);

      // Drain the 300ms Future.delayed timer inside MockBleManager.connect().
      // This causes status → connected and starts the 100ms periodic ticker.
      await tester.pump(const Duration(milliseconds: 350));
      // Dispose mock to cancel the periodic ticker before test ends.
      ble.dispose();
      await tester.pump();
    });
  });

  group('INST-01: InstrumentScreen is pushed after ConnectionStatus.connected', () {
    testWidgets('INST-01: navigates to InstrumentScreen on connected status',
        (tester) async {
      // Use a wide surface to prevent RenderFlex overflow when InstrumentScreen renders
      // its 80sp angle readout.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ble = MockBleManager();
      await tester.pumpWidget(buildHarness(ble));
      await tester.pump();

      // ScanScreen visible initially.
      expect(find.text('Scan'), findsOneWidget);

      // Trigger scan so device appears.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.text('Inclinometer'), findsOneWidget);

      // Tap device row — triggers connect() via connectionNotifierProvider.
      await tester.tap(find.text('Inclinometer'));
      // Let connecting status propagate.
      await tester.pump(const Duration(milliseconds: 50));

      // Advance through the 300ms connect delay → connected.
      await tester.pump(const Duration(milliseconds: 350));
      // Extra pump for Navigator push post-frame callback.
      await tester.pump();

      // InstrumentScreen should now be visible — it shows a 'Disconnected' or
      // 'Connected' chip in its AppBar (unlike ScanScreen which shows 'Idle'/'Scanning').
      // We look for InstrumentScreen by type or check for the 'Zero X' button unique to it.
      expect(find.byType(InstrumentScreen), findsOneWidget);

      // Drain 100ms periodic ticker and dispose.
      await tester.pump(const Duration(milliseconds: 100));
      ble.dispose();
      await tester.pump();
    });
  });
}
