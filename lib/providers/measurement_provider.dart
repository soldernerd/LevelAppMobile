// lib/providers/measurement_provider.dart
// Riverpod notifiers driving the two triggered instrument actions: zero
// calibration (180° reversal test) and the triggered precision measurement.
//
// Both wire actions (EXECUTE ...) to a client-side poll loop (GET .../status)
// since neither is subscribable in this firmware build — see
// docs/api-reference.md's "Zero calibration" / "Triggered precision
// measurement" sections. All BLE access goes through [bleManagerProvider];
// no flutter_blue_plus import here (CLAUDE.md architecture rule).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// How often the UI polls device-side progress while a run is active.
const _pollInterval = Duration(milliseconds: 200);

/// Consecutive failed polls (comms hiccup, not a real device response)
/// tolerated before giving up and surfacing an error — ~2 s at [_pollInterval].
const _maxConsecutivePollFailures = 10;

String _statusMessage(Api2Status status) => switch (status) {
      Api2Status.ok => 'OK',
      Api2Status.busyResource =>
        'The instrument is busy — make sure live readings are active '
            '(displacement OK) and no other measurement is already running.',
      Api2Status.busyExclusive =>
        'Another operation is using the sensor right now. Try again shortly.',
      Api2Status.unknown =>
        'Lost contact with the instrument. Check the connection and try again.',
      _ => 'The instrument rejected the request (${status.name}).',
    };

// ---------------------------------------------------------------------------
// Zero calibration
// ---------------------------------------------------------------------------

enum ZeroCalUiPhase {
  idle,
  runningStep1,
  awaitingRotation,
  runningStep2,
  success,
  error,
}

class ZeroCalUiState {
  const ZeroCalUiState({
    this.phase = ZeroCalUiPhase.idle,
    this.progress = 0,
    this.target = 32,
    this.errorMessage,
  });

  final ZeroCalUiPhase phase;
  final int progress;
  final int target;
  final String? errorMessage;

  ZeroCalUiState copyWith({
    ZeroCalUiPhase? phase,
    int? progress,
    int? target,
    String? errorMessage,
  }) {
    return ZeroCalUiState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      target: target ?? this.target,
      errorMessage: errorMessage,
    );
  }
}

/// Drives the 180°-reversal zero-calibration flow.
///
/// Step 1 and step 2 each EXECUTE then poll `GET Raw data 0x7/0x03` until the
/// firmware phase advances — see [ZeroCalPhase] doc for why "step2Running
/// then straight to idle" (skipping the transient resultReady) counts as
/// success.
class ZeroCalibrationNotifier extends Notifier<ZeroCalUiState> {
  Timer? _poller;
  int _pollFailures = 0;

  /// Guards against overlapping polls: a slow/dropped round trip must not
  /// let a second request for the same opcode go out before the first
  /// resolves (see [RealBleManager._request] for what that races with).
  bool _pollInFlight = false;

  /// Bumped by every action that makes prior polls stale ([start],
  /// [confirmRotated], [cancel], [reset]). A [_poll] callback that resolves
  /// after its generation has moved on is discarded — this stops a poll
  /// that was in flight when the user hit Cancel (or a fresh run started)
  /// from landing a late update (or a manufactured timeout error) on top of
  /// whatever state came after it.
  int _generation = 0;

  @override
  ZeroCalUiState build() {
    ref.onDispose(() => _poller?.cancel());
    return const ZeroCalUiState();
  }

  Future<void> start() async {
    if (state.phase != ZeroCalUiPhase.idle &&
        state.phase != ZeroCalUiPhase.error) {
      return;
    }
    final gen = ++_generation;
    _poller?.cancel();
    state = const ZeroCalUiState(phase: ZeroCalUiPhase.runningStep1);
    final status =
        await ref.read(bleManagerProvider).zeroCalibrationStep1();
    if (gen != _generation) return; // superseded while awaiting the EXECUTE
    if (status != Api2Status.ok) {
      state = ZeroCalUiState(
        phase: ZeroCalUiPhase.error,
        errorMessage: _statusMessage(status),
      );
      return;
    }
    _startPolling(gen);
  }

