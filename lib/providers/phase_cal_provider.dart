import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/calibration/calibration_math.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/flip_cal_provider.dart' show SensorMask;

enum PhaseStage {
  /// Choose the sensors, read the current phases.
  select,

  /// Instrument flat / unshimmed — ready to capture the reference.
  reference,
  capturingReference,

  /// Tilt step applied — ready to capture.
  tilted,
  capturingTilted,

  /// Computed; the user reviews and applies.
  review,
  applying,
  done,
  error,
}

class PhaseCalState {
  const PhaseCalState({
    this.stage = PhaseStage.select,
    this.mask = SensorMask.both,
    this.captureProgress = 0,
    this.samples = 0,
    this.current,
    this.estimates = const [null, null],
    this.before,
    this.after,
    this.message,
    this.needsService = false,
  });

  final PhaseStage stage;
  final int mask;

  /// 0..1 of the capture time.
  final double captureProgress;

  /// Batches received in the running capture.
  final int samples;

  /// Stored phases, centidegrees, [S1, S2], as last read.
  final List<int>? current;

  /// The computed phase per sensor (null if it could not be estimated).
  final List<PhaseEstimate?> estimates;
  final List<int>? before;
  final List<int>? after;
  final String? message;
  final bool needsService;

  PhaseCalState copyWith({
    PhaseStage? stage,
    int? mask,
    double? captureProgress,
    int? samples,
    List<int>? current,
    List<PhaseEstimate?>? estimates,
    List<int>? before,
    List<int>? after,
    String? message,
    bool? needsService,
    bool keepStatus = false,
  }) =>
      PhaseCalState(
        stage: stage ?? this.stage,
        mask: mask ?? this.mask,
        captureProgress: captureProgress ?? this.captureProgress,
        samples: samples ?? this.samples,
        current: current ?? this.current,
        estimates: estimates ?? this.estimates,
        before: before ?? this.before,
        after: after ?? this.after,
        message: keepStatus ? this.message : message,
        needsService:
            keepStatus ? this.needsService : (needsService ?? false),
      );
}

/// Phase calibration. Each sensor's tilt signal lies along `e^{jφ}` in the
/// complex plane of `u = S / (A − B)`. Capture the phasor stream flat and
/// again with a known tilt step; the direction of the change in `u` is φ —
/// independent of the stored phase and of the size of the step. See
/// [estimatePhase].
class PhaseCalNotifier extends Notifier<PhaseCalState> {
  /// Length of one capture. ~40 batches/s, so ~325 batches.
  static const captureDuration = Duration(seconds: 8);
  static const minSamples = 60;

  final List<ComplexStats> _flat = [ComplexStats(), ComplexStats()];
  final List<ComplexStats> _tilt = [ComplexStats(), ComplexStats()];

  StreamSubscription<ApiPhasorEntry>? _sub;
  Timer? _timer;
  int _gen = 0;

