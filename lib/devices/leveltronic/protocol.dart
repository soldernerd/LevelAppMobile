/// Leveltronic resource ids and payload codecs on top of the shared API v3
/// framing ([api_v3.dart]): the command / topic / procedure resources of the
/// precision level and the decoders for what they return.
///
/// The resource list is `docs/api-reference.md` in the InclinationMeterFirmware
/// repo (generated from its `tools/api_spec.py`). Pure Dart, unit-tested in
/// isolation.
library;

import 'dart:typed_data';


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
