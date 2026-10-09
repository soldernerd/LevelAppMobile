import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/ble/precision_run.dart';
import 'package:inclinometer/calibration/calibration_math.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/flip_cal_provider.dart' show SensorMask;

enum GainStage {
  /// Choose the sensors and the known tilt step.
  setup,

  /// Instrument level / unshimmed — ready to measure the baseline.
  baseline,
  measuringBaseline,

  /// Known tilt step applied — ready to measure.
  shim,
  measuringShim,

  /// Computed; the user reviews and applies.
  review,
  applying,

  /// Re-measuring with the step still applied, to prove the new k.
  verifying,
  done,
  error,
}

class GainCalState {
  const GainCalState({
    this.stage = GainStage.setup,
    this.mask = SensorMask.both,
    this.shimHeightMm = 0.100,
    this.baselineMm = 1000.0,
    this.progress = 0,
    this.disturbed = false,
    this.currentK,
    this.baselineReading,
    this.shimReading,
    this.estimates = const [null, null],
    this.kBefore,
    this.kAfter,
    this.verifyReading,
    this.message,
    this.needsService = false,
  });

  final GainStage stage;
  final int mask;

  /// The known tilt step: a shim of this height (mm) under one end of a
  /// baseline of this length (mm).
  final double shimHeightMm;
  final double baselineMm;

  /// 0..1 of the running precision measurement.
  final double progress;
  final bool disturbed;

  /// Stored k per sensor, 1e-6 per mm/m, as last read.
  final List<int>? currentK;

  /// Precision readings [S1, S2] without / with the step.
  final List<double>? baselineReading;
  final List<double>? shimReading;
  final List<GainEstimate?> estimates;
  final List<int>? kBefore;
  final List<int>? kAfter;

  /// Reading change [S1, S2] re-measured after applying (compare to the
  /// known tilt).
  final List<double>? verifyReading;
  final String? message;
  final bool needsService;

  double get knownTilt => shimTilt(shimHeightMm, baselineMm);

  GainCalState copyWith({
    GainStage? stage,
    int? mask,
    double? shimHeightMm,
    double? baselineMm,
    double? progress,
    bool? disturbed,
    List<int>? currentK,
    List<double>? baselineReading,
    List<double>? shimReading,
    List<GainEstimate?>? estimates,
    List<int>? kBefore,
    List<int>? kAfter,
    List<double>? verifyReading,
    String? message,
    bool? needsService,
    bool keepStatus = false,
  }) =>
      GainCalState(
        stage: stage ?? this.stage,
        mask: mask ?? this.mask,
        shimHeightMm: shimHeightMm ?? this.shimHeightMm,
        baselineMm: baselineMm ?? this.baselineMm,
        progress: progress ?? this.progress,
        disturbed: disturbed ?? this.disturbed,
        currentK: currentK ?? this.currentK,
        baselineReading: baselineReading ?? this.baselineReading,
        shimReading: shimReading ?? this.shimReading,
        estimates: estimates ?? this.estimates,
        kBefore: kBefore ?? this.kBefore,
        kAfter: kAfter ?? this.kAfter,
        verifyReading: verifyReading ?? this.verifyReading,
        message: keepStatus ? this.message : message,
        needsService:
            keepStatus ? this.needsService : (needsService ?? false),
      );
}

/// Gain (sensitivity k) calibration against a known tilt step. Measure a
/// baseline and the same with a shim of known height under one end of a
/// baseline of known length (precision measurements, so each is a clean
/// 2 s window); `kNew = kOld · |Δreading| / tilt` ([estimateGain]).
class GainCalNotifier extends Notifier<GainCalState> {
  PrecisionRun? _run;
  StreamSubscription<ApiPrecisionStatus>? _sub;
  int _gen = 0;

  @override
  GainCalState build() {
    ref.onDispose(() {
      _sub?.cancel();
      final r = _run;
      _run = null;
      if (r != null) unawaited(r.cancel());
    });
    Future(refreshValues);
    return const GainCalState();
  }

  Future<List<int>> _readK() async {
    final api = ref.read(instrumentApiProvider);
    return Future.wait(kSensorK.map(api.readValue));
  }

  Future<void> refreshValues() async {
    try {
      final v = await _readK();
      if (!ref.mounted) return;
      state = state.copyWith(currentK: v, keepStatus: true);
    } catch (_) {}
  }

  void selectSensors(int mask) {
    if (state.stage != GainStage.setup) return;
    state = state.copyWith(mask: mask);
  }

  void setShim({double? heightMm, double? baselineMm}) {
    if (state.stage != GainStage.setup) return;
    state = state.copyWith(shimHeightMm: heightMm, baselineMm: baselineMm);
  }

  /// Leave the setup and go to "measure the baseline".
  void begin() {
    if (state.stage != GainStage.setup || state.knownTilt <= 0) return;
    state = state.copyWith(stage: GainStage.baseline);
  }

