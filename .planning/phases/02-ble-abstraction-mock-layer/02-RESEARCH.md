# Phase 2: BLE Abstraction + Mock Layer - Research

**Researched:** 2026-06-04
**Domain:** Dart async streams, Timer, and unit-testing patterns
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Tick interval: 100ms (`Timer.periodic(Duration(milliseconds: 100), ...)`).
- **D-02:** Angle step per tick: `(Random().nextDouble() - 0.5) * 0.2` — ±0.1° per tick.
- **D-03:** Angle bounds: ±45°. Clamp `_angleX` and `_angleY` to `[-45.0, 45.0]`.
- **D-04:** Battery: starts at 85%, drains 1% every 10 seconds (1 decrement per 100 ticks). Min 0%.
- **D-05:** Connect delay: **300ms** (`Future.delayed(const Duration(milliseconds: 300))`). CLAUDE.md overrides ARCHITECTURE.md's 600ms draft.
- **D-06:** `startScan()` emits exactly one `ScannedDevice` after ~500ms delay.
- **D-07:** Mock device: `ScannedDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'Inclinometer', rssi: -65)`.
- **D-08:** `stopScan()` cancels the pending scan timer; stream stays open.
- **D-09:** `sendCommand(kCmdZeroX)` resets `_angleX = 0.0`; `sendCommand(kCmdZeroY)` resets `_angleY = 0.0`. Unknown commands are silent no-ops.
- **D-10:** Unknown command bytes silently no-op.
- **D-11:** `simulateDisconnect()` cancels ticker immediately, adds `ConnectionStatus.disconnected` to `_statusController`. Statepackets goes silent.
- **D-12:** After `simulateDisconnect()`, calling `connect()` again must work (ticker restarts, no state reset of angles unless Claude decides otherwise).
- **D-13:** `disconnect()` (user-initiated) emits `ConnectionStatus.disconnecting` then `ConnectionStatus.disconnected`, cancels ticker.
- **D-14:** `dispose()` cancels ticker, cancels any pending scan timer, closes all three `StreamController`s.

### Claude's Discretion
- `_tickCount` counter approach for battery drain.
- Whether `_angleX`/`_angleY` reset to 0.0 on reconnect after disconnect (resetting on reconnect feels natural).
- RSSI value for mock device (fixed at -65, easily changed).

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MOCK-01 | `MockBleManager` produces animated angle_x and angle_y via random walk (small increments per tick, bounded range) | Timer.periodic + StreamController.broadcast() pattern documented; clamping to ±45° with `clamp()` |
| MOCK-02 | `MockBleManager` produces a slowly drifting battery level (0–100%, random walk) | `_tickCount % 100 == 0` decrement pattern; testable with fakeAsync.elapse() |
| MOCK-03 | `MockBleManager.connect()` simulates a ~300ms delay before resolving to `connected`, exercising the `connecting` UI state | `Future.delayed(const Duration(milliseconds: 300))` — standard Dart async delay; testable without fakeAsync |
| MOCK-04 | `MockBleManager` exposes `simulateDisconnect()` debug method that fires an involuntary disconnect event | `_ticker?.cancel()` + `_statusController.add(ConnectionStatus.disconnected)`; verified via stream silence test |
</phase_requirements>

---

## Summary

Phase 2 replaces the Phase 1 `UnimplementedError` stub in `MockBleManager` with production-quality streaming behaviour. The entire implementation lives in one file (`lib/ble/mock_ble_manager.dart`) and uses only `dart:async`, `dart:math`, and the project's own models.

The core pattern — three `StreamController.broadcast()` instances driven by a `Timer.periodic` ticker — is well-documented in Dart's standard library and requires no external packages beyond what is already in `pubspec.lock`. All unit tests can be written using `package:fake_async` (already a transitive dependency via `flutter_test` at version 1.3.3 — confirmed in `pubspec.lock`), `package:test` (direct dev dependency), and `package:async` (transitive, provides `StreamQueue`). No `pubspec.yaml` changes are needed for Phase 2.

The two key testing strategies are: (1) `fakeAsync + async.elapse()` for advancing virtual time to test `Timer.periodic` behaviour without real delays, and (2) `expectLater + emitsInOrder` for asserting stream emission sequences. For `simulateDisconnect()` silence verification, a short `async.elapse()` after the call and `neverEmits` / absence of new events is the reliable approach.

