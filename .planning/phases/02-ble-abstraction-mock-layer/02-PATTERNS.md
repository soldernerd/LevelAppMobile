# Phase 2: BLE Abstraction + Mock Layer - Pattern Map

**Mapped:** 2026-06-04
**Files analyzed:** 3
**Analogs found:** 3 / 3

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/ble/mock_ble_manager.dart` | service (BLE mock) | event-driven + streaming | `lib/ble/mock_ble_manager.dart` (Phase 1 stub) | exact predecessor |
| `test/ble/mock_ble_manager_test.dart` | test | event-driven | `test/ble/ble_protocol_test.dart` | role-match (same test framework, same package) |
| `pubspec.yaml` | config | — | `pubspec.yaml` (current) | exact (additive change only) |

---

## Pattern Assignments

### `lib/ble/mock_ble_manager.dart` (service, event-driven + streaming)

**Analog:** `lib/ble/mock_ble_manager.dart` (Phase 1 stub — direct predecessor)
**Interface contract source:** `lib/ble/ble_manager.dart`
**Protocol source:** `lib/ble/ble_protocol.dart`

**Imports pattern** — copy and extend from Phase 1 stub (lines 1–4), adding `dart:math`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
```

**Interface members to override** — all 9 from `lib/ble/ble_manager.dart` (lines 11–26):

```dart
// From ble_manager.dart — every one of these must remain @override in Phase 2
Stream<ScannedDevice> get scanResults;
Stream<ConnectionStatus> get connectionStatus;
Stream<List<int>> get statePackets;
Future<void> startScan();
Future<void> stopScan();
Future<void> connect(String deviceId);
Future<void> disconnect();
Future<void> sendCommand(int commandByte);
void dispose();
```

