/// What a device family plugs into the app: how to recognise it, how to talk to
/// it, and which screens it brings.
///
/// The shared BLE transport ([BleManager]) opens a [DeviceConnection] to
/// whatever the user picks. [DeviceRegistry.identify] reads System IDENTITY
/// from it and asks the registered [DeviceDriver]s which one claims the
/// `product`; that driver then builds a [DeviceSession] — the device-specific
/// typed API, live feeds and so on — which lives for as long as the connection.
/// Nothing outside `lib/devices/<device>/` knows what a particular device can do.
///
/// Adding a device: implement a [DeviceDriver] (and a [DeviceSession] subclass),
/// put it in `lib/devices/<device>/`, and add it to the registry in `main.dart`.
library;

import 'dart:async';

import 'package:go_router/go_router.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';

/// Why a connection was refused, in words fit for the scan screen.
abstract class ConnectFailure implements Exception {
  String get message;
}

/// The device answered, but no registered driver claims what it is.
class UnsupportedDeviceException implements ConnectFailure {
  const UnsupportedDeviceException(this.product);

  /// The IDENTITY `product`, or null if the device did not identify itself.
  final String? product;

  @override
  String get message => product == null
      ? 'This device did not identify itself. Its firmware may be too old for '
          'this app.'
      : 'This app does not support "$product".';

  @override
  String toString() => 'UnsupportedDeviceException($message)';
}

/// A family of devices: recognition, protocol and UI.
abstract class DeviceDriver {
  const DeviceDriver();

  /// Short stable id (`leveltronic`); also the first segment of the driver's
  /// routes.
  String get id;

  /// Shown to the user.
  String get displayName;

  /// Advertised-name prefixes of this family. Only a scan filter: whether a
  /// connected device really belongs to the driver is decided by
  /// [claims] on its IDENTITY.
  List<String> get advertisedNamePrefixes;

  /// Whether the device that reported [identity] is one of this family.
  bool claims(ApiIdentity identity);

  /// Builds the session for a device this driver [claims]: checks that the
  /// firmware is one the driver can speak (throwing a [ConnectFailure] if not)
  /// and starts whatever the driver keeps running for a connected device.
  /// The registry closes [connection] if this throws.
  Future<DeviceSession> open(DeviceConnection connection, ApiIdentity identity);

  /// The driver's route tree, rooted at [homeLocation]: the home screen and
  /// everything below it.
  GoRoute get route;

  String get homeLocation => '/$id';
}

/// One identified, open device. Subclasses add the device-specific API.
abstract class DeviceSession {
  DeviceSession({
    required this.driver,
    required this.connection,
    required this.identity,
  });

  final DeviceDriver driver;
  final DeviceConnection connection;
  final ApiIdentity identity;

  /// The BLE id; unique among the open sessions.
  String get id => connection.id;

  /// How the user tells this device from another: the driver's name and the
  /// serial number, or the tail of the BLE address if it has none.
  String get label {
    final tail = id.length > 5 ? id.substring(id.length - 5) : id;
    return '${driver.displayName} ${identity.serial.isEmpty ? tail : identity.serial}';
  }

  /// Completes when the link is gone.
  Future<void> get closed => connection.closed;

  /// Stops what the session keeps running and ends the connection.
  Future<void> close() => connection.close();
}

/// The drivers this build knows.
class DeviceRegistry {
  DeviceRegistry(this.drivers)
      : assert(drivers.map((d) => d.id).toSet().length == drivers.length,
            'driver ids must be unique');

  final List<DeviceDriver> drivers;

  /// Whether a scan should show an advertiser with this name.
  bool acceptsAdvertisedName(String name) => name.isNotEmpty &&
      drivers.any((d) => d.advertisedNamePrefixes.any(name.startsWith));

  DeviceDriver? byId(String id) {
    for (final d in drivers) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The driver that claims [identity], or null.
  DeviceDriver? driverFor(ApiIdentity identity) {
    for (final d in drivers) {
      if (d.claims(identity)) return d;
    }
    return null;
  }

  /// Reads System IDENTITY from [connection], picks the driver and opens its
  /// session. Closes [connection] and rethrows if anything fails. The first
  /// request right after enabling notifications is occasionally lost on the
  /// RN4871, so a timeout gets two more tries; a real answer (including "not
  /// one of ours") is final.
  Future<DeviceSession> openSession(DeviceConnection connection) async {
    try {
      final identity = await _identify(connection);
      final driver = driverFor(identity);
      if (driver == null) throw UnsupportedDeviceException(identity.product);
      return await driver.open(connection, identity);
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Future<ApiIdentity> _identify(DeviceLink link) async {
    for (var attempt = 1;; attempt++) {
      try {
        final r = await link.request(opGet(ApiCat.system, SysRes.identity));
        final id = r.ok ? ApiIdentity.decode(r.data) : null;
        // An older firmware answers v3's IDENTITY opcode with an error or with
        // a short payload.
        if (id == null) throw const UnsupportedDeviceException(null);
        return id;
      } on LinkException {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }
}
