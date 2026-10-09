/// Device API v3 — wire framing, opcodes, status codes and payload codecs.
///
/// Host-side counterpart of the firmware's `Services/svc_api*`; the resource
/// list is `docs/api-reference.md` in the InclinationMeterFirmware repo
/// (generated from its `tools/api_spec.py`), the protocol is
/// `docs/api-v3-spec.md`. Pure Dart, no BLE dependency, so it is unit-tested
/// in isolation.
///
/// ```
/// [OPCODE 2B][LEN 2B][PAYLOAD 0..LEN][CRC16 2B]      (little-endian)
/// ```
/// `CRC16` is CRC-16/CCITT-FALSE over opcode, length and payload. Every
/// response echoes the request opcode and starts its payload with an
/// [ApiStatus] byte; data follows only for [ApiStatus.ok]. Subscription pushes
/// arrive under the SUBSCRIBE opcode as `[OK][issue_seq][page][data…]`.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Opcode structure: [VERB:4][CATEGORY:4][RESOURCE:8]
// ---------------------------------------------------------------------------

/// The protocol version this app speaks. System IDENTITY reports it.
const int kApiVersion = 3;

class ApiVerb {
  static const int get = 0x0;
  static const int set = 0x1;
  static const int execute = 0x2;
  static const int subscribe = 0x3;
  static const int unsubscribe = 0x4;
  static const int startBulk = 0x5;
  static const int cancelBulk = 0x6;
}

class ApiCat {
  static const int system = 0x0;
  static const int commands = 0x1;
  static const int calibrations = 0x2;
  static const int settings = 0x3;
  static const int measurements = 0x4;
  static const int topics = 0x5;
  static const int debugLog = 0x6;
  static const int diagnostics = 0x7;
  static const int bulk = 0x8;
  static const int procedures = 0x9;
}

int opcode(int verb, int category, int resource) =>
    ((verb & 0xF) << 12) | ((category & 0xF) << 8) | (resource & 0xFF);
int opcodeVerb(int op) => (op >> 12) & 0xF;
int opcodeCategory(int op) => (op >> 8) & 0xF;
int opcodeResource(int op) => op & 0xFF;

/// Opcode with the verb replaced — e.g. the UNSUBSCRIBE opcode for a
/// SUBSCRIBE opcode.
int withVerb(int op, int verb) => (op & 0x0FFF) | ((verb & 0xF) << 12);

class SysRes {
  static const int identity = 0x00;
  static const int state = 0x01;
  static const int health = 0x02;
  static const int rtc = 0x03;
}

class CmdRes {
  static const int powerOff = 0x40;
  static const int reboot = 0x41;
  static const int rebootDfu = 0x42; // service mode
  static const int forceCharge = 0x43;
  static const int endCharging = 0x44;
  static const int chargeInhibit = 0x45;
  static const int tiltDemod = 0x50;
  static const int zeroCal = 0x51; // service mode
  static const int precision = 0x52;
  static const int factoryDefaults = 0x60; // service mode
  static const int clearCounters = 0x61;
  static const int serviceEnd = 0x62;
  static const int testBeep = 0x70;
}

class TopicRes {
  static const int env = 0x00;
  static const int status = 0x01;
  static const int live = 0x02;
  static const int raw = 0x03;
  static const int phasorStream = 0x04;
  static const int signalDiag = 0x05;
}

class ProcRes {
  static const int zeroCal = 0x00;
  static const int precision = 0x01;
}

int opGet(int category, int res) => opcode(ApiVerb.get, category, res);
int opSet(int category, int res) => opcode(ApiVerb.set, category, res);
int opExecute(int res) => opcode(ApiVerb.execute, ApiCat.commands, res);
int opSubscribe(int category, int res) =>
    opcode(ApiVerb.subscribe, category, res);

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------

enum ApiStatus {
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
  serviceModeRequired(0x0B),
  unknown(0xFF);

  const ApiStatus(this.value);
  final int value;

  static ApiStatus fromByte(int b) {
    for (final s in ApiStatus.values) {
      if (s.value == b) return s;
    }
    return ApiStatus.unknown;
  }
}

