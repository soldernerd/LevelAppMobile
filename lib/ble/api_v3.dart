/// Device API v3 — the wire framing, opcode scheme, status codes and System
/// IDENTITY that every device family on the shared BLE transport speaks.
///
/// Host-side counterpart of the firmware's `Services/svc_api*`; the protocol is
/// `docs/api-v3-spec.md` in the InclinationMeterFirmware repo. Pure Dart, no
/// BLE dependency, so it is unit-tested in isolation. What the resources of a
/// particular device mean (and their payload codecs) lives with its driver, in
/// `lib/devices/<device>/`.
///
/// ```
/// [OPCODE 2B][LEN 2B][PAYLOAD 0..LEN][CRC16 2B]      (little-endian)
/// ```
/// `CRC16` is CRC-16/CCITT-FALSE over opcode, length and payload. Every
/// response echoes the request opcode and starts its payload with an
/// [ApiStatus] byte; data follows only for [ApiStatus.ok]. Subscription pushes
/// arrive under the SUBSCRIBE opcode as `[OK][issue_seq][page][data…]`.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Opcode structure: [VERB:4][CATEGORY:4][RESOURCE:8]
// ---------------------------------------------------------------------------

/// The protocol version of the framing/opcode scheme. System IDENTITY reports it.
const int kApiVersion = 3;

class ApiVerb {
  static const int get = 0x0;
  static const int set = 0x1;
  static const int execute = 0x2;
  static const int subscribe = 0x3;
  static const int unsubscribe = 0x4;
  static const int startBulk = 0x5;
  static const int cancelBulk = 0x6;
}

class ApiCat {
  static const int system = 0x0;
  static const int commands = 0x1;
  static const int calibrations = 0x2;
  static const int settings = 0x3;
  static const int measurements = 0x4;
  static const int topics = 0x5;
  static const int debugLog = 0x6;
  static const int diagnostics = 0x7;
  static const int bulk = 0x8;
  static const int procedures = 0x9;
}

int opcode(int verb, int category, int resource) =>
    ((verb & 0xF) << 12) | ((category & 0xF) << 8) | (resource & 0xFF);
int opcodeVerb(int op) => (op >> 12) & 0xF;
int opcodeCategory(int op) => (op >> 8) & 0xF;
int opcodeResource(int op) => op & 0xFF;

/// Opcode with the verb replaced — e.g. the UNSUBSCRIBE opcode for a
/// SUBSCRIBE opcode.
int withVerb(int op, int verb) => (op & 0x0FFF) | ((verb & 0xF) << 12);

class SysRes {
  static const int identity = 0x00;
  static const int state = 0x01;
  static const int health = 0x02;
  static const int rtc = 0x03;
}

int opGet(int category, int res) => opcode(ApiVerb.get, category, res);
int opSet(int category, int res) => opcode(ApiVerb.set, category, res);
int opExecute(int res) => opcode(ApiVerb.execute, ApiCat.commands, res);
int opSubscribe(int category, int res) =>
    opcode(ApiVerb.subscribe, category, res);

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------

enum ApiStatus {
  ok(0x00),
  unknownCategory(0x01),
  verbNotValid(0x02),
  unknownResource(0x03),
  badCrc(0x04),
  badLength(0x05),
  busyResource(0x06),
  busyExclusive(0x07),
  invalidParameter(0x08),
  notSubscribed(0x09),
  nothingToCancel(0x0A),
  serviceModeRequired(0x0B),
  unknown(0xFF);

  const ApiStatus(this.value);
  final int value;

  static ApiStatus fromByte(int b) {
    for (final s in ApiStatus.values) {
      if (s.value == b) return s;
    }
    return ApiStatus.unknown;
  }
}

// ---------------------------------------------------------------------------
// CRC-16/CCITT-FALSE
// ---------------------------------------------------------------------------

