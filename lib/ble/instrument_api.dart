/// Typed operations on the instrument, built on a [DeviceLink]. No BLE and no
/// Flutter here — the wizards, providers and screens talk to the instrument
/// only through this class, which keeps them testable against the simulator.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';

/// The connected instrument does not speak the protocol this app does.
class IncompatibleFirmwareException implements Exception {
  const IncompatibleFirmwareException(this.apiVersion, this.firmware);

  /// The `api_version` the instrument reported, or null if it did not answer
  /// a v3 IDENTITY request at all (a v2 or older firmware).
  final int? apiVersion;
  final String? firmware;

  String get message => apiVersion == null
      ? 'This instrument runs firmware that does not speak API v$kApiVersion. '
          'Update it to 0.11 or newer.'
      : 'This instrument speaks API v$apiVersion (firmware ${firmware ?? '?'}); '
          'this app needs API v$kApiVersion.';

  @override
  String toString() => 'IncompatibleFirmwareException($message)';
}

class InstrumentApi {
  const InstrumentApi(this.link);

  final DeviceLink link;

  // --- helpers --------------------------------------------------------------

  Future<Uint8List> _get(int op, String what) async =>
      (await link.request(op)).orThrow(what).data;

  T _decoded<T>(T? v, String what) {
    if (v == null) throw LinkException('malformed $what reply');
    return v;
  }

  // --- System ---------------------------------------------------------------

  Future<ApiIdentity> identity() async => _decoded(
      ApiIdentity.decode(await _get(opGet(ApiCat.system, SysRes.identity),
          'identity')),
      'identity');

  /// Reads IDENTITY and throws [IncompatibleFirmwareException] unless it
  /// reports API v[kApiVersion].
  Future<ApiIdentity> verifyCompatible() async {
    final r = await link.request(opGet(ApiCat.system, SysRes.identity));
    final id = r.ok ? ApiIdentity.decode(r.data) : null;
    if (id == null) {
      // An older firmware answers v3's IDENTITY opcode with an error or with
      // the short v2 payload.
      throw const IncompatibleFirmwareException(null, null);
    }
    if (id.apiVersion != kApiVersion) {
      throw IncompatibleFirmwareException(id.apiVersion, id.firmware);
    }
    return id;
  }

  Future<ApiSystemState> state() async => _decoded(
      ApiSystemState.decode(
          await _get(opGet(ApiCat.system, SysRes.state), 'state')),
      'state');

  Future<ApiHealth> health() async => _decoded(
      ApiHealth.decode(
          await _get(opGet(ApiCat.system, SysRes.health), 'health')),
      'health');

  Future<ApiRtc> rtc() async => _decoded(
      ApiRtc.decode(await _get(opGet(ApiCat.system, SysRes.rtc), 'clock')),
      'clock');

  Future<void> setRtc(DateTime t) async {
    (await link.request(opSet(ApiCat.system, SysRes.rtc), ApiRtc.encodeSet(t)))
        .orThrow('set clock');
  }

  // --- Topics (GET) -----------------------------------------------------------

  Future<ApiLive> live() async => _decoded(
      ApiLive.decode(await _get(opGet(ApiCat.topics, TopicRes.live), 'live')),
      'live');

  Future<ApiSystemState> status() async => _decoded(
      ApiSystemState.decode(
          await _get(opGet(ApiCat.topics, TopicRes.status), 'status')),
      'status');

  Future<ApiEnvironmental> env() async => _decoded(
      ApiEnvironmental.decode(
          await _get(opGet(ApiCat.topics, TopicRes.env), 'environment')),
      'environment');

  // --- Settings / calibrations ------------------------------------------------

  /// Reads one value. Throws [ApiException] on any non-OK status.
  Future<int> readValue(ApiValueDef def) async {
    final data = await _get(def.getOpcode, def.label);
    if (!def.type.covers(data)) throw LinkException('short ${def.label}');
    return def.type.decode(data);
  }

  /// Like [readValue], but a firmware without this (optional) resource gives
  /// null instead of throwing.
  Future<int?> tryReadValue(ApiValueDef def) async {
    final r = await link.request(def.getOpcode);
    if (r.status == ApiStatus.unknownResource) return null;
    r.orThrow(def.label);
    if (!def.type.covers(r.data)) throw LinkException('short ${def.label}');
    return def.type.decode(r.data);
  }

  /// Writes one value; the device persists it immediately.
  Future<void> writeValue(ApiValueDef def, int value) async {
    (await link.request(def.setOpcode, def.type.encode(value)))
        .orThrow(def.label);
  }

  // --- Commands -----------------------------------------------------------------

