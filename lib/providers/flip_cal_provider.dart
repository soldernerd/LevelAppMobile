import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Which sensors a calibration run covers: bit0 S1, bit1 S2.
class SensorMask {
  static const s1 = 1;
  static const s2 = 2;
  static const both = 3;

  static bool has(int mask, int sensorIndex) => mask & (1 << sensorIndex) != 0;
  static String label(int mask) => switch (mask) {
        s1 => 'S1',
        s2 => 'S2',
        _ => 'S1 and S2',
      };
}

/// Calibration values of the two sensors at one moment.
class ZeroSnapshot {
  const ZeroSnapshot(this.zeroPpm, this.kMicro);

  /// zero in ppm of the ratio, per sensor.
  final List<int> zeroPpm;

  /// k in 1e-6 per mm/m, per sensor.
  final List<int> kMicro;

  /// The level point in mm/m — `zero / k`, what the display would read with
  /// the instrument perfectly level.
  double zeroMmPerM(int i) => zeroPpm[i] / kMicro[i];
}

/// One finished flip-calibration run.
class FlipRun {
  const FlipRun(this.mask, this.before, this.after);
  final int mask;
  final ZeroSnapshot before;
  final ZeroSnapshot after;
}

enum FlipStage {
  /// Choose the sensors, read the current values.
  select,

  /// Step 1 running (instrument in its starting position).
  measuring1,

  /// Step 1 done — turn the instrument by 180° and continue.
  turn,

  /// Step 2 running.
  measuring2,

  /// Done: before / after values.
  result,

  error,
}

class FlipCalState {
  const FlipCalState({
    this.stage = FlipStage.select,
    this.mask = SensorMask.both,
    this.progress = 0,
    this.target = 64,
    this.current,
    this.runs = const [],
    this.message,
    this.needsService = false,
  });

  final FlipStage stage;
  final int mask;
  final int progress;
  final int target;

  /// The values as last read (before the run in the select stage).
  final ZeroSnapshot? current;

  /// Finished runs, newest last — comparing two consecutive ones is the
  /// manual's "repeat once and check that two runs agree".
  final List<FlipRun> runs;
  final String? message;
  final bool needsService;

  FlipRun? get lastRun => runs.isEmpty ? null : runs.last;

  FlipCalState copyWith({
    FlipStage? stage,
    int? mask,
    int? progress,
    int? target,
    ZeroSnapshot? current,
    List<FlipRun>? runs,
    String? message,
    bool? needsService,
    bool keepStatus = false,
  }) =>
      FlipCalState(
        stage: stage ?? this.stage,
        mask: mask ?? this.mask,
        progress: progress ?? this.progress,
        target: target ?? this.target,
        current: current ?? this.current,
        runs: runs ?? this.runs,
        message: keepStatus ? this.message : message,
        needsService:
            keepStatus ? this.needsService : (needsService ?? false),
      );
}

/// The flip (zero) calibration wizard: step 1, turn by 180°, step 2, show
/// the stored zero before and after. Driven by the Procedures ZERO_CAL
/// subscription.
class FlipCalNotifier extends Notifier<FlipCalState> {
  StreamSubscription<ApiZeroCalStatus>? _sub;
  int _gen = 0;
  ZeroSnapshot? _before;
  int _runMask = SensorMask.both;
  bool _sawStep2 = false;

  @override
  FlipCalState build() {
    ref.onDispose(() {
      _sub?.cancel();
    });
    Future(refreshValues);
    return const FlipCalState();
  }

  Future<ZeroSnapshot> _read() async {
    final api = ref.read(instrumentApiProvider);
    final zero = await Future.wait(kSensorZero.map(api.readValue));
    final k = await Future.wait(kSensorK.map(api.readValue));
    return ZeroSnapshot(zero, k);
  }

  Future<void> refreshValues() async {
    try {
      final snap = await _read();
      if (!ref.mounted) return;
      state = state.copyWith(current: snap, keepStatus: true);
    } catch (_) {
      // The select stage shows "—" until the next try.
    }
  }

