import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/ble/simulated_peripheral.dart';
import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_driver.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_session.dart';
import 'package:inclinometer/devices/leveltronic/simulated_device.dart';
import 'package:inclinometer/models/connection.dart';
import 'package:inclinometer/providers/device_provider.dart';

import '../support/harness.dart';

/// A second device family, to prove the app does not assume the Leveltronic.
class _OtherDriver extends DeviceDriver {
  const _OtherDriver();

  @override
  String get id => 'other';
  @override
  String get displayName => 'Other';
  @override
  List<String> get advertisedNamePrefixes => const ['Other'];
  @override
  bool claims(ApiIdentity identity) => identity.product == 'OtherDevice';
  @override
  Future<DeviceSession> open(DeviceConnection c, ApiIdentity identity) async =>
      _OtherSession(driver: this, connection: c, identity: identity);
  @override
  GoRoute get route => GoRoute(
        path: homeLocation,
        builder: (context, state) => const SizedBox(),
      );
}

class _OtherSession extends DeviceSession {
  _OtherSession({
    required super.driver,
    required super.connection,
    required super.identity,
  });
}

/// Answers System IDENTITY with the given product and nothing else.
class _OtherPeripheral implements SimulatedPeripheral {
  _OtherPeripheral([this.product = 'OtherDevice']);

  final String product;

  @override
  void Function()? onLinkDown;

  @override
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    if (opcode != opGet(ApiCat.system, SysRes.identity)) {
      return const ApiReply(ApiStatus.unknownResource);
    }
    final d = Uint8List(50);
    d[3] = kApiVersion;
    ByteData.sublistView(d).setUint16(4, kApiMaxPayload, Endian.little);
    d.setRange(6, 6 + product.length, product.codeUnits);
    d.setRange(22, 26, 'OT01'.codeUnits);
    return ApiReply(ApiStatus.ok, d);
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) =>
      const Stream<Uint8List>.empty();

  @override
  void linkDown() => onLinkDown?.call();

  @override
  void dispose() {}
}

const _levelId = 'AA:00';
const _otherId = 'BB:00';

ProviderContainer _container(MockBleManager mock) {
  final c = ProviderContainer(overrides: [
    bleManagerProvider.overrideWithValue(mock),
    deviceRegistryProvider.overrideWithValue(
        DeviceRegistry(const [LeveltronicDriver(), _OtherDriver()])),
  ]);
  addTearDown(c.dispose);
  addTearDown(mock.dispose);
  return c;
}

