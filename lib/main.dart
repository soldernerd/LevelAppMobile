import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:inclinometer/ble/real_ble_manager.dart';
import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_driver.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/router.dart';

// Disposes the container (and with it every open device connection) when the
// OS tears the app down. `detached` is the only reliable hook for that
// (process exit / task swipe on Android); the isolate can still run briefly.
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _container.dispose();
    }
  }
}

// The devices this build supports: one driver per device family.
final _registry = DeviceRegistry(const [LeveltronicDriver(), NeigMessDriver()]);

// The single place the concrete BLE implementation is chosen. (The scan
// screen's "Open demo instrument" tile brings a MockBleManager of its own.)
final _container = ProviderContainer(
  overrides: [
    bleManagerProvider.overrideWithValue(RealBleManager()),
    deviceRegistryProvider.overrideWithValue(_registry),
  ],
);

// The router lives in router.dart so tests can build the same one.
final _router = buildRouter(
  registry: _registry,
  readActive: () => _container.read(activeSessionProvider),
);

Future<void> main() async {
  // Must run before any platform channel call (permission_handler below).
  WidgetsFlutterBinding.ensureInitialized();

  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  // Cold start: detect permanently denied BLE permissions on Android, so the
  // scan screen can show its banner on the first build. Read .status first:
  // isPermanentlyDenied is true on a fresh install if asked on its own
  // (permission_handler behaviour).
  if (Platform.isAndroid) {
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    final permanentlyDenied =
        (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) &&
        !scanStatus.isGranted &&
        !connectStatus.isGranted;
    _container
        .read(blePermissionPermanentlyDeniedProvider.notifier)
        .set(permanentlyDenied);
  }

  runApp(
    // UncontrolledProviderScope injects the pre-built container; a plain
    // ProviderScope(overrides: ...) would create a second one.
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        title: 'LevelApp Mobile',
        // Dark theme only.
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    ),
  );
}
