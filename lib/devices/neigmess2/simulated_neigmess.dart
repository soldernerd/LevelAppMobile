/// An in-memory NeigMess2 that speaks its API v2 at the request/reply level —
/// behind [MockBleManager] for hardware-free runs and the test suite. It models
/// what the app uses: IDENTITY (the 19-byte v2 layout), the Sensors topic, the
/// tilt measurements, the zero / clear / store / neutral commands, the
/// calibrations and the periodic pushes of subscriptions.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/simulated_peripheral.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';

class SimulatedNeigMess implements SimulatedPeripheral {
  SimulatedNeigMess();

  @override
  void Function()? onLinkDown;

  // --------------------------------------------------------------------------
  // Test / dev hooks
  // --------------------------------------------------------------------------

  /// What the four sensors read, sensor units (without the zero offset).
  List<double> sensorUnits = [52.5, 51.0, 53.2, 171.5];

  /// Centi-degrees.
  int angleXCdeg = 12, angleYCdeg = -34, angleZCdeg = 9000;

  /// µm/m, valid only while [tiltStatus] is ok.
  double tilt = 12.5;
  double plateCapPf = 16.4;
  NmTiltStatus tiltStatus = NmTiltStatus.ok;

  /// Calibrations as stored.
  List<double> zeroOffsets = [0, 0, 0, 0];
  int trimMultiplierX1000 = 1000;
  int trimOffsetTenth = 0;
  double neutralCapPf = 16.38;

  /// How often the EEPROM was written (zero / clear / store / calibration SET).
  int eepromWrites = 0;

  // The EEPROM copy of the calibration; RAM above, stored by _commit().
  List<double> _eZero = [0, 0, 0, 0];
  int _eMul = 1000, _eOfs = 0;
  double _eNeutral = 16.38;

  // The flip-test zero routine.
  NmZeroState _zState = NmZeroState.idle;
  int _zProgress = 0;
  bool _zPos1Valid = false, _zPos2Valid = false;
  double _zPos1 = 0, _zPos2 = 0;
  Timer? _zTimer;

  /// The flip-test zero: the instrument really reads [flipTilt] in position 1
  /// and -[flipTilt] in position 2, plus its own zero error [flipBias] (µm/m).
  /// The routine should find an offset of -[flipBias].
  double flipTilt = 100.0, flipBias = 3.0;

  final Map<int, Timer> _timers = {};
  final Map<int, StreamController<Uint8List>> _subs = {};

  // --------------------------------------------------------------------------
  // DeviceLink
  // --------------------------------------------------------------------------

  @override
  Future<ApiReply> request(
    int op, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    final cat = opcodeCategory(op);
    final res = opcodeResource(op);
    switch (opcodeVerb(op)) {
      case ApiVerb.get:
        if (cat == ApiCat.system) {
          return res == SysRes.identity
              ? ApiReply(ApiStatus.ok, _identity())
              : res == 0x01
              ? ApiReply(ApiStatus.ok, Uint8List(4))
              : const ApiReply(ApiStatus.unknownResource);
        }
        final data = _read(cat, res);
        if (data == null) {
          return ApiReply(
            _knownCategory(cat)
                ? ApiStatus.unknownResource
                : ApiStatus.unknownCategory,
          );
        }
        return ApiReply(ApiStatus.ok, data);
      case ApiVerb.set:
        return cat == ApiCat.calibrations
            ? _setCalibration(res, Uint8List.fromList(payload))
            : const ApiReply(ApiStatus.verbNotValid);
      case ApiVerb.execute:
        return cat == ApiCat.commands
            ? _command(res)
            : const ApiReply(ApiStatus.verbNotValid);
      default:
        return const ApiReply(ApiStatus.verbNotValid);
    }
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) {
    final existing = _subs[subscribeOpcode];
    if (existing != null && !existing.isClosed) return existing.stream;
    final cat = opcodeCategory(subscribeOpcode);
    final res = opcodeResource(subscribeOpcode);
    if (_read(cat, res) == null) {
      return Stream<Uint8List>.error(
        ApiException(ApiStatus.unknownResource, 'subscribe'),
      );
    }
    if (intervalMs < 50) {
      return Stream<Uint8List>.error(
        ApiException(ApiStatus.invalidParameter, 'subscribe'),
      );
    }
    late final StreamController<Uint8List> c;
    c = StreamController<Uint8List>.broadcast(
      onListen: () {
        _timers[subscribeOpcode] = Timer.periodic(
          Duration(milliseconds: intervalMs),
          (_) {
            final data = _read(cat, res);
            if (data != null && !c.isClosed) c.add(data);
          },
        );
      },
      onCancel: () {
        _timers.remove(subscribeOpcode)?.cancel();
        _subs.remove(subscribeOpcode);
      },
    );
    _subs[subscribeOpcode] = c;
    return c.stream;
  }

