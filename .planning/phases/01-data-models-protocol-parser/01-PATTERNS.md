# Phase 1: Data Models + Protocol Parser - Pattern Map

**Mapped:** 2026-06-04
**Files analyzed:** 7 new files (brand-new Flutter project — no existing Dart analog files)
**Analogs found:** 0 / 7 (codebase has no Dart source yet; all patterns sourced from RESEARCH.md + ARCHITECTURE.md)

---

## File Classification

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `lib/models/device_state.dart` | model | transform (bytes → typed) | None in codebase — see Pattern 2 | canonical design |
| `lib/ble/ble_protocol.dart` | service/utility | transform (bytes ↔ struct) | None in codebase — see Pattern 1 | canonical design |
| `lib/ble/ble_manager.dart` | service/interface | event-driven | None in codebase — see Pattern 3 | canonical design |
| `lib/ble/mock_ble_manager.dart` | service/stub | event-driven | None in codebase — see Pattern 3 | canonical design |
| `lib/providers/device_provider.dart` | provider/stub | request-response | None in codebase — see Pattern 4 | canonical design |
| `lib/main.dart` | entry point | request-response | None in codebase — see Pattern 4 | canonical design |
| `test/ble/ble_protocol_test.dart` | test | batch | None in codebase — see Pattern 5 | canonical design |

> **Note:** This is a brand-new Flutter project. `flutter create` has not yet been run. There are no existing Dart files in `lib/` or `test/`. All patterns below are sourced directly from `.planning/research/ARCHITECTURE.md` and `.planning/phases/01-data-models-protocol-parser/01-RESEARCH.md`, which are the canonical design authorities for this phase.

---

## Pattern Assignments

### `lib/models/device_state.dart` (model, transform)

**Source:** `.planning/research/ARCHITECTURE.md` + `01-RESEARCH.md` Pattern 2

**Role:** Pure Dart data classes only. No BLE API imports, no Flutter imports.

**Imports pattern:**
```dart
import 'package:flutter/foundation.dart'; // @immutable annotation only
```

**ConnectionStatus enum (all 7 values, defined in full now to avoid Phase 3 edit):**
```dart
// Source: .planning/research/ARCHITECTURE.md — "Connection state machine in Riverpod"
enum ConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnecting,
  disconnected,
  error,
}
```

**DeviceState manual equality pattern (D-04):**
```dart
// Source: 01-RESEARCH.md Pattern 2
@immutable
class DeviceState {
  final double angleX;
  final double angleY;
  final int battery;

  const DeviceState({
    required this.angleX,
    required this.angleY,
    required this.battery,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          angleX == other.angleX &&
          angleY == other.angleY &&
          battery == other.battery;

  @override
  int get hashCode => Object.hash(angleX, angleY, battery);
}
```

**ScannedDevice manual equality pattern:**
```dart
// Source: 01-RESEARCH.md — "ScannedDevice with manual equality"
@immutable
class ScannedDevice {
  final String id;
  final String name;
  final int rssi;

  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedDevice &&
          id == other.id &&
          name == other.name &&
          rssi == other.rssi;

  @override
  int get hashCode => Object.hash(id, name, rssi);
}
```

**Key implementation notes:**
- Use `Object.hash(a, b, c)` — never XOR fields manually (bad distribution)
- `identical(this, other)` short-circuit before field comparison is idiomatic Dart
- All fields `final`; constructors `const` — these classes are value objects
- Riverpod 3.x uses `==` to suppress duplicate emissions; correct `==` here prevents spurious widget rebuilds

---

### `lib/ble/ble_protocol.dart` (service/utility, transform)

**Source:** `.planning/research/ARCHITECTURE.md` — "Parsing implementation" + `01-RESEARCH.md` Pattern 1

**Role:** Pure Dart utility. No state, no Flutter imports, no BLE package imports. Contains protocol constants and the `StatePacket` class.

**Imports pattern:**
```dart
import 'dart:typed_data';
import 'package:inclinometer/models/device_state.dart';
```

**UUID and command constants:**
```dart
// Source: .planning/research/ARCHITECTURE.md — "Parsing implementation"
const String kServiceUuid     = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid   = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid = '0000ZZZZ-0000-1000-8000-00805f9b34fb';

const int kCmdZeroX = 0x01;
const int kCmdZeroY = 0x02;
```

