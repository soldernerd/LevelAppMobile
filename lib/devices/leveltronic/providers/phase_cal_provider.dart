import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/api_catalog.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/calibration/calibration_math.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';
import 'package:inclinometer/devices/leveltronic/calibration/sensor_mask.dart';

/// Which tilts the phase calibration measures.
enum PhaseMode {
  /// A clear positive and a clear negative tilt: the zero offset cancels and
  /// the two phases are 180° apart in theory. The most accurate.
  both,

  /// One clear positive tilt only.
  positiveOnly,

  /// One clear negative tilt only.
  negativeOnly;

  /// The tilts to capture, in order.
  List<PhaseTilt> get tilts => switch (this) {
        PhaseMode.both => const [PhaseTilt.positive, PhaseTilt.negative],
        PhaseMode.positiveOnly => const [PhaseTilt.positive],
        PhaseMode.negativeOnly => const [PhaseTilt.negative],
      };
}

/// The direction of a tilt: positive is the one the instrument reads as a
/// positive tilt (the front, the end with the red mark, up).
enum PhaseTilt { positive, negative }

enum PhaseStage {
  /// Choose the sensors and the tilts, read the current phases.
  select,

  /// The tilt in [PhaseCalState.tilt] is to be applied, then captured.
  ready,
  capturing,

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
    this.mode = PhaseMode.both,
    this.tilt = PhaseTilt.positive,
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
  final PhaseMode mode;

  /// The tilt being prepared or captured.
  final PhaseTilt tilt;

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

  /// 1-based position of [tilt] among the tilts of the [mode].
  int get step => mode.tilts.indexOf(tilt) + 1;
  int get steps => mode.tilts.length;

  PhaseCalState copyWith({
    PhaseStage? stage,
    int? mask,
    PhaseMode? mode,
    PhaseTilt? tilt,
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
        mode: mode ?? this.mode,
        tilt: tilt ?? this.tilt,
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
/// complex plane of `u = S / (A − B)`: a positive tilt points at φ, a negative
/// one at φ + 180°. Capture the phasor stream with a clear positive and a clear
/// negative tilt (the direction of their difference is φ, the zero offset
/// cancels), or with one of them only (the direction of `u` itself). Neither
/// the size of the tilt nor the stored phase matters. See
/// [estimatePhaseFromTilts].
class PhaseCalNotifier extends Notifier<PhaseCalState> {
  /// Length of one capture. ~40 batches/s, so ~325 batches.
  static const captureDuration = Duration(seconds: 8);
  static const minSamples = 60;

  final List<ComplexStats> _pos = [ComplexStats(), ComplexStats()];
  final List<ComplexStats> _neg = [ComplexStats(), ComplexStats()];

  /// The sensors' invert flags: an inverted sensor reads positive for a
  /// negative raw signal, which the stored phase must absorb.
  List<int> _invert = const [0, 0];

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

  Future<List<int>> _readInvert() async {
    final api = ref.read(instrumentApiProvider);
    return Future.wait(kSensorInvert.map(api.readValue));
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

  void selectMode(PhaseMode mode) {
    if (state.stage != PhaseStage.select) return;
    state = state.copyWith(mode: mode);
  }

  /// Leave the selection and go to the first tilt.
  Future<void> begin() async {
    if (state.stage != PhaseStage.select) return;
    final gen = ++_gen;
    try {
      _invert = await _readInvert();
    } catch (e) {
      _fail(gen, e);
      return;
    }
    if (gen != _gen || !ref.mounted) return;
    state = state.copyWith(stage: PhaseStage.ready, tilt: state.mode.tilts.first);
  }

  /// Captures the tilt that is ready.
  Future<void> capture() async {
    if (state.stage != PhaseStage.ready) return;
    final into = state.tilt == PhaseTilt.positive ? _pos : _neg;
    final gen = ++_gen;
    for (final s in into) {
      s.reset();
    }
    state = state.copyWith(
        stage: PhaseStage.capturing, captureProgress: 0, samples: 0);

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
        unawaited(_endCapture(gen, into));
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

  Future<void> _endCapture(int gen, List<ComplexStats> into) async {
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
    final tilts = state.mode.tilts;
    final next = tilts.indexOf(state.tilt) + 1;
    if (next < tilts.length) {
      state = state.copyWith(
        stage: PhaseStage.ready,
        tilt: tilts[next],
        samples: into[0].n,
      );
      return;
    }
    final est = <PhaseEstimate?>[
      for (var i = 0; i < 2; i++) _estimate(i, tilts),
    ];
    state = state.copyWith(
      stage: PhaseStage.review,
      samples: into[0].n,
      estimates: est,
    );
  }

  PhaseEstimate? _estimate(int i, List<PhaseTilt> tilts) {
    final e = estimatePhaseFromTilts(
      positive: tilts.contains(PhaseTilt.positive) ? _pos[i] : null,
      negative: tilts.contains(PhaseTilt.negative) ? _neg[i] : null,
    );
    // The estimate is the direction of a tilt that reads positive; with the
    // sign of the reading inverted that is the raw signal turned by 180°.
    return e != null && _invert[i] == 1 ? e.rotated(180) : e;
  }

  /// Back to the first tilt (e.g. the table was bumped).
  void redo() {
    _gen++;
    _sub?.cancel();
    _timer?.cancel();
    state = state.copyWith(stage: PhaseStage.ready, tilt: state.mode.tilts.first);
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
        if (!SensorMask.has(state.mask, i) || est == null) continue;
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
