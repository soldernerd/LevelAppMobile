/// NeigMess2 resource ids and payload codecs on top of the shared API framing
/// ([api_v3.dart]); the resource list is `docs/device_api.md` in the NeigMess2
/// repo. Pure Dart.
///
/// Sensor values 0–3 are *sensor units*, not pF: the PCap04's `C / Cref`
/// divided by one million (see [kUnitToPf]).
library;

import 'dart:typed_data';

/// Nominal pF per sensor unit: `Cref ≈ 12.8 pF`, `ratio = unit / 134.217728`.
/// The ratio is exact, the absolute pF only as good as the nominal Cref.
const double kUnitToPf = 12.8 / 134.217728;

/// Measurements (category 0x4) resource ids.
class NmMeas {
  static const int sensor0 = 0x00;
  static const int sensor1 = 0x01;
  static const int sensor2 = 0x02;
  static const int sensor3 = 0x03; // the centre ("main") sensor
  static const int angleX = 0x04;
  static const int angleY = 0x05;
  static const int angleZ = 0x06;
  static const int tilt = 0x07;
  static const int plateCap = 0x08;
  static const int tiltStatus = 0x09;
  static const int zeroRoutine = 0x0A; // flip-test zero progress
}

/// Commands (category 0x1) resource ids. Zero, clear and store write the EEPROM.
class NmCmd {
  static const int zero = 0x00;
  static const int clearZero = 0x01;
  static const int store = 0x02;
  static const int captureNeutral = 0x03;
  static const int recall = 0x04; // reload the EEPROM calibration into RAM
  static const int zeroNext = 0x05; // KEY3 of the flip-test zero
  static const int zeroQuit = 0x06; // KEY2: abandon the flip-test zero
}

/// Calibrations (category 0x2) resource ids.
class NmCal {
  static const int zeroOffsets = 0x00;
  static const int tiltTrim = 0x01;
  static const int angleOffsets = 0x02;
  static const int neutralCap = 0x03;
}

/// Topic groups (category 0x5) resource ids.
class NmTopic {
  static const int sensors = 0x00;
}

/// The Sensors topic group (20 bytes): four sensor readings (without the zero
/// offset) and the X / Y angles, all from the same instant.
class NmSensors {
  const NmSensors({
    required this.units,
    required this.angleXCdeg,
    required this.angleYCdeg,
  });

  /// Sensors 0–3 in sensor units.
  final List<double> units;

  /// Centi-degrees, raw sensor output.
  final int angleXCdeg, angleYCdeg;

  double get angleXDeg => angleXCdeg / 100;
  double get angleYDeg => angleYCdeg / 100;

  static NmSensors? decode(Uint8List d) {
    if (d.length < 20) return null;
    final bd = ByteData.sublistView(d);
    return NmSensors(
      units: [for (var i = 0; i < 4; i++) bd.getFloat32(i * 4, Endian.little)],
      angleXCdeg: bd.getInt16(16, Endian.little),
      angleYCdeg: bd.getInt16(18, Endian.little),
    );
  }

  Uint8List encode() {
    final b = Uint8List(20);
    final bd = ByteData.sublistView(b);
    for (var i = 0; i < 4; i++) {
      bd.setFloat32(i * 4, units[i], Endian.little);
    }
    bd.setInt16(16, angleXCdeg, Endian.little);
    bd.setInt16(18, angleYCdeg, Endian.little);
    return b;
  }
}

/// Calibrations 0x00: the zero offsets of the four sensors, sensor units.
class NmZeroOffsets {
  const NmZeroOffsets(this.units);

  final List<double> units;

  static NmZeroOffsets? decode(Uint8List d) {
    if (d.length < 16) return null;
    final bd = ByteData.sublistView(d);
    return NmZeroOffsets([
      for (var i = 0; i < 4; i++) bd.getFloat32(i * 4, Endian.little),
    ]);
  }

  Uint8List encode() {
    final b = Uint8List(16);
    final bd = ByteData.sublistView(b);
    for (var i = 0; i < 4; i++) {
      bd.setFloat32(i * 4, units[i], Endian.little);
    }
    return b;
  }
}

/// Calibrations 0x01: the two fine-trim knobs. Result =
/// `multiplier/1000 × (theory + offset/10)`.
class NmTiltTrim {
  const NmTiltTrim({
    required this.multiplierX1000,
    required this.offsetTenthUmPerM,
  });

  final int multiplierX1000;
  final int offsetTenthUmPerM;