  Future<void> confirmRotated() async {
    if (state.phase != ZeroCalUiPhase.awaitingRotation) return;
    final gen = ++_generation;
    _poller?.cancel();
    state = state.copyWith(phase: ZeroCalUiPhase.runningStep2, progress: 0);
    final status =
        await ref.read(bleManagerProvider).zeroCalibrationStep2();
    if (gen != _generation) return;
    if (status != Api2Status.ok) {
      state = ZeroCalUiState(
        phase: ZeroCalUiPhase.error,
        errorMessage: _statusMessage(status),
      );
      return;
    }
    _startPolling(gen);
  }

  Future<void> cancel() async {
    _generation++;
    _poller?.cancel();
    await ref.read(bleManagerProvider).zeroCalibrationCancel();
    state = const ZeroCalUiState();
  }

  /// Returns to [ZeroCalUiPhase.idle] without touching the device — used to
  /// dismiss a success/error screen.
  void reset() {
    _generation++;
    _poller?.cancel();
    state = const ZeroCalUiState();
  }

  void _startPolling(int gen) {
    _poller?.cancel();
    _pollFailures = 0;
    // Deliberately not resetting _pollInFlight: if a poll from a just-ended
    // phase is still in flight, let its own `finally` clear the flag once it
    // resolves (and gets discarded by the generation check) rather than
    // risking two requests for the same opcode in flight at once.
    _poller = Timer.periodic(_pollInterval, (_) => _poll(gen));
  }

  Future<void> _poll(int gen) async {
    if (_pollInFlight) return; // previous round trip hasn't resolved yet
    _pollInFlight = true;
    try {
      final status = await ref.read(bleManagerProvider).pollZeroCalibration();
      if (gen != _generation) return; // a newer run/cancel/reset happened

      if (status == null) {
        _pollFailures++;
        if (_pollFailures >= _maxConsecutivePollFailures) {
          _poller?.cancel();
          state = ZeroCalUiState(
            phase: ZeroCalUiPhase.error,
            errorMessage: _statusMessage(Api2Status.unknown),
          );
        }
        return;
      }
      _pollFailures = 0;

      switch (status.phase) {
        case ZeroCalPhase.step1Running:
          state = state.copyWith(
            phase: ZeroCalUiPhase.runningStep1,
            progress: status.progress,
            target: status.target,
          );
        case ZeroCalPhase.step1Done:
          _poller?.cancel();
          state = state.copyWith(
            phase: ZeroCalUiPhase.awaitingRotation,
            progress: status.target,
            target: status.target,
          );
        case ZeroCalPhase.step2Running:
          state = state.copyWith(
            phase: ZeroCalUiPhase.runningStep2,
            progress: status.progress,
            target: status.target,
          );
        case ZeroCalPhase.resultReady:
        case ZeroCalPhase.idle:
          // The device applies step 2 within one tick (resultReady is
          // transient) — observing idle right after runningStep2 is success.
          if (state.phase == ZeroCalUiPhase.runningStep2) {
            _poller?.cancel();
            state = state.copyWith(
              phase: ZeroCalUiPhase.success,
              progress: status.target,
            );
          }
        case ZeroCalPhase.unknown:
          break;
      }
    } finally {
      _pollInFlight = false;
    }
  }
}

final zeroCalibrationProvider =
    NotifierProvider<ZeroCalibrationNotifier, ZeroCalUiState>(
  ZeroCalibrationNotifier.new,
);

// ---------------------------------------------------------------------------
// Triggered precision measurement
// ---------------------------------------------------------------------------

enum PrecisionUiPhase { idle, running, done, error }

class PrecisionUiState {
  const PrecisionUiState({
    this.phase = PrecisionUiPhase.idle,
    this.count1 = 0,
    this.count2 = 0,
    this.target = 64,
    this.elapsedMs = 0,
    this.timedOut = false,
    this.delta1Mm = 0.0,
    this.delta2Mm = 0.0,
    this.errorMessage,
  });

  final PrecisionUiPhase phase;
  final int count1;
  final int count2;
  final int target;
  final int elapsedMs;
  final bool timedOut;
  final double delta1Mm;
  final double delta2Mm;
  final String? errorMessage;

