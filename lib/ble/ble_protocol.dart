import 'dart:typed_data';

import 'package:inclinometer/models/device_state.dart';

// GATT service and characteristic UUIDs (placeholder values for WP1).
const String kServiceUuid = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid = '0000ZZZZ-0000-1000-8000-00805f9b34fb';

// Command byte constants sent to the instrument.
const int kCmdZeroX = 0x01;
const int kCmdZeroY = 0x02;

/// Parses and encodes the 9-byte state packet:
///   bytes 0–3  angleX   float32 LE
///   bytes 4–7  angleY   float32 LE
///   byte  8    battery  uint8
class StatePacket {
  /// Parses a raw 9-byte BLE characteristic value into a [DeviceState].
  ///
  /// Throws [ArgumentError] if [bytes] is not exactly 9 bytes, or if the
  /// battery byte exceeds 100 (valid range is 0–100 percent).
  /// Unlike `assert`, these guards fire in both debug and release builds.
  static DeviceState parse(List<int> bytes) {
    if (bytes.length != 9) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'State packet must be exactly 9 bytes',
      );
    }
    final rawBattery = bytes[8];
    if (rawBattery > 100) {
      throw ArgumentError.value(
        rawBattery,
        'battery',
        'Battery must be 0–100 (got $rawBattery — firmware protocol error?)',
      );
    }
    // ByteData.sublistView requires TypedData — Uint8List.fromList() is mandatory.
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return DeviceState(
      angleX: bd.getFloat32(0, Endian.little),
      angleY: bd.getFloat32(4, Endian.little),
      battery: rawBattery,
    );
  }

  /// Encodes angle and battery values into a 9-byte packet.
  static List<int> encode(double ax, double ay, int battery) {
    final bd = ByteData(9);
    bd.setFloat32(0, ax, Endian.little);
    bd.setFloat32(4, ay, Endian.little);
    bd.setUint8(8, battery);
    return bd.buffer.asUint8List().toList();
  }
}
