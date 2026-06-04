import 'package:test/test.dart';

import 'package:inclinometer/ble/ble_protocol.dart';

void main() {
  group('StatePacket', () {
    test('encode then parse round-trips float values', () {
      const ax = 12.345;
      const ay = -0.678;
      const battery = 72;

      final bytes = StatePacket.encode(ax, ay, battery);
      final state = StatePacket.parse(bytes);

      // float64 → float32 → float64 is lossy; use closeTo, NOT equals.
      expect(state.angleX, closeTo(ax, 1e-4));
      expect(state.angleY, closeTo(ay, 1e-4));
      expect(state.battery, equals(battery));
    });

    test('parse asserts on wrong packet length', () {
      expect(
        () => StatePacket.parse([0, 1, 2]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('encode produces exactly 9 bytes', () {
      final bytes = StatePacket.encode(0.0, 0.0, 100);
      expect(bytes.length, equals(9));
    });

    test('command constants have correct values', () {
      expect(kCmdZeroX, equals(0x01));
      expect(kCmdZeroY, equals(0x02));
    });

    test('UUID constants are non-empty strings', () {
      expect(kServiceUuid.isNotEmpty, isTrue);
      expect(kStateCharUuid.isNotEmpty, isTrue);
      expect(kCommandCharUuid.isNotEmpty, isTrue);
    });
  });
}
