/// Device API v2 — wire framing, opcodes, status codes, and payload decoders.
///
/// This is the host-side counterpart to the firmware's `Services/svc_api.*`
/// and mirrors the reference client in
/// `InclinationMeterFirmware/PythonTestCode/apiv2.py`. It is pure Dart with
/// no BLE dependency so it can be unit-tested in isolation and reused across
/// transports.
///
/// Packet on the wire (little-endian throughout):
/// ```
/// [OPCODE 2B][LEN 2B][PAYLOAD 0..LEN][CRC16 2B]
/// ```
/// `LEN` is the payload byte count; total on the wire is always `6 + LEN`
/// (no padding). `CRC16` is CRC-16/CCITT-FALSE over `OPCODE + LEN + PAYLOAD`.
///
/// Every response echoes the request's opcode. The first payload byte of a
/// response is an [Api2Status]; resource data follows only when status is
/// [Api2Status.ok]. Subscription pushes arrive under the same opcode as the
/// SUBSCRIBE request, with payload `[status][issue_seq][page][data…]`.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Opcode structure: [VERB:4 (top nibble)][CATEGORY:4][RESOURCE:8]
// ---------------------------------------------------------------------------

/// API v2 verbs (top nibble of the opcode).
class Api2Verb {
  static const int get = 0x0;
  static const int set = 0x1;
  static const int execute = 0x2;
  static const int subscribe = 0x3;
  static const int unsubscribe = 0x4;
  static const int startBulk = 0x5;
  static const int cancelBulk = 0x6;
}

/// API v2 categories (middle nibble of the opcode).
class Api2Category {
  static const int systemStatus = 0x0;
  static const int commands = 0x1;
  static const int calibrations = 0x2;
  static const int settings = 0x3;
  static const int measurements = 0x4;
  static const int topicGroups = 0x5;
  static const int debugMessages = 0x6;
  static const int rawData = 0x7;
  static const int bulk = 0x8;
}

/// Builds a 16-bit opcode from verb, category and resource index.
int opcode(int verb, int category, int resource) =>
    ((verb & 0xF) << 12) | ((category & 0xF) << 8) | (resource & 0xFF);

int opcodeVerb(int op) => (op >> 12) & 0xF;
int opcodeCategory(int op) => (op >> 8) & 0xF;
int opcodeResource(int op) => op & 0xFF;

// ---------------------------------------------------------------------------
// Well-known resources / opcodes (subset this firmware build implements)
// ---------------------------------------------------------------------------

/// System status (0x0) resource indices.
class Api2SysRes {
  static const int identity = 0x00;
  static const int deviceState = 0x01;
  static const int rtc = 0x02;
}

/// Topic group (0x5) resource indices.
class Api2TopicRes {
  static const int environmental = 0x00; // 14-byte payload
  static const int deviceStatus = 0x01; // 18-byte payload
}

/// Measurement (0x4) resource indices.
class Api2MeasRes {
  static const int onboardTemp = 0x00; // i16 centi-°C
  static const int batteryMv = 0x01; // u16 mV
  static const int batterySoc = 0x02; // u8 %
  static const int bme280Temp = 0x03; // i16 centi-°C
  static const int bme280Pressure = 0x04; // u32 Pa
  static const int bme280Humidity = 0x05; // u16 centi-%RH
  static const int bme280Ok = 0x06; // u8 0/1
  static const int externalTemp = 0x07; // i16 centi-°C
  static const int externalTempOk = 0x08; // u8 0/1
}

/// Command (0x1) resource indices — EXECUTE only.
class Api2CmdRes {
  static const int testBeep = 0x00; // no payload
  static const int signalAnalysis = 0x01; // 1 byte: 0 stop / 1 start
  static const int forceCharge = 0x02; // no payload
}

int opGetIdentity() =>
    opcode(Api2Verb.get, Api2Category.systemStatus, Api2SysRes.identity);
int opGetDeviceState() =>
    opcode(Api2Verb.get, Api2Category.systemStatus, Api2SysRes.deviceState);

int opGetTopic(int res) => opcode(Api2Verb.get, Api2Category.topicGroups, res);
int opSubscribeTopic(int res) =>
    opcode(Api2Verb.subscribe, Api2Category.topicGroups, res);
int opUnsubscribeTopic(int res) =>
    opcode(Api2Verb.unsubscribe, Api2Category.topicGroups, res);

int opGetMeasurement(int res) =>
    opcode(Api2Verb.get, Api2Category.measurements, res);
int opSubscribeMeasurement(int res) =>
    opcode(Api2Verb.subscribe, Api2Category.measurements, res);

int opExecuteCommand(int res) =>
    opcode(Api2Verb.execute, Api2Category.commands, res);

// ---------------------------------------------------------------------------
// Status codes (first byte of every response payload)
// ---------------------------------------------------------------------------

enum Api2Status {
  ok(0x00),
  unknownCategory(0x01),
  verbNotValid(0x02),
  unknownResource(0x03),
  badCrc(0x04),
  badLength(0x05),
  busyResource(0x06),
  busyExclusive(0x07),
  invalidParameter(0x08),
  notSubscribed(0x09),
  nothingToCancel(0x0A),
  unknown(0xFF);