  void selectSensors(int mask) {
    if (state.stage != FlipStage.select && state.stage != FlipStage.result) {
      return;
    }
    state = state.copyWith(mask: mask, stage: FlipStage.select);
  }

  /// Step 1.
  Future<void> start() async {
    final gen = ++_gen;
    final api = ref.read(instrumentApiProvider);
    _runMask = state.mask;
    _sawStep2 = false;
    try {
      _before = await _read();
      if (gen != _gen) return;
      state = state.copyWith(
        stage: FlipStage.measuring1,
        progress: 0,
        current: _before,
      );
      unawaited(_sub?.cancel());
      _sub = api.zeroCalUpdates().listen(
            (s) => _onStatus(gen, s),
            onError: (Object e) => _fail(gen, e),
          );
      await api.zeroCalStep1(_runMask);
    } catch (e) {
      _fail(gen, e);
    }
  }

  /// Step 2, after the user turned the instrument by 180°.
  Future<void> confirmTurned() async {
    if (state.stage != FlipStage.turn) return;
    final gen = _gen;
    state = state.copyWith(stage: FlipStage.measuring2, progress: 0);
    try {
      await ref.read(instrumentApiProvider).zeroCalStep2();
    } catch (e) {
      _fail(gen, e);
    }
  }

  Future<void> cancel() async {
    _gen++;
    unawaited(_sub?.cancel());
    _sub = null;
    state = state.copyWith(stage: FlipStage.select, progress: 0);
    try {
      await ref.read(instrumentApiProvider).zeroCalCancel();
    } catch (_) {}
    unawaited(refreshValues());
  }

  /// Back to the sensor selection after a result or an error.
  void backToStart() {
    state = state.copyWith(stage: FlipStage.select, progress: 0);
    unawaited(refreshValues());
  }

  void _onStatus(int gen, ApiZeroCalStatus s) {
    if (gen != _gen) return;
    switch (s.phase) {
      case ZeroCalPhase.step1Running:
        if (state.stage == FlipStage.measuring1) {
          state = state.copyWith(progress: s.progress, target: s.target);
        }
      case ZeroCalPhase.step1Done:
        if (state.stage == FlipStage.measuring1) {
          state = state.copyWith(
              stage: FlipStage.turn, progress: s.target, target: s.target);
        }
      case ZeroCalPhase.step2Running:
        _sawStep2 = true;
        if (state.stage == FlipStage.measuring2) {
          state = state.copyWith(progress: s.progress, target: s.target);
        }
      case ZeroCalPhase.resultReady:
      case ZeroCalPhase.idle:
        // The result is stored automatically and the phase falls back to idle
        // (resultReady is transient). Idle after step 2 means done.
        if (state.stage == FlipStage.measuring2 && _sawStep2) {
          unawaited(_finish(gen));
        }
      case ZeroCalPhase.unknown:
        break;
    }
  }

  Future<void> _finish(int gen) async {
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      final after = await _read();
      if (gen != _gen) return;
      final run = FlipRun(_runMask, _before ?? after, after);
      state = state.copyWith(
        stage: FlipStage.result,
        current: after,
        runs: [...state.runs, run],
      );
    } catch (e) {
      _fail(gen, e);
    }
  }

  void _fail(int gen, Object e) {
    if (gen != _gen) return;
    _gen++;
    _sub?.cancel();
    _sub = null;
    final needsService = e is ApiException && e.isServiceModeRequired;
    final message = switch (e) {
      ApiException() => e.message,
      LinkException() => 'Lost contact with the instrument.',
      _ => 'Something went wrong: $e',
    };
    state = state.copyWith(
      stage: FlipStage.error,
      message: message,
      needsService: needsService,
    );
  }
}

final flipCalProvider =
    NotifierProvider.autoDispose<FlipCalNotifier, FlipCalState>(
  FlipCalNotifier.new,
);
