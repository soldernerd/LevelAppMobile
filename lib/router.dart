import 'package:go_router/go_router.dart';

import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/ui/scan_screen.dart';

/// The app's routes:
///
/// ```
/// /scan
/// /<driver id>/...       each registered driver's route tree (its home
///                        screen at /<driver id>), e.g. /leveltronic
/// ```
///
/// A driver's routes need a live connection to a device of that driver — the
/// active one ([readActive]); otherwise the way leads back to /scan.
///
/// No refreshListenable: the redirect fires only on navigation attempts, not
/// on live state changes. Post-connect navigation to the device is done by
/// ScanScreen via `context.go`, the way back (or on to another open device) by
/// [ActiveSessionRedirect] on a driver's home screen.
GoRouter buildRouter({
  required DeviceRegistry registry,
  required DeviceSession? Function() readActive,
  String initialLocation = '/scan',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      final segments = state.matchedLocation.split('/');
      final driver = segments.length > 1 ? registry.byId(segments[1]) : null;
      // The matchedLocation check prevents redirect loops when already on /scan.
      if (driver != null && readActive()?.driver.id != driver.id) {
        return '/scan';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      for (final driver in registry.drivers) driver.route,
    ],
  );
}