  @override
  PhaseCalState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
    });
    Future(refreshValues);
    return const PhaseCalState();
  }

  Future<List<int>> _readPhases() async {
    final api = ref.read(instrumentApiProvider);
    return Future.wait(kSensorPhase.map(api.readValue));
  }

  Future<void> refreshValues() async {
    try {
      final v = await _readPhases();
      if (!ref.mounted) return;
      state = state.copyWith(current: v, keepStatus: true);
    } catch (_) {}
  }

  void selectSensors(int mask) {
    if (state.stage != PhaseStage.select) return;
    state = state.copyWith(mask: mask);
  }

  /// Leave the selection and go to "capture the reference".
  void begin() {
    if (state.stage != PhaseStage.select) return;
    state = state.copyWith(stage: PhaseStage.reference);
  }

  Future<void> captureReference() async {
    if (state.stage != PhaseStage.reference) return;
    await _capture(
        PhaseStage.capturingReference, PhaseStage.tilted, _flat);
  }

  Future<void> captureTilted() async {
    if (state.stage != PhaseStage.tilted) return;
    await _capture(PhaseStage.capturingTilted, PhaseStage.review, _tilt);
  }

  Future<void> _capture(
    PhaseStage during,
    PhaseStage next,
    List<ComplexStats> into,
  ) async {
    final gen = ++_gen;
    for (final s in into) {
      s.reset();
    }
    state = state.copyWith(stage: during, captureProgress: 0, samples: 0);

    var ticks = 0;
    final total = captureDuration.inMilliseconds ~/ 200;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (gen != _gen) {
        t.cancel();
        return;
      }
      ticks++;
      state = state.copyWith(captureProgress: (ticks / total).clamp(0.0, 1.0));
      if (ticks >= total) {
        t.cancel();
        unawaited(_endCapture(gen, next, into));
      }
    });

    unawaited(_sub?.cancel());
    final api = ref.read(instrumentApiProvider);
    _sub = api.phasorStream().listen(
      (e) {
        if (gen != _gen) return;
        // u = S / D with D = A − B
        final dr = e.iA - e.iB, di = e.qA - e.qB;
        final u1 = complexDivide(e.iS1, e.qS1, dr, di);
        final u2 = complexDivide(e.iS2, e.qS2, dr, di);
        if (u1 == null || u2 == null) return;
        into[0].add(u1.$1, u1.$2);
        into[1].add(u2.$1, u2.$2);
        if (into[0].n % 8 == 0) {
          state = state.copyWith(samples: into[0].n);
        }
      },
      onError: (Object e) => _fail(gen, e),
    );
  }

  Future<void> _endCapture(
    int gen,
    PhaseStage next,
    List<ComplexStats> into,
  ) async {
    if (gen != _gen) return;
    unawaited(_sub?.cancel());
    _sub = null;
    if (into[0].n < minSamples) {
      _fail(
        gen,
        const LinkException('too few phasor batches arrived — is the '
            'tilt measurement running?'),
      );
      return;
    }
    if (next == PhaseStage.review) {
      final est = [
        estimatePhase(_flat[0], _tilt[0]),
        estimatePhase(_flat[1], _tilt[1]),
      ];
      state = state.copyWith(
        stage: PhaseStage.review,
        samples: into[0].n,
        estimates: est,
      );
    } else {
      state = state.copyWith(stage: next, samples: into[0].n);
    }
  }

  /// Back to "capture the reference" (e.g. the table was bumped).
  void redoReference() {
    _gen++;
    _sub?.cancel();
    _timer?.cancel();
    state = state.copyWith(stage: PhaseStage.reference);
  }

  void redoTilted() {
    _gen++;
    _sub?.cancel();
    _timer?.cancel();
    state = state.copyWith(stage: PhaseStage.tilted);
  }

  /// Writes the estimated phase of every selected sensor that has a usable
  /// one. Needs service mode.
  Future<void> apply() async {
    if (state.stage != PhaseStage.review) return;
    final gen = ++_gen;
    final api = ref.read(instrumentApiProvider);
    state = state.copyWith(stage: PhaseStage.applying);
    try {
      final before = await _readPhases();
      for (var i = 0; i < 2; i++) {
        final est = state.estimates[i];
        if (!SensorMask.has(state.mask, i) || est == null || !est.inRange) {
          continue;
        }
        await api.writeValue(kSensorPhase[i], est.centiDegrees);
      }
      final after = await _readPhases();
      if (gen != _gen) return;
      state = state.copyWith(
        stage: PhaseStage.done,
        before: before,
        after: after,
        current: after,
      );
    } catch (e) {
      _fail(gen, e);
    }
  }

  void backToStart() {
    _gen++;
    _sub?.cancel();
    _timer?.cancel();
    state = state.copyWith(stage: PhaseStage.select, estimates: const [null, null]);
    unawaited(refreshValues());
  }

  void _fail(int gen, Object e) {
    if (gen != _gen) return;
    _gen++;
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    final needsService = e is ApiException && e.isServiceModeRequired;
    final message = switch (e) {
      ApiException() => e.message,
      LinkException() => e.message,
      _ => 'Something went wrong: $e',
    };
    state = state.copyWith(
      stage: PhaseStage.error,
      message: message,
      needsService: needsService,
    );
  }
}

final phaseCalProvider =
    NotifierProvider.autoDispose<PhaseCalNotifier, PhaseCalState>(
  PhaseCalNotifier.new,
);