  @override
  void linkDown() {
    _stopAll();
    final cb = onLinkDown;
    cb?.call();
  }

  @override
  void dispose() => _stopAll();

  void _stopAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _zTimer?.cancel();
    for (final c in _subs.values.toList()) {
      if (!c.isClosed) c.close();
    }
    _subs.clear();
  }

  // --------------------------------------------------------------------------
  // Resources
  // --------------------------------------------------------------------------

  Uint8List _identity() {
    final d = Uint8List(19);
    d.setRange(0, 3, [0, 1, 0]);
    d.setRange(3, 3 + 9, 'NeigMess2'.codeUnits);
    return d;
  }

  bool _knownCategory(int cat) =>
      cat == ApiCat.measurements ||
      cat == ApiCat.topics ||
      cat == ApiCat.calibrations;

  /// The data of GET (and of every push) of a resource, or null if undefined.
  Uint8List? _read(int cat, int res) {
    if (cat == ApiCat.topics && res == NmTopic.sensors) {
      return NmSensors(
        units: sensorUnits,
        angleXCdeg: angleXCdeg,
        angleYCdeg: angleYCdeg,
      ).encode();
    }
    if (cat == ApiCat.measurements) {
      if (res >= NmMeas.sensor0 && res <= NmMeas.sensor3) {
        return encodeFloat(sensorUnits[res]);
      }
      Uint8List i16(int v) =>
          Uint8List(2)..buffer.asByteData().setInt16(0, v, Endian.little);
      return switch (res) {
        NmMeas.angleX => i16(angleXCdeg),
        NmMeas.angleY => i16(angleYCdeg),
        NmMeas.angleZ => i16(angleZCdeg),
        NmMeas.tilt => encodeFloat(tiltStatus == NmTiltStatus.ok ? tilt : 0),
        NmMeas.plateCap => encodeFloat(plateCapPf),
        NmMeas.tiltStatus => Uint8List.fromList([tiltStatus.value]),
        NmMeas.zeroRoutine => _routine().encode(),
        _ => null,
      };
    }
    if (cat == ApiCat.calibrations) {
      return switch (res) {
        NmCal.zeroOffsets => NmZeroOffsets(zeroOffsets).encode(),
        NmCal.tiltTrim => NmTiltTrim(
          multiplierX1000: trimMultiplierX1000,
          offsetTenthUmPerM: trimOffsetTenth,
        ).encode(),
        NmCal.angleOffsets => Uint8List(4),
        NmCal.neutralCap => encodeFloat(neutralCapPf),
        _ => null,
      };
    }
    return null;
  }

  ApiReply _setCalibration(int res, Uint8List p) {
    switch (res) {
      case NmCal.zeroOffsets:
        final z = NmZeroOffsets.decode(p);
        if (p.length != 16 || z == null) {
          return const ApiReply(ApiStatus.badLength);
        }
        if (z.units.any((v) => !v.isFinite)) {
          return const ApiReply(ApiStatus.invalidParameter);
        }
        zeroOffsets = z.units;
      case NmCal.tiltTrim:
        final t = NmTiltTrim.decode(p);
        if (p.length != 4 || t == null) {
          return const ApiReply(ApiStatus.badLength);
        }
        trimMultiplierX1000 = t.multiplierX1000;
        trimOffsetTenth = t.offsetTenthUmPerM;
      case NmCal.neutralCap:
        final v = decodeFloat(p);
        if (p.length != 4 || v == null) {
          return const ApiReply(ApiStatus.badLength);
        }
        if (!v.isFinite || v < 5 || v > 100) {
          return const ApiReply(ApiStatus.invalidParameter);
        }
        neutralCapPf = v;
      default:
        return const ApiReply(ApiStatus.unknownResource);
    }
    _commit();
    return const ApiReply(ApiStatus.ok);
  }

  /// Writes the RAM calibration to the (simulated) EEPROM.
  void _commit() {
    _eZero = List.of(zeroOffsets);
    _eMul = trimMultiplierX1000;
    _eOfs = trimOffsetTenth;
    _eNeutral = neutralCapPf;
    eepromWrites++;
  }

  NmZeroRoutine _routine() => NmZeroRoutine(
    state: _zState,
    progress: _zProgress,
    pos1Valid: _zPos1Valid,
    pos2Valid: _zPos2Valid,
    pos1: _zPos1,
    pos2: _zPos2,
    offsetTenth: trimOffsetTenth,
  );

  /// KEY3: start, start measuring, or dismiss; ignored while measuring.
  void _zeroNext() {
    switch (_zState) {
      case NmZeroState.idle:
        _zPos1Valid = _zPos2Valid = false;
        _zProgress = 0;
        _zState = NmZeroState.readyPos1;
      case NmZeroState.readyPos1:
        _measure(NmZeroState.measuring1);
      case NmZeroState.readyPos2:
        _measure(NmZeroState.measuring2);
      case NmZeroState.done || NmZeroState.failed:
        _zState = NmZeroState.idle;
      case NmZeroState.measuring1 || NmZeroState.measuring2:
        break;
    }
  }

  /// A measurement takes about 5 s.
  void _measure(NmZeroState measuring) {
    _zState = measuring;
    _zProgress = 0;
    _zTimer?.cancel();
    _zTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _zProgress += 2;
      if (_zProgress < 100) return;
      t.cancel();
      if (measuring == NmZeroState.measuring1) {
        _zPos1 = flipTilt + flipBias;
        _zPos1Valid = true;
        _zState = NmZeroState.readyPos2;
      } else {
        _zPos2 = -flipTilt + flipBias;
        _zPos2Valid = true;
        final ofs = (-(_zPos1 + _zPos2) / 2 * 10).round();
        if (ofs.abs() > 1000) {
          _zState = NmZeroState.failed;
        } else {
          trimOffsetTenth = ofs;
          _commit();
          _zState = NmZeroState.done;
        }
      }
    });
  }

  ApiReply _command(int res) {
    switch (res) {
      case NmCmd.zero:
        zeroOffsets = List.of(sensorUnits);
        _commit();
      case NmCmd.clearZero:
        zeroOffsets = [0, 0, 0, 0];
        _commit();
      case NmCmd.store:
        _commit();
      case NmCmd.recall:
        zeroOffsets = List.of(_eZero);
        trimMultiplierX1000 = _eMul;
        trimOffsetTenth = _eOfs;
        neutralCapPf = _eNeutral;
      case NmCmd.zeroNext:
        _zeroNext();
      case NmCmd.zeroQuit:
        _zTimer?.cancel();
        _zState = NmZeroState.idle;
      case NmCmd.captureNeutral:
        if (tiltStatus != NmTiltStatus.ok) {
          return const ApiReply(ApiStatus.invalidParameter);
        }
        neutralCapPf = plateCapPf;
      default:
        return const ApiReply(ApiStatus.unknownResource);
    }
    return const ApiReply(ApiStatus.ok);
  }
}
