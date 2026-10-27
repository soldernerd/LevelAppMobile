import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/precision_run.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';

enum PrecisionStage { idle, running, done, failed, error }

class PrecisionUiState {
  const PrecisionUiState({
    this.stage = PrecisionStage.idle,
    this.count = 0,
    this.target = 81,
    this.elapsedMs = 0,
    this.disturbed = false,
    this.tiltS1 = 0,
    this.tiltS2 = 0,
    this.tiltDiff = 0,
    this.message,
  });

  final PrecisionStage stage;

  /// Contiguous clean batches so far / needed.
  final int count;
  final int target;
  final int elapsedMs;

  /// While running: the newest window is not clean (table not quiet yet).
  final bool disturbed;

  /// The result, valid when [stage] is [PrecisionStage.done].
  final double tiltS1, tiltS2, tiltDiff;
  final String? message;

  double get progress => target == 0 ? 0 : (count / target).clamp(0.0, 1.0);
}

/// The precision-measurement flow of the live screen: start it, follow the
/// pushed progress, show the one reliable value (or "no clean window").
class PrecisionNotifier extends Notifier<PrecisionUiState> {
  PrecisionRun? _run;
  StreamSubscription<ApiPrecisionStatus>? _sub;
  int _gen = 0;

  @override
  PrecisionUiState build() {
    ref.onDispose(() {
      _sub?.cancel();
      final run = _run;
      _run = null;
      if (run != null) unawaited(run.cancel());
    });
    return const PrecisionUiState();
  }

  Future<void> start() async {
    if (state.stage == PrecisionStage.running) return;
    final gen = ++_gen;
    unawaited(_sub?.cancel());
    final run = PrecisionRun(ref.read(instrumentApiProvider));
    _run = run;
    state = const PrecisionUiState(stage: PrecisionStage.running);
    _sub = run.updates.listen((s) {
      if (gen != _gen) return;
      if (s.phase == PrecisionPhase.running) {
        state = PrecisionUiState(
          stage: PrecisionStage.running,
          count: s.count,
          target: s.target,
          elapsedMs: s.elapsedMs,
          disturbed: s.disturbed,
        );
      }
    });

    try {
      final result = await run.start();
      if (gen != _gen) return;
      state = result.failed
          ? PrecisionUiState(
              stage: PrecisionStage.failed,
              target: result.target,
              elapsedMs: result.elapsedMs,
              message: 'No quiet window within 5 s. Wait until the table is '
                  'calm and try again.',
            )
          : PrecisionUiState(
              stage: PrecisionStage.done,
              count: result.count,
              target: result.target,
              elapsedMs: result.elapsedMs,
              tiltS1: result.tiltS1,
              tiltS2: result.tiltS2,
              tiltDiff: result.tiltDiff,
            );
    } on PrecisionCancelled {
      // cancel() already reset the state
    } on ApiException catch (e) {
      if (gen == _gen) {
        state = PrecisionUiState(
            stage: PrecisionStage.error, message: e.message);
      }
    } catch (e) {
      if (gen == _gen) {
        state = const PrecisionUiState(
          stage: PrecisionStage.error,
          message: 'Lost contact with the instrument.',
        );
      }
    } finally {
      if (gen == _gen) {
        unawaited(_sub?.cancel());
        _sub = null;
        _run = null;
      }
    }
  }

  Future<void> cancel() async {
    _gen++;
    final run = _run;
    _run = null;
    unawaited(_sub?.cancel());
    _sub = null;
    state = const PrecisionUiState();
    if (run != null) await run.cancel();
  }

  /// Dismiss a result / error without touching the device.
  void reset() {
    if (state.stage == PrecisionStage.running) return;
    state = const PrecisionUiState();
  }
}

final precisionProvider =
    NotifierProvider.autoDispose<PrecisionNotifier, PrecisionUiState>(
  PrecisionNotifier.new,
);
