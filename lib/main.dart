import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:inclinometer/ble/real_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/router.dart';

// WR-02: Dispose _container when the app process is torn down by the OS.
// WidgetsBindingObserver is the only reliable hook that fires on detach
// (process exit / task-swipe on Android) — the isolate can still run briefly.
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _container.dispose();
    }
  }
}

// The single place the concrete BLE implementation is chosen. Swap in
// MockBleManager.demo() here to drive the UI with a simulated instrument
// (service mode can be flipped from the debug-only menu entry in a test).
// All overrides live on _container — ProviderScope uses parent: _container.
final _container = ProviderContainer(
  overrides: [
    bleManagerProvider.overrideWithValue(RealBleManager()),
  ],
);

// The router lives in router.dart so tests can build the same one.
final _router = buildRouter(
  readStatus: () => _container.read(connectionNotifierProvider),
);

Future<void> main() async {
  // RESEARCH.md Pitfall 2: WidgetsFlutterBinding.ensureInitialized() must be
  // called before any platform channel calls (e.g. permission_handler).
  WidgetsFlutterBinding.ensureInitialized();

  // WR-02: Register lifecycle observer so _container is disposed on app detach.
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  // D-01: Cold-start check — detect permanently denied BLE permissions on Android.
  // Writes result to _container so ScanScreen can read it immediately on first build.
  // CR-01 fix: check .status first; isPermanentlyDenied returns true on fresh installs
  // if called directly without first reading .status (permission_handler behaviour).
  if (Platform.isAndroid) {
    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;
    final permanentlyDenied =
        (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) &&
        !scanStatus.isGranted &&
        !connectStatus.isGranted;
    _container
        .read(blePermissionPermanentlyDeniedProvider.notifier)
        .state = permanentlyDenied;
  }

  runApp(
    // RESEARCH.md Pitfall 3: use UncontrolledProviderScope to inject the
    // pre-configured _container directly — do NOT use ProviderScope(overrides:)
    // since overrides (MockBleManager) are already declared on _container above.
    // D-07: ProviderContainer carries bleManagerProvider override; ProviderScope
    // uses parent: _container (implemented via UncontrolledProviderScope).
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        title: 'Leveltronic',
        // D-05: dark theme only — no light/adaptive theme.
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    ),
  );
}
