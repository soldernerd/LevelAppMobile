/// An in-memory instrument that speaks API v3 at the request/reply level —
/// behind [MockBleManager] for hardware-free runs and the test suite. It is
/// not a toy: it models the sensor physics (excitation phasors, phase / k /
/// zero calibration, invert), the flip-calibration and precision-measurement
/// state machines, service mode gating, settings ranges and the topic
/// subscriptions, so the wizards can be exercised end to end.
///
/// Physics: each sensor sees a physical tilt `T` (mm/m, native sign). The
/// carrier phasors are
/// `A = 1000·e^{jθ}`, `B = −A`, `S = PGA·(A−B)·u` with
/// `u = (zeroTrue + T·kTrue)·e^{jφTrue}`, and the "firmware" computes, from
/// the *stored* calibration, `x = u·e^{−jφcal}`,
/// `tilt = (Re x − zero) / k` — exactly `Math/math_displacement.c`.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';

class SimulatedDevice implements DeviceLink {
  SimulatedDevice({
    Random? random,
    this.noise = 0.0,
    this.apiVersion = kApiVersion,
    this.latency = Duration.zero,
    this.supportsChargeFullTimeout = false,
    DateTime Function()? clock,
  })  : _rng = random ?? Random(1),
        _clock = clock ?? DateTime.now {
    _resetDefaults();
  }

  /// Reading noise (mm/m, std-dev, uniform ±noise). 0 = exact.
  final double noise;

  /// Reported in IDENTITY. Tests set 2 to exercise the incompatibility path.
  final int apiVersion;

  /// Artificial delay before each reply.
  final Duration latency;

  /// Whether Settings 0x53 exists (it is not on firmware master yet).
  final bool supportsChargeFullTimeout;

  final Random _rng;
  final DateTime Function() _clock;

  /// Called when the instrument drops the link (power off, reboot, DFU).
  void Function()? onLinkDown;

  // --------------------------------------------------------------------------
  // Test / dev hooks
  // --------------------------------------------------------------------------

  /// What each sensor physically sees, mm/m in its native sign.
  List<double> physicalTilt = [0.8000, 0.5000];

  /// The instrument's true electrical parameters (what calibration should
  /// converge to): ratio per mm/m, level-point ratio, signal phase (deg).
  List<double> trueK = [0.050, 0.048];
  List<double> trueZero = [0.0012, -0.0008];
  List<double> truePhaseDeg = [12.0, 10.5];

  /// Let the physical tilt wander (dev runs); off in tests.
  bool wander = false;

  /// Marks the readings doubtful (vibration).
  bool disturbed = false;

  /// Makes a precision measurement never find a clean window.
  bool precisionNeverClean = false;

  /// Service mode can only be entered on the instrument; this is its stand-in.
  void setServiceMode(bool on) {
    _serviceMode = on;
    _touchServiceTimer();
  }

  bool get serviceMode => _serviceMode;

  /// Stored calibration, for assertions.
  int calibration(ApiValueDef def) => _values[_key(def)]!;

  void setCalibration(ApiValueDef def, int v) => _values[_key(def)] = v;

  int setting(ApiValueDef def) => _values[_key(def)]!;

  /// The batteries / charger.
  void setBattery({int? soc, int? mv, bool? usb, bool? charging}) {
    if (soc != null) _soc = soc;
    if (mv != null) _mv = mv;
    if (usb != null) _usb = usb;
    if (charging != null) _charging = charging;
  }

  // --------------------------------------------------------------------------
  // State
  // --------------------------------------------------------------------------

  final Map<int, int> _values = {};
  int _key(ApiValueDef d) => (d.category << 8) | d.id;

  bool _serviceMode = false;
  Timer? _serviceTimer;

  bool _demodRunning = true;
  bool _phasorActive = false;
  final bool _bulkActive = false;