  const Api2Status(this.value);

  final int value;

  static Api2Status fromByte(int b) {
    for (final s in Api2Status.values) {
      if (s.value == b) return s;
    }
    return Api2Status.unknown;
  }
}

// ---------------------------------------------------------------------------
// CRC-16/CCITT-FALSE — poly 0x1021, init 0xFFFF, no reflection, no XOR-out
// ---------------------------------------------------------------------------

int crc16Ccitt(List<int> data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= (byte & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc & 0xFFFF;
}

// ---------------------------------------------------------------------------
// Packet framing
// ---------------------------------------------------------------------------

const int kApiHeaderBytes = 4; // opcode(2) + len(2)
const int kApiCrcBytes = 2;

/// Firmware's reassembly ceiling (`API2_PACKET_MAX_SIZE`). A declared length
/// implying a larger packet is treated as a desync and the reassembler
/// resyncs one byte at a time.
const int kApiMaxPacket = 128;

/// Encodes a request packet: `[opcode][len][payload][crc16]`, all LE.
Uint8List buildPacket(int op, [List<int> payload = const []]) {
  final len = payload.length;
  final body = Uint8List(kApiHeaderBytes + len);
  final bd = ByteData.sublistView(body);
  bd.setUint16(0, op, Endian.little);
  bd.setUint16(2, len, Endian.little);
  body.setRange(kApiHeaderBytes, kApiHeaderBytes + len, payload);

  final crc = crc16Ccitt(body);
  final out = Uint8List(body.length + kApiCrcBytes);
  out.setRange(0, body.length, body);
  ByteData.sublistView(out).setUint16(body.length, crc, Endian.little);
  return out;
}

/// A decoded API v2 frame.
///
/// [data] is the payload *after* the leading status byte (and, for
/// subscription pushes, after the `[issue_seq][page]` prefix — see
/// [issueSeq]/[page]). [crcOk] is false when the CRC did not verify; callers
/// discard such frames (host-side corruption is not retransmitted).
class Api2Frame {
  const Api2Frame({
    required this.opcode,
    required this.status,
    required this.data,
    required this.crcOk,
    this.issueSeq,
    this.page,
  });

  final int opcode;
  final Api2Status status;
  final Uint8List data;
  final bool crcOk;

  /// Present only when [asPush] parsed a subscription push prefix.
  final int? issueSeq;
  final int? page;

  int get verb => opcodeVerb(opcode);
  int get category => opcodeCategory(opcode);
  int get resource => opcodeResource(opcode);

  bool get isOk => crcOk && status == Api2Status.ok;

  /// Reinterprets this frame as a subscription push, splitting the leading
  /// `[issue_seq][page]` bytes off [data]. Returns `this` unchanged if the
  /// payload is too short to carry the prefix.
  Api2Frame asPush() {
    if (data.length < 2) return this;
    return Api2Frame(
      opcode: opcode,
      status: status,
      data: Uint8List.sublistView(data, 2),
      crcOk: crcOk,
      issueSeq: data[0],
      page: data[1],
    );
  }

  @override
  String toString() =>
      'Api2Frame(op=0x${opcode.toRadixString(16).padLeft(4, '0')}, '
      'status=$status, crcOk=$crcOk, ${data.length}B)';
}

/// Rebuilds [Api2Frame]s from a raw byte stream (BLE Transparent UART).
///
/// Feed inbound notification chunks with [addBytes]; it returns zero or more
/// complete frames. A frame whose CRC fails is still returned, with
/// [Api2Frame.crcOk] == false, so the caller can count/log it. A declared
/// length that exceeds [kApiMaxPacket] is treated as a desync: one byte is
/// dropped and reassembly retried.
class Api2Reassembler {
  final List<int> _buf = [];

  void reset() => _buf.clear();

  List<Api2Frame> addBytes(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <Api2Frame>[];

    while (_buf.length >= kApiHeaderBytes) {
      final payLen = _buf[2] | (_buf[3] << 8);
      final total = kApiHeaderBytes + payLen + kApiCrcBytes;

      if (total > kApiMaxPacket) {
        _buf.removeAt(0); // desync — resync one byte at a time
        continue;
      }
      if (_buf.length < total) break; // wait for the rest

      final packet = Uint8List.fromList(_buf.sublist(0, total));
      _buf.removeRange(0, total);
      frames.add(_parse(packet));
    }
    return frames;
  }

  static Api2Frame _parse(Uint8List packet) {
    final bd = ByteData.sublistView(packet);
    final op = bd.getUint16(0, Endian.little);
    final payLen = bd.getUint16(2, Endian.little);
    final body = Uint8List.sublistView(packet, 0, kApiHeaderBytes + payLen);
    final gotCrc = bd.getUint16(kApiHeaderBytes + payLen, Endian.little);
    final crcOk = crc16Ccitt(body) == gotCrc;

    final payload =
        Uint8List.sublistView(packet, kApiHeaderBytes, kApiHeaderBytes + payLen);
    if (payload.isEmpty) {
      return Api2Frame(
        opcode: op,
        status: Api2Status.unknown,
        data: Uint8List(0),
        crcOk: crcOk,
      );
    }
    return Api2Frame(
      opcode: op,
      status: Api2Status.fromByte(payload[0]),
      data: Uint8List.sublistView(payload, 1),
      crcOk: crcOk,
    );
  }
}

// ---------------------------------------------------------------------------
// Payload decoders
// ---------------------------------------------------------------------------

/// Firmware identity (`GET 0x0/0x00`, 27-byte payload).
class Api2Identity {
  const Api2Identity({
    required this.fwMajor,
    required this.fwMinor,
    required this.fwPatch,
    required this.product,
    required this.serial,
  });

  final int fwMajor;
  final int fwMinor;
  final int fwPatch;
  final String product;
  final String serial;

  String get version => '$fwMajor.$fwMinor.$fwPatch';

  static Api2Identity? decode(Uint8List d) {
    if (d.length < 27) return null;
    String cstr(int start, int end) {
      final bytes = d.sublist(start, end);
      final nul = bytes.indexOf(0);
      return String.fromCharCodes(nul >= 0 ? bytes.sublist(0, nul) : bytes);
    }

    return Api2Identity(
      fwMajor: d[0],
      fwMinor: d[1],
      fwPatch: d[2],
      product: cstr(3, 19),
      serial: cstr(19, 27),
    );
  }
}

/// Battery charge state (firmware `battery_state_t`).
enum BatteryState {
  normal(0),
  low(1),
  critical(2),
  charging(3),
  full(4),
  unknown(0xFF);

  const BatteryState(this.value);

  final int value;

  static BatteryState fromByte(int b) {
    for (final s in BatteryState.values) {
      if (s.value == b) return s;
    }
    return BatteryState.unknown;
  }
}

/// Decoded `Topic groups / Environmental` payload (`0x5/0x00`, 14 bytes).
class Api2Environmental {
  const Api2Environmental({
    required this.bme280TempC,
    required this.pressurePa,
    required this.humidityPct,
    required this.bme280Ok,
    required this.onboardTempC,
    required this.externalTempC,
    required this.externalTempOk,
  });

  final double bme280TempC;
  final int pressurePa;
  final double humidityPct;
  final bool bme280Ok;
  final double onboardTempC;
  final double externalTempC;
  final bool externalTempOk;

  static Api2Environmental? decode(Uint8List d) {
    if (d.length < 14) return null;
    final bd = ByteData.sublistView(d);
    return Api2Environmental(
      bme280TempC: bd.getInt16(0, Endian.little) / 100.0,
      pressurePa: bd.getUint32(2, Endian.little),
      humidityPct: bd.getUint16(6, Endian.little) / 100.0,
      bme280Ok: d[8] != 0,
      onboardTempC: bd.getInt16(9, Endian.little) / 100.0,
      externalTempC: bd.getInt16(11, Endian.little) / 100.0,
      externalTempOk: d[13] != 0,
    );
  }
}

/// Decoded `Topic groups / Device status` payload (`0x5/0x01`, 18 bytes).
class Api2DeviceStatus {
  const Api2DeviceStatus({
    required this.batteryMv,
    required this.batterySocPct,
    required this.batteryState,
    required this.usbConnected,
    required this.bleConnected,
    required this.charging,
    required this.forceCharging,
    required this.rail3v3On,
    required this.rail5vOn,
    required this.rtcYear,
    required this.rtcMonth,
    required this.rtcDay,
    required this.rtcHour,
    required this.rtcMinute,
    required this.rtcSecond,
    required this.rtcSet,
  });

  final int batteryMv;
  final int batterySocPct;
  final BatteryState batteryState;
  final bool usbConnected;
  final bool bleConnected;
  final bool charging;
  final bool forceCharging;
  final bool rail3v3On;
  final bool rail5vOn;
  final int rtcYear;
  final int rtcMonth;
  final int rtcDay;
  final int rtcHour;
  final int rtcMinute;
  final int rtcSecond;
  final bool rtcSet;

  static Api2DeviceStatus? decode(Uint8List d) {
    if (d.length < 18) return null;
    final bd = ByteData.sublistView(d);
    return Api2DeviceStatus(
      batteryMv: bd.getUint16(0, Endian.little),
      batterySocPct: d[2],
      batteryState: BatteryState.fromByte(d[3]),
      usbConnected: d[4] != 0,
      bleConnected: d[5] != 0,
      charging: d[6] != 0,
      forceCharging: d[7] != 0,
      rail3v3On: d[8] != 0,
      rail5vOn: d[9] != 0,
      rtcYear: bd.getUint16(10, Endian.little),
      rtcMonth: d[12],
      rtcDay: d[13],
      rtcHour: d[14],
      rtcMinute: d[15],
      rtcSecond: d[16],
      rtcSet: d[17] != 0,
    );
  }
}
