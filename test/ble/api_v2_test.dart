import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:inclinometer/ble/api_v2.dart';

void main() {
  group('crc16Ccitt', () {
    test('matches the CRC-16/CCITT-FALSE check value for "123456789"', () {
      expect(crc16Ccitt('123456789'.codeUnits), equals(0x29B1));
    });

    test('init value 0xFFFF for empty input', () {
      expect(crc16Ccitt(const []), equals(0xFFFF));
    });
  });

  group('opcode helpers', () {
    test('packs verb/category/resource the same way the firmware macro does',
        () {
      // SUBSCRIBE (0x3) + Topic groups (0x5) + resource 0x00 -> 0x3500
      expect(opSubscribeTopic(Api2TopicRes.environmental), equals(0x3500));
      // GET (0x0) + System status (0x0) + Device state (0x01) -> 0x0001
      expect(opGetDeviceState(), equals(0x0001));
      // EXECUTE (0x2) + Commands (0x1) + Test beep (0x00) -> 0x2100
      expect(opExecuteCommand(Api2CmdRes.testBeep), equals(0x2100));
    });

    test('field extractors invert opcode()', () {
      final op = opcode(Api2Verb.subscribe, Api2Category.measurements, 0x07);
      expect(opcodeVerb(op), equals(Api2Verb.subscribe));
      expect(opcodeCategory(op), equals(Api2Category.measurements));
      expect(opcodeResource(op), equals(0x07));
    });
  });

  group('buildPacket / Api2Reassembler', () {
    test('round-trips a request packet through the reassembler', () {
      final pkt = buildPacket(opGetIdentity());
      // [OPCODE 2][LEN 2][CRC 2] = 6 bytes, no payload.
      expect(pkt.length, equals(6));

      final frames = Api2Reassembler().addBytes(pkt);
      expect(frames, hasLength(1));
      expect(frames.single.opcode, equals(opGetIdentity()));
      expect(frames.single.crcOk, isTrue);
    });

    test('reassembles a frame split across two notification chunks', () {
      final pkt = _response(opGetDeviceState(), Api2Status.ok, _bytes(7));
      final r = Api2Reassembler();
      expect(r.addBytes(pkt.sublist(0, 3)), isEmpty);
      final frames = r.addBytes(pkt.sublist(3));
      expect(frames, hasLength(1));
      expect(frames.single.isOk, isTrue);
      expect(frames.single.data, hasLength(7));
    });

    test('emits multiple frames delivered in one chunk', () {
      final a = buildPacket(opGetIdentity());
      final b = buildPacket(opGetDeviceState());
      final frames = Api2Reassembler().addBytes([...a, ...b]);
      expect(frames.map((f) => f.opcode),
          containsAllInOrder([opGetIdentity(), opGetDeviceState()]));
    });

    test('flags a corrupted frame with crcOk == false', () {
      final pkt = _response(opGetDeviceState(), Api2Status.ok, _bytes(7));
      pkt[pkt.length - 1] ^= 0xFF; // trash the CRC
      final frames = Api2Reassembler().addBytes(pkt);
      expect(frames.single.crcOk, isFalse);
    });

    test('recovers a good packet that follows a run of junk bytes', () {
      // Six leading zero bytes parse as one bad-CRC frame, then the real one.
      final good = buildPacket(opGetIdentity());
      final frames =
          Api2Reassembler().addBytes([0, 0, 0, 0, 0, 0, ...good]);
      expect(frames.last.opcode, equals(opGetIdentity()));
      expect(frames.last.crcOk, isTrue);
      expect(frames.any((f) => !f.crcOk), isTrue);
    });
  });

  group('Api2Frame.asPush', () {
    test('splits the [issue_seq][page] prefix off the payload', () {
      final push = _response(
        opSubscribeTopic(Api2TopicRes.environmental),
        Api2Status.ok,
        [0x2A, 0x00, ..._bytes(14)], // issue=42, page=0, then 14 data bytes
      );
      final frame = Api2Reassembler().addBytes(push).single.asPush();
      expect(frame.issueSeq, equals(0x2A));
      expect(frame.page, equals(0));
      expect(frame.data, hasLength(14));
    });
  });

  group('payload decoders', () {
    test('decodes an Environmental topic-group payload', () {
      final d = ByteData(14)
        ..setInt16(0, 2345, Endian.little) // bme temp 23.45 C
        ..setUint32(2, 96400, Endian.little) // 96400 Pa
        ..setUint16(6, 4120, Endian.little) // 41.20 %RH
        ..setUint8(8, 1) // bme ok
        ..setInt16(9, 2480, Endian.little) // onboard 24.80 C
        ..setInt16(11, -530, Endian.little) // external -5.30 C
        ..setUint8(13, 1); // external ok
      final env = Api2Environmental.decode(d.buffer.asUint8List())!;
      expect(env.bme280TempC, closeTo(23.45, 1e-9));
      expect(env.pressurePa, equals(96400));
      expect(env.humidityPct, closeTo(41.20, 1e-9));
      expect(env.bme280Ok, isTrue);
      expect(env.onboardTempC, closeTo(24.80, 1e-9));
      expect(env.externalTempC, closeTo(-5.30, 1e-9));
      expect(env.externalTempOk, isTrue);
    });

    test('decodes a Device status topic-group payload', () {
      final d = ByteData(18)
        ..setUint16(0, 3987, Endian.little) // 3987 mV
        ..setUint8(2, 64) // 64 %
        ..setUint8(3, BatteryState.charging.value)
        ..setUint8(4, 1) // usb
        ..setUint8(5, 1) // ble
        ..setUint8(6, 1) // charging
        ..setUint8(7, 0)
        ..setUint8(8, 1)
        ..setUint8(9, 1)
        ..setUint16(10, 2026, Endian.little)
        ..setUint8(12, 9)
        ..setUint8(13, 8)
        ..setUint8(14, 14)
        ..setUint8(15, 30)
        ..setUint8(16, 0)
        ..setUint8(17, 1);
      final st = Api2DeviceStatus.decode(d.buffer.asUint8List())!;
      expect(st.batteryMv, equals(3987));
      expect(st.batterySocPct, equals(64));
      expect(st.batteryState, equals(BatteryState.charging));
      expect(st.usbConnected, isTrue);
      expect(st.charging, isTrue);
      expect(st.rtcYear, equals(2026));
      expect(st.rtcSet, isTrue);
    });

    test('decoders return null on a short payload', () {
      expect(Api2Environmental.decode(Uint8List(13)), isNull);
      expect(Api2DeviceStatus.decode(Uint8List(17)), isNull);
      expect(Api2Identity.decode(Uint8List(26)), isNull);
    });

    test('decodes a 27-byte Identity payload', () {
      final b = Uint8List(27);
      b[0] = 1;
      b[1] = 2;
      b[2] = 3;
      b.setRange(3, 3 + 'Leveltronic'.length, 'Leveltronic'.codeUnits);
      b.setRange(19, 19 + 'ABC123'.length, 'ABC123'.codeUnits);
      final id = Api2Identity.decode(b)!;
      expect(id.version, equals('1.2.3'));
      expect(id.product, equals('Leveltronic'));
      expect(id.serial, equals('ABC123'));
    });
  });
}

/// Builds a device→host response packet: `[opcode][len][status][data][crc]`.
Uint8List _response(int op, Api2Status status, List<int> data) =>
    buildPacket(op, [status.value, ...data]);

List<int> _bytes(int n) => List<int>.generate(n, (i) => i & 0xFF);
