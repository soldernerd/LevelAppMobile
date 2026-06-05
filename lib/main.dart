import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/instrument_screen.dart';
import 'package:inclinometer/ui/scan_screen.dart';

// WP2 swap point: replace MockBleManager() with RealBleManager() here.
// All overrides live on _container — ProviderScope uses parent: _container.
final _container = ProviderContainer(
  overrides: [
    bleManagerProvider.overrideWithValue(MockBleManager()),
  ],
);

// GoRouter instance — no refreshListenable (D-04).
// Redirect fires only on navigation attempts, not on live state changes.
// Post-connect navigation to /instrument is handled explicitly by ScanScreen
// via context.go('/instrument').
final _router = GoRouter(
  initialLocation: '/scan',
  redirect: (context, state) {
    // Guard: only redirect to /scan if the user is trying to reach /instrument
    // without being connected. The matchedLocation check prevents redirect loops
    // when already on /scan (RESEARCH.md Pitfall 1).
    if (state.matchedLocation == '/instrument' &&
        _container.read(connectionNotifierProvider) !=
            ConnectionStatus.connected) {
      return '/scan';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/scan',
      builder: (context, state) => const ScanScreen(),
    ),
    GoRoute(
      path: '/instrument',
      builder: (context, state) => const InstrumentScreen(),
    ),
  ],
);

Future<void> main() async {
  // RESEARCH.md Pitfall 2: WidgetsFlutterBinding.ensureInitialized() must be
  // called before any platform channel calls (e.g. permission_handler).
  WidgetsFlutterBinding.ensureInitialized();

  // D-01: Cold-start check — detect permanently denied BLE permissions on Android.
  // Writes result to _container so ScanScreen can read it immediately on first build.
  if (Platform.isAndroid) {
    final permanentlyDenied =
        await Permission.bluetoothScan.isPermanentlyDenied ||
            await Permission.bluetoothConnect.isPermanentlyDenied;
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
        title: 'Inclinometer',
        // D-05: dark theme only — no light/adaptive theme.
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    ),
  );
}
