import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:inclinometer/ble/api_v3.dart';

void main() {
  group('crc16Ccitt', () {
    test('matches the CRC-16/CCITT-FALSE check value for "123456789"', () {
      expect(crc16Ccitt('123456789'.codeUnits), equals(0x29B1));
    });

    test('init value 0xFFFF for empty input', () {
      expect(crc16Ccitt(const []), equals(0xFFFF));
    });
  });

  group('opcodes', () {
    test('match the reference (docs/api-reference.md)', () {
      expect(opExecute(CmdRes.zeroCal), equals(0x2151));
      expect(opExecute(CmdRes.precision), equals(0x2152));
      expect(opExecute(CmdRes.tiltDemod), equals(0x2150));
      expect(opExecute(CmdRes.serviceEnd), equals(0x2162));
      expect(opGet(ApiCat.system, SysRes.identity), equals(0x0000));
      expect(opGet(ApiCat.system, SysRes.state), equals(0x0001));
      expect(opGet(ApiCat.system, SysRes.rtc), equals(0x0003));
      expect(opSet(ApiCat.system, SysRes.rtc), equals(0x1003));
      expect(opGet(ApiCat.topics, TopicRes.live), equals(0x0502));
      expect(opSubscribe(ApiCat.topics, TopicRes.live), equals(0x3502));
      expect(opSubscribe(ApiCat.topics, TopicRes.phasorStream),
          equals(0x3504));
      expect(opSubscribe(ApiCat.topics, TopicRes.signalDiag), equals(0x3505));
      expect(opSubscribe(ApiCat.procedures, ProcRes.zeroCal), equals(0x3900));
      expect(
          opSubscribe(ApiCat.procedures, ProcRes.precision), equals(0x3901));
    });

    test('withVerb swaps only the verb', () {
      expect(withVerb(0x3502, ApiVerb.unsubscribe), equals(0x4502));
    });

    test('field extractors invert opcode()', () {
      final op = opcode(ApiVerb.subscribe, ApiCat.procedures, 0x01);
      expect(opcodeVerb(op), equals(ApiVerb.subscribe));
      expect(opcodeCategory(op), equals(ApiCat.procedures));
      expect(opcodeResource(op), equals(0x01));
    });
  });

  group('buildPacket / ApiReassembler', () {
    test('round-trips a request through the reassembler', () {
      final pkt = buildPacket(opGet(ApiCat.system, SysRes.identity));
      expect(pkt.length, equals(6));
      final frames = ApiReassembler().addBytes(pkt);
      expect(frames, hasLength(1));
      expect(frames.single.opcode, equals(0x0000));
      expect(frames.single.crcOk, isTrue);
    });

    test('reassembles a frame split across notification chunks', () {
      final pkt = _response(0x0001, ApiStatus.ok, _bytes(15));
      final r = ApiReassembler();
      expect(r.addBytes(pkt.sublist(0, 3)), isEmpty);
      expect(r.addBytes(pkt.sublist(3, 12)), isEmpty);
      final frames = r.addBytes(pkt.sublist(12));
      expect(frames, hasLength(1));
      expect(frames.single.isOk, isTrue);
      expect(frames.single.data, hasLength(15));
    });

    test('emits several frames delivered in one chunk', () {
      final a = buildPacket(0x0000);
      final b = buildPacket(0x0001);
      final frames = ApiReassembler().addBytes([...a, ...b]);
      expect(frames.map((f) => f.opcode), equals([0x0000, 0x0001]));
    });

    test('drops a corrupted frame and counts it', () {
      final pkt = _response(0x0001, ApiStatus.ok, _bytes(15));
      pkt[pkt.length - 1] ^= 0xFF;
      final r = ApiReassembler();
      expect(r.addBytes(pkt), isEmpty);
      expect(r.crcErrors, greaterThan(0));
    });

    test('accepts the largest packet (122 B payload)', () {
      final pkt = buildPacket(0x0505, [0, ..._bytes(121)]);
      expect(pkt.length, equals(kApiMaxPacket));
      final f = ApiReassembler().addBytes(pkt).single;
      expect(f.crcOk, isTrue);
      expect(f.data, hasLength(121));
    });

    test('a declared length beyond the packet limit is dropped, not awaited',
        () {
      // Without the guard this header would make the reassembler wait for
      // 32 K bytes and swallow everything after it.
      final r = ApiReassembler();
      r.addBytes([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x00]);
      final frames = r.addBytes(buildPacket(0x0000));
      expect(frames.any((f) => f.opcode == 0x0000 && f.crcOk), isTrue);
      expect(r.desyncs, greaterThan(0));
    });

    test('junk before a packet does not cost the packet', () {
      final good = buildPacket(0x0000);
      for (final junk in [
        [0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0x7F],
        [0x12, 0x34, 0x02, 0x00, 0x99],
      ]) {
        final frames = ApiReassembler().addBytes([...junk, ...good]);
        expect(frames.map((f) => f.opcode), contains(0x0000),
            reason: 'junk $junk');
      }
    });

    test('a packet damaged in the middle does not swallow the next one', () {
      final bad = _response(0x0001, ApiStatus.ok, _bytes(15));
      bad[8] ^= 0x40;
      final good = _response(0x0502, ApiStatus.ok, _bytes(15));
      final frames = ApiReassembler().addBytes([...bad, ...good]);
      expect(frames.map((f) => f.opcode), equals([0x0502]));
    });
  });

  group('ApiFrame push handling', () {
    test('a SUBSCRIBE ack has no data and is not a push', () {
      final ack = ApiReassembler()
          .addBytes(_response(0x3502, ApiStatus.ok, const []))
          .single;
      expect(ack.looksLikePush, isFalse);
    });

    test('an error is not a push', () {
      final err = ApiReassembler()
          .addBytes(_response(0x3504, ApiStatus.busyExclusive, const []))
          .single;
      expect(err.looksLikePush, isFalse);
      expect(err.status, equals(ApiStatus.busyExclusive));
    });

    test('splits [issue_seq][page] off a push', () {
      final f = ApiReassembler()
          .addBytes(_response(0x3502, ApiStatus.ok, [42, 0, 1, 2, 3]))
          .single;
      expect(f.looksLikePush, isTrue);
      expect(f.issueSeq, equals(42));
      expect(f.pushData, equals([1, 2, 3]));
    });
  });

  group('status', () {
    test('SERVICE_MODE_REQUIRED is 0x0B', () {
      expect(ApiStatus.fromByte(0x0B), equals(ApiStatus.serviceModeRequired));
    });
    test('an unknown byte maps to unknown', () {
      expect(ApiStatus.fromByte(0x55), equals(ApiStatus.unknown));
    });
  });

  group('decoders', () {
    test('IDENTITY (50 bytes)', () {
      final b = Uint8List(50);
      final bd = ByteData.sublistView(b);
      b[0] = 0;
      b[1] = 11;
      b[2] = 1;
      b[3] = 3;
      bd.setUint16(4, 122, Endian.little);
      b.setRange(6, 6 + 16, 'InclinationMeter'.codeUnits);
      b.setRange(22, 30, '6DA08073'.codeUnits);
      b.setRange(30, 30 + 14, '1371e8b0-dirty'.codeUnits);
      final id = ApiIdentity.decode(b)!;
      expect(id.firmware, equals('0.11.1'));
      expect(id.apiVersion, equals(3));
      expect(id.maxPayload, equals(122));
      expect(id.product, equals('InclinationMeter'));
      expect(id.serial, equals('6DA08073'));
      expect(id.build, equals('1371e8b0-dirty'));
    });

    test('a v2 IDENTITY (27 bytes) does not decode', () {
      expect(ApiIdentity.decode(Uint8List(27)), isNull);
    });

    test('STATE / STATUS (15 bytes)', () {
      final b = Uint8List(15);
      final bd = ByteData.sublistView(b);
      b[0] = BatteryState.charging.value;
      b[1] = 64;
      bd.setUint16(2, 3987, Endian.little);
      b.setRange(4, 15, [1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 1]);
      final s = ApiSystemState.decode(b)!;
      expect(s.batteryState, equals(BatteryState.charging));
      expect(s.batterySocPct, equals(64));
      expect(s.batteryMv, equals(3987));
      expect(s.usbConnected, isTrue);
      expect(s.charging, isTrue);
      expect(s.forceCharging, isFalse);
      expect(s.chargeInhibited, isTrue);
      expect(s.demodRunning, isTrue);
      expect(s.phasorStreamActive, isFalse);
      expect(s.bulkActive, isFalse);
      expect(s.serviceMode, isTrue);
    });

    test('HEALTH (31 bytes)', () {
      final b = Uint8List(31);
      final bd = ByteData.sublistView(b);
      b.setRange(0, 5, [1, 1, 1, 1, 0]);
      b[5] = 1;
      b[6] = 1;
      b[8] = 0x0C; // software + IWDG
      b[9] = 1;
      bd.setUint32(10, 90061, Endian.little);
      bd.setUint16(14, 1, Endian.little);
      bd.setUint16(16, 2, Endian.little);
      bd.setUint16(18, 3, Endian.little);
      bd.setUint16(20, 4, Endian.little);
      b[22] = 1;
      bd.setUint32(23, 0x08001234, Endian.little);
      bd.setUint32(27, 0x08005678, Endian.little);
      final h = ApiHealth.decode(b)!;
      expect(h.bmeOk, isFalse);
      expect(h.settingsSaveFailed, isTrue);
      expect(h.uptimeS, equals(90061));
      expect(h.resetCauseNames, equals(['software', 'independent watchdog']));
      expect(h.bleTxDropped, equals(2));
      expect(h.rxMalformed, equals(4));
      expect(h.lastFaultKind, equals(1));
      expect(h.lastFaultPc, equals(0x08001234));
    });

    test('RTC (10 bytes) and the SET payload', () {
      final b = Uint8List(10);
      ByteData.sublistView(b).setUint16(0, 2026, Endian.little);
      b.setRange(2, 10, [10, 9, 5, 14, 30, 15, 1, 128]);
      final r = ApiRtc.decode(b)!;
      expect(r.dateTime, equals(DateTime(2026, 10, 9, 14, 30, 15)));
      expect(r.isSet, isTrue);
      expect(r.subsecond, equals(128));

      final set = ApiRtc.encodeSet(DateTime(2026, 10, 9, 14, 30, 15));
      expect(set, hasLength(7));
      expect(ByteData.sublistView(set).getUint16(0, Endian.little),
          equals(2026));
      expect(set.sublist(2), equals([10, 9, 14, 30, 15]));
    });

    test('ENV (14 bytes)', () {
      final b = Uint8List(14);
      final bd = ByteData.sublistView(b);
      bd.setInt16(0, 2345, Endian.little);
      bd.setUint32(2, 96400, Endian.little);
      bd.setUint16(6, 4120, Endian.little);
      b[8] = 1;
      bd.setInt16(9, 2480, Endian.little);
      bd.setInt16(11, -530, Endian.little);
      b[13] = 1;
      final e = ApiEnvironmental.decode(b)!;
      expect(e.bmeTempC, closeTo(23.45, 1e-9));
      expect(e.pressureHpa, closeTo(964.0, 1e-9));
      expect(e.humidityPct, closeTo(41.2, 1e-9));
      expect(e.onboardTempC, closeTo(24.8, 1e-9));
      expect(e.externalTempC, closeTo(-5.3, 1e-9));
      expect(e.externalTempOk, isTrue);
    });

    test('LIVE (15 bytes) and its flags', () {
      final b = Uint8List(15);
      final bd = ByteData.sublistView(b);
      bd.setUint16(0, 513, Endian.little);
      b[2] = 0x05; // valid + S2 doubtful
      bd.setFloat32(3, 0.1234, Endian.little);
      bd.setFloat32(7, -0.5, Endian.little);
      bd.setFloat32(11, 0.6234, Endian.little);
      final l = ApiLive.decode(b)!;
      expect(l.seq, equals(513));
      expect(l.valid, isTrue);
      expect(l.s1Doubtful, isFalse);
      expect(l.s2Doubtful, isTrue);
      expect(l.anyDoubtful, isTrue);
      expect(l.tiltS1, closeTo(0.1234, 1e-6));
      expect(l.tiltS2, closeTo(-0.5, 1e-6));
      expect(l.tiltDiff, closeTo(0.6234, 1e-6));
    });

    test('SIGNAL_DIAG (56 bytes), channel order S2, B, A, S1', () {
      final b = Uint8List(56);
      final bd = ByteData.sublistView(b);
      for (var i = 0; i < 4; i++) {
        bd.setFloat32(4 * i, 10.0 + i, Endian.little);
        bd.setFloat32(16 + 4 * i, 30.0 + i, Endian.little);
        bd.setFloat32(32 + 4 * i, 90.0 * i, Endian.little);
      }
      bd.setFloat32(48, 0.25, Endian.little);
      bd.setFloat32(52, -0.25, Endian.little);
      final d = ApiSignalDiag.decode(b)!;
      expect(ApiSignalDiag.channelNames, equals(['S2', 'B', 'A', 'S1']));
      expect(d.rmsMv, equals([10.0, 11.0, 12.0, 13.0]));
      expect(d.p2pMv, equals([30.0, 31.0, 32.0, 33.0]));
      expect(d.phaseDeg, equals([0.0, 90.0, 180.0, 270.0]));
      expect(d.theoreticalTiltS1, closeTo(0.25, 1e-6));
      expect(d.theoreticalTiltS2, closeTo(-0.25, 1e-6));
    });

    test('a PHASOR_STREAM entry round-trips (34 bytes)', () {
      const e = ApiPhasorEntry(
          iB: -1, qB: -2, iA: 1, qA: 2, iS1: 3, qS1: 4, iS2: 5, qS2: 6, seq: 640);
      final back = ApiPhasorEntry.decode(e.encode())!;
      expect(back.iB, equals(-1));
      expect(back.qS2, equals(6));
      expect(back.seq, equals(640));
    });

    test('Procedures ZERO_CAL (6 bytes)', () {
      final b = Uint8List(6);
      final bd = ByteData.sublistView(b);
      b[0] = ZeroCalPhase.step2Running.value;
      bd.setUint16(1, 17, Endian.little);
      bd.setUint16(3, 64, Endian.little);
      b[5] = 2;
      final z = ApiZeroCalStatus.decode(b)!;
      expect(z.phase, equals(ZeroCalPhase.step2Running));
      expect(z.progress, equals(17));
      expect(z.target, equals(64));
      expect(z.sensorMask, equals(2));
    });

    test('Procedures PRECISION (23 bytes)', () {
      final b = Uint8List(23);
      final bd = ByteData.sublistView(b);
      b[0] = PrecisionPhase.done.value;
      bd.setUint16(1, 81, Endian.little);
      bd.setUint16(3, 81, Endian.little);
      bd.setUint32(5, 2150, Endian.little);
      b[9] = 0;
      bd.setFloat32(10, 0.1, Endian.little);
      bd.setFloat32(14, 0.05, Endian.little);
      bd.setFloat32(18, 0.05, Endian.little);
      b[22] = 1;
      final p = ApiPrecisionStatus.decode(b)!;
      expect(p.phase, equals(PrecisionPhase.done));
      expect(p.target, equals(81));
      expect(p.count, equals(81));
      expect(p.elapsedMs, equals(2150));
      expect(p.failed, isFalse);
      expect(p.tiltS1, closeTo(0.1, 1e-6));
      expect(p.tiltDiff, closeTo(0.05, 1e-6));
      expect(p.disturbed, isTrue);
    });

    test('decoders return null on a short payload', () {
      expect(ApiIdentity.decode(Uint8List(49)), isNull);
      expect(ApiSystemState.decode(Uint8List(14)), isNull);
      expect(ApiHealth.decode(Uint8List(30)), isNull);
      expect(ApiRtc.decode(Uint8List(9)), isNull);
      expect(ApiEnvironmental.decode(Uint8List(13)), isNull);
      expect(ApiLive.decode(Uint8List(14)), isNull);
      expect(ApiSignalDiag.decode(Uint8List(55)), isNull);
      expect(ApiPhasorEntry.decode(Uint8List(33)), isNull);
      expect(ApiZeroCalStatus.decode(Uint8List(5)), isNull);
      expect(ApiPrecisionStatus.decode(Uint8List(22)), isNull);
    });
  });
}

Uint8List _response(int op, ApiStatus status, List<int> data) =>
    buildPacket(op, [status.value, ...data]);

List<int> _bytes(int n) => List<int>.generate(n, (i) => i & 0xFF);