**Primary recommendation:** Eager-initialize all three `StreamController`s in the class body (not lazily), use `_controller.isClosed` guards in the ticker callback to prevent `StateError: Cannot add new events after calling close`, and inject `Random` as an optional constructor parameter to enable seeded deterministic tests.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Streaming mock angle/battery data | Service / BLE Layer (`MockBleManager`) | — | Data production belongs to the BLE layer; providers in Phase 3 only consume |
| Protocol encoding (StatePacket.encode) | Service / BLE Layer (`ble_protocol.dart`) | — | Already implemented in Phase 1; mock calls it directly |
| Connection state emission | Service / BLE Layer (`MockBleManager`) | — | `connectionStatus` stream is part of the `BleManager` interface contract |
| Scan result emission | Service / BLE Layer (`MockBleManager`) | — | `scanResults` stream is part of the `BleManager` interface contract |
| Timer lifecycle management | Service / BLE Layer (`MockBleManager`) | — | `Timer` is an implementation detail of the mock; no higher layer sees it |

---

## Standard Stack

### Core (no new packages required)

| Library | Version in Lock | Purpose | Why Standard |
|---------|----------------|---------|--------------|
| `dart:async` | SDK built-in | `StreamController.broadcast()`, `Timer.periodic()`, `Future.delayed()` | Standard Dart async primitives |
| `dart:math` | SDK built-in | `Random()` for random-walk angle deltas | Standard Dart math library |
| `package:test` | 1.31.0 (direct dev) | Test runner, `test()`, `expect()`, `expectLater()`, stream matchers | Already in pubspec.yaml |
| `package:fake_async` | 1.3.3 (transitive) | Advance virtual time in Timer.periodic tests without real delays | Pulled in by flutter_test SDK dep |
| `package:async` | 2.13.1 (transitive) | `StreamQueue` for sequential stream consumption in tests | Pulled in transitively |

[VERIFIED: pubspec.lock] — all five packages confirmed present in the project's lock file.

### No New Packages Needed

`pubspec.yaml` requires zero changes for Phase 2. All required testing utilities are already resolvable.

**Important:** `fake_async` is a **transitive** dependency. To use it in tests, add it as a direct dev dependency so the import is stable and the version is explicit:

```yaml
dev_dependencies:
  fake_async: ^1.3.3   # was transitive — promote to direct for test imports
```

[ASSUMED] — promoting a transitive to a direct dev dep is standard practice when you import it explicitly, but the project will also compile without this change since pub resolves transitives. The planner should decide whether to include a `pub add` task.

---

## Package Legitimacy Audit

> All packages used in Phase 2 are either Dart SDK built-ins or packages already present in `pubspec.lock`. No new packages are being introduced. This section confirms existing package provenance.

| Package | Registry | Source | Disposition |
|---------|----------|--------|-------------|
| `dart:async` | Dart SDK | Built-in | Approved — SDK primitive |
| `dart:math` | Dart SDK | Built-in | Approved — SDK primitive |
| `package:test` | pub.dev | Direct dev dep, dart.dev publisher | Approved — already in pubspec |
| `package:fake_async` | pub.dev | Transitive (via flutter_test), dart.dev publisher | Approved — in pubspec.lock at 1.3.3 |
| `package:async` | pub.dev | Transitive (via test), dart.dev publisher | Approved — in pubspec.lock at 2.13.1 |

**Packages removed due to slopcheck:** none
**Packages flagged as suspicious:** none

*slopcheck was not run (no new packages to verify). All packages are verified via `pubspec.lock` [VERIFIED: pubspec.lock].*

---

## Architecture Patterns

### System Architecture Diagram

```
 test harness (fakeAsync zone)
        │
        │  advance virtual time via async.elapse()
        ▼
 MockBleManager
  ├── _scanController (StreamController.broadcast)
  │     └── startScan() ──Timer(500ms)──► add(ScannedDevice('AA:BB:CC:DD:EE:FF'))
  │
  ├── _statusController (StreamController.broadcast)
  │     ├── connect()  ──Future.delayed(300ms)──► add(connecting) → add(connected)
  │     ├── disconnect() ──► add(disconnecting) → add(disconnected)
  │     └── simulateDisconnect() ──► add(disconnected)
  │
  └── _packetController (StreamController.broadcast)
        └── _ticker (Timer.periodic 100ms)
              │  _angleX += (rng.nextDouble() - 0.5) * 0.2  → clamp([-45, 45])
              │  _angleY += (rng.nextDouble() - 0.5) * 0.2  → clamp([-45, 45])
              │  if (_tickCount % 100 == 0) _battery = max(0, _battery - 1)
              └── add(StatePacket.encode(_angleX, _angleY, _battery))

 Downstream consumers (Phase 3)
  ├── scanResultsProvider ←── _scanController.stream
  ├── connectionProvider  ←── _statusController.stream
  └── deviceStateProvider ←── _packetController.stream
                                   .map(StatePacket.parse)
```

