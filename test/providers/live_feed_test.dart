import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/live_feed.dart';
import 'package:inclinometer/ble/instrument_api.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/ble/simulated_device.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

import '../support/harness.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('LiveFeed', () {
    test('merges LIVE, STATUS and ENV into one state', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        settle(async, mock.connect('x'));
        final feed = LiveFeed(InstrumentApi(mock));
        final seen = <DeviceState>[];
        feed.stream.listen(seen.add);
        feed.start();
        pass(async, const Duration(seconds: 2));

        final s = feed.state;
        expect(s.hasReading, isTrue);
        expect(s.tiltS1, isNotNull);
        expect(s.tiltDiff, closeTo(s.tiltS1! - s.tiltS2!, 1e-4));
        expect(s.batteryPercent, equals(85));
        expect(s.batteryMv, equals(4020));
        expect(s.onboardTempC, closeTo(24.5, 1e-9));
        expect(s.env!.humidityPct, closeTo(41.0, 1e-9));
        expect(seen.length, greaterThan(5), reason: 'about 4 readings a second');
        feed.stop();
      });
    });

    test('is seeded at once, before the first push', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        settle(async, mock.connect('x'));
        final feed = LiveFeed(InstrumentApi(mock))..start();
        pass(async, const Duration(milliseconds: 60));
        expect(feed.state.status, isNotNull);
        expect(feed.state.live, isNotNull);
        expect(feed.state.env, isNotNull);
        feed.stop();
      });
    });

    test('starts the demodulation if a previous host left it stopped', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        settle(async, mock.connect('x'));
        final api = InstrumentApi(mock);
        settle(async, api.setTiltDemod(false));
        expect(settle(async, api.state()).demodRunning, isFalse);
        final feed = LiveFeed(api)..start();
        pass(async, const Duration(seconds: 1));
        expect(settle(async, api.state()).demodRunning, isTrue);
        feed.stop();
      });
    });

    test('reports service mode from STATUS within a second', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        settle(async, mock.connect('x'));
        final feed = LiveFeed(InstrumentApi(mock))..start();
        pass(async, const Duration(seconds: 1));
        expect(feed.state.serviceMode, isFalse);
        mock.sim.setServiceMode(true);
        pass(async, const Duration(milliseconds: 1500));
        expect(feed.state.serviceMode, isTrue);
        feed.stop();
      });
    });

    test('flags a disturbed table per sensor', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        settle(async, mock.connect('x'));
        final feed = LiveFeed(InstrumentApi(mock))..start();
        pass(async, const Duration(seconds: 1));
        expect(feed.state.diffDoubtful, isFalse);
        mock.sim.disturbed = true;
        pass(async, const Duration(seconds: 1));
        expect(feed.state.s1Doubtful, isTrue);
        expect(feed.state.s2Doubtful, isTrue);
        expect(feed.state.diffDoubtful, isTrue);
        feed.stop();
      });
    });
  });

  group('connection', () {
    test('connecting starts the feed and publishes DeviceState', () {
      fakeAsync((async) {
        final h = SimHarness();
        final seen = <DeviceState?>[];
        h.container.listen(instrumentDataProvider, (_, next) {
          if (next.hasValue) seen.add(next.value);
        });
        h.connect(async);
        pass(async, const Duration(seconds: 1));
        expect(seen.whereType<DeviceState>(), isNotEmpty);
        expect(seen.whereType<DeviceState>().last.hasReading, isTrue);
      });
    });

    test('a link loss ends with the stale sentinel and a disconnected state', () {
      fakeAsync((async) {
        final h = SimHarness();
        final seen = <DeviceState?>[];
        h.container.listen(instrumentDataProvider, (_, next) {
          if (next.hasValue) seen.add(next.value);
        });
        h.connect(async);
        pass(async, const Duration(seconds: 1));
        h.mock.simulateDisconnect();
        pass(async, const Duration(milliseconds: 200));
        expect(h.container.read(connectionNotifierProvider),
            equals(ConnectionStatus.disconnected));
        expect(seen.last, isNull);
      });
    });

    test('an API v2 instrument is refused, with a message that says why', () {
      fakeAsync((async) {
        final h = SimHarness(device: SimulatedDevice(apiVersion: 2));
        settle(async,
            h.container.read(connectionNotifierProvider.notifier).connect('x'));
        expect(h.container.read(connectionNotifierProvider),
            equals(ConnectionStatus.error));
        expect(h.container.read(connectionErrorProvider), contains('API v2'));
        expect(h.container.read(connectionErrorProvider), contains('API v3'));
      });
    });

    test('a later successful connect clears the error', () {
      fakeAsync((async) {
        final h = SimHarness();
        h.container.read(connectionErrorProvider.notifier).state = 'old';
        h.connect(async);
        expect(h.container.read(connectionErrorProvider), isNull);
      });
    });

    test('requests on a link that is not connected fail loudly', () {
      fakeAsync((async) {
        final mock = MockBleManager();
        addTearDown(mock.dispose);
        expect(
          () => settle(async, mock.request(opGet(ApiCat.system, SysRes.state))),
          throwsA(isA<Object>()),
        );
      });
    });
  });
}