MockBleManager _mock({String otherProduct = 'OtherDevice'}) =>
    MockBleManager.withPeripherals([
      MockPeripheral(
          id: _levelId, name: 'Leveltronic-0001', sim: SimulatedDevice()),
      MockPeripheral(
          id: _otherId,
          name: 'Other-0002',
          sim: _OtherPeripheral(otherProduct)),
    ]);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('DeviceRegistry', () {
    test('a scan accepts the advertised names of every driver', () {
      final r = DeviceRegistry(const [LeveltronicDriver(), _OtherDriver()]);
      expect(r.acceptsAdvertisedName('Leveltronic-EEFF'), isTrue);
      expect(r.acceptsAdvertisedName('Other-1'), isTrue);
      expect(r.acceptsAdvertisedName('Headphones'), isFalse);
      expect(r.acceptsAdvertisedName(''), isFalse);
    });

    test('the IDENTITY product, not the name, chooses the driver', () {
      fakeAsync((async) {
        final mock = _mock();
        final c = _container(mock);
        final registry = c.read(deviceRegistryProvider);
        final conn = settle(async, mock.open(_levelId));
        final s = settle(async, registry.openSession(conn));
        expect(s, isA<LeveltronicSession>());
        expect(s.driver.id, equals('leveltronic'));
        final other = settle(async, mock.open(_otherId));
        expect(settle(async, registry.openSession(other)).driver.id,
            equals('other'));
      });
    });

    test('a product nobody claims is refused and the link is closed', () {
      fakeAsync((async) {
        final mock = _mock(otherProduct: 'Mystery');
        final c = _container(mock);
        final conn = settle(async, mock.open(_otherId));
        expect(
          () => settle(
              async, c.read(deviceRegistryProvider).openSession(conn)),
          throwsA(isA<UnsupportedDeviceException>()
              .having((e) => e.message, 'message', contains('Mystery'))),
        );
        var closed = false;
        conn.closed.then((_) => closed = true);
        async.flushMicrotasks();
        expect(closed, isTrue);
      });
    });
  });

  group('several connections', () {
    test('devices of different families are open at once', () {
      fakeAsync((async) {
        final mock = _mock();
        final c = _container(mock);
        final n = c.read(connectionNotifierProvider.notifier);

        settle(async, n.connect(_levelId));
        settle(async, n.connect(_otherId));
        pass(async, const Duration(milliseconds: 600));

        final open = c.read(sessionsProvider);
        expect(open.all.map((s) => s.driver.id),
            equals(['leveltronic', 'other']));
        expect(open.activeId, equals(_otherId),
            reason: 'the newest connection becomes the active one');
        expect(c.read(connectionNotifierProvider),
            equals(ConnectionStatus.connected));

        // The Leveltronic keeps streaming in the background.
        final level = open.all.first as LeveltronicSession;
        expect(level.state.hasReading, isTrue);
      });
    });

    test('connecting to an open device just switches to it', () {
      fakeAsync((async) {
        final mock = _mock();
        final c = _container(mock);
        final n = c.read(connectionNotifierProvider.notifier);
        settle(async, n.connect(_levelId));
        settle(async, n.connect(_otherId));

        settle(async, n.connect(_levelId));
        expect(c.read(sessionsProvider).all, hasLength(2));
        expect(c.read(activeSessionProvider)?.id, equals(_levelId));
      });
    });

    test('losing the active device falls back to the other one', () {
      fakeAsync((async) {
        final mock = _mock();
        final c = _container(mock);
        final n = c.read(connectionNotifierProvider.notifier);
        settle(async, n.connect(_levelId));
        settle(async, n.connect(_otherId));

        mock.simulateDisconnect(_otherId);
        pass(async, const Duration(milliseconds: 100));

        expect(c.read(sessionsProvider).all.map((s) => s.id),
            equals([_levelId]));
        expect(c.read(activeSessionProvider)?.id, equals(_levelId));
        expect(c.read(connectionNotifierProvider),
            equals(ConnectionStatus.connected));
      });
    });

    test('disconnecting one leaves the other; the last one ends the session',
        () {
      fakeAsync((async) {
        final mock = _mock();
        final c = _container(mock);
        final n = c.read(connectionNotifierProvider.notifier);
        settle(async, n.connect(_levelId));
        settle(async, n.connect(_otherId));

        settle(async, n.disconnect(deviceId: _levelId));
        expect(c.read(sessionsProvider).all.map((s) => s.id),
            equals([_otherId]));
        expect(c.read(connectionNotifierProvider),
            equals(ConnectionStatus.connected));

        settle(async, n.disconnect());
        pass(async, const Duration(milliseconds: 50));
        expect(c.read(sessionsProvider).isEmpty, isTrue);
        expect(c.read(connectionNotifierProvider),
            equals(ConnectionStatus.disconnected));
      });
    });

    test('an unsupported device is reported and does not disturb the others',
        () {
      fakeAsync((async) {
        final mock = _mock(otherProduct: 'Mystery');
        final c = _container(mock);
        final n = c.read(connectionNotifierProvider.notifier);
        settle(async, n.connect(_levelId));

        settle(async, n.connect(_otherId));
        expect(c.read(connectionNotifierProvider),
            equals(ConnectionStatus.error));
        expect(c.read(connectionErrorProvider), contains('Mystery'));
        expect(c.read(sessionsProvider).all.map((s) => s.id),
            equals([_levelId]));
        expect(c.read(activeSessionProvider)?.id, equals(_levelId));
      });
    });
  });
}