  /// 0.0–1.0, the slower of the two sensors — a fair single progress bar.
  double get progress =>
      target == 0 ? 0.0 : (count1 < count2 ? count1 : count2) / target;

  PrecisionUiState copyWith({
    PrecisionUiPhase? phase,
    int? count1,
    int? count2,
    int? target,
    int? elapsedMs,
    bool? timedOut,
    double? delta1Mm,
    double? delta2Mm,
    String? errorMessage,
  }) {
    return PrecisionUiState(
      phase: phase ?? this.phase,
      count1: count1 ?? this.count1,
      count2: count2 ?? this.count2,
      target: target ?? this.target,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      timedOut: timedOut ?? this.timedOut,
      delta1Mm: delta1Mm ?? this.delta1Mm,
      delta2Mm: delta2Mm ?? this.delta2Mm,
      errorMessage: errorMessage,
    );
  }
}

/// Drives the "trigger it, device reports one reliable value" flow.
class PrecisionMeasurementNotifier extends Notifier<PrecisionUiState> {
  Timer? _poller;
  int _pollFailures = 0;

  /// Guards against overlapping polls — see [ZeroCalibrationNotifier] for why.
  bool _pollInFlight = false;

  /// Bumped by [start], [cancel] and [reset]; see [ZeroCalibrationNotifier].
  int _generation = 0;

  @override
  PrecisionUiState build() {
    ref.onDispose(() => _poller?.cancel());
    return const PrecisionUiState();
  }

  Future<void> start() async {
    final gen = ++_generation;
    _poller?.cancel();
    state = const PrecisionUiState(phase: PrecisionUiPhase.running);
    final status =
        await ref.read(bleManagerProvider).startPrecisionMeasurement();
    if (gen != _generation) return; // superseded while awaiting the EXECUTE
    if (status != Api2Status.ok) {
      state = PrecisionUiState(
        phase: PrecisionUiPhase.error,
        errorMessage: _statusMessage(status),
      );
      return;
    }
    _pollFailures = 0;
    _poller = Timer.periodic(_pollInterval, (_) => _poll(gen));
  }

  Future<void> cancel() async {
    _generation++;
    _poller?.cancel();
    await ref.read(bleManagerProvider).cancelPrecisionMeasurement();
    state = const PrecisionUiState();
  }

  /// Returns to [PrecisionUiPhase.idle] without touching the device.
  void reset() {
    _generation++;
    _poller?.cancel();
    state = const PrecisionUiState();
  }

  Future<void> _poll(int gen) async {
    if (_pollInFlight) return; // previous round trip hasn't resolved yet
    _pollInFlight = true;
    try {
      final status =
          await ref.read(bleManagerProvider).pollPrecisionMeasurement();
      if (gen != _generation) return; // a newer run/cancel/reset happened

      if (status == null) {
        _pollFailures++;
        if (_pollFailures >= _maxConsecutivePollFailures) {
          _poller?.cancel();
          state = PrecisionUiState(
            phase: PrecisionUiPhase.error,
            errorMessage: _statusMessage(Api2Status.unknown),
          );
        }
        return;
      }
      _pollFailures = 0;

      switch (status.phase) {
        case PrecisionPhase.running:
          state = state.copyWith(
            phase: PrecisionUiPhase.running,
            count1: status.count1,
            count2: status.count2,
            target: status.target,
            elapsedMs: status.elapsedMs,
          );
        case PrecisionPhase.done:
          _poller?.cancel();
          state = state.copyWith(
            phase: PrecisionUiPhase.done,
            count1: status.count1,
            count2: status.count2,
            target: status.target,
            elapsedMs: status.elapsedMs,
            timedOut: status.timedOut,
            delta1Mm: status.delta1Mm,
            delta2Mm: status.delta2Mm,
          );
        case PrecisionPhase.idle:
        case PrecisionPhase.unknown:
          break;
      }
    } finally {
      _pollInFlight = false;
    }
  }
}

final precisionMeasurementProvider =
    NotifierProvider<PrecisionMeasurementNotifier, PrecisionUiState>(
  PrecisionMeasurementNotifier.new,
);
