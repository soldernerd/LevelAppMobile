import 'dart:async';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';

/// The run was cancelled by the caller.
class PrecisionCancelled implements Exception {
  const PrecisionCancelled();
}

/// One triggered precision measurement, driven by the Procedures PRECISION
/// subscription: start it, watch [updates], await the final status.
///
/// The final status is either a result (`failed == false`) or "no clean
/// window within 5 s" (`failed == true`). Anything else — the device refusing
/// the start, the link dropping, no answer for [timeout] — throws.
///
/// A stale `done` left over from a previous run is ignored until this run has
/// been seen `running` (or [staleGrace] has passed), because the resource
/// stays readable after the last run.
class PrecisionRun {
  PrecisionRun(
    this.api, {
    this.timeout = const Duration(seconds: 9),
    this.staleGrace = const Duration(seconds: 3),
  });

  final InstrumentApi api;
  final Duration timeout;
  final Duration staleGrace;

  final _updates = StreamController<ApiPrecisionStatus>.broadcast();
  final _done = Completer<ApiPrecisionStatus>();

  StreamSubscription<ApiPrecisionStatus>? _sub;
  Timer? _timer;
  bool _sawRunning = false;
  bool _finished = false;
  int _seconds = 0;
  int _quietSeconds = 0;

  /// Every status push (and fallback poll) of this run.
  Stream<ApiPrecisionStatus> get updates => _updates.stream;

  Future<ApiPrecisionStatus> start() {
    _done.future.ignore();
    _sub = api.precisionUpdates().listen(
          _onStatus,
          onError: (Object e) => _fail(e),
        );
    unawaited(_trigger());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return _done.future;
  }

  Future<void> _trigger() async {
    try {
      await api.precisionStart();
    } catch (e) {
      _fail(e);
    }
  }

  void _tick() {
    if (_finished) return;
    _seconds++;
    _quietSeconds++;
    if (_seconds * 1000 > timeout.inMilliseconds) {
      _fail(const LinkException('the measurement did not finish'));
      return;
    }
    // Pushes come about every 250 ms while running; a second of silence means
    // one was lost — ask once.
    if (_quietSeconds >= 1) {
      unawaited(api
          .precisionStatus()
          .then<void>(_onStatus, onError: (Object _) {}));
    }
  }

  void _onStatus(ApiPrecisionStatus s) {
    if (_finished) return;
    _quietSeconds = 0;
    if (!_updates.isClosed) _updates.add(s);
    switch (s.phase) {
      case PrecisionPhase.running:
        _sawRunning = true;
      case PrecisionPhase.done:
        final fresh =
            _sawRunning || _seconds * 1000 >= staleGrace.inMilliseconds;
        if (fresh) _finish(s);
      case PrecisionPhase.idle:
      case PrecisionPhase.unknown:
        break;
    }
  }

  void _finish(ApiPrecisionStatus s) {
    if (_finished) return;
    _finished = true;
    if (!_done.isCompleted) _done.complete(s);
    _cleanup();
  }

  void _fail(Object e) {
    if (_finished) return;
    _finished = true;
    if (!_done.isCompleted) _done.completeError(e);
    _cleanup();
  }

  /// Aborts the run (also on the device). Completes [start] with
  /// [PrecisionCancelled].
  Future<void> cancel() async {
    if (_finished) return;
    _fail(const PrecisionCancelled());
    try {
      await api.precisionCancel();
    } catch (_) {}
  }

  void _cleanup() {
    _timer?.cancel();
    _sub?.cancel();
    _sub = null;
    // Closed on the next turn so listeners still see the final push.
    scheduleMicrotask(() {
      if (!_updates.isClosed) _updates.close();
    });
  }
}
