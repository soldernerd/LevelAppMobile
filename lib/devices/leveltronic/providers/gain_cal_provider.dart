import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inclinometer/devices/leveltronic/api_catalog.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/precision_run.dart';
import 'package:inclinometer/devices/leveltronic/calibration/calibration_math.dart';
import 'package:inclinometer/devices/leveltronic/providers/info_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';
import 'package:inclinometer/devices/leveltronic/calibration/sensor_mask.dart';

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
  done,
  error,
}

class GainCalState {
  const GainCalState({
    this.stage = GainStage.setup,
    this.mask = SensorMask.both,
    this.shimHeightMm = const [0.100, 0.100],
    this.baselineMm = const [150.0, 150.0],
    this.progress = 0,
    this.disturbed = false,
    this.currentK,
    this.baselineReading,
    this.shimReading,
    this.estimates = const [null, null],
    this.kBefore,
    this.kAfter,
    this.message,
    this.needsService = false,
  });

  final GainStage stage;
  final int mask;

  /// Per-sensor shim setup: [S1, S2]. A shim of shimHeightMm[i] mm under one
  /// end of a baseline of baselineMm[i] mm gives the known tilt for sensor i.
  final List<double> shimHeightMm;
  final List<double> baselineMm;

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

  final String? message;
  final bool needsService;

  List<double> get knownTilts =>
      [for (var i = 0; i < 2; i++) shimTilt(shimHeightMm[i], baselineMm[i])];

  GainCalState copyWith({
    GainStage? stage,
    int? mask,
    List<double>? shimHeightMm,
    List<double>? baselineMm,
    double? progress,
    bool? disturbed,
    List<int>? currentK,
    List<double>? baselineReading,
    List<double>? shimReading,
    List<GainEstimate?>? estimates,
    List<int>? kBefore,
    List<int>? kAfter,
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
  String? _serial;

  static String _keyHeight(String s, int i) => 'gain_cal_shim_height_${s}_$i';
  static String _keyBaseline(String s, int i) => 'gain_cal_baseline_${s}_$i';

  @override
  GainCalState build() {
    ref.onDispose(() {
      _sub?.cancel();
      final r = _run;
      _run = null;
      if (r != null) unawaited(r.cancel());
    });
    final serial = ref.watch(identityProvider)?.serial;
    _serial = serial;
    if (serial != null) unawaited(_loadShim(serial));
    Future(refreshValues);
    return const GainCalState();
  }

  Future<void> _loadShim(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final h = List<double>.from(state.shimHeightMm);
      final b = List<double>.from(state.baselineMm);
      var changed = false;
      for (var i = 0; i < 2; i++) {
        final hv = prefs.getDouble(_keyHeight(serial, i));
        final bv = prefs.getDouble(_keyBaseline(serial, i));
        if (hv != null) { h[i] = hv; changed = true; }
        if (bv != null) { b[i] = bv; changed = true; }
      }
      if (!ref.mounted || _serial != serial) return;
      if (changed) {
        state = state.copyWith(shimHeightMm: h, baselineMm: b, keepStatus: true);
      }
    } catch (_) {}
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

  void setShimForSensor(int sensor, {double? heightMm, double? baselineMm}) {
    if (state.stage != GainStage.setup) return;
    final h = List<double>.from(state.shimHeightMm);
    final b = List<double>.from(state.baselineMm);
    if (heightMm != null) h[sensor] = heightMm;
    if (baselineMm != null) b[sensor] = baselineMm;
    state = state.copyWith(shimHeightMm: h, baselineMm: b);
    _saveShim();
  }

  Future<void> _saveShim() async {
    final serial = _serial;
    if (serial == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 2; i++) {
        // A cleared or half-typed field reads as 0; that is not a setup worth
        // keeping for the next visit.
        final h = state.shimHeightMm[i], b = state.baselineMm[i];
        if (h <= 0 || b <= 0) continue;
        await prefs.setDouble(_keyHeight(serial, i), h);
        await prefs.setDouble(_keyBaseline(serial, i), b);
      }
    } catch (_) {}
  }

  /// Leave the setup and go to "measure the baseline".
  void begin() {
    if (state.stage != GainStage.setup) return;
    final tilts = state.knownTilts;
    for (var i = 0; i < 2; i++) {
      if (SensorMask.has(state.mask, i) && tilts[i] <= 0) return;
    }
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
    final gen = _gen;
    final base = state.baselineReading!;
    final tilted = [reading.tiltS1, reading.tiltS2];
    final List<int> k;
    try {
      k = state.currentK ?? await _readK();
    } catch (e) {
      _fail(gen, e);
      return;
    }
    if (gen != _gen) return;
    final est = [
      for (var i = 0; i < 2; i++)
        estimateGain(
          kOldMicro: k[i],
          baseline: base[i],
          tilted: tilted[i],
          trueTilt: state.knownTilts[i],
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

  /// Writes the estimated k of every selected sensor that has a usable one.
  /// Nothing is measured again: the new k is only stored.
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
        stage: GainStage.done,
        kBefore: before,
        kAfter: after,
        currentK: after,
        progress: 0,
      );
    } catch (e) {
      _fail(gen, e);
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