// ---------------------------------------------------------------------------
// CRC-16/CCITT-FALSE
// ---------------------------------------------------------------------------

int crc16Ccitt(List<int> data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= (byte & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc & 0xFFFF;
}

// ---------------------------------------------------------------------------
// Packet framing
// ---------------------------------------------------------------------------

const int kApiHeaderBytes = 4;
const int kApiCrcBytes = 2;

/// Largest payload any packet may carry (System IDENTITY `max_payload`).
const int kApiMaxPayload = 122;

/// Largest packet on the wire.
const int kApiMaxPacket = kApiHeaderBytes + kApiMaxPayload + kApiCrcBytes;

Uint8List buildPacket(int op, [List<int> payload = const []]) {
  final len = payload.length;
  final body = Uint8List(kApiHeaderBytes + len);
  final bd = ByteData.sublistView(body);
  bd.setUint16(0, op, Endian.little);
  bd.setUint16(2, len, Endian.little);
  body.setRange(kApiHeaderBytes, kApiHeaderBytes + len, payload);

  final out = Uint8List(body.length + kApiCrcBytes);
  out.setRange(0, body.length, body);
  ByteData.sublistView(out)
      .setUint16(body.length, crc16Ccitt(body), Endian.little);
  return out;
}

/// A decoded frame. [data] is the payload after the status byte.
class ApiFrame {
  const ApiFrame({
    required this.opcode,
    required this.status,
    required this.data,
    required this.crcOk,
  });

  final int opcode;
  final ApiStatus status;
  final Uint8List data;
  final bool crcOk;

  bool get isOk => crcOk && status == ApiStatus.ok;

  /// A frame that starts with `[issue_seq][page]` is a subscription push; a
  /// SUBSCRIBE ack (or an error) carries no data after the status byte.
  bool get looksLikePush => status == ApiStatus.ok && data.length >= 2;

  /// The push data after `[issue_seq][page]`.
  Uint8List get pushData =>
      data.length >= 2 ? Uint8List.sublistView(data, 2) : Uint8List(0);

  int? get issueSeq => data.length >= 2 ? data[0] : null;

  @override
  String toString() =>
      'ApiFrame(op=0x${opcode.toRadixString(16).padLeft(4, '0')}, '
      '$status, crcOk=$crcOk, ${data.length}B)';
}

/// Rebuilds [ApiFrame]s from a byte stream (BLE, UART).
///
/// Resynchronisation: a declared length beyond [kApiMaxPacket], or a
/// candidate packet whose CRC fails, means the stream is out of step (a lost
/// notification, a bit error) — one byte is dropped and parsing retried, so a
/// valid packet lying behind the damage is still found. Such discards are
/// counted in [crcErrors] / [desyncs]; only frames that pass their CRC are
/// returned.
class ApiReassembler {
  final List<int> _buf = [];

  /// Candidate packets rejected by their CRC.
  int crcErrors = 0;

  /// Headers that declared an impossible length.
  int desyncs = 0;

  void reset() => _buf.clear();

  List<ApiFrame> addBytes(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <ApiFrame>[];
    while (_buf.length >= kApiHeaderBytes) {
      final payLen = _buf[2] | (_buf[3] << 8);
      final total = kApiHeaderBytes + payLen + kApiCrcBytes;
      if (total > kApiMaxPacket) {
        desyncs++;
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      final packet = Uint8List.fromList(_buf.sublist(0, total));
      final frame = _parse(packet);
      if (!frame.crcOk) {
        crcErrors++;
        _buf.removeAt(0);
        continue;
      }
      _buf.removeRange(0, total);
      frames.add(frame);
    }
    return frames;
  }

  static ApiFrame _parse(Uint8List packet) {
    final bd = ByteData.sublistView(packet);
    final op = bd.getUint16(0, Endian.little);
    final payLen = bd.getUint16(2, Endian.little);
    final body = Uint8List.sublistView(packet, 0, kApiHeaderBytes + payLen);
    final gotCrc = bd.getUint16(kApiHeaderBytes + payLen, Endian.little);
    final crcOk = crc16Ccitt(body) == gotCrc;
    final payload =
        Uint8List.sublistView(packet, kApiHeaderBytes, kApiHeaderBytes + payLen);
    if (payload.isEmpty) {
      return ApiFrame(
          opcode: op,
          status: ApiStatus.unknown,
          data: Uint8List(0),
          crcOk: crcOk);
    }
    return ApiFrame(
      opcode: op,
      status: ApiStatus.fromByte(payload[0]),
      data: Uint8List.sublistView(payload, 1),
      crcOk: crcOk,
    );
  }
}

// ---------------------------------------------------------------------------
// Payload helpers
// ---------------------------------------------------------------------------

Uint8List u32le(int v) {
  final b = Uint8List(4);
  ByteData.sublistView(b).setUint32(0, v, Endian.little);
  return b;
}

String _cstr(Uint8List d, int start, int len) {
  final bytes = d.sublist(start, start + len);
  final nul = bytes.indexOf(0);
  return String.fromCharCodes(nul >= 0 ? bytes.sublist(0, nul) : bytes);
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

/// System IDENTITY (50 bytes).
class ApiIdentity {
  const ApiIdentity({
    required this.fwMajor,
    required this.fwMinor,
    required this.fwPatch,
    required this.apiVersion,
    required this.maxPayload,
    required this.product,
    required this.serial,
    required this.build,
  });

  final int fwMajor, fwMinor, fwPatch;
  final int apiVersion;
  final int maxPayload;
  final String product;
  final String serial;
  final String build;

  String get firmware => '$fwMajor.$fwMinor.$fwPatch';

  static ApiIdentity? decode(Uint8List d) {
    if (d.length < 50) return null;
    final bd = ByteData.sublistView(d);
    return ApiIdentity(
      fwMajor: d[0],
      fwMinor: d[1],
      fwPatch: d[2],
      apiVersion: d[3],
      maxPayload: bd.getUint16(4, Endian.little),
      product: _cstr(d, 6, 16),
      serial: _cstr(d, 22, 8),
      build: _cstr(d, 30, 20),
    );
  }
}

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

/// System STATE / Topics STATUS (15 bytes).
class ApiSystemState {
  const ApiSystemState({
    required this.batteryState,
    required this.batterySocPct,
    required this.batteryMv,
    this.usbConnected = false,
    this.bleConnected = true,
    this.charging = false,
    this.forceCharging = false,
    this.chargeInhibited = false,
    this.rail3v3On = true,
    this.rail5vOn = true,
    this.demodRunning = true,
    this.phasorStreamActive = false,
    this.bulkActive = false,
    this.serviceMode = false,
  });

  final BatteryState batteryState;
  final int batterySocPct;
  final int batteryMv;
  final bool usbConnected;
  final bool bleConnected;
  final bool charging;
  final bool forceCharging;
  final bool chargeInhibited;
  final bool rail3v3On;
  final bool rail5vOn;
  final bool demodRunning;
  final bool phasorStreamActive;
  final bool bulkActive;
  final bool serviceMode;

  static ApiSystemState? decode(Uint8List d) {
    if (d.length < 15) return null;
    final bd = ByteData.sublistView(d);
    return ApiSystemState(
      batteryState: BatteryState.fromByte(d[0]),
      batterySocPct: d[1],
      batteryMv: bd.getUint16(2, Endian.little),
      usbConnected: d[4] != 0,
      bleConnected: d[5] != 0,
      charging: d[6] != 0,
      forceCharging: d[7] != 0,
      chargeInhibited: d[8] != 0,
      rail3v3On: d[9] != 0,
      rail5vOn: d[10] != 0,
      demodRunning: d[11] != 0,
      phasorStreamActive: d[12] != 0,
      bulkActive: d[13] != 0,
      serviceMode: d[14] != 0,
    );
  }
}

/// System HEALTH (31 bytes).
class ApiHealth {
  const ApiHealth({
    required this.adcOk,
    required this.dacOk,
    required this.adsOk,
    required this.displayOk,
    required this.bmeOk,
    required this.eepromSelftest,
    required this.settingsSaveFailed,
    required this.wokeFromStandby,
    required this.resetCause,
    required this.rtcSet,
    required this.uptimeS,
    required this.usbTxDropped,
    required this.bleTxDropped,
    required this.uartTxDropped,
    required this.rxMalformed,
    required this.lastFaultKind,
    required this.lastFaultPc,
    required this.lastFaultLr,
  });

  final bool adcOk, dacOk, adsOk, displayOk, bmeOk;

  /// 0 not run, 1 passed, 2 failed.
  final int eepromSelftest;
  final bool settingsSaveFailed;
  final bool wokeFromStandby;

  /// bit0 pin, 1 power-on/brown-out, 2 software, 3 IWDG, 4 WWDG, 5 low-power,
  /// 6 option-byte load.
  final int resetCause;
  final bool rtcSet;
  final int uptimeS;
  final int usbTxDropped, bleTxDropped, uartTxDropped, rxMalformed;

  /// 0 none, 1 HardFault, 2 init failure.
  final int lastFaultKind;
  final int lastFaultPc, lastFaultLr;

  static const _resetNames = [
    'pin',
    'power-on / brown-out',
    'software',
    'independent watchdog',
    'window watchdog',
    'low-power',
    'option-byte load',
  ];

  /// Human-readable reset causes, in bit order.
  List<String> get resetCauseNames => [
        for (var i = 0; i < _resetNames.length; i++)
          if ((resetCause >> i) & 1 == 1) _resetNames[i],
      ];

  static ApiHealth? decode(Uint8List d) {
    if (d.length < 31) return null;
    final bd = ByteData.sublistView(d);
    return ApiHealth(
      adcOk: d[0] != 0,
      dacOk: d[1] != 0,
      adsOk: d[2] != 0,
      displayOk: d[3] != 0,
      bmeOk: d[4] != 0,
      eepromSelftest: d[5],
      settingsSaveFailed: d[6] != 0,
      wokeFromStandby: d[7] != 0,
      resetCause: d[8],
      rtcSet: d[9] != 0,
      uptimeS: bd.getUint32(10, Endian.little),
      usbTxDropped: bd.getUint16(14, Endian.little),
      bleTxDropped: bd.getUint16(16, Endian.little),
      uartTxDropped: bd.getUint16(18, Endian.little),
      rxMalformed: bd.getUint16(20, Endian.little),
      lastFaultKind: d[22],
      lastFaultPc: bd.getUint32(23, Endian.little),
      lastFaultLr: bd.getUint32(27, Endian.little),
    );
  }
}

/// System RTC response (10 bytes).
class ApiRtc {
  const ApiRtc({
    required this.year,
    required this.month,
    required this.day,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.second,
    required this.isSet,
    this.subsecond = 0,
  });

  final int year, month, day, weekday, hour, minute, second;
  final bool isSet;

  /// 1/256 s.
  final int subsecond;

  DateTime get dateTime => DateTime(year, month, day, hour, minute, second);

  static ApiRtc? decode(Uint8List d) {
    if (d.length < 10) return null;
    final bd = ByteData.sublistView(d);
    return ApiRtc(
      year: bd.getUint16(0, Endian.little),
      month: d[2],
      day: d[3],
      weekday: d[4],
      hour: d[5],
      minute: d[6],
      second: d[7],
      isSet: d[8] != 0,
      subsecond: d[9],
    );
  }

  /// SET request payload (7 bytes).
  static Uint8List encodeSet(DateTime t) {
    final b = Uint8List(7);
    final bd = ByteData.sublistView(b);
    bd.setUint16(0, t.year, Endian.little);
    b[2] = t.month;
    b[3] = t.day;
    b[4] = t.hour;
    b[5] = t.minute;
    b[6] = t.second;
    return b;
  }
}

// ---------------------------------------------------------------------------
// Topics
// ---------------------------------------------------------------------------

/// Topics ENV (14 bytes).
class ApiEnvironmental {
  const ApiEnvironmental({
    required this.bmeTempC,
    required this.pressurePa,
    required this.humidityPct,
    required this.bmeOk,
    required this.onboardTempC,
    required this.externalTempC,
    required this.externalTempOk,
  });

  final double bmeTempC;
  final int pressurePa;
  final double humidityPct;
  final bool bmeOk;
  final double onboardTempC;
  final double externalTempC;
  final bool externalTempOk;

  double get pressureHpa => pressurePa / 100.0;

  static ApiEnvironmental? decode(Uint8List d) {
    if (d.length < 14) return null;
    final bd = ByteData.sublistView(d);
    return ApiEnvironmental(
      bmeTempC: bd.getInt16(0, Endian.little) / 100.0,
      pressurePa: bd.getUint32(2, Endian.little),
      humidityPct: bd.getUint16(6, Endian.little) / 100.0,
      bmeOk: d[8] != 0,
      onboardTempC: bd.getInt16(9, Endian.little) / 100.0,
      externalTempC: bd.getInt16(11, Endian.little) / 100.0,
      externalTempOk: d[13] != 0,
    );
  }
}

/// Topics LIVE (15 bytes): the live tilt reading with its quality flags.
class ApiLive {
  const ApiLive({
    required this.seq,
    required this.flags,
    required this.tiltS1,
    required this.tiltS2,
    required this.tiltDiff,
  });

  final int seq;

  /// bit0 valid, bit1 sensor 1 doubtful, bit2 sensor 2 doubtful.
  final int flags;
  final double tiltS1, tiltS2, tiltDiff;

  bool get valid => flags & 1 != 0;
  bool get s1Doubtful => flags & 2 != 0;
  bool get s2Doubtful => flags & 4 != 0;
  bool get anyDoubtful => s1Doubtful || s2Doubtful;

  static ApiLive? decode(Uint8List d) {
    if (d.length < 15) return null;
    final bd = ByteData.sublistView(d);
    return ApiLive(
      seq: bd.getUint16(0, Endian.little),
      flags: d[2],
      tiltS1: bd.getFloat32(3, Endian.little),
      tiltS2: bd.getFloat32(7, Endian.little),
      tiltDiff: bd.getFloat32(11, Endian.little),
    );
  }
}

/// Topics SIGNAL_DIAG (56 bytes). Channel order is S2, B, A, S1.
class ApiSignalDiag {
  const ApiSignalDiag({
    required this.rmsMv,
    required this.p2pMv,
    required this.phaseDeg,
    required this.theoreticalTiltS1,
    required this.theoreticalTiltS2,
  });

  final List<double> rmsMv; // 4
  final List<double> p2pMv; // 4
  final List<double> phaseDeg; // 4
  final double theoreticalTiltS1, theoreticalTiltS2;

  static const channelNames = ['S2', 'B', 'A', 'S1'];

  static ApiSignalDiag? decode(Uint8List d) {
    if (d.length < 56) return null;
    final bd = ByteData.sublistView(d);
    List<double> four(int off) => [
          for (var i = 0; i < 4; i++) bd.getFloat32(off + 4 * i, Endian.little),
        ];
    return ApiSignalDiag(
      rmsMv: four(0),
      p2pMv: four(16),
      phaseDeg: four(32),
      theoreticalTiltS1: bd.getFloat32(48, Endian.little),
      theoreticalTiltS2: bd.getFloat32(52, Endian.little),
    );
  }
}

/// One Topics PHASOR_STREAM push: the raw phasors of a 64-cycle batch.
class ApiPhasorEntry {
  const ApiPhasorEntry({
    required this.iB,
    required this.qB,
    required this.iA,
    required this.qA,
    required this.iS1,
    required this.qS1,
    required this.iS2,
    required this.qS2,
    required this.seq,
  });

  final double iB, qB, iA, qA, iS1, qS1, iS2, qS2;

  /// Cycle counter of the batch's last cycle (steps of 64, wraps at 65536).
  final int seq;

  static ApiPhasorEntry? decode(Uint8List d) {
    if (d.length < 34) return null;
    final bd = ByteData.sublistView(d);
    double f(int i) => bd.getFloat32(4 * i, Endian.little);
    return ApiPhasorEntry(
      iB: f(0),
      qB: f(1),
      iA: f(2),
      qA: f(3),
      iS1: f(4),
      qS1: f(5),
      iS2: f(6),
      qS2: f(7),
      seq: bd.getUint16(32, Endian.little),
    );
  }

  Uint8List encode() {
    final b = Uint8List(34);
    final bd = ByteData.sublistView(b);
    final v = [iB, qB, iA, qA, iS1, qS1, iS2, qS2];
    for (var i = 0; i < 8; i++) {
      bd.setFloat32(4 * i, v[i], Endian.little);
    }
    bd.setUint16(32, seq, Endian.little);
    return b;
  }
}

// ---------------------------------------------------------------------------
// Procedures
// ---------------------------------------------------------------------------

/// Procedures ZERO_CAL phase.
enum ZeroCalPhase {
  idle(0),
  step1Running(1),
  step1Done(2),
  step2Running(3),
  resultReady(4),
  unknown(0xFF);

  const ZeroCalPhase(this.value);
  final int value;

  static ZeroCalPhase fromByte(int b) {
    for (final p in ZeroCalPhase.values) {
      if (p.value == b) return p;
    }
    return ZeroCalPhase.unknown;
  }
}

/// Procedures ZERO_CAL (6 bytes).
class ApiZeroCalStatus {
  const ApiZeroCalStatus({
    required this.phase,
    required this.progress,
    required this.target,
    required this.sensorMask,
  });

  final ZeroCalPhase phase;
  final int progress;
  final int target;
  final int sensorMask;

  static ApiZeroCalStatus? decode(Uint8List d) {
    if (d.length < 6) return null;
    final bd = ByteData.sublistView(d);
    return ApiZeroCalStatus(
      phase: ZeroCalPhase.fromByte(d[0]),
      progress: bd.getUint16(1, Endian.little),
      target: bd.getUint16(3, Endian.little),
      sensorMask: d[5],
    );
  }
}

enum PrecisionPhase {
  idle(0),
  running(1),
  done(2),
  unknown(0xFF);

  const PrecisionPhase(this.value);
  final int value;

  static PrecisionPhase fromByte(int b) {
    for (final p in PrecisionPhase.values) {
      if (p.value == b) return p;
    }
    return PrecisionPhase.unknown;
  }
}

/// Procedures PRECISION (23 bytes).
class ApiPrecisionStatus {
  const ApiPrecisionStatus({
    required this.phase,
    required this.target,
    required this.count,
    required this.elapsedMs,
    required this.failed,
    required this.tiltS1,
    required this.tiltS2,
    required this.tiltDiff,
    required this.disturbed,
  });

  final PrecisionPhase phase;

  /// Window length in batches (81 ≈ 1.99 s).
  final int target;

  /// Contiguous clean batches collected since the trigger.
  final int count;
  final int elapsedMs;

  /// Done without a result: no clean window within 5 s.
  final bool failed;

  /// Valid when [phase] is done and not [failed].
  final double tiltS1, tiltS2, tiltDiff;

  /// While running: the newest full window is not clean.
  final bool disturbed;

  static ApiPrecisionStatus? decode(Uint8List d) {
    if (d.length < 23) return null;
    final bd = ByteData.sublistView(d);
    return ApiPrecisionStatus(
      phase: PrecisionPhase.fromByte(d[0]),
      target: bd.getUint16(1, Endian.little),
      count: bd.getUint16(3, Endian.little),
      elapsedMs: bd.getUint32(5, Endian.little),
      failed: d[9] != 0,
      tiltS1: bd.getFloat32(10, Endian.little),
      tiltS2: bd.getFloat32(14, Endian.little),
      tiltDiff: bd.getFloat32(18, Endian.little),
      disturbed: d[22] != 0,
    );
  }
}
