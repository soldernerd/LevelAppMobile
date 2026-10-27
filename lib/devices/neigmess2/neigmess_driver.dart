import 'package:go_router/go_router.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_session.dart';
import 'package:inclinometer/devices/neigmess2/ui/neigmess_screen.dart';

/// The NeigMess2 capacitive inclination meter (API v2 over the same RN4871
/// Transparent UART): live tilt and sensor readings, zeroing.
///
/// ```
/// /neigmess2        live screen
/// ```
class NeigMessDriver extends DeviceDriver {
  const NeigMessDriver();

  /// The `product` in System IDENTITY.
  static const product = 'NeigMess2';

  @override
  String get id => 'neigmess2';

  @override
  String get displayName => 'NeigMess2';

  @override
  List<String> get advertisedNamePrefixes => const ['NeigMess2'];

  @override
  bool claims(ApiIdentity identity) => identity.product == product;

  @override
  Future<DeviceSession> open(
    DeviceConnection connection,
    ApiIdentity identity,
  ) async =>
      NeigMessSession(driver: this, connection: connection, identity: identity)
        ..start();

  @override
  GoRoute get route => GoRoute(
        path: homeLocation,
        builder: (context, state) => const NeigMessScreen(),
      );
}
