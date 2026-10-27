import 'dart:async';

import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_api.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_state.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';

/// An open NeigMess2: the typed [api] plus the always-on feed that merges the
/// Sensors topic, the tilt measurements and the flip-test zero routine into
/// one [NeigMessState]. Keeps running for as long as the connection does.
///
/// Everything the keys and knobs on the instrument do is available here, so
/// the device can be used from the app alone.
class NeigMessSession extends DeviceSession {
  NeigMessSession({
    required super.driver,
    required super.connection,
    required super.identity,
  }) : api = NeigMessApi(connection) {
    _state = const NeigMessState();
  }

  final NeigMessApi api;

  final _controller = StreamController<NeigMessState>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  late NeigMessState _state;
  bool _started = false;

  /// The last merged snapshot.
  NeigMessState get state => _state;

  /// Emits the merged snapshot on every update of any part; completes when the
  /// session is closed.
  Stream<NeigMessState> get states => _controller.stream;

  /// Subscribes to everything and seeds the state with one GET of each (the
  /// first push only comes one interval after the subscription).
  void start() {
    if (_started) return;
    _started = true;
    _subs.add(
      api.sensorUpdates().listen(
        (v) => _update(_state.copyWith(sensors: v)),
        onError: _ignore,
      ),
    );
    _subs.add(
      api.tiltUpdates().listen(
        (v) => _update(_state.copyWith(tilt: v)),
        onError: _ignore,
      ),
    );
    _subs.add(
      api.plateCapUpdates().listen(
        (v) => _update(_state.copyWith(plateCapPf: v)),
        onError: _ignore,
      ),
    );
    _subs.add(
      api.tiltStatusUpdates().listen(
        (v) => _update(_state.copyWith(tiltStatus: v)),
        onError: _ignore,
      ),
    );
    _subs.add(api.zeroRoutineUpdates().listen(_onRoutine, onError: _ignore));
    unawaited(_seed());
  }

  Future<void> _seed() async {
    try {
      final results = await Future.wait<Object?>([
        api.sensors().then<Object?>((v) => v).catchError((_) => null),
        api.tilt().then<Object?>((v) => v).catchError((_) => null),
        api.plateCapPf().then<Object?>((v) => v).catchError((_) => null),
        api.tiltStatus().then<Object?>((v) => v).catchError((_) => null),
        api.zeroOffsets().then<Object?>((v) => v).catchError((_) => null),
        api.tiltTrim().then<Object?>((v) => v).catchError((_) => null),
        api.neutralCapPf().then<Object?>((v) => v).catchError((_) => null),
        api.zeroRoutine().then<Object?>((v) => v).catchError((_) => null),
      ]);
      // A push that arrived meanwhile is newer than the seed.
      _update(
        NeigMessState(
          sensors: _state.sensors ?? results[0] as NmSensors?,
          tilt: _state.tilt ?? results[1] as double?,
          plateCapPf: _state.plateCapPf ?? results[2] as double?,
          tiltStatus: _state.tiltStatus ?? results[3] as NmTiltStatus?,
          offsets: _state.offsets ?? results[4] as NmZeroOffsets?,
          trim: _state.trim ?? results[5] as NmTiltTrim?,
          neutralCapPf: _state.neutralCapPf ?? results[6] as double?,
          zeroRoutine: _state.zeroRoutine ?? results[7] as NmZeroRoutine?,
        ),
      );
    } catch (_) {
      // Seeding is best effort; the subscriptions fill the state in anyway.
    }
  }

  void _onRoutine(NmZeroRoutine r) {
    final was = _state.zeroRoutine?.state;
    _update(_state.copyWith(zeroRoutine: r));
    // The routine stores a new tilt offset by itself at the end of position 2.
    if (r.state == NmZeroState.done && was != NmZeroState.done) {
      unawaited(reloadCalibration().catchError((_) {}));
    }
  }

  /// The calibrations are not pushed; read them again after changing them.
  Future<void> reloadCalibration() async {
    final offsets = await api.zeroOffsets();
    final trim = await api.tiltTrim();
    final neutral = await api.neutralCapPf();
    _update(
      _state.copyWith(offsets: offsets, trim: trim, neutralCapPf: neutral),
    );
  }

  /// The current readings become the zero offsets (EEPROM write).
  Future<void> zeroSensors() async {
    await api.zeroSensors();
    await reloadCalibration();
  }

  Future<void> clearZero() async {
    await api.clearZero();
    await reloadCalibration();
  }

  /// The two fine-trim knobs (EEPROM write).
  Future<void> setTiltTrim(NmTiltTrim trim) async {
    await api.setTiltTrim(trim);
    await reloadCalibration();
  }

  /// Takes the present plate capacitance as the aligned neutral. RAM only until
  /// [storeCalibration].
  Future<void> captureNeutral() async {
    await api.captureNeutral();
    await reloadCalibration();
  }

  /// Written to the EEPROM (5…100 pF).
  Future<void> setNeutralCapPf(double pf) async {
    await api.setNeutralCapPf(pf);
    await reloadCalibration();
  }

  Future<void> storeCalibration() => api.storeCalibration();

  /// Discards unsaved changes and reloads the EEPROM calibration.
  Future<void> recallCalibration() async {
    await api.recallCalibration();
    await reloadCalibration();
  }

  /// Flip-test zero: starts it, starts each measurement, dismisses the result.
  Future<void> zeroRoutineNext() => api.zeroRoutineNext();

  Future<void> zeroRoutineQuit() => api.zeroRoutineQuit();

  void _update(NeigMessState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void _ignore(Object _) {}

  @override
  Future<void> close() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    await _controller.close();
    await super.close();
  }
}
