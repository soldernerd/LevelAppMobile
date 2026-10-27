import 'package:go_router/go_router.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_session.dart';
import 'package:inclinometer/devices/leveltronic/ui/calibration_hub_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/diagnostics_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/flip_cal_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/gain_cal_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/info_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/instrument_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/phase_cal_screen.dart';
import 'package:inclinometer/devices/leveltronic/ui/settings_screen.dart';

/// The Leveltronic precision level (STM32G0B1 / RN4871, firmware API v3).
///
/// ```
/// /leveltronic                       live screen
///   /leveltronic/calibration         hub
///     .../phase  .../gain  .../flip wizards
///   /leveltronic/settings            ?tab=0 settings, 1 actions, 2 calibration
///   /leveltronic/info                all values
///   /leveltronic/diagnostics         signal diagnostics
/// ```
class LeveltronicDriver extends DeviceDriver {
  const LeveltronicDriver();

  /// The `product` the firmware reports in System IDENTITY.
  static const product = 'InclinationMeter';

  @override
  String get id => 'leveltronic';

  @override
  String get displayName => 'Leveltronic';

  /// The instrument advertises as `Leveltronic-<last 2 MAC bytes>` (firmware
  /// `Config/config.h` `BLE_DEVICE_NAME`).
  @override
  List<String> get advertisedNamePrefixes => const ['Leveltronic'];

  @override
  bool claims(ApiIdentity identity) => identity.product == product;

  @override
  Future<DeviceSession> open(
    DeviceConnection connection,
    ApiIdentity identity,
  ) async {
    ensureCompatible(identity);
    return LeveltronicSession(
      driver: this,
      connection: connection,
      identity: identity,
    )..start();
  }

  @override
  GoRoute get route => GoRoute(
        path: homeLocation,
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
      );
}