  Future<ApiReply> _exec(int res, [List<int> payload = const []]) =>
      link.request(opExecute(res), payload);

  Future<void> _execOk(int res, String what,
      [List<int> payload = const []]) async {
    (await _exec(res, payload)).orThrow(what);
  }

  Future<void> powerOff() => _execOk(CmdRes.powerOff, 'power off');
  Future<void> reboot() => _execOk(CmdRes.reboot, 'reboot');
  Future<void> rebootToDfu() => _execOk(CmdRes.rebootDfu, 'reboot to DFU');
  Future<void> forceCharge() => _execOk(CmdRes.forceCharge, 'force charge');
  Future<void> endCharging() => _execOk(CmdRes.endCharging, 'end charging');
  Future<void> setChargeInhibit(bool inhibit) =>
      _execOk(CmdRes.chargeInhibit, 'charge inhibit', [inhibit ? 1 : 0]);
  Future<void> setTiltDemod(bool run) =>
      _execOk(CmdRes.tiltDemod, 'tilt demodulation', [run ? 1 : 0]);
  Future<void> testBeep() => _execOk(CmdRes.testBeep, 'beep');
  Future<void> clearCounters() =>
      _execOk(CmdRes.clearCounters, 'clear counters');
  Future<void> serviceEnd() => _execOk(CmdRes.serviceEnd, 'leave service mode');
  Future<void> factoryDefaults() =>
      _execOk(CmdRes.factoryDefaults, 'factory defaults', [0xA5]);

  // --- Procedures -----------------------------------------------------------------

  /// Flip calibration step 1 on the sensors in [sensorMask] (bit0 S1, bit1 S2).
  Future<void> zeroCalStep1(int sensorMask) =>
      _execOk(CmdRes.zeroCal, 'flip calibration', [1, sensorMask]);
  Future<void> zeroCalStep2() =>
      _execOk(CmdRes.zeroCal, 'flip calibration', [2]);
  Future<void> zeroCalCancel() =>
      _execOk(CmdRes.zeroCal, 'cancel flip calibration', [0]);

  Future<void> precisionStart() =>
      _execOk(CmdRes.precision, 'precision measurement', [0]);
  Future<void> precisionCancel() =>
      _execOk(CmdRes.precision, 'cancel precision measurement', [1]);

  Future<ApiZeroCalStatus> zeroCalStatus() async => _decoded(
      ApiZeroCalStatus.decode(await _get(
          opGet(ApiCat.procedures, ProcRes.zeroCal), 'flip calibration')),
      'flip calibration');

  Future<ApiPrecisionStatus> precisionStatus() async => _decoded(
      ApiPrecisionStatus.decode(await _get(
          opGet(ApiCat.procedures, ProcRes.precision), 'precision')),
      'precision');

  // --- Subscriptions ---------------------------------------------------------------

  Stream<T> _decodedStream<T>(
    Stream<Uint8List> raw,
    T? Function(Uint8List) decode,
  ) =>
      raw.map(decode).where((v) => v != null).cast<T>();

  Stream<ApiLive> liveUpdates() => _decodedStream(
      link.subscribe(opSubscribe(ApiCat.topics, TopicRes.live)),
      ApiLive.decode);

  Stream<ApiSystemState> statusUpdates({int intervalMs = 1000}) =>
      _decodedStream(
          link.subscribe(opSubscribe(ApiCat.topics, TopicRes.status),
              intervalMs: intervalMs),
          ApiSystemState.decode);

  Stream<ApiEnvironmental> envUpdates({int intervalMs = 2000}) =>
      _decodedStream(
          link.subscribe(opSubscribe(ApiCat.topics, TopicRes.env),
              intervalMs: intervalMs),
          ApiEnvironmental.decode);

  Stream<ApiSignalDiag> signalDiagUpdates({int intervalMs = 500}) =>
      _decodedStream(
          link.subscribe(opSubscribe(ApiCat.topics, TopicRes.signalDiag),
              intervalMs: intervalMs),
          ApiSignalDiag.decode);

  Stream<ApiPhasorEntry> phasorStream() => _decodedStream(
      link.subscribe(opSubscribe(ApiCat.topics, TopicRes.phasorStream)),
      ApiPhasorEntry.decode);

  Stream<ApiZeroCalStatus> zeroCalUpdates() => _decodedStream(
      link.subscribe(opSubscribe(ApiCat.procedures, ProcRes.zeroCal)),
      ApiZeroCalStatus.decode);

  Stream<ApiPrecisionStatus> precisionUpdates() => _decodedStream(
      link.subscribe(opSubscribe(ApiCat.procedures, ProcRes.precision)),
      ApiPrecisionStatus.decode);
}
