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
          return ApiReply(_knownCategory(cat)
              ? ApiStatus.unknownResource
              : ApiStatus.unknownCategory);
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
          ApiException(ApiStatus.unknownResource, 'subscribe'));
    }
    if (intervalMs < 50) {
      return Stream<Uint8List>.error(
          ApiException(ApiStatus.invalidParameter, 'subscribe'));
    }
    late final StreamController<Uint8List> c;
    c = StreamController<Uint8List>.broadcast(
      onListen: () {
        _timers[subscribeOpcode] =
            Timer.periodic(Duration(milliseconds: intervalMs), (_) {
          final data = _read(cat, res);
          if (data != null && !c.isClosed) c.add(data);
        });
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
        NmMeas.tilt =>
          encodeFloat(tiltStatus == NmTiltStatus.ok ? tilt : 0),
        NmMeas.plateCap => encodeFloat(plateCapPf),
        NmMeas.tiltStatus => Uint8List.fromList([tiltStatus.value]),
        _ => null,
      };
    }
    if (cat == ApiCat.calibrations) {
      return switch (res) {
        NmCal.zeroOffsets => NmZeroOffsets(zeroOffsets).encode(),
        NmCal.tiltTrim => NmTiltTrim(
                multiplierX1000: trimMultiplierX1000,
                offsetTenthUmPerM: trimOffsetTenth)
            .encode(),
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
    eepromWrites++;
    return const ApiReply(ApiStatus.ok);
  }

  ApiReply _command(int res) {
    switch (res) {
      case NmCmd.zero:
        zeroOffsets = List.of(sensorUnits);
        eepromWrites++;
      case NmCmd.clearZero:
        zeroOffsets = [0, 0, 0, 0];
        eepromWrites++;
      case NmCmd.store:
        eepromWrites++;
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