### Recommended Project Structure

No structural changes to the project layout — Phase 2 is a single file replacement:

```
lib/
└── ble/
    ├── ble_manager.dart        # unchanged — abstract interface
    ├── mock_ble_manager.dart   # REPLACED — full implementation
    └── ble_protocol.dart       # unchanged — StatePacket.encode() called by mock

test/
└── ble/
    ├── ble_protocol_test.dart  # existing Phase 1 tests
    └── mock_ble_manager_test.dart  # NEW — Phase 2 tests
```

### Pattern 1: Eager StreamController Initialization

**What:** Initialize all three `StreamController.broadcast()` instances as `final` fields in the class body, not lazily.
**When to use:** Any class that owns streams and has a `dispose()` method. Eager initialization prevents null-check boilerplate and ensures `isClosed` is always valid to query.

```dart
// Source: dart.dev/dart-async/StreamController/StreamController.broadcast.html
class MockBleManager implements BleManager {
  final _scanController    = StreamController<ScannedDevice>.broadcast();
  final _statusController  = StreamController<ConnectionStatus>.broadcast();
  final _packetController  = StreamController<List<int>>.broadcast();

  Timer? _ticker;
  Timer? _scanTimer;
  // ...
}
```

[CITED: https://api.flutter.dev/flutter/dart-async/StreamController/StreamController.broadcast.html]

### Pattern 2: isClosed Guard in Timer Callback

**What:** Check `_packetController.isClosed` before calling `.add()` inside the Timer callback.
**When to use:** Any Timer callback that adds to a StreamController — the timer fires asynchronously and `dispose()` may have been called between ticks.

```dart
// Source: dart.dev StreamController.isClosed property
void _startTicker() {
  _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (_packetController.isClosed) return;   // guard against post-dispose tick
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

[CITED: https://api.flutter.dev/flutter/dart-async/StreamController/isClosed.html]

### Pattern 3: Timer Cancellation

**What:** Use `Timer?` nullable field, call `_ticker?.cancel()`, and null-check before cancel.
**When to use:** Any object that conditionally creates and destroys a `Timer.periodic`.

```dart
// Source: dart.dev/dart-async/Timer/Timer.periodic.html
Timer? _ticker;

void _stopTicker() {
  _ticker?.cancel();
  _ticker = null;   // prevent double-cancel confusion; also enables isActive checks
}

@override
void dispose() {
  _stopTicker();
  _scanTimer?.cancel();
  _scanController.close();
  _statusController.close();
  _packetController.close();
}
```

[CITED: https://api.dart.dev/stable/dart-async/Timer/Timer.periodic.html]

**Key fact about cancel():** Calling `cancel()` on an already-cancelled timer is safe — subsequent calls are no-ops. [CITED: dart.dev API docs] Nulling the field after cancel is belt-and-suspenders and documents intent clearly.

### Pattern 4: Injected Random for Testability

**What:** Accept `Random?` as an optional constructor parameter; fall back to `Random()` if null.
**When to use:** Any class with non-deterministic behaviour that needs unit testing.

```dart
// Source: api.flutter.dev/flutter/dart-math/Random/Random.html
import 'dart:math';

class MockBleManager implements BleManager {
  final Random _rng;

  MockBleManager({Random? random}) : _rng = random ?? Random();
  // ...
}

// In tests — deterministic sequence:
final mock = MockBleManager(random: Random(42));

// In production (main.dart) — unseeded:
MockBleManager()
```

[CITED: https://api.flutter.dev/flutter/dart-math/Random/Random.html]

### Pattern 5: fakeAsync for Timer-Driven Streams

**What:** Wrap test body in `fakeAsync((async) { ... async.elapse(Duration); })` to advance virtual time without real delays.
**When to use:** Any test that involves `Timer.periodic`, `Future.delayed`, or time-gated stream emissions.
**Import:** `import 'package:fake_async/fake_async.dart';`

```dart
// Source: pub.dev/packages/fake_async
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

test('emits 5 packets in 500ms', () {
  fakeAsync((async) {
    final mock = MockBleManager(random: Random(0));
    final packets = <List<int>>[];
    mock.statePackets.listen(packets.add);

    mock.connect('AA:BB:CC:DD:EE:FF');
    async.elapse(const Duration(milliseconds: 300));  // connect delay fires
    async.elapse(const Duration(milliseconds: 500));  // 5 ticks at 100ms each

    expect(packets.length, greaterThanOrEqualTo(5));
    mock.dispose();
  });
});
```

[CITED: https://pub.dev/packages/fake_async]

### Pattern 6: expectLater + emitsInOrder for Connection State Sequence

**What:** Use `expectLater` (not `expect`) for stream matchers; place it BEFORE the method that triggers emissions.
**When to use:** Testing ordered sequences of stream events.

```dart
// Source: codewithandrea.com/articles/async-tests-streams-flutter/
test('connect() emits connecting then connected', () async {
  final mock = MockBleManager();
  
  // Set up expectation BEFORE triggering emissions
  expectLater(
    mock.connectionStatus,
    emitsInOrder([ConnectionStatus.connecting, ConnectionStatus.connected]),
  );
  
  await mock.connect('AA:BB:CC:DD:EE:FF');
  mock.dispose();
});
```

[CITED: https://codewithandrea.com/articles/async-tests-streams-flutter/]

### Pattern 7: Testing Stream Silence after simulateDisconnect

**What:** After `simulateDisconnect()`, verify no more packets arrive using fakeAsync + event counting.
**When to use:** Testing that a stream stops emitting after an action.

```dart
// Source: dart.dev stream matcher docs
test('statePackets goes silent after simulateDisconnect', () {
  fakeAsync((async) {
    final mock = MockBleManager(random: Random(0));
    mock.connect('AA:BB:CC:DD:EE:FF');
    async.elapse(const Duration(milliseconds: 400)); // connected + a few ticks

    int countBefore = 0;
    mock.statePackets.listen((_) => countBefore++);
    async.elapse(const Duration(milliseconds: 500));  // 5 more ticks

    final countAtDisconnect = countBefore;
    mock.simulateDisconnect();

    async.elapse(const Duration(milliseconds: 500));  // no new ticks should fire
    // countBefore should not have grown after simulateDisconnect
    expect(countBefore, equals(countAtDisconnect));
    mock.dispose();
  });
});
```

[ASSUMED] — exact test structure based on `fakeAsync` mechanics. The fakeAsync zone stops timers when cancelled; elapsing after cancel produces no new callbacks.

### Anti-Patterns to Avoid

- **Adding to closed controller:** Always guard `_packetController.add(...)` with `if (_packetController.isClosed) return;` inside the Timer callback. The Timer fires asynchronously; `dispose()` may race it.
- **Single-subscription controller:** Using `StreamController()` instead of `StreamController.broadcast()` will throw `Bad state: Stream has already been listened to` when Phase 3 wires multiple providers.
- **`await Future.delayed()`in tests without fakeAsync:** Tests for `connect()`'s 300ms delay will take real time. Use `fakeAsync` + `async.elapse(Duration(milliseconds: 300))` to keep tests fast.
- **Not nulling `_ticker` after cancel:** Calling cancel is safe but not setting to null means `_ticker?.isActive` checks become unreliable. Null after cancel.
- **Resetting `_angleX/_angleY` inside `_startTicker()`:** Don't reset angles there. Reset in `connect()` before calling `_startTicker()` so the decision is visible at the call site (Claude's discretion — D-12 says reconnect restarts from current values, but resetting on reconnect "feels natural").

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Advancing virtual time in tests | `await Future.delayed()` in tests | `fakeAsync + async.elapse()` | Real delays make test suite slow; 100ms × many tests = seconds |
| Stream sequence assertion | Manual counter + comparison | `expectLater + emitsInOrder` | Built-in stream matchers handle async timing correctly |
| Sequential stream consumption | Manual listener + completer | `StreamQueue` from `package:async` | Prevents race conditions in tests that need to await specific events |
| Protocol byte encoding | Custom byte builder in MockBleManager | `StatePacket.encode()` already in `ble_protocol.dart` | Already tested and verified in Phase 1 |

**Key insight:** The only hand-rolling needed is the random-walk arithmetic itself (three arithmetic ops). Everything else — streaming, timing, testing — has a standard Dart primitive or tested package.

---

## Common Pitfalls

### Pitfall 1: StateError "Cannot add new events after calling close"

**What goes wrong:** The `Timer.periodic` callback fires after `dispose()` has been called and closed the `StreamController`.
**Why it happens:** `dispose()` calls `_ticker?.cancel()` and then `_packetController.close()`. The cancel is async-safe but a tick already queued before cancel fires may execute after close.
**How to avoid:** Guard every `.add()` call in the Timer callback with `if (_packetController.isClosed) return;`.
**Warning signs:** `StateError` crash in tests that call `dispose()` immediately after starting the ticker.

[CITED: https://github.com/felangel/bloc/issues/52 — same root cause pattern]

### Pitfall 2: expectLater Placed After Method Call

**What goes wrong:** Test calls the method that emits events, THEN calls `expectLater`. The stream has already emitted; the matcher never matches; test hangs indefinitely.
**Why it happens:** Broadcast streams don't buffer past events. The matcher only sees future events.
**How to avoid:** Always set up `expectLater(stream, ...)` before calling the method that produces events. This is the canonical Flutter stream testing pattern.
**Warning signs:** Test hangs without timeout; passes if you add an artificial delay.

[CITED: https://codewithandrea.com/articles/async-tests-streams-flutter/]

### Pitfall 3: fakeAsync + async/await Interaction

**What goes wrong:** Using `await` inside `fakeAsync` for code that uses `Future.delayed` — the await suspends but no one advances the fake clock, so the future never resolves.
**Why it happens:** `fakeAsync` controls the virtual clock; `await` without `async.elapse()` will block forever on a delayed future.
**How to avoid:** For `connect()` test (which uses `Future.delayed(300ms)`): either (a) call `async.elapse(Duration(milliseconds: 300))` without await, or (b) use `mock.connect(...)` synchronously and then elapse. If you need to await the connect future, use `async.flushFutures()` after calling `async.elapse()`.
**Warning signs:** Test hangs inside `fakeAsync` block when a `Future.delayed` is in the code path.

[CITED: https://pub.dev/packages/fake_async]

### Pitfall 4: Broadcast Stream Drops Events With No Listeners

**What goes wrong:** `startScan()` emits a `ScannedDevice` 500ms after call, but the test didn't listen to `scanResults` before calling `startScan()`. The event is dropped.
**Why it happens:** `StreamController.broadcast()` does not buffer — events with no listeners are silently discarded.
**How to avoid:** Subscribe to `scanResults` before calling `startScan()` in both test and production code.
**Warning signs:** Test listening for scan result events receives empty stream.

[CITED: https://api.flutter.dev/flutter/dart-async/StreamController/StreamController.broadcast.html]

### Pitfall 5: double.clamp() Return Type

**What goes wrong:** `_angleX.clamp(-45.0, 45.0)` returns `num`, not `double`, if min/max are not double literals.
**Why it happens:** Dart's `clamp()` returns the type of the narrower bound. With `int` bounds it returns `num`.
**How to avoid:** Always write bounds as `double` literals: `.clamp(-45.0, 45.0)`. The `-45.0` / `45.0` suffix is required.
**Warning signs:** Compile-time type error assigning `num` to `double _angleX`.

[ASSUMED] — based on Dart type system behaviour; standard pitfall in numeric Dart code.

---

## Code Examples

### Complete MockBleManager Skeleton

```dart
// lib/ble/mock_ble_manager.dart
// Source: patterns verified from dart.dev API docs + ARCHITECTURE.md sketch

import 'dart:async';
import 'dart:math';

import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';

/// WP1 mock implementation of [BleManager].
///
/// Produces animated random-walk angle and battery streams behind the
/// [BleManager] interface. All behaviour is testable without a device.
///
/// [simulateDisconnect] is a WP1-only debug escape hatch. It is NOT part of
/// the [BleManager] interface — only code with a concrete [MockBleManager]
/// reference may call it (e.g. a debug button or a test).
class MockBleManager implements BleManager {
  // --- streams (eager-initialized) ---
  final _scanController    = StreamController<ScannedDevice>.broadcast();
  final _statusController  = StreamController<ConnectionStatus>.broadcast();
  final _packetController  = StreamController<List<int>>.broadcast();

  // --- mutable state ---
  double _angleX  = 0.0;
  double _angleY  = 0.0;
  int    _battery = 85;
  int    _tickCount = 0;

  Timer? _ticker;
  Timer? _scanTimer;

  final Random _rng;

  MockBleManager({Random? random}) : _rng = random ?? Random();

  // --- BleManager interface ---

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<List<int>> get statePackets => _packetController.stream;

  @override
  Future<void> startScan() async {
    _statusController.add(ConnectionStatus.scanning);
    _scanTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_scanController.isClosed) {
        _scanController.add(const ScannedDevice(
          id:   'AA:BB:CC:DD:EE:FF',
          name: 'Inclinometer',
          rssi: -65,
        ));
      }
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<void> connect(String deviceId) async {
    _statusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 300));  // D-05
    _angleX = 0.0;  // reset on reconnect (Claude's discretion)
    _angleY = 0.0;
    _tickCount = 0;
    _statusController.add(ConnectionStatus.connected);
    _startTicker();
  }

  @override
  Future<void> disconnect() async {
    _statusController.add(ConnectionStatus.disconnecting);
    _stopTicker();
    _statusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendCommand(int commandByte) async {
    if (commandByte == kCmdZeroX) _angleX = 0.0;
    if (commandByte == kCmdZeroY) _angleY = 0.0;
    // unknown commands: silent no-op (D-10)
  }

  /// WP1-only debug method. Simulates an involuntary disconnect.
  /// Not part of [BleManager] — only [MockBleManager] callers may use this.
  void simulateDisconnect() {
    _stopTicker();
    if (!_statusController.isClosed) {
      _statusController.add(ConnectionStatus.disconnected);
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _scanTimer?.cancel();
    _scanController.close();
    _statusController.close();
    _packetController.close();
  }

  // --- internal helpers ---

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

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
```

[CITED: ARCHITECTURE.md §MockBleManager implementation sketch, dart.dev API docs]
Note: Connect delay is 300ms (D-05, CLAUDE.md) — not 600ms from ARCHITECTURE.md draft.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| `StateNotifierProvider` | `Notifier` / `AsyncNotifier` (Riverpod 3.x) | Phase 3 must use new API — already in CLAUDE.md |
| `quiver` package's FakeAsync | `package:fake_async` (standalone, dart.dev) | Use `fake_async` directly, not `quiver` |
| Single-subscription `StreamController()` | `StreamController.broadcast()` | Multiple Phase 3 providers can listen simultaneously |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Promoting `fake_async` from transitive to direct dev dep is needed for explicit import stability | Standard Stack | Low — package still resolves as transitive; only version pinning is looser |
| A2 | `double.clamp(-45.0, 45.0)` returns `double` when both bounds are double literals | Code Examples / Pitfall 5 | Compile error if wrong — easily caught at implementation time |
| A3 | Resetting `_angleX/_angleY` to 0.0 on `connect()` reconnect is the right behaviour (Claude's discretion per D-12) | Code Examples | UX: angles don't carry over after disconnect; acceptable for WP1 mock |
| A4 | fakeAsync zone handles both `Future.delayed` and `Timer.periodic` simultaneously | Pitfall 3 / Pattern 5 | Tests may hang if assumption is wrong; mitigated by `async.flushFutures()` after `elapse()` |

**All other claims were verified from `pubspec.lock`, `dart.dev` official docs, or cited articles.**

---

## Open Questions

1. **Should `fake_async` be promoted to a direct dev dependency?**
   - What we know: It's already in `pubspec.lock` as `transitive` at 1.3.3. Tests can import it today without adding it to `pubspec.yaml`.
   - What's unclear: Whether keeping it as transitive-only is acceptable project hygiene.
   - Recommendation: Promote to direct dev dep with `flutter pub add --dev fake_async` in a Wave 0 task. Explicit beats implicit for test infrastructure.

2. **Should `_angleX`/`_angleY` reset to 0.0 on reconnect?**
   - What we know: D-12 says ticker restarts from current angle values; the CONTEXT.md note says "resetting on reconnect feels natural" under Claude's discretion.
   - Recommendation: Reset to 0.0 in `connect()`. This makes the UI behave predictably in Phase 4 testing sessions (known starting state after simulated disconnect/reconnect cycle).

---

## Environment Availability

> Phase 2 has no external dependencies beyond the Flutter SDK and packages already in pubspec.lock.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | dart:async, dart:math | ✓ | per pubspec.lock | — |
| `package:test` | Unit tests | ✓ | 1.31.0 (direct dev) | — |
| `package:fake_async` | Timer.periodic tests | ✓ | 1.3.3 (transitive) | Use real delays (slow but functional) |
| `package:async` | StreamQueue in tests | ✓ | 2.13.1 (transitive) | Use manual listener pattern |

[VERIFIED: pubspec.lock]

**Missing dependencies with no fallback:** none
**Missing dependencies with fallback:** none

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `package:test` 1.31.0 + `package:fake_async` 1.3.3 |
| Config file | none (uses default `dart test` discovery) |
| Quick run command | `flutter test test/ble/mock_ble_manager_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MOCK-01 | Packets arrive at 10 Hz with bounded angle values after connect | unit | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |
| MOCK-01 | Angles stay within [-45.0, 45.0] after many ticks | unit | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |
| MOCK-02 | Battery decrements by 1 after 100 ticks (10 seconds virtual) | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |
| MOCK-03 | connect() emits connecting then connected with ~300ms delay | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |
| MOCK-04 | simulateDisconnect() emits disconnected and stops packets | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |
| MOCK-04 | sendCommand(kCmdZeroX) resets angleX to 0.0 in next packet | unit | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/ble/mock_ble_manager_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/ble/mock_ble_manager_test.dart` — covers MOCK-01 through MOCK-04
- [ ] No additional framework install needed — `package:test` already present

---

## Security Domain

> Phase 2 is a pure Dart mock layer with no network I/O, no user input, no storage, and no authentication. ASVS categories do not apply.

| ASVS Category | Applies | Rationale |
|---------------|---------|-----------|
| V2 Authentication | No | No auth primitives |
| V3 Session Management | No | No session tokens |
| V4 Access Control | No | No access decisions |
| V5 Input Validation | No | `sendCommand` input is an `int` from trusted Phase 4 callers |
| V6 Cryptography | No | No crypto operations |

---

## Sources

### Primary (HIGH confidence)

- `pubspec.lock` — confirmed presence and versions of all packages [VERIFIED: pubspec.lock]
- `lib/ble/ble_manager.dart` — interface contract (9 members) confirmed by reading file
- `lib/ble/ble_protocol.dart` — `StatePacket.encode()` and `kCmdZeroX/kCmdZeroY` confirmed by reading file
- `lib/models/device_state.dart` — `ConnectionStatus`, `ScannedDevice`, `DeviceState` confirmed by reading file
- [dart.dev StreamController.broadcast](https://api.flutter.dev/flutter/dart-async/StreamController/StreamController.broadcast.html) — broadcast semantics, onListen/onCancel, no buffering
- [dart.dev Timer.periodic](https://api.dart.dev/stable/dart-async/Timer/Timer.periodic.html) — cancellation, double-cancel safety
- [dart.dev Random constructor](https://api.flutter.dev/flutter/dart-math/Random/Random.html) — seed parameter for reproducible tests
- [pub.dev fake_async](https://pub.dev/packages/fake_async) — fakeAsync + elapse pattern, current version 1.3.3

### Secondary (MEDIUM confidence)

- [codewithandrea.com async stream tests](https://codewithandrea.com/articles/async-tests-streams-flutter/) — expectLater placement rule, emitsInOrder pattern
- [invertase.io stream matchers cheat sheet](https://invertase.io/blog/assertions-in-dart-and-flutter-tests-now-for-sure-an-ultimate-cheat-sheet) — emits, neverEmits, emitsInOrder, emitsDone
- [flutter/flutter issue #19541](https://github.com/flutter/flutter/issues/19541) — confirms flutter_test runs in FakeAsync zone (indirectly confirms fake_async is a transitive dep)

### Tertiary (LOW confidence)

- None — all material claims have primary or secondary citations.

---

## Metadata

**Confidence breakdown:**

- Standard Stack: HIGH — all packages verified in pubspec.lock
- Architecture: HIGH — interface and model files read directly; canonical sketch in ARCHITECTURE.md
- Pitfalls: HIGH (Pitfall 1-4) / MEDIUM (Pitfall 5) — dart.dev citations for 1-4; type behaviour for 5 is assumed
- Testing patterns: HIGH — confirmed via pub.dev fake_async docs and codewithandrea article

**Research date:** 2026-06-04
**Valid until:** 2026-07-04 (stable Dart stdlib; fake_async is dart.dev maintained)