  static NmTiltTrim? decode(Uint8List d) {
    if (d.length < 4) return null;
    final bd = ByteData.sublistView(d);
    return NmTiltTrim(
      multiplierX1000: bd.getUint16(0, Endian.little),
      offsetTenthUmPerM: bd.getInt16(2, Endian.little),
    );
  }

  Uint8List encode() {
    final b = Uint8List(4);
    ByteData.sublistView(b)
      ..setUint16(0, multiplierX1000, Endian.little)
      ..setInt16(2, offsetTenthUmPerM, Endian.little);
    return b;
  }
}

/// Measurements 0x09.
enum NmTiltStatus {
  ok(0),

  /// The plates would touch (≳ +2100 µm/m).
  over(1),

  /// Capacitance far too small: sensor missing or baseline wrong.
  under(2),
  invalid(3);

  const NmTiltStatus(this.value);
  final int value;

  static NmTiltStatus fromByte(int b) => NmTiltStatus.values.firstWhere(
    (s) => s.value == b,
    orElse: () => NmTiltStatus.invalid,
  );
}

double? decodeFloat(Uint8List d) =>
    d.length < 4 ? null : ByteData.sublistView(d).getFloat32(0, Endian.little);

Uint8List encodeFloat(double v) {
  final b = Uint8List(4);
  ByteData.sublistView(b).setFloat32(0, v, Endian.little);
  return b;
}

/// Measurements 0x0A: the state of the flip-test zero routine.
enum NmZeroState {
  idle(0),
  readyPos1(1),
  measuring1(2),

  /// Rotate the instrument 180°, then start position 2.
  readyPos2(3),
  measuring2(4),

  /// The zero has been stored; dismiss the result.
  done(5),

  /// The resulting offset was out of range; nothing was stored.
  failed(6);

  const NmZeroState(this.value);
  final int value;

  static NmZeroState fromByte(int b) => NmZeroState.values.firstWhere(
    (s) => s.value == b,
    orElse: () => NmZeroState.idle,
  );

  bool get isMeasuring => this == measuring1 || this == measuring2;

  /// The routine is under way (or showing a result), not idle.
  bool get isActive => this != idle;
}

/// Measurements 0x0A (14 bytes). The routine shows on the instrument's LCD too;
/// its keys and the API commands act on the same state.
class NmZeroRoutine {
  const NmZeroRoutine({
    this.state = NmZeroState.idle,
    this.progress = 0,
    this.pos1Valid = false,
    this.pos2Valid = false,
    this.unsteady = false,
    this.pos1 = 0,
    this.pos2 = 0,
    this.offsetTenth = 0,
  });

  final NmZeroState state;

  /// Percent of the current measurement.
  final int progress;
  final bool pos1Valid, pos2Valid;

  /// The instrument moved; the measurement starts again.
  final bool unsteady;

  /// µm/m, model tilt before the fine trim.
  final double pos1, pos2;

  /// The zero offset now in force, 0.1 µm/m (the trim's offset).
  final int offsetTenth;

  double get offsetUmPerM => offsetTenth / 10;

  static NmZeroRoutine? decode(Uint8List d) {
    if (d.length < 14) return null;
    final bd = ByteData.sublistView(d);
    final flags = d[2];
    return NmZeroRoutine(
      state: NmZeroState.fromByte(d[0]),
      progress: d[1].clamp(0, 100),
      pos1Valid: flags & 1 != 0,
      pos2Valid: flags & 2 != 0,
      unsteady: flags & 4 != 0,
      pos1: bd.getFloat32(4, Endian.little),
      pos2: bd.getFloat32(8, Endian.little),
      offsetTenth: bd.getInt16(12, Endian.little),
    );
  }

  Uint8List encode() {
    final b = Uint8List(14);
    b[0] = state.value;
    b[1] = progress;
    b[2] = (pos1Valid ? 1 : 0) | (pos2Valid ? 2 : 0) | (unsteady ? 4 : 0);
    ByteData.sublistView(b)
      ..setFloat32(4, pos1, Endian.little)
      ..setFloat32(8, pos2, Endian.little)
      ..setInt16(12, offsetTenth, Endian.little);
    return b;
  }

  @override
  bool operator ==(Object other) =>
      other is NmZeroRoutine &&
      state == other.state &&
      progress == other.progress &&
      pos1Valid == other.pos1Valid &&
      pos2Valid == other.pos2Valid &&
      unsteady == other.unsteady &&
      pos1 == other.pos1 &&
      pos2 == other.pos2 &&
      offsetTenth == other.offsetTenth;

  @override
  int get hashCode => Object.hash(
    state,
    progress,
    pos1Valid,
    pos2Valid,
    unsteady,
    pos1,
    pos2,
    offsetTenth,
  );
}
