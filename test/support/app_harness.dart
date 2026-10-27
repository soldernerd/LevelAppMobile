import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/devices/leveltronic/simulated_device.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'registry.dart';
import 'package:inclinometer/router.dart';

/// The whole app (real router, real providers) on a simulated instrument.
class AppHarness {
  AppHarness._(this.mock, this.container, this.router);

  final MockBleManager mock;
  final ProviderContainer container;
  final GoRouter router;

  SimulatedDevice get sim => mock.sim;

  /// Builds the app, connects, lets the live feed seed, and opens
  /// [location]. The surface is a tall phone.
  static Future<AppHarness> start(
    WidgetTester tester, {
    SimulatedDevice? device,
    String location = '/leveltronic',
    Map<String, Object> prefs = const {},
    GlobalKey? repaintKey,
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final mock = MockBleManager(device: device ?? SimulatedDevice());
    final container = ProviderContainer(
      overrides: [
        bleManagerProvider.overrideWithValue(mock),
        deviceRegistryProvider.overrideWithValue(testRegistry),
      ],
    );
    late final GoRouter router;
    router = buildRouter(
      registry: testRegistry,
      readActive: () => container.read(activeSessionProvider),
    );
    Widget app = MaterialApp.router(
      theme: theme ?? ThemeData.dark(),
      routerConfig: router,
    );
    if (repaintKey != null) app = RepaintBoundary(key: repaintKey, child: app);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: app,
    ));

    final h = AppHarness._(mock, container, router);
    // Not awaited: the mock's connect delay is a fake-clock timer, which only
    // advances when the test pumps.
    container
        .read(connectionNotifierProvider.notifier)
        .connect('AA:BB:CC:DD:EE:FF');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    if (location != '/scan') {
      router.go(location);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
    }
    return h;
  }

  Future<void> pump(WidgetTester tester, Duration d,
      {Duration step = const Duration(milliseconds: 100)}) async {
    var elapsed = Duration.zero;
    while (elapsed < d) {
      await tester.pump(step);
      elapsed += step;
    }
  }

  /// Tears everything down so no timer outlives the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    mock.dispose();
    await tester.pump();
  }
}
