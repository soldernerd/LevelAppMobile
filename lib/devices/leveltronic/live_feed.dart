import 'dart:async';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';
import 'package:inclinometer/devices/leveltronic/device_state.dart';

/// Keeps the three always-on subscriptions (LIVE, STATUS, ENV) and merges
/// their pushes into one [DeviceState] stream. One GET of each seeds the
/// state at once instead of waiting for the first push. If the tilt
/// demodulation turns out to be stopped it is started once.
class LiveFeed {
  LiveFeed(this.api);

  final InstrumentApi api;

  final _controller = StreamController<DeviceState>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  DeviceState _state = const DeviceState();
  bool _started = false;
  bool _demodChecked = false;

  /// Emits the merged state on every update of any part.
  Stream<DeviceState> get stream => _controller.stream;

  /// The last merged state.
  DeviceState get state => _state;

  /// Called once when the link goes down (a subscription stream completed).
  void Function()? onLinkDown;

  void start() {
    if (_started) return;
    _started = true;

    _subs.add(api.liveUpdates().listen(
          (v) => _update(_state.copyWith(live: v)),
          onError: _ignore,
          onDone: _linkDown,
        ));
    _subs.add(api.statusUpdates().listen(
          _onStatus,
          onError: _ignore,
        ));
    _subs.add(api.envUpdates().listen(
          (v) => _update(_state.copyWith(env: v)),
          onError: _ignore,
        ));

    unawaited(_seed());
  }

  Future<void> _seed() async {
    try {
      final status = await api.status();
      _onStatus(status);
      final results = await Future.wait<Object?>([
        api.live().then<Object?>((v) => v).catchError((_) => null),
        api.env().then<Object?>((v) => v).catchError((_) => null),
      ]);
      final live = results[0] as ApiLive?;
      final env = results[1] as ApiEnvironmental?;
      _update(_state.copyWith(live: _state.live ?? live, env: _state.env ?? env));
    } catch (_) {
      // Seeding is best effort; the subscriptions fill the state in anyway.
    }
  }

  void _onStatus(ApiSystemState s) {
    _update(_state.copyWith(status: s));
    // The demodulation runs from boot; if a previous host stopped it, start
    // it again once so the live screen has something to show.
    if (!_demodChecked) {
      _demodChecked = true;
      if (!s.demodRunning && !s.bulkActive) {
        unawaited(api.setTiltDemod(true).catchError((_) {}));
      }
    }
  }

  void _update(DeviceState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void _ignore(Object _) {}

  void _linkDown() {
    final cb = onLinkDown;
    onLinkDown = null;
    cb?.call();
  }

  Future<void> stop() async {
    onLinkDown = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    await _controller.close();
  }
}
