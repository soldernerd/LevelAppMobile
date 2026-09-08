import 'package:test/test.dart';

import 'package:inclinometer/ble/ble_protocol.dart';

void main() {
  group('GATT constants', () {
    test('Transparent UART service/characteristic UUIDs are the RN4871 values',
        () {
      expect(kServiceUuid, equals('49535343-fe7d-4ae5-8fa9-9fafd205e455'));
      expect(kRxCharUuid, equals('49535343-8841-43f4-a8d4-ecbe34729bb3'));
      expect(kTxCharUuid, equals('49535343-1e4d-4bd9-ba61-23c647249616'));
    });

    test('device name prefix matches the firmware BLE_DEVICE_NAME', () {
      expect(kDeviceNamePrefix, equals('Leveltronic'));
    });

    test('subscription interval respects the 50 ms firmware floor', () {
      expect(kSubscriptionInterval.inMilliseconds, greaterThanOrEqualTo(50));
    });
  });
}