  Future<void> measureBaseline() async {
    if (state.stage != GainStage.baseline) return;
    final reading = await _measure(
        GainStage.measuringBaseline, GainStage.baseline);
    if (reading == null) return;
    state = state.copyWith(
      stage: GainStage.shim,
      baselineReading: [reading.tiltS1, reading.tiltS2],
    );
  }

  Future<void> measureShim() async {
    if (state.stage != GainStage.shim) return;
    final reading =
        await _measure(GainStage.measuringShim, GainStage.shim);
    if (reading == null) return;
    final base = state.baselineReading!;
    final tilted = [reading.tiltS1, reading.tiltS2];
    final k = state.currentK ?? await _readK();
    final est = [
      for (var i = 0; i < 2; i++)
        estimateGain(
          kOldMicro: k[i],
          baseline: base[i],
          tilted: tilted[i],
          trueTilt: state.knownTilt,
        ),
    ];
    state = state.copyWith(
      stage: GainStage.review,
      shimReading: tilted,
      currentK: k,
      estimates: est,
    );
  }

  /// One precision measurement; null if it did not give a result (the stage
  /// then returns to [fallback] with a message).
  Future<ApiPrecisionStatus?> _measure(
      GainStage during, GainStage fallback) async {
    final gen = ++_gen;
    final run = PrecisionRun(ref.read(instrumentApiProvider));
    _run = run;
    state = state.copyWith(stage: during, progress: 0, disturbed: false);
    unawaited(_sub?.cancel());
    _sub = run.updates.listen((s) {
      if (gen != _gen || s.phase != PrecisionPhase.running) return;
      state = state.copyWith(
        progress: s.target == 0 ? 0 : s.count / s.target,
        disturbed: s.disturbed,
      );
    });
    try {
      final result = await run.start();
      if (gen != _gen) return null;
      if (result.failed) {
        state = state.copyWith(
          stage: fallback,
          message: 'No quiet 2 s window within 5 s. Keep the table still and '
              'measure again.',
        );
        return null;
      }
      return result;
    } on PrecisionCancelled {
      return null;
    } catch (e) {
      _fail(gen, e);
      return null;
    } finally {
      unawaited(_sub?.cancel());
      _sub = null;
      if (gen == _gen) _run = null;
    }
  }

  void measureAgainBaseline() {
    _cancelRun();
    state = state.copyWith(stage: GainStage.baseline);
  }

  void measureAgainShim() {
    _cancelRun();
    state = state.copyWith(stage: GainStage.shim);
  }

  /// Writes the estimated k of every selected sensor that has a usable one,
  /// then re-measures with the step still applied to prove it.
  Future<void> apply() async {
    if (state.stage != GainStage.review) return;
    final gen = ++_gen;
    final api = ref.read(instrumentApiProvider);
    state = state.copyWith(stage: GainStage.applying);
    try {
      final before = await _readK();
      for (var i = 0; i < 2; i++) {
        final est = state.estimates[i];
        if (!SensorMask.has(state.mask, i) || est == null || !est.inRange) {
          continue;
        }
        await api.writeValue(kSensorK[i], est.kNewMicro);
      }
      final after = await _readK();
      if (gen != _gen) return;
      state = state.copyWith(
        stage: GainStage.verifying,
        kBefore: before,
        kAfter: after,
        currentK: after,
        progress: 0,
      );
    } catch (e) {
      _fail(gen, e);
      return;
    }

    // Verification: the same step must now read as the known tilt.
    final verify = await _measure(GainStage.verifying, GainStage.done);
    if (verify != null) {
      final base = state.baselineReading!;
      state = state.copyWith(
        stage: GainStage.done,
        verifyReading: [
          verify.tiltS1 - base[0],
          verify.tiltS2 - base[1],
        ],
      );
    } else if (state.stage != GainStage.error) {
      state = state.copyWith(stage: GainStage.done);
    }
  }

  void backToStart() {
    _cancelRun();
    state = GainCalState(
      mask: state.mask,
      shimHeightMm: state.shimHeightMm,
      baselineMm: state.baselineMm,
      currentK: state.currentK,
    );
    unawaited(refreshValues());
  }

  void _cancelRun() {
    _gen++;
    final r = _run;
    _run = null;
    _sub?.cancel();
    _sub = null;
    if (r != null) unawaited(r.cancel());
  }

  void _fail(int gen, Object e) {
    if (gen != _gen) return;
    _gen++;
    final needsService = e is ApiException && e.isServiceModeRequired;
    final message = switch (e) {
      ApiException() => e.message,
      LinkException() => e.message,
      _ => 'Something went wrong: $e',
    };
    state = state.copyWith(
      stage: GainStage.error,
      message: message,
      needsService: needsService,
    );
  }
}

final gainCalProvider =
    NotifierProvider.autoDispose<GainCalNotifier, GainCalState>(
  GainCalNotifier.new,
);