  int _soc = 85;
  int _mv = 4020;
  bool _usb = false;
  bool _charging = false;
  bool _forceCharging = false;
  bool _chargeInhibited = false;

  Duration _rtcOffset = Duration.zero;
  bool _rtcSet = false;
  final DateTime _boot = DateTime.now();

  int _liveSeq = 0;
  Timer? _liveTimer;

  // Procedures
  ZeroCalPhase _zPhase = ZeroCalPhase.idle;
  int _zProgress = 0;
  int _zMask = 3;
  static const _zTarget = 64;
  final List<double> _zAvg1 = [0, 0];
  Timer? _zTimer;

  PrecisionPhase _pPhase = PrecisionPhase.idle;
  int _pCount = 0;
  int _pElapsed = 0;
  bool _pFailed = false;
  List<double> _pResult = [0, 0, 0];
  Timer? _pTimer;
  static const _pTarget = 81;

  bool _rotated = false; // physical tilt negated during flip step 2

  // Subscriptions
  final Map<int, _SimSub> _subs = {};

  void _resetDefaults() {
    _values.clear();
    void put(ApiValueDef d, int v) => _values[_key(d)] = v;
    // Settings
    for (final d in kSettings) {
      put(d, switch (d.id) {
        0x60 => 300,
        0x52 => 3700,
        0x51 => 3600,
        0x50 => 3400,
        0x53 => 120,
        0x61 => 4,
        0x40 => 10,
        0x41 => 20,
        0x42 => 20,
        0x43 => 1000,
        0x44 => 1000,
        _ => d.min,
      });
    }
    // Calibrations: deliberately not equal to the "true" parameters so the
    // wizards have something to correct.
    put(kS1K, 45000);
    put(kS1Zero, 500);
    put(kS1Phase, 1000);
    put(kS1Invert, 0);
    put(kS2K, 50000);
    put(kS2Zero, -300);
    put(kS2Phase, 900);
    put(kS2Invert, 0);
    for (final d in kCalibrations) {
      _values.putIfAbsent(_key(d), () => switch (d.id) {
            0x50 => 1000,
            0x51 => 1000,
            0x61 || 0x62 || 0x65 || 0x66 => 1000,
            0x68 => 10,
            0x63 => 1500,
            _ => 0,
          });
    }
  }

  // --------------------------------------------------------------------------
  // Physics
  // --------------------------------------------------------------------------

  double _effectiveTilt(int i) => _rotated ? -physicalTilt[i] : physicalTilt[i];

  /// (re, im) of u for sensor i at tilt [t].
  (double, double) _u(int i, double t) {
    final mag = trueZero[i] + t * trueK[i];
    final ph = truePhaseDeg[i] * pi / 180;
    return (mag * cos(ph), mag * sin(ph));
  }

  /// What the firmware would report for sensor i at tilt [t] with the stored
  /// calibration (invert applied).
  double _reading(int i, double t, {bool applyInvert = true}) {
    final (ur, ui) = _u(i, t);
    final phCal = _values[_key(kSensorPhase[i])]! * pi / 18000;
    final xRe = ur * cos(phCal) + ui * sin(phCal);
    final k = _values[_key(kSensorK[i])]! * 1e-6;
    final zero = _values[_key(kSensorZero[i])]! * 1e-6;
    final native = (xRe - zero) / k;
    final inv = _values[_key(kSensorInvert[i])]! == 1;
    return (applyInvert && inv) ? -native : native;
  }

  double _noise() => noise == 0 ? 0 : (_rng.nextDouble() * 2 - 1) * noise;

  // --------------------------------------------------------------------------
  // DeviceLink
  // --------------------------------------------------------------------------

