/// Typed operations on the NeigMess2, built on a [DeviceLink]. No BLE and no
/// Flutter here.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';

class NeigMessApi {
  const NeigMessApi(this.link);

  final DeviceLink link;

  Future<Uint8List> _get(int op, String what) async =>
      (await link.request(op)).orThrow(what).data;

  T _decoded<T>(T? v, String what) {
    if (v == null) throw LinkException('malformed $what reply');
    return v;
  }

  // --- readings -------------------------------------------------------------

  Future<NmSensors> sensors() async => _decoded(
    NmSensors.decode(
      await _get(opGet(ApiCat.topics, NmTopic.sensors), 'sensors'),
    ),
    'sensors',
  );

  Future<double> tilt() async => _decoded(
    decodeFloat(await _get(opGet(ApiCat.measurements, NmMeas.tilt), 'tilt')),
    'tilt',
  );

  Future<double> plateCapPf() async => _decoded(
    decodeFloat(
      await _get(
        opGet(ApiCat.measurements, NmMeas.plateCap),
        'plate capacitance',
      ),
    ),
    'plate capacitance',
  );

  Future<NmTiltStatus> tiltStatus() async {
    final d = await _get(
      opGet(ApiCat.measurements, NmMeas.tiltStatus),
      'tilt status',
    );
    if (d.isEmpty) throw const LinkException('malformed tilt status reply');
    return NmTiltStatus.fromByte(d[0]);
  }

  Future<NmZeroRoutine> zeroRoutine() async => _decoded(
    NmZeroRoutine.decode(
      await _get(
        opGet(ApiCat.measurements, NmMeas.zeroRoutine),
        'zero routine',
      ),
    ),
    'zero routine',
  );

  // --- calibrations -----------------------------------------------------------

  Future<NmZeroOffsets> zeroOffsets() async => _decoded(
    NmZeroOffsets.decode(
      await _get(opGet(ApiCat.calibrations, NmCal.zeroOffsets), 'zero offsets'),
    ),
    'zero offsets',
  );

  Future<NmTiltTrim> tiltTrim() async => _decoded(
    NmTiltTrim.decode(
      await _get(opGet(ApiCat.calibrations, NmCal.tiltTrim), 'tilt trim'),
    ),
    'tilt trim',
  );

  Future<double> neutralCapPf() async => _decoded(
    decodeFloat(
      await _get(
        opGet(ApiCat.calibrations, NmCal.neutralCap),
        'neutral capacitance',
      ),
    ),
    'neutral capacitance',
  );

  /// Written to the EEPROM before the device acknowledges.
  Future<void> setTiltTrim(NmTiltTrim trim) async {
    (await link.request(
      opSet(ApiCat.calibrations, NmCal.tiltTrim),
      trim.encode(),
    )).orThrow('tilt trim');
  }

  /// Written to the EEPROM before the device acknowledges. 5…100 pF.
  Future<void> setNeutralCapPf(double pf) async {
    (await link.request(
      opSet(ApiCat.calibrations, NmCal.neutralCap),
      encodeFloat(pf),
    )).orThrow('neutral capacitance');
  }

  // --- commands (the first three write the EEPROM: do not call in a loop) ----

  Future<void> _exec(int res, String what) async {
    // They write the EEPROM, which takes tens of milliseconds.
    (await link.request(
      opExecute(res),
      const [],
      const Duration(seconds: 3),
    )).orThrow(what);
  }

  Future<void> zeroSensors() => _exec(NmCmd.zero, 'zero sensors');
  Future<void> clearZero() => _exec(NmCmd.clearZero, 'clear zero');
  Future<void> storeCalibration() => _exec(NmCmd.store, 'store calibration');

  /// Only accepted while the alignment is OK; RAM only until
  /// [storeCalibration].
  Future<void> captureNeutral() =>
      _exec(NmCmd.captureNeutral, 'capture neutral');

  /// Reloads the EEPROM calibration into RAM, discarding unsaved changes.
  Future<void> recallCalibration() => _exec(NmCmd.recall, 'recall calibration');

  /// KEY3 of the flip-test zero: starts the routine from idle, starts the
  /// measurement of the present position when it is ready, dismisses the
  /// result when it is done. Ignored while measuring.
  Future<void> zeroRoutineNext() => _exec(NmCmd.zeroNext, 'zero routine');

  /// KEY2: abandons the flip-test zero.
  Future<void> zeroRoutineQuit() => _exec(NmCmd.zeroQuit, 'zero routine');

  // --- subscriptions ----------------------------------------------------------

  Stream<T> _decodedStream<T>(
    Stream<Uint8List> raw,
    T? Function(Uint8List) decode,
  ) => raw.map(decode).where((v) => v != null).cast<T>();

  Stream<NmSensors> sensorUpdates({int intervalMs = 500}) => _decodedStream(
    link.subscribe(
      opSubscribe(ApiCat.topics, NmTopic.sensors),
      intervalMs: intervalMs,
    ),
    NmSensors.decode,
  );

  Stream<double> tiltUpdates({int intervalMs = 500}) => _decodedStream(
    link.subscribe(
      opSubscribe(ApiCat.measurements, NmMeas.tilt),
      intervalMs: intervalMs,
    ),
    decodeFloat,
  );

  Stream<double> plateCapUpdates({int intervalMs = 500}) => _decodedStream(
    link.subscribe(
      opSubscribe(ApiCat.measurements, NmMeas.plateCap),
      intervalMs: intervalMs,
    ),
    decodeFloat,
  );

  Stream<NmTiltStatus> tiltStatusUpdates({int intervalMs = 500}) => link
      .subscribe(
        opSubscribe(ApiCat.measurements, NmMeas.tiltStatus),
        intervalMs: intervalMs,
      )
      .where((d) => d.isNotEmpty)
      .map((d) => NmTiltStatus.fromByte(d[0]));

  Stream<NmZeroRoutine> zeroRoutineUpdates({int intervalMs = 250}) =>
      _decodedStream(
        link.subscribe(
          opSubscribe(ApiCat.measurements, NmMeas.zeroRoutine),
          intervalMs: intervalMs,
        ),
        NmZeroRoutine.decode,
      );
}
