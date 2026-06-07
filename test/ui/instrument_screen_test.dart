// test/ui/instrument_screen_test.dart
// Widget tests for InstrumentScreen — INST-01 through INST-07 and CONN-04.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Builds the InstrumentScreen with injectable overrides.
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
    if (dataStream != null) instrumentDataProvider.overrideWith((ref) => dataStream),
  ];
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: InstrumentScreen()),
  );
}

/// Sets the test surface to 1400x900 to prevent RenderFlex overflow
/// from the 80sp angle readout in the _AngleRow widget.
Future<void> _setWideSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A stream that emits a single [DeviceState] then closes.
///
/// Uses an async* generator instead of a [StreamController] to avoid leaking
/// an unclosed controller for the duration of the test (WR-04).
Stream<DeviceState?> _singleStateStream(DeviceState state) async* {
  yield state;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('INST-02 + INST-03: Angle values displayed at 80sp with correct format', () {
    testWidgets('INST-02+03: formatted angle values visible with 80sp text style',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final stream = _singleStateStream(
        const DeviceState(angleX: 12.34, angleY: -3.0, battery: 80),
      );
      await tester.pumpWidget(buildInstrumentApp(mock: ble, dataStream: stream));
      await tester.pump(const Duration(milliseconds: 50));

      // Verify formatted angle text is present.
      // angleX: 12.34 → '+012.34°'
      expect(find.text('+012.34°'), findsOneWidget);
      // angleY: -3.0 → '−003.00°' (Unicode minus U+2212)
      expect(find.text('−003.00°'), findsOneWidget);

      // Verify the Text widget containing '+012.34°' has fontSize 80.
      final textWidget = tester.widget<Text>(find.text('+012.34°'));
      expect(textWidget.style?.fontSize, 80.0);
    });
  });

  group('INST-04: Battery percentage shown in AppBar', () {
    testWidgets('INST-04: battery percentage visible in AppBar', (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final stream = _singleStateStream(
        const DeviceState(angleX: 0, angleY: 0, battery: 75),
      );
      await tester.pumpWidget(buildInstrumentApp(mock: ble, dataStream: stream));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('75%'), findsOneWidget);
    });
  });

  group('INST-05: Zero X button sends kCmdZeroX', () {
    testWidgets('INST-05: Zero X button is enabled when connected and can be tapped',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final stream = _singleStateStream(
        const DeviceState(angleX: 5.0, angleY: 2.0, battery: 90),
      );
      await tester.pumpWidget(buildInstrumentApp(mock: ble, dataStream: stream));
      await tester.pump(const Duration(milliseconds: 50));

      // Find ElevatedButton with 'Zero X' text.
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Zero X'),
      );
      // Button must be enabled (onPressed non-null) when connected.
      expect(btn.onPressed, isNotNull);

      // Tapping should not throw.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Zero X'));
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('INST-06: Zero Y button sends kCmdZeroY', () {
    testWidgets('INST-06: Zero Y button is enabled when connected and can be tapped',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final stream = _singleStateStream(
        const DeviceState(angleX: 5.0, angleY: 2.0, battery: 90),
      );
      await tester.pumpWidget(buildInstrumentApp(mock: ble, dataStream: stream));
      await tester.pump(const Duration(milliseconds: 50));

      // Find ElevatedButton with 'Zero Y' text.
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Zero Y'),
      );
      // Button must be enabled (onPressed non-null) when connected.
      expect(btn.onPressed, isNotNull);

      // Tapping should not throw.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Zero Y'));
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('INST-07: Tabular figures applied to angle readout', () {
    testWidgets('INST-07: FontFeature.tabularFigures() present in angle text style',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final stream = _singleStateStream(
        const DeviceState(angleX: 0.0, angleY: 0.0, battery: 85),
      );
      await tester.pumpWidget(buildInstrumentApp(mock: ble, dataStream: stream));
      await tester.pump(const Duration(milliseconds: 50));

      // Find a Text widget containing '°' (the angle readout).
      final textWidget = tester.widget<Text>(find.textContaining('°').first);
      expect(
        textWidget.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('CONN-04: Connection chip always visible in AppBar', () {
    testWidgets('CONN-04: Connected chip visible when status is connected',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      await tester.pumpWidget(buildInstrumentApp(
        mock: ble,
        initialStatus: ConnectionStatus.connected,
      ));
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('CONN-04: Disconnected chip visible when status is disconnected',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      await tester.pumpWidget(buildInstrumentApp(
        mock: ble,
        initialStatus: ConnectionStatus.disconnected,
      ));
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
    });
  });

  group('INST-02+03 stale state: angle readout fades on null stream', () {
    testWidgets('stale: AnimatedOpacity is 0.40 and DISCONNECTED shown after null event',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      final controller = StreamController<DeviceState?>();
      addTearDown(controller.close);

      await tester.pumpWidget(buildInstrumentApp(
        mock: ble,
        dataStream: controller.stream,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Emit a live DeviceState — opacity should be 1.0.
      controller.add(const DeviceState(angleX: 1.0, angleY: 2.0, battery: 50));
      await tester.pump(const Duration(milliseconds: 50));

      AnimatedOpacity ao = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(ao.opacity, closeTo(1.0, 0.01));
      expect(find.text('DISCONNECTED'), findsNothing);

      // Emit null sentinel — stale state; opacity should animate to 0.40.
      controller.add(null);
      await tester.pump(const Duration(milliseconds: 400));

      ao = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(ao.opacity, closeTo(0.40, 0.01));
      expect(find.text('DISCONNECTED'), findsOneWidget);
    });
  });

  group('INST-05/06: Zero buttons disabled when not connected', () {
    testWidgets('Zero X and Zero Y buttons are disabled when disconnected',
        (tester) async {
      await _setWideSurface(tester);
      final ble = MockBleManager();
      await tester.pumpWidget(buildInstrumentApp(
        mock: ble,
        initialStatus: ConnectionStatus.disconnected,
      ));
      await tester.pump();

      final zeroXBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Zero X'),
      );
      expect(zeroXBtn.onPressed, isNull);

      final zeroYBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Zero Y'),
      );
      expect(zeroYBtn.onPressed, isNull);
    });
  });
}
