// Widget tests for InstrumentScreen — live displacement readings,
// real-measurement readouts, connection chip, and stale-data behaviour.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/instrument_screen.dart';

/// A fixed-status notifier for testing specific connection states.
class _FixedStatusNotifier extends ConnectionNotifier {
  _FixedStatusNotifier(this._status);
  final ConnectionStatus _status;

  @override
  ConnectionStatus build() => _status;
}

Widget buildInstrumentApp({
  required MockBleManager mock,
  ConnectionStatus initialStatus = ConnectionStatus.connected,
  Stream<DeviceState?>? dataStream,
}) {
  addTearDown(mock.dispose);
  final overrides = [
    bleManagerProvider.overrideWithValue(mock),
    connectionNotifierProvider.overrideWith(
      () => _FixedStatusNotifier(initialStatus),
    ),
    if (dataStream != null)
      instrumentDataProvider.overrideWith((ref) => dataStream),
  ];
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: InstrumentScreen()),
  );
}

Future<void> _setWideSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

DeviceState _state({
  double? displacementS1Mm = 1.234,
  double? displacementS2Mm = -0.567,
  bool displacementOk = true,
  bool quality1Ok = true,
  bool quality2Ok = true,
  int batteryPercent = 80,
  int batteryMillivolts = 4020,
  BatteryState batteryState = BatteryState.normal,
  double? onboardTempC = 24.80,
  double? externalTempC = -5.30,
  double? bme280TempC = 23.45,
  int? pressurePa = 96400,
  double? humidityPct = 41.0,
  bool bme280Fresh = true,
  bool charging = false,
}) {
  return DeviceState(
    displacementS1Mm: displacementS1Mm,
    displacementS2Mm: displacementS2Mm,
    displacementOk: displacementOk,
    quality1Ok: quality1Ok,
    quality2Ok: quality2Ok,
    batteryPercent: batteryPercent,
    batteryMillivolts: batteryMillivolts,
    batteryState: batteryState,
    onboardTempC: onboardTempC,
    externalTempC: externalTempC,
    bme280TempC: bme280TempC,
    pressurePa: pressurePa,
    humidityPct: humidityPct,
    bme280Fresh: bme280Fresh,
    charging: charging,
  );
}

Stream<DeviceState?> _single(DeviceState state) async* {
  yield state;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('renders real measurements from the device stream', (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: _single(_state()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('4.020 V'), findsOneWidget); // battery voltage
    expect(find.text('80 %'), findsOneWidget); // charge
    expect(find.text('+24.80 °C'), findsOneWidget); // on-board temp
    expect(find.text('−5.30 °C'), findsOneWidget); // external probe (U+2212)
    expect(find.text('41.0 %RH'), findsOneWidget); // humidity
    expect(find.text('964.0 hPa'), findsOneWidget); // 96400 Pa -> hPa
  });

  testWidgets('battery percentage shown in the AppBar', (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: _single(_state(batteryPercent: 75)),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('shows live S1/S2 displacement readings', (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: _single(_state()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('+1.234 mm'), findsOneWidget);
    expect(find.text('−0.567 mm'), findsOneWidget); // U+2212
    expect(
      find.text('Live readings not available — sensor not running'),
      findsNothing,
    );
  });

  testWidgets(
      'shows a placeholder and "not available" note when displacement is not ok',
      (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: _single(_state(displacementOk: false)),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('––.––– mm'), findsNWidgets(2));
    expect(
      find.text('Live readings not available — sensor not running'),
      findsOneWidget,
    );
  });

  testWidgets('Zero Calibration and Measure actions are enabled when connected',
      (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      initialStatus: ConnectionStatus.connected,
      dataStream: _single(_state()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    final zeroBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Zero Calibration'),
    );
    final measureBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Measure'),
    );
    expect(zeroBtn.onPressed, isNotNull);
    expect(measureBtn.onPressed, isNotNull);
  });

  testWidgets(
      'Zero Calibration and Measure actions are disabled when not connected',
      (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      initialStatus: ConnectionStatus.disconnected,
    ));
    await tester.pump();

    final zeroBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Zero Calibration'),
    );
    final measureBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Measure'),
    );
    expect(zeroBtn.onPressed, isNull);
    expect(measureBtn.onPressed, isNull);
  });

  testWidgets('missing optional fields render as an em dash', (tester) async {
    await _setWideSurface(tester);
    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: _single(_state(
        onboardTempC: null,
        externalTempC: null,
        humidityPct: null,
        pressurePa: null,
      )),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('—'), findsWidgets);
  });

  group('connection chip', () {
    testWidgets('shows Connected when connected', (tester) async {
      await _setWideSurface(tester);
      await tester.pumpWidget(buildInstrumentApp(
        mock: MockBleManager(),
        initialStatus: ConnectionStatus.connected,
      ));
      await tester.pump();
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('shows Disconnected when disconnected', (tester) async {
      await _setWideSurface(tester);
      await tester.pumpWidget(buildInstrumentApp(
        mock: MockBleManager(),
        initialStatus: ConnectionStatus.disconnected,
      ));
      await tester.pump();
      expect(find.text('Disconnected'), findsOneWidget);
    });
  });

  testWidgets('readouts fade and DISCONNECTED shows on a null stale event',
      (tester) async {
    await _setWideSurface(tester);
    final controller = StreamController<DeviceState?>();
    addTearDown(controller.close);

    await tester.pumpWidget(buildInstrumentApp(
      mock: MockBleManager(),
      dataStream: controller.stream,
    ));
    await tester.pump(const Duration(milliseconds: 50));

    controller.add(_state());
    await tester.pump(const Duration(milliseconds: 50));

    AnimatedOpacity ao =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(ao.opacity, closeTo(1.0, 0.01));
    expect(find.text('DISCONNECTED'), findsNothing);

    controller.add(null);
    await tester.pump(const Duration(milliseconds: 400));

    ao = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(ao.opacity, closeTo(0.40, 0.01));
    expect(find.text('DISCONNECTED'), findsOneWidget);
  });
}