**StatePacket.parse() — PROT-04 (canonical):**
```dart
// Source: .planning/research/ARCHITECTURE.md — "Parsing implementation"
// CRITICAL: ByteData.sublistView requires TypedData — Uint8List.fromList() conversion is MANDATORY
class StatePacket {
  static DeviceState parse(List<int> bytes) {
    assert(bytes.length == 9, 'State packet must be 9 bytes, got ${bytes.length}');
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return DeviceState(
      angleX:  bd.getFloat32(0, Endian.little),
      angleY:  bd.getFloat32(4, Endian.little),
      battery: bytes[8],
    );
  }

  static List<int> encode(double ax, double ay, int battery) {
    final bd = ByteData(9);
    bd.setFloat32(0, ax, Endian.little);
    bd.setFloat32(4, ay, Endian.little);
    bd.setUint8(8, battery);
    return bd.buffer.asUint8List().toList();
  }
}
```

**Key implementation notes:**
- `ByteData.sublistView(plainList)` will NOT compile — `sublistView` takes `TypedData`. The `Uint8List.fromList(bytes)` conversion is required (see 01-RESEARCH.md Anti-Patterns)
- `assert` for length check is correct per D-context decision — this is a dev-time protocol contract, not user input
- `encode()` is included in Phase 1 (D-03) to enable round-trip unit tests
- Packet layout: bytes 0–3 = `angleX` float32LE, bytes 4–7 = `angleY` float32LE, byte 8 = `battery` uint8

---

### `lib/ble/ble_manager.dart` (service/interface, event-driven)

**Source:** `.planning/research/ARCHITECTURE.md` — "BLE Abstraction Pattern" + `01-RESEARCH.md` Pattern 3

**Role:** Abstract class defining the seam between mock (WP1) and real (WP2) BLE. Zero BLE package imports — ever.

**Imports pattern:**
```dart
import 'package:inclinometer/models/device_state.dart';
```

**Abstract class definition (canonical — do not deviate):**
```dart
// Source: .planning/research/ARCHITECTURE.md — "Use an abstract class with two concrete implementations"
abstract class BleManager {
  /// Emits ScannedDevice entries while scanning is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state stream for the active device.
  Stream<ConnectionStatus> get connectionStatus;

  /// Raw 9-byte state packet stream from the instrument characteristic.
  Stream<List<int>> get statePackets;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendCommand(int commandByte);

  void dispose();
}
```

**Key implementation notes:**
- No `flutter_blue_plus` import — this is the architecture constraint (ARCH-02, CLAUDE.md)
- No Riverpod imports — `BleManager` is a plain Dart interface
- No `isMock` flag — the abstract class/two-implementations pattern is mandatory (see ARCHITECTURE.md Anti-Patterns)
- `dispose()` is synchronous — managers own their `StreamController`s and must close them

---

### `lib/ble/mock_ble_manager.dart` (service/stub, event-driven)

**Source:** `01-RESEARCH.md` Pattern 3 + ARCHITECTURE.md "MockBleManager implementation sketch"

**Placement rationale (from RESEARCH.md recommendation):** Separate file `mock_ble_manager.dart` because the file pair will each exceed ~80 lines once Phase 2 fills in behavior. Phase 1 stub is minimal but the separation avoids Phase 2 refactor.

**Imports pattern:**
```dart
import 'dart:async';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
```

**Phase 1 stub pattern (all methods throw UnimplementedError — D-05):**
```dart
// Source: 01-RESEARCH.md Pattern 3
class MockBleManager implements BleManager {
  @override
  Stream<ScannedDevice> get scanResults =>
      throw UnimplementedError('Phase 2: scanResults');

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      throw UnimplementedError('Phase 2: connectionStatus');

  @override
  Stream<List<int>> get statePackets =>
      throw UnimplementedError('Phase 2: statePackets');

  @override
  Future<void> startScan() => throw UnimplementedError('Phase 2: startScan');

  @override
  Future<void> stopScan() => throw UnimplementedError('Phase 2: stopScan');

  @override
  Future<void> connect(String deviceId) =>
      throw UnimplementedError('Phase 2: connect');

  @override
  Future<void> disconnect() => throw UnimplementedError('Phase 2: disconnect');

  @override
  Future<void> sendCommand(int commandByte) =>
      throw UnimplementedError('Phase 2: sendCommand');

  @override
  void dispose() {}
}
```