**Eager StreamController initialization pattern** (replaces stub's `throw UnimplementedError` getters):

```dart
// Three broadcast controllers — eager, final fields in class body
// Source: dart.dev StreamController.broadcast API
final _scanController    = StreamController<ScannedDevice>.broadcast();
final _statusController  = StreamController<ConnectionStatus>.broadcast();
final _packetController  = StreamController<List<int>>.broadcast();
```

**Mutable state fields** (new — not in Phase 1 stub):

```dart
double _angleX    = 0.0;
double _angleY    = 0.0;
int    _battery   = 85;
int    _tickCount = 0;

Timer? _ticker;
Timer? _scanTimer;

final Random _rng;

MockBleManager({Random? random}) : _rng = random ?? Random();
```

**Stream getter pattern** (replaces Phase 1 stub lines 16–25 that threw):

```dart
@override
Stream<ScannedDevice> get scanResults => _scanController.stream;

@override
Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

@override
Stream<List<int>> get statePackets => _packetController.stream;
```

**isClosed guard pattern** — critical, prevents StateError on post-dispose tick (see Research PITFALL-1):

```dart
// Every .add() inside a Timer callback must be guarded
void _startTicker() {
  _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (_packetController.isClosed) return;
    _angleX = (_angleX + (_rng.nextDouble() - 0.5) * 0.2).clamp(-45.0, 45.0);
    _angleY = (_angleY + (_rng.nextDouble() - 0.5) * 0.2).clamp(-45.0, 45.0);
    _tickCount++;
    if (_tickCount % 100 == 0) {
      _battery = (_battery - 1).clamp(0, 100);
    }
    _packetController.add(StatePacket.encode(_angleX, _angleY, _battery));
  });
}
```

Note: `.clamp(-45.0, 45.0)` — bounds must be double literals. `.clamp(-45, 45)` returns `num`, not `double` (Research PITFALL-5).

**StatePacket.encode usage** — from `lib/ble/ble_protocol.dart` (lines 50–56):

```dart
// Call signature: StatePacket.encode(double ax, double ay, int battery) → List<int>
// Used inside _startTicker to produce the raw packet bytes
_packetController.add(StatePacket.encode(_angleX, _angleY, _battery));
```

**Command constants** — from `lib/ble/ble_protocol.dart` (lines 11–12):

```dart
// Use these constants in sendCommand() — never raw 0x01/0x02 literals
const int kCmdZeroX = 0x01;
const int kCmdZeroY = 0x02;
```

**connect() pattern** — replaces Phase 1 stub line 34–35:

```dart
@override
Future<void> connect(String deviceId) async {
  _statusController.add(ConnectionStatus.connecting);
  await Future.delayed(const Duration(milliseconds: 300));  // D-05; CLAUDE.md overrides ARCHITECTURE.md's 600ms
  _angleX = 0.0;   // reset on reconnect (Claude's discretion, D-12)
  _angleY = 0.0;
  _tickCount = 0;
  _statusController.add(ConnectionStatus.connected);
  _startTicker();
}
```

**disconnect() pattern** — replaces Phase 1 stub line 38 (user-initiated, emits disconnecting first per D-13):

```dart
@override
Future<void> disconnect() async {
  _statusController.add(ConnectionStatus.disconnecting);
  _stopTicker();
  _statusController.add(ConnectionStatus.disconnected);
}
```

**simulateDisconnect() pattern** — NOT on BleManager interface; concrete-only method (CONTEXT specifics):

```dart
/// WP1-only debug escape hatch. Simulates involuntary disconnect.
/// NOT part of [BleManager] — only [MockBleManager] callers may call this
/// (e.g. a debug button in Phase 4 or a test).
void simulateDisconnect() {
  _stopTicker();
  if (!_statusController.isClosed) {
    _statusController.add(ConnectionStatus.disconnected);
  }
}
```

**dispose() pattern** — extends Phase 1 stub's empty `void dispose() {}` (line 45):

```dart
@override
void dispose() {
  _stopTicker();
  _scanTimer?.cancel();
  _scanController.close();
  _statusController.close();
  _packetController.close();
}

void _stopTicker() {
  _ticker?.cancel();
  _ticker = null;   // null after cancel — prevents stale isActive checks
}
```

**ConnectionStatus enum values available** — from `lib/models/device_state.dart` (lines 4–12):

```dart
// All 7 values — reference for which to emit in which method
enum ConnectionStatus {
  idle,
  scanning,      // emitted by startScan()
  connecting,    // emitted by connect() before delay
  connected,     // emitted by connect() after delay
  disconnecting, // emitted by disconnect() only (not simulateDisconnect)
  disconnected,  // emitted by disconnect() and simulateDisconnect()
  error,
}
```

---

### `test/ble/mock_ble_manager_test.dart` (test, event-driven)

**Analog:** `test/ble/ble_protocol_test.dart` (only existing test file — lines 1–54)

**Imports pattern** — extend analog's imports (ble_protocol_test.dart lines 1–3), adding fake_async:

```dart
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
```

**Test file structure pattern** — copy from `test/ble/ble_protocol_test.dart` (lines 5–54):

```dart
// Outer structure — single main() with group() blocks
void main() {
  group('MockBleManager', () {
    // tests here
  });
}
```

**fakeAsync test pattern** — used for all Timer.periodic and Future.delayed tests (Research Pattern 5):

```dart
// Wrap body in fakeAsync; use async.elapse() to advance virtual clock
// Never use await inside fakeAsync without async.flushFutures() (Research PITFALL-3)
test('description', () {
  fakeAsync((async) {
    final mock = MockBleManager(random: Random(0));  // seeded = deterministic
    // ... set up listeners BEFORE triggering emissions (Research PITFALL-2) ...
    mock.connect('AA:BB:CC:DD:EE:FF');
    async.elapse(const Duration(milliseconds: 300));  // fires connect delay
    async.flushFutures();                              // resolves the Future
    // ... assertions ...
    mock.dispose();
  });
});
```

**expectLater placement rule** — BEFORE the method that emits (Research PITFALL-2):

```dart
// CORRECT: expectLater set up BEFORE calling connect()
test('connect() emits connecting then connected', () async {
  final mock = MockBleManager();
  expectLater(
    mock.connectionStatus,
    emitsInOrder([ConnectionStatus.connecting, ConnectionStatus.connected]),
  );
  await mock.connect('AA:BB:CC:DD:EE:FF');
  mock.dispose();
});
```

**Stream silence test pattern** — for simulateDisconnect (Research Pattern 7):

```dart
// Count events before and after; count must not grow after simulateDisconnect
test('statePackets goes silent after simulateDisconnect', () {
  fakeAsync((async) {
    final mock = MockBleManager(random: Random(0));
    mock.connect('AA:BB:CC:DD:EE:FF');
    async.elapse(const Duration(milliseconds: 400));
    async.flushFutures();

    var count = 0;
    mock.statePackets.listen((_) => count++);
    async.elapse(const Duration(milliseconds: 500));
    final countAtDisconnect = count;

    mock.simulateDisconnect();
    async.elapse(const Duration(milliseconds: 500));

    expect(count, equals(countAtDisconnect));
    mock.dispose();
  });
});
```

**Error/exception assertion pattern** — copy from analog `test/ble/ble_protocol_test.dart` lines 21–28:

```dart
// Analog uses throwsA(isA<ArgumentError>()) pattern
expect(() => someCall(), throwsA(isA<SomeError>()));
```

**Requirements → test coverage map** (from Research validation section):

| Req | Test description |
|-----|-----------------|
| MOCK-01 | Packets arrive at 10 Hz with bounded angle values after connect |
| MOCK-01 | Angles stay within [-45.0, 45.0] after many ticks |
| MOCK-02 | Battery decrements by 1 after 100 ticks (10 seconds virtual time) |
| MOCK-03 | connect() emits connecting then connected with ~300ms delay |
| MOCK-04 | simulateDisconnect() emits disconnected and stops packets |
| MOCK-04 | sendCommand(kCmdZeroX) resets angleX to 0.0 in next packet |

---

### `pubspec.yaml` (config, additive change)

**Analog:** `pubspec.yaml` (current — lines 39–49)

**Current dev_dependencies block** (lines 39–49) — insertion point is after `test: ^1.31.0`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter

  flutter_lints: ^6.0.0
  test: ^1.31.0
  # ADD HERE:
  fake_async: ^1.3.3   # promote from transitive — stable import for Timer tests
```

**Rationale:** `fake_async` is already in `pubspec.lock` at 1.3.3 as a transitive dep via `flutter_test`. Promoting to direct dev dep pins the version explicitly and makes `import 'package:fake_async/fake_async.dart'` stable against future `flutter_test` dep changes. Research Open Question 1 recommends this; the context decision in RESEARCH.md says the planner should decide — include a `flutter pub add --dev fake_async` task in Wave 0.

---

## Shared Patterns

### ConnectionStatus enum usage
**Source:** `lib/models/device_state.dart` lines 4–12
**Apply to:** `mock_ble_manager.dart` (all methods that emit status), `mock_ble_manager_test.dart` (emitsInOrder matchers)

The 7 values map to methods: `startScan()` → `scanning`; `connect()` → `connecting` then `connected`; `disconnect()` → `disconnecting` then `disconnected`; `simulateDisconnect()` → `disconnected` only.

### isClosed guard
**Source:** Research Pattern 2 (from dart.dev StreamController.isClosed)
**Apply to:** Every `.add()` call inside a `Timer` callback in `mock_ble_manager.dart`

```dart
if (_packetController.isClosed) return;
```

Also guard `_scanController.add()` and `_statusController.add()` inside timer callbacks and async code paths that may race `dispose()`.

### Seeded Random for tests
**Source:** Research Pattern 4 (dart:math Random constructor)
**Apply to:** Every test in `mock_ble_manager_test.dart` that exercises angle or battery values

```dart
final mock = MockBleManager(random: Random(0));  // deterministic sequence
```

Tests that only check connection state (no angle/battery assertions) may use `MockBleManager()` (unseeded).

### Package import path convention
**Source:** `lib/ble/mock_ble_manager.dart` (Phase 1) lines 3–4, `test/ble/ble_protocol_test.dart` lines 3–4

All project-local imports use `package:inclinometer/...` — never relative paths:

```dart
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
```

---

## No Analog Found

All three files have strong analogs. No entries.

---

## Metadata

**Analog search scope:** `lib/ble/`, `lib/models/`, `test/ble/`, `pubspec.yaml`
**Files scanned:** 6 source files read (`mock_ble_manager.dart`, `ble_manager.dart`, `ble_protocol.dart`, `device_state.dart`, `ble_protocol_test.dart`, `pubspec.yaml`)
**Pattern extraction date:** 2026-06-04