int crc16Ccitt(List<int> data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= (byte & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc & 0xFFFF;
}

// ---------------------------------------------------------------------------
// Packet framing
// ---------------------------------------------------------------------------

const int kApiHeaderBytes = 4;
const int kApiCrcBytes = 2;

/// Largest payload any packet may carry (System IDENTITY `max_payload`).
const int kApiMaxPayload = 122;

/// Largest packet on the wire.
const int kApiMaxPacket = kApiHeaderBytes + kApiMaxPayload + kApiCrcBytes;

Uint8List buildPacket(int op, [List<int> payload = const []]) {
  final len = payload.length;
  final body = Uint8List(kApiHeaderBytes + len);
  final bd = ByteData.sublistView(body);
  bd.setUint16(0, op, Endian.little);
  bd.setUint16(2, len, Endian.little);
  body.setRange(kApiHeaderBytes, kApiHeaderBytes + len, payload);

  final out = Uint8List(body.length + kApiCrcBytes);
  out.setRange(0, body.length, body);
  ByteData.sublistView(out)
      .setUint16(body.length, crc16Ccitt(body), Endian.little);
  return out;
}

/// A decoded frame. [data] is the payload after the status byte.
class ApiFrame {
  const ApiFrame({
    required this.opcode,
    required this.status,
    required this.data,
    required this.crcOk,
  });

  final int opcode;
  final ApiStatus status;
  final Uint8List data;
  final bool crcOk;

  bool get isOk => crcOk && status == ApiStatus.ok;

  /// A frame that starts with `[issue_seq][page]` is a subscription push; a
  /// SUBSCRIBE ack (or an error) carries no data after the status byte.
  bool get looksLikePush => status == ApiStatus.ok && data.length >= 2;

  /// The push data after `[issue_seq][page]`.
  Uint8List get pushData =>
      data.length >= 2 ? Uint8List.sublistView(data, 2) : Uint8List(0);

  int? get issueSeq => data.length >= 2 ? data[0] : null;

  @override
  String toString() =>
      'ApiFrame(op=0x${opcode.toRadixString(16).padLeft(4, '0')}, '
      '$status, crcOk=$crcOk, ${data.length}B)';
}

/// Rebuilds [ApiFrame]s from a byte stream (BLE, UART).
///
/// Resynchronisation: a declared length beyond [kApiMaxPacket], or a
/// candidate packet whose CRC fails, means the stream is out of step (a lost
/// notification, a bit error) — one byte is dropped and parsing retried, so a
/// valid packet lying behind the damage is still found. Such discards are
/// counted in [crcErrors] / [desyncs]; only frames that pass their CRC are
/// returned.
class ApiReassembler {
  final List<int> _buf = [];

  /// Candidate packets rejected by their CRC.
  int crcErrors = 0;

  /// Headers that declared an impossible length.
  int desyncs = 0;

  void reset() => _buf.clear();

  List<ApiFrame> addBytes(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <ApiFrame>[];
    while (_buf.length >= kApiHeaderBytes) {
      final payLen = _buf[2] | (_buf[3] << 8);
      final total = kApiHeaderBytes + payLen + kApiCrcBytes;
      if (total > kApiMaxPacket) {
        desyncs++;
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      final packet = Uint8List.fromList(_buf.sublist(0, total));
      final frame = _parse(packet);
      if (!frame.crcOk) {
        crcErrors++;
        _buf.removeAt(0);
        continue;
      }
      _buf.removeRange(0, total);
      frames.add(frame);
    }
    return frames;
  }

  static ApiFrame _parse(Uint8List packet) {
    final bd = ByteData.sublistView(packet);
    final op = bd.getUint16(0, Endian.little);
    final payLen = bd.getUint16(2, Endian.little);
    final body = Uint8List.sublistView(packet, 0, kApiHeaderBytes + payLen);
    final gotCrc = bd.getUint16(kApiHeaderBytes + payLen, Endian.little);
    final crcOk = crc16Ccitt(body) == gotCrc;
    final payload =
        Uint8List.sublistView(packet, kApiHeaderBytes, kApiHeaderBytes + payLen);
    if (payload.isEmpty) {
      return ApiFrame(
          opcode: op,
          status: ApiStatus.unknown,
          data: Uint8List(0),
          crcOk: crcOk);
    }
    return ApiFrame(
      opcode: op,
      status: ApiStatus.fromByte(payload[0]),
      data: Uint8List.sublistView(payload, 1),
      crcOk: crcOk,
    );
  }
}

// ---------------------------------------------------------------------------
// Payload helpers
// ---------------------------------------------------------------------------

Uint8List u32le(int v) {
  final b = Uint8List(4);
  ByteData.sublistView(b).setUint32(0, v, Endian.little);
  return b;
}

String cString(Uint8List d, int start, int len) {
  final bytes = d.sublist(start, start + len);
  final nul = bytes.indexOf(0);
  return String.fromCharCodes(nul >= 0 ? bytes.sublist(0, nul) : bytes);
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

/// System IDENTITY. Two layouts share the opcode: the 50-byte v3 one
/// (`fw[3] api_version max_payload product[16] serial[8] build[20]`) and the
/// 19-byte v2 one (`fw[3] product[16]`) of devices still on API v2 such as the
/// NeigMess2, which has no version field, serial or build; those decode with
/// [apiVersion] 2 and an empty [serial] and [build].
class ApiIdentity {
  const ApiIdentity({
    required this.fwMajor,
    required this.fwMinor,
    required this.fwPatch,
    required this.apiVersion,
    required this.maxPayload,
    required this.product,
    required this.serial,
    required this.build,
  });

  final int fwMajor, fwMinor, fwPatch;
  final int apiVersion;
  final int maxPayload;
  final String product;
  final String serial;
  final String build;

  String get firmware => '$fwMajor.$fwMinor.$fwPatch';

  static ApiIdentity? decode(Uint8List d) {
    if (d.length == 19) {
      return ApiIdentity(
        fwMajor: d[0],
        fwMinor: d[1],
        fwPatch: d[2],
        apiVersion: 2,
        maxPayload: kApiMaxPayload,
        product: cString(d, 3, 16),
        serial: '',
        build: '',
      );
    }
    if (d.length < 50) return null;
    final bd = ByteData.sublistView(d);
    return ApiIdentity(
      fwMajor: d[0],
      fwMinor: d[1],
      fwPatch: d[2],
      apiVersion: d[3],
      maxPayload: bd.getUint16(4, Endian.little),
      product: cString(d, 6, 16),
      serial: cString(d, 22, 8),
      build: cString(d, 30, 20),
    );
  }
}