**Phase 2 reference sketch (for context — NOT implemented in Phase 1):**
The ARCHITECTURE.md shows the Phase 2 full implementation using `StreamController.broadcast()`, a `Timer`, and `StatePacket.encode()` for random-walk data. Phase 1 just needs the stub above to satisfy `ARCH-01` ("compiles without stub warnings").

**Key implementation notes:**
- `dispose()` must NOT throw — it's called on cleanup regardless of connection state
- Phase 2 will add `StreamController` fields and a `Timer`; the stub above is the minimal compile target
- CLAUDE.md constraint: `connect()` in Phase 2 must simulate ~300ms delay; `simulateDisconnect()` debug method required — these are Phase 2 concerns, not Phase 1

---

### `lib/providers/device_provider.dart` (provider/stub, request-response)

**Source:** `.planning/research/ARCHITECTURE.md` — "Inject via ProviderScope override" + `01-RESEARCH.md` Pitfall 4 recommendation

**Placement rationale (from RESEARCH.md Pitfall 4):** Define `bleManagerProvider` here (not in `main.dart`) to avoid a Phase 3 refactor. The file is ~5 lines in Phase 1.

**Imports pattern:**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/ble_manager.dart';
```

**bleManagerProvider stub:**
```dart
// Source: .planning/research/ARCHITECTURE.md — "Inject via ProviderScope override"
// This provider MUST be overridden at root via ProviderScope.overrides
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});
```

**Key implementation notes:**
- `Provider<BleManager>` is NOT autoDispose (Riverpod 3.x default is autoDispose, but `Provider` at module level is kept alive by default — no explicit `keepAlive` needed for a top-level `Provider`)
- Phase 3 adds `ConnectionNotifier`, `scanResultsProvider`, `deviceStateProvider` to this same file
- Phase 1 creates only the `bleManagerProvider` — no other providers yet

---

### `lib/main.dart` (entry point, request-response)

**Source:** `.planning/research/ARCHITECTURE.md` — "Inject via ProviderScope override" + `01-RESEARCH.md` Pattern 4

**Role:** Minimal Phase 1 stub. Wires `MockBleManager` via `ProviderScope.overrides`. WP2 swap is one line change.

**Imports pattern:**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
```

**Phase 1 minimal stub:**
```dart
// Source: 01-RESEARCH.md Pattern 4
void main() {
  runApp(
    ProviderScope(
      overrides: [
        bleManagerProvider.overrideWith((_) => MockBleManager()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Text('Phase 1'))),
      ),
    ),
  );
}
```

**Key implementation notes:**
- `bleManagerProvider` is now in `lib/providers/device_provider.dart` — import from there, not defined here
- `overrideWith((_) => MockBleManager())` is the canonical Riverpod override pattern; WP2 replaces `MockBleManager()` with `RealBleManager()` — no other change
- Phase 5 replaces the `MaterialApp(home: Scaffold(...))` placeholder with real `go_router` routing
- Counter app boilerplate must be wiped (D-02): delete generated `lib/main.dart` content, replace with this stub

---

### `test/ble/ble_protocol_test.dart` (test, batch)

**Source:** `01-RESEARCH.md` Pattern 5

**Role:** Pure Dart unit tests for `StatePacket.parse()` and `encode()`. Uses `package:test` (not `flutter_test` — no widgets involved).

**Imports pattern:**
```dart
import 'package:test/test.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
```

**Round-trip test structure:**
```dart
// Source: 01-RESEARCH.md Pattern 5
void main() {
  group('StatePacket', () {
    test('encode then parse round-trips float values', () {
      const ax = 12.345;
      const ay = -0.678;
      const battery = 72;

      final bytes = StatePacket.encode(ax, ay, battery);
      final state = StatePacket.parse(bytes);

      // float32 round-trip: use closeTo NOT equals — float64→float32→float64 is lossy
      expect(state.angleX, closeTo(ax, 1e-4));
      expect(state.angleY, closeTo(ay, 1e-4));
      expect(state.battery, equals(battery));
    });

    test('parse asserts on wrong packet length', () {
      expect(
        () => StatePacket.parse([0, 1, 2]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('encode produces exactly 9 bytes', () {
      final bytes = StatePacket.encode(0.0, 0.0, 100);
      expect(bytes.length, equals(9));
    });
  });
}
```