  @override
  Future<ApiReply> request(
    int op, [
    List<int> payload = const [],
    Duration? timeout,
  ]) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    _touchServiceTimer();
    return _handle(op, Uint8List.fromList(payload));
  }

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) {
    final existing = _subs[subscribeOpcode];
    if (existing != null && !existing.controller.isClosed) {
      return existing.controller.stream;
    }
    late final _SimSub sub;
    final c = StreamController<Uint8List>.broadcast(
      onListen: () => _startSub(subscribeOpcode, sub, intervalMs, payload),
      onCancel: () => _stopSub(subscribeOpcode, sub),
    );
    sub = _SimSub(c);
    _subs[subscribeOpcode] = sub;
    return c.stream;
  }

  /// The instrument vanishes: all subscriptions end.
  void linkDown() {
    for (final s in _subs.values.toList()) {
      s.timer?.cancel();
      if (!s.controller.isClosed) s.controller.close();
    }
    _subs.clear();
    _phasorActive = false;
    _liveTimer?.cancel();
    _liveTimer = null;
    _zTimer?.cancel();
    _pTimer?.cancel();
    _serviceTimer?.cancel();
    _serviceMode = false;
    _zPhase = ZeroCalPhase.idle;
    _pPhase = PrecisionPhase.idle;
    final cb = onLinkDown;
    cb?.call();
  }

  void dispose() {
    for (final s in _subs.values.toList()) {
      s.timer?.cancel();
      if (!s.controller.isClosed) s.controller.close();
    }
    _subs.clear();
    _liveTimer?.cancel();
    _zTimer?.cancel();
    _pTimer?.cancel();
    _serviceTimer?.cancel();
  }

  // --------------------------------------------------------------------------
  // Service mode idle timeout (10 minutes without a request)
  // --------------------------------------------------------------------------

  void _touchServiceTimer() {
    _serviceTimer?.cancel();
    if (_serviceMode) {
      _serviceTimer = Timer(const Duration(minutes: 10), () {
        _serviceMode = false;
      });
    }
  }

  // --------------------------------------------------------------------------
  // Request dispatch
  // --------------------------------------------------------------------------

  ApiReply _ok([List<int> data = const []]) =>
      ApiReply(ApiStatus.ok, Uint8List.fromList(data));
  ApiReply _err(ApiStatus s) => ApiReply(s);

  ApiReply _handle(int op, Uint8List p) {
    final verb = opcodeVerb(op);
    final cat = opcodeCategory(op);
    final res = opcodeResource(op);

    switch (cat) {
      case ApiCat.system:
        return _system(verb, res, p);
      case ApiCat.commands:
        return verb == ApiVerb.execute
            ? _command(res, p)
            : _err(ApiStatus.verbNotValid);
      case ApiCat.calibrations:
      case ApiCat.settings:
        return _valueResource(verb, cat, res, p);
      case ApiCat.topics:
        return _topicGet(verb, res, p);
      case ApiCat.procedures:
        return _procedureGet(verb, res);
      case ApiCat.measurements:
      case ApiCat.debugLog:
      case ApiCat.diagnostics:
      case ApiCat.bulk:
        return _err(ApiStatus.unknownResource);
      default:
        return _err(ApiStatus.unknownCategory);
    }
  }

  // --- System ---------------------------------------------------------------

  ApiReply _system(int verb, int res, Uint8List p) {
    switch (res) {
      case SysRes.identity:
        if (verb != ApiVerb.get) return _err(ApiStatus.verbNotValid);
        final b = Uint8List(50);
        final bd = ByteData.sublistView(b);
        b[0] = 1;
        b[1] = 0;
        b[2] = 0;
        b[3] = apiVersion;
        bd.setUint16(4, kApiMaxPayload, Endian.little);
        _putStr(b, 6, 16, 'InclinationMeter');
        _putStr(b, 22, 8, '6DA08073');
        _putStr(b, 30, 20, '1371e8b0');
        return _ok(b);
      case SysRes.state:
        return verb == ApiVerb.get ? _ok(_stateBytes()) : _err(ApiStatus.verbNotValid);
      case SysRes.health:
        if (verb != ApiVerb.get) return _err(ApiStatus.verbNotValid);
        final b = Uint8List(31);
        final bd = ByteData.sublistView(b);
        b.setRange(0, 5, [1, 1, 1, 1, 1]);
        b[5] = 1;
        b[8] = 2; // power-on
        b[9] = _rtcSet ? 1 : 0;
        bd.setUint32(10, _clock().difference(_boot).inSeconds, Endian.little);
        return _ok(b);
      case SysRes.rtc:
        if (verb == ApiVerb.get) return _ok(_rtcBytes());
        if (verb == ApiVerb.set) {
          if (p.length != 7) return _err(ApiStatus.badLength);
          final bd = ByteData.sublistView(p);
          final year = bd.getUint16(0, Endian.little);
          if (year < 2000 || year > 2099) {
            return _err(ApiStatus.invalidParameter);
          }
          final t = DateTime(year, p[2], p[3], p[4], p[5], p[6]);
          _rtcOffset = t.difference(_clock());
          _rtcSet = true;
          return _ok();
        }
        return _err(ApiStatus.verbNotValid);
      default:
        return _err(ApiStatus.unknownResource);
    }
  }

  void _putStr(Uint8List b, int off, int len, String s) {
    final units = s.codeUnits;
    for (var i = 0; i < len && i < units.length; i++) {
      b[off + i] = units[i];
    }
  }

  Uint8List _stateBytes() {
    final b = Uint8List(15);
    final bd = ByteData.sublistView(b);
    final st = _charging
        ? BatteryState.charging
        : (_mv < (_values[_key(kSettings.firstWhere((d) => d.id == 0x51))] ?? 0)
            ? BatteryState.low
            : BatteryState.normal);
    b[0] = st.value;
    b[1] = _soc;
    bd.setUint16(2, _mv, Endian.little);
    b[4] = _usb ? 1 : 0;
    b[5] = 1;
    b[6] = _charging ? 1 : 0;
    b[7] = _forceCharging ? 1 : 0;
    b[8] = _chargeInhibited ? 1 : 0;
    b[9] = 1;
    b[10] = 1;
    b[11] = _demodRunning ? 1 : 0;
    b[12] = _phasorActive ? 1 : 0;
    b[13] = _bulkActive ? 1 : 0;
    b[14] = _serviceMode ? 1 : 0;
    return b;
  }

  Uint8List _rtcBytes() {
    final t = _clock().add(_rtcOffset);
    final b = Uint8List(10);
    ByteData.sublistView(b).setUint16(0, t.year, Endian.little);
    b[2] = t.month;
    b[3] = t.day;
    b[4] = t.weekday;
    b[5] = t.hour;
    b[6] = t.minute;
    b[7] = t.second;
    b[8] = _rtcSet ? 1 : 0;
    b[9] = (t.millisecond * 256 ~/ 1000) & 0xFF;
    return b;
  }

  // --- Settings / calibrations ----------------------------------------------

  ApiValueDef? _def(int cat, int res) {
    final list = cat == ApiCat.settings ? kSettings : kCalibrations;
    for (final d in list) {
      if (d.id == res) {
        if (d.optional && !supportsChargeFullTimeout) return null;
        return d;
      }
    }
    return null;
  }

  ApiReply _valueResource(int verb, int cat, int res, Uint8List p) {
    final def = _def(cat, res);
    if (def == null) return _err(ApiStatus.unknownResource);
    if (verb == ApiVerb.get) {
      return _ok(def.type.encode(_values[_key(def)]!));
    }
    if (verb != ApiVerb.set) return _err(ApiStatus.verbNotValid);
    if (p.length != def.type.bytes) return _err(ApiStatus.badLength);
    if (def.service && !_serviceMode) {
      return _err(ApiStatus.serviceModeRequired);
    }
    final v = def.type.decode(p);
    if (v < def.min || v > def.max) return _err(ApiStatus.invalidParameter);
    // Cross-field rule: critical < low.
    if (cat == ApiCat.settings && res == 0x50 &&
        v >= _values[_key(kSettings.firstWhere((d) => d.id == 0x51))]!) {
      return _err(ApiStatus.invalidParameter);
    }
    if (cat == ApiCat.settings && res == 0x51 &&
        v <= _values[_key(kSettings.firstWhere((d) => d.id == 0x50))]!) {
      return _err(ApiStatus.invalidParameter);
    }
    _values[_key(def)] = v;
    return _ok();
  }

  // --- Commands -----------------------------------------------------------------

  ApiReply _command(int res, Uint8List p) {
    ApiReply needService(ApiReply Function() body) =>
        _serviceMode ? body() : _err(ApiStatus.serviceModeRequired);

    switch (res) {
      case CmdRes.powerOff:
      case CmdRes.reboot:
        Timer.run(linkDown);
        return _ok();
      case CmdRes.rebootDfu:
        return needService(() {
          Timer.run(linkDown);
          return _ok();
        });
      case CmdRes.forceCharge:
        if (_usb) _forceCharging = true;
        return _ok();
      case CmdRes.endCharging:
        _forceCharging = false;
        return _ok();
      case CmdRes.chargeInhibit:
        if (p.length != 1) return _err(ApiStatus.badLength);
        _chargeInhibited = p[0] != 0;
        if (_chargeInhibited) _forceCharging = false;
        return _ok();
      case CmdRes.tiltDemod:
        if (p.length != 1) return _err(ApiStatus.badLength);
        if (_phasorActive || _bulkActive) {
          return _err(ApiStatus.busyExclusive);
        }
        _demodRunning = p[0] != 0;
        return _ok();
      case CmdRes.zeroCal:
        return needService(() => _zeroCalCommand(p));
      case CmdRes.precision:
        return _precisionCommand(p);
      case CmdRes.factoryDefaults:
        return needService(() {
          if (p.length != 1) return _err(ApiStatus.badLength);
          if (p[0] != 0xA5) return _err(ApiStatus.invalidParameter);
          _resetDefaults();
          return _ok();
        });
      case CmdRes.clearCounters:
        return _ok();
      case CmdRes.serviceEnd:
        _serviceMode = false;
        _serviceTimer?.cancel();
        return _ok();
      case CmdRes.testBeep:
        return _ok();
      default:
        return _err(ApiStatus.unknownResource);
    }
  }

  // --- Zero calibration -----------------------------------------------------------

  ApiReply _zeroCalCommand(Uint8List p) {
    if (p.isEmpty || p.length > 2) return _err(ApiStatus.badLength);
    switch (p[0]) {
      case 0:
        _zTimer?.cancel();
        _zPhase = ZeroCalPhase.idle;
        _zProgress = 0;
        _rotated = false;
        _pushZero();
        return _ok();
      case 1:
        if (!_demodRunning || _pPhase == PrecisionPhase.running) {
          return _err(ApiStatus.busyResource);
        }
        final mask = p.length > 1 ? p[1] : 3;
        if (mask < 1 || mask > 3) return _err(ApiStatus.invalidParameter);
        _zMask = mask;
        _zPhase = ZeroCalPhase.step1Running;
        _zProgress = 0;
        _rotated = false;
        _startZeroTimer(step: 1);
        _pushZero();
        return _ok();
      case 2:
        if (_zPhase != ZeroCalPhase.step1Done) {
          return _err(ApiStatus.busyResource);
        }
        _zPhase = ZeroCalPhase.step2Running;
        _zProgress = 0;
        _rotated = true; // the user turned the instrument by 180 degrees
        _startZeroTimer(step: 2);
        _pushZero();
        return _ok();
      default:
        return _err(ApiStatus.invalidParameter);
    }
  }

  void _startZeroTimer({required int step}) {
    _zTimer?.cancel();
    _zTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _zProgress = min(_zProgress + 8, _zTarget);
      if (_zProgress < _zTarget) {
        _pushZero();
        return;
      }
      _zTimer?.cancel();
      if (step == 1) {
        for (var i = 0; i < 2; i++) {
          _zAvg1[i] = _reading(i, _effectiveTilt(i), applyInvert: false);
        }
        _zPhase = ZeroCalPhase.step1Done;
        _pushZero();
      } else {
        for (var i = 0; i < 2; i++) {
          if (_zMask & (1 << i) == 0) continue;
          final avg2 = _reading(i, _effectiveTilt(i), applyInvert: false);
          final oldZero = _values[_key(kSensorZero[i])]!;
          final kMicro = _values[_key(kSensorK[i])]!;
          // math_zero_cal_new_zero(): new zero in mm/m, back to ppm.
          final newZeroMmPerM = oldZero / kMicro + (_zAvg1[i] + avg2) / 2;
          final ppm = (newZeroMmPerM * kMicro)
              .round()
              .clamp(kSensorZero[i].min, kSensorZero[i].max);
          _values[_key(kSensorZero[i])] = ppm;
        }
        _rotated = false;
        _zPhase = ZeroCalPhase.resultReady;
        _pushZero();
        _zPhase = ZeroCalPhase.idle;
        _zProgress = 0;
        _pushZero();
      }
    });
  }

  Uint8List _zeroBytes() {
    final b = Uint8List(6);
    final bd = ByteData.sublistView(b);
    b[0] = _zPhase.value;
    bd.setUint16(1, _zProgress, Endian.little);
    bd.setUint16(3, _zTarget, Endian.little);
    b[5] = _zMask;
    return b;
  }

  void _pushZero() =>
      _subs[opSubscribe(ApiCat.procedures, ProcRes.zeroCal)]?.add(_zeroBytes());

  // --- Precision ----------------------------------------------------------------------

  ApiReply _precisionCommand(Uint8List p) {
    if (p.length != 1) return _err(ApiStatus.badLength);
    if (p[0] == 1) {
      _pTimer?.cancel();
      _pPhase = PrecisionPhase.idle;
      _pushPrecision();
      return _ok();
    }
    if (p[0] != 0) return _err(ApiStatus.invalidParameter);
    if (!_demodRunning || _zPhase != ZeroCalPhase.idle) {
      return _err(ApiStatus.busyResource);
    }
    _pPhase = PrecisionPhase.running;
    _pCount = 0;
    _pElapsed = 0;
    _pFailed = false;
    _pTimer?.cancel();
    _pTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pElapsed += 100;
      if (!precisionNeverClean) {
        _pCount = min(_pCount + 4, _pTarget);
      }
      if (_pCount >= _pTarget) {
        _pPhase = PrecisionPhase.done;
        final s1 = _reading(0, _effectiveTilt(0)) + _noise();
        final s2 = _reading(1, _effectiveTilt(1)) + _noise();
        _pResult = [s1, s2, s1 - s2];
        _pTimer?.cancel();
      } else if (_pElapsed >= 5000) {
        _pPhase = PrecisionPhase.done;
        _pFailed = true;
        _pTimer?.cancel();
      }
      _pushPrecision();
    });
    _pushPrecision();
    return _ok();
  }

  Uint8List _precisionBytes() {
    final b = Uint8List(23);
    final bd = ByteData.sublistView(b);
    b[0] = _pPhase.value;
    bd.setUint16(1, _pTarget, Endian.little);
    bd.setUint16(3, _pCount, Endian.little);
    bd.setUint32(5, _pElapsed, Endian.little);
    b[9] = _pFailed ? 1 : 0;
    final done = _pPhase == PrecisionPhase.done && !_pFailed;
    bd.setFloat32(10, done ? _pResult[0] : 0, Endian.little);
    bd.setFloat32(14, done ? _pResult[1] : 0, Endian.little);
    bd.setFloat32(18, done ? _pResult[2] : 0, Endian.little);
    b[22] = (_pPhase == PrecisionPhase.running && precisionNeverClean) ? 1 : 0;
    return b;
  }

  void _pushPrecision() => _subs[opSubscribe(ApiCat.procedures, ProcRes.precision)]
      ?.add(_precisionBytes());

  // --- Topics / procedures GET -----------------------------------------------------

  ApiReply _topicGet(int verb, int res, Uint8List p) {
    if (verb != ApiVerb.get) return _err(ApiStatus.verbNotValid);
    final data = _topicData(res);
    return data == null ? _err(ApiStatus.unknownResource) : _ok(data);
  }

  ApiReply _procedureGet(int verb, int res) {
    if (verb != ApiVerb.get) return _err(ApiStatus.verbNotValid);
    return switch (res) {
      ProcRes.zeroCal => _ok(_zeroBytes()),
      ProcRes.precision => _ok(_precisionBytes()),
      _ => _err(ApiStatus.unknownResource),
    };
  }

  Uint8List? _topicData(int res) {
    switch (res) {
      case TopicRes.env:
        final b = Uint8List(14);
        final bd = ByteData.sublistView(b);
        bd.setInt16(0, 2380, Endian.little);
        bd.setUint32(2, 96400, Endian.little);
        bd.setUint16(6, 4100, Endian.little);
        b[8] = 1;
        bd.setInt16(9, 2450, Endian.little);
        bd.setInt16(11, 2200, Endian.little);
        b[13] = 0;
        return b;
      case TopicRes.status:
        return _stateBytes();
      case TopicRes.live:
        return _liveBytes();
      case TopicRes.signalDiag:
        return _diagBytes();
      default:
        return null;
    }
  }

  Uint8List _liveBytes() {
    final b = Uint8List(15);
    final bd = ByteData.sublistView(b);
    final s1 = _reading(0, _effectiveTilt(0)) + _noise();
    final s2 = _reading(1, _effectiveTilt(1)) + _noise();
    bd.setUint16(0, _liveSeq & 0xFFFF, Endian.little);
    b[2] = (_demodRunning ? 1 : 0) | (disturbed ? 6 : 0);
    bd.setFloat32(3, s1, Endian.little);
    bd.setFloat32(7, s2, Endian.little);
    bd.setFloat32(11, s1 - s2, Endian.little);
    return b;
  }

  Uint8List _diagBytes() {
    final b = Uint8List(56);
    final bd = ByteData.sublistView(b);
    // Channel order S2, B, A, S1.
    const rms = [4.1, 310.0, 309.5, 3.8];
    const p2p = [11.6, 877.0, 875.4, 10.8];
    final ph = [truePhaseDeg[1], 180.0, 0.0, truePhaseDeg[0]];
    for (var i = 0; i < 4; i++) {
      bd.setFloat32(4 * i, rms[i], Endian.little);
      bd.setFloat32(16 + 4 * i, p2p[i], Endian.little);
      bd.setFloat32(32 + 4 * i, ph[i], Endian.little);
    }
    bd.setFloat32(48, physicalTilt[0], Endian.little);
    bd.setFloat32(52, physicalTilt[1], Endian.little);
    return b;
  }

  Uint8List _phasorBytes(int seq) {
    // A = 1000 e^{j th}, B = -A, S = PGA * (A - B) * u
    const th = 0.3;
    final ar = 1000 * cos(th), ai = 1000 * sin(th);
    final dr = 2 * ar, di = 2 * ai;
    double n() => noise == 0 ? 0 : (_rng.nextDouble() * 2 - 1) * noise * 20;
    (double, double) s(int i) {
      final (ur, ui) = _u(i, _effectiveTilt(i));
      return (16 * (dr * ur - di * ui) + n(), 16 * (dr * ui + di * ur) + n());
    }

    final (s1r, s1i) = s(0);
    final (s2r, s2i) = s(1);
    return ApiPhasorEntry(
      iB: -ar,
      qB: -ai,
      iA: ar,
      qA: ai,
      iS1: s1r,
      qS1: s1i,
      iS2: s2r,
      qS2: s2i,
      seq: seq & 0xFFFF,
    ).encode();
  }

  // --------------------------------------------------------------------------
  // Subscriptions
  // --------------------------------------------------------------------------

  void _startSub(int op, _SimSub sub, int intervalMs, List<int>? payload) {
    final cat = opcodeCategory(op);
    final res = opcodeResource(op);
    final status = _validateSubscribe(cat, res);
    if (status != ApiStatus.ok) {
      scheduleMicrotask(() {
        if (!sub.controller.isClosed) {
          sub.controller.addError(ApiException(status, 'subscribe'));
          sub.controller.close();
        }
        if (identical(_subs[op], sub)) _subs.remove(op);
      });
      return;
    }
    final period = payload != null && payload.length >= 4
        ? ByteData.sublistView(Uint8List.fromList(payload))
            .getUint32(0, Endian.little)
        : intervalMs;
    if (cat == ApiCat.topics && res == TopicRes.phasorStream) {
      _phasorActive = true;
      var seq = 0;
      sub.timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
        seq += 64;
        sub.add(_phasorBytes(seq));
      });
    } else if (cat == ApiCat.topics && res == TopicRes.live) {
      _ensureLiveTimer();
    } else if (cat == ApiCat.procedures) {
      // pushed on change; send the current state once like the device does
      scheduleMicrotask(() => sub.add(
          res == ProcRes.zeroCal ? _zeroBytes() : _precisionBytes()));
    } else {
      final data = _topicData(res);
      sub.timer = Timer.periodic(Duration(milliseconds: max(period, 50)), (_) {
        final d = _topicData(res);
        if (d != null) sub.add(d);
      });
      if (data != null) scheduleMicrotask(() => sub.add(data));
    }
  }

  ApiStatus _validateSubscribe(int cat, int res) {
    if (cat == ApiCat.topics) {
      switch (res) {
        case TopicRes.env:
        case TopicRes.status:
        case TopicRes.live:
        case TopicRes.signalDiag:
          return ApiStatus.ok;
        case TopicRes.phasorStream:
          return _bulkActive ? ApiStatus.busyExclusive : ApiStatus.ok;
        default:
          return ApiStatus.unknownResource;
      }
    }
    if (cat == ApiCat.procedures &&
        (res == ProcRes.zeroCal || res == ProcRes.precision)) {
      return ApiStatus.ok;
    }
    return ApiStatus.unknownResource;
  }

  void _stopSub(int op, _SimSub sub) {
    sub.timer?.cancel();
    if (identical(_subs[op], sub)) _subs.remove(op);
    if (opcodeCategory(op) == ApiCat.topics &&
        opcodeResource(op) == TopicRes.phasorStream) {
      _phasorActive = false;
    }
    if (opcodeCategory(op) == ApiCat.topics &&
        opcodeResource(op) == TopicRes.live &&
        !_subs.containsKey(op)) {
      _liveTimer?.cancel();
      _liveTimer = null;
    }
  }

  void _ensureLiveTimer() {
    _liveTimer ??= Timer.periodic(const Duration(milliseconds: 246), (_) {
      if (wander) {
        for (var i = 0; i < 2; i++) {
          physicalTilt[i] += (_rng.nextDouble() - 0.5) * 0.004;
        }
      }
      _liveSeq++;
      _subs[opSubscribe(ApiCat.topics, TopicRes.live)]?.add(_liveBytes());
    });
  }
}

class _SimSub {
  _SimSub(this.controller);
  final StreamController<Uint8List> controller;
  Timer? timer;

  void add(Uint8List data) {
    if (!controller.isClosed) controller.add(data);
  }
}
