import 'package:go_router/go_router.dart';

import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/ui/calibration_hub_screen.dart';
import 'package:inclinometer/ui/diagnostics_screen.dart';
import 'package:inclinometer/ui/flip_cal_screen.dart';
import 'package:inclinometer/ui/gain_cal_screen.dart';
import 'package:inclinometer/ui/info_screen.dart';
import 'package:inclinometer/ui/instrument_screen.dart';
import 'package:inclinometer/ui/phase_cal_screen.dart';
import 'package:inclinometer/ui/scan_screen.dart';
import 'package:inclinometer/ui/settings_screen.dart';

/// The app's routes:
///
/// ```
/// /scan
/// /instrument                       live screen
///   /instrument/calibration         hub
///     .../phase  .../gain  .../flip wizards
///   /instrument/settings            ?tab=0 settings, 1 actions, 2 calibration
///   /instrument/info                all values
///   /instrument/diagnostics         signal diagnostics
/// ```
///
/// No refreshListenable: the redirect fires only on navigation attempts, not
/// on live state changes. Post-connect navigation to /instrument is done by
/// ScanScreen via `context.go`, the way back by InstrumentScreen on a
/// disconnect.
GoRouter buildRouter({
  required ConnectionStatus Function() readStatus,
  String initialLocation = '/scan',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      // Anything under /instrument needs a live connection. The
      // matchedLocation check prevents redirect loops when already on /scan.
      if (state.matchedLocation.startsWith('/instrument') &&
          readStatus() != ConnectionStatus.connected) {
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
        routes: [
          GoRoute(
            path: 'calibration',
            builder: (context, state) => const CalibrationHubScreen(),
            routes: [
              GoRoute(
                path: 'phase',
                builder: (context, state) => const PhaseCalScreen(),
              ),
              GoRoute(
                path: 'gain',
                builder: (context, state) => const GainCalScreen(),
              ),
              GoRoute(
                path: 'flip',
                builder: (context, state) => const FlipCalScreen(),
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => SettingsScreen(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: 'info',
            builder: (context, state) => const InfoScreen(),
          ),
          GoRoute(
            path: 'diagnostics',
            builder: (context, state) => const DiagnosticsScreen(),
          ),
        ],
      ),
    ],
  );
}