**Key implementation notes:**
- Use `closeTo(value, 1e-4)` NOT `equals()` for float round-trips — float64→float32→float64 loses ~7 decimal digits (01-RESEARCH.md Pitfall 3)
- `battery` field is integer — `equals()` is correct for it
- Run with `flutter test test/ble/ble_protocol_test.dart` (flutter test runner works for pure Dart tests)
- `test/widget_test.dart` (generated by `flutter create`) MUST be deleted as part of D-02 — it imports the counter app widget that no longer exists

---

## Shared Patterns

### Manual hashCode Combining
**Source:** `01-RESEARCH.md` — "Don't Hand-Roll" section
**Apply to:** `DeviceState`, `ScannedDevice` in `lib/models/device_state.dart`
```dart
// Use Object.hash — do NOT XOR fields manually
@override
int get hashCode => Object.hash(fieldA, fieldB, fieldC);
```

### Dart Assertion for Protocol Validation
**Source:** `01-RESEARCH.md` Pattern 1 + Context decision
**Apply to:** `StatePacket.parse()` in `lib/ble/ble_protocol.dart`
```dart
// Dev-time contract check — assertions are disabled in release mode (intentional)
assert(bytes.length == 9, 'State packet must be 9 bytes, got ${bytes.length}');
```

### UnimplementedError Stub Convention
**Source:** `01-RESEARCH.md` Pattern 3
**Apply to:** `MockBleManager` (Phase 1) and `bleManagerProvider` in `device_provider.dart`
```dart
// Phase N label in the message aids debugging when an unimplemented path is hit
throw UnimplementedError('Phase 2: methodName');
```

### Riverpod 3.x Provider Type (Not Legacy)
**Source:** CLAUDE.md, `01-RESEARCH.md` "State of the Art"
**Apply to:** `bleManagerProvider` in `lib/providers/device_provider.dart`; all future providers
- Use `Provider`, `NotifierProvider`, `AsyncNotifierProvider` — never `StateNotifierProvider`
- `StateNotifierProvider` was moved to `package:flutter_riverpod/legacy.dart` in Riverpod 3.x
- `Ref` is a single type in Riverpod 3.x — `FutureProviderRef<T>`, `StreamProviderRef<T>` etc. no longer exist

---

## No Analog Found

All Phase 1 files have no existing codebase analog (brand-new project). Patterns sourced exclusively from canonical design docs:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/models/device_state.dart` | model | transform | New project |
| `lib/ble/ble_protocol.dart` | service/utility | transform | New project |
| `lib/ble/ble_manager.dart` | service/interface | event-driven | New project |
| `lib/ble/mock_ble_manager.dart` | service/stub | event-driven | New project |
| `lib/providers/device_provider.dart` | provider | request-response | New project |
| `lib/main.dart` | entry point | request-response | New project |
| `test/ble/ble_protocol_test.dart` | test | batch | New project |

---

## Build Order Constraint

Files must be created bottom-up (each layer depends on the layer below):

```
1. lib/models/device_state.dart         (no deps — pure Dart)
2. lib/ble/ble_protocol.dart            (imports models)
3. lib/ble/ble_manager.dart             (imports models)
4. lib/ble/mock_ble_manager.dart        (imports ble_manager + models)
5. lib/providers/device_provider.dart   (imports ble_manager)
6. lib/main.dart                        (imports providers + mock_ble_manager)
7. test/ble/ble_protocol_test.dart      (imports ble_protocol + models)
```

Pre-requisite: `flutter create --org com.soldernerd --project-name inclinometer .` must run first, followed by boilerplate wipe (delete `test/widget_test.dart`, replace `lib/main.dart`).

---

## Metadata

**Analog search scope:** `.planning/` docs (no Dart source files exist yet)
**Files scanned:** 4 planning documents (`ARCHITECTURE.md`, `STACK.md`, `PROJECT.md`, `01-RESEARCH.md`, `01-CONTEXT.md`)
**Pattern extraction date:** 2026-06-04
**Canonical design authority:** `.planning/research/ARCHITECTURE.md` (all code shapes derive from this)
