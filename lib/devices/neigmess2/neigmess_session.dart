import 'dart:async';

import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_api.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_state.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';

/// An open NeigMess2: the typed [api] plus the always-on feed that merges the
/// Sensors topic and the tilt measurements into one [NeigMessState]. Keeps
/// running for as long as the connection does.
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
    _subs.add(api
        .sensorUpdates()
        .listen((v) => _update(_state.copyWith(sensors: v)), onError: _ignore));
    _subs.add(api
        .tiltUpdates()
        .listen((v) => _update(_state.copyWith(tilt: v)), onError: _ignore));
    _subs.add(api.plateCapUpdates().listen(
        (v) => _update(_state.copyWith(plateCapPf: v)),
        onError: _ignore));
    _subs.add(api.tiltStatusUpdates().listen(
        (v) => _update(_state.copyWith(tiltStatus: v)),
        onError: _ignore));
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
      ]);
      // A push that arrived meanwhile is newer than the seed.
      _update(NeigMessState(
        sensors: _state.sensors ?? results[0] as NmSensors?,
        tilt: _state.tilt ?? results[1] as double?,
        plateCapPf: _state.plateCapPf ?? results[2] as double?,
        tiltStatus: _state.tiltStatus ?? results[3] as NmTiltStatus?,
        offsets: _state.offsets ?? results[4] as NmZeroOffsets?,
      ));
    } catch (_) {
      // Seeding is best effort; the subscriptions fill the state in anyway.
    }
  }

  /// The zero offsets are not pushed; read them again after changing them.
  Future<void> reloadOffsets() async =>
      _update(_state.copyWith(offsets: await api.zeroOffsets()));

  /// The current readings become the zero offsets (EEPROM write).
  Future<void> zeroSensors() async {
    await api.zeroSensors();
    await reloadOffsets();
  }

  Future<void> clearZero() async {
    await api.clearZero();
    await reloadOffsets();
  }

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
