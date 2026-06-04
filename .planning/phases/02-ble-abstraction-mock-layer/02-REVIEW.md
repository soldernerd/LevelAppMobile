---
phase: 02-ble-abstraction-mock-layer
reviewed: 2026-06-04T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/ble/mock_ble_manager.dart
  - test/ble/mock_ble_manager_test.dart
  - pubspec.yaml
findings:
  critical: 2
  warning: 5
  info: 3
  total: 10
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-04
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 2 delivers a working `MockBleManager` implementation with `fake_async`-based unit tests covering the four MOCK requirements. The core logic is sound: packet encoding round-trips correctly through `StatePacket.encode/parse`, angle clamping uses correct `double` literals, `simulateDisconnect()` is correctly kept off the `BleManager` interface, and the `isClosed` guard in the ticker callback averts the T-02-02 post-dispose crash.

Two critical issues were found: a double-ticker resource leak when `connect()` is called on an already-connected instance, and missing `isClosed` guards in `connect()` and `disconnect()` that `simulateDisconnect()` already carries — the inconsistency means a racing `dispose()` during connection or disconnection causes an unhandled `StateError`. Five warnings address a leaked scan timer, a fragile battery boundary assertion, and misalignment between the implementation and plan-mandated patterns in the test file.

---

## Critical Issues

### CR-01: Double-ticker resource leak on repeated `connect()` calls

**File:** `lib/ble/mock_ble_manager.dart:79`
**Issue:** `connect()` calls `_startTicker()` without first calling `_stopTicker()`. If `connect()` is called while already connected (or called a second time before the first `await Future.delayed` resolves), a new `Timer.periodic` is created while the old one is still running. Both timers fire concurrently: packets emit at double rate (20 Hz instead of 10 Hz), `_tickCount` is incremented twice per wall-clock tick, and battery drain runs at 2× speed. The old timer reference is overwritten in `_ticker` with no way to cancel it, leaking it for the lifetime of the object.

This will happen in any reconnect scenario (device goes out of range, user taps "Reconnect") and is testable with fakeAsync.

**Fix:**
```dart
@override
Future<void> connect(String deviceId) async {
  _stopTicker(); // cancel any in-flight ticker before reconnecting
  _statusController.add(ConnectionStatus.connecting);
  await Future.delayed(const Duration(milliseconds: 300));
  _angleX = 0.0;
  _angleY = 0.0;
  _tickCount = 0;
  _statusController.add(ConnectionStatus.connected);
  _startTicker();
}
```

---

### CR-02: `connect()` and `disconnect()` do not guard `isClosed` before adding to `_statusController`

**File:** `lib/ble/mock_ble_manager.dart:73,78,84,87`
**Issue:** `simulateDisconnect()` (line 101) correctly guards with `if (!_statusController.isClosed)` before calling `.add()`. However, the four `.add()` calls inside `connect()` (lines 73, 78) and `disconnect()` (lines 84, 87) have no such guard. Calling `.add()` on a closed `StreamController` throws an unhandled `StateError`. The race is real in practice: `dispose()` can be called during navigation teardown while a `connect()` `await Future.delayed` is still pending — the continuation on line 78 will then throw. The inconsistency is especially telling because `simulateDisconnect()` already has the pattern; it was simply not applied consistently.

**Fix:**
```dart
@override
Future<void> connect(String deviceId) async {
  _stopTicker();
  if (_statusController.isClosed) return;
  _statusController.add(ConnectionStatus.connecting);
  await Future.delayed(const Duration(milliseconds: 300));
  _angleX = 0.0;
  _angleY = 0.0;
  _tickCount = 0;
  if (!_statusController.isClosed) {
    _statusController.add(ConnectionStatus.connected);
    _startTicker();
  }
}

@override
Future<void> disconnect() async {
  if (_statusController.isClosed) return;
  _statusController.add(ConnectionStatus.disconnecting);
  _stopTicker();
  if (!_statusController.isClosed) {
    _statusController.add(ConnectionStatus.disconnected);
  }
}
```

Apply the same guard to `startScan()` line 53 (`_statusController.add(ConnectionStatus.scanning)`).

---

## Warnings

### WR-01: `startScan()` leaks the previous scan timer on repeated calls

**File:** `lib/ble/mock_ble_manager.dart:54`
**Issue:** `startScan()` assigns `_scanTimer = Timer(...)` without canceling any existing `_scanTimer`. If `startScan()` is called twice, the first `Timer` fires and emits a `ScannedDevice` unimpeded, then `_scanTimer` points to the second timer. `stopScan()` and `dispose()` only cancel the latest reference; the first timer is never canceled. This causes a spurious `ScannedDevice` emission on every extra `startScan()` call.

**Fix:**
```dart
@override
Future<void> startScan() async {
  _scanTimer?.cancel(); // cancel any in-flight scan timer first
  _scanTimer = null;
  _statusController.add(ConnectionStatus.scanning);
  _scanTimer = Timer(const Duration(milliseconds: 500), () {
    if (!_scanController.isClosed) {
      _scanController.add(const ScannedDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Inclinometer',
        rssi: -65,
      ));
    }
  });
}
```

---

### WR-02: `flushMicrotasks()` used instead of plan-mandated `flushFutures()` in MOCK-01 and MOCK-02 tests

**File:** `test/ble/mock_ble_manager_test.dart:25,59`
**Issue:** The plan (02-01-PLAN.md Task 3) explicitly mandates `async.flushFutures()` to resolve the `Future.delayed` continuation inside `connect()`. The tests instead use `async.flushMicrotasks()`. While these happen to be equivalent for the current `Future.delayed` implementation (because `elapse()` fires the timer, and `flushMicrotasks()` drains the `.then()` continuation), they diverge the moment any nested async work is introduced inside `connect()`. `flushFutures()` pumps both timers and microtasks iteratively until quiescence; `flushMicrotasks()` only drains the microtask queue once. The inconsistency will cause silent test failures if `connect()` is extended with chained `Future` operations.

**Fix:** Replace `async.flushMicrotasks()` with `async.flushFutures()` at lines 25 and 59.

---

### WR-03: MOCK-04 uses list inspection instead of `expectLater` for `disconnected` status assertion

**File:** `test/ble/mock_ble_manager_test.dart:107-139`
**Issue:** The plan explicitly specifies: "set up `expectLater(mock.connectionStatus, emits(ConnectionStatus.disconnected))` BEFORE calling `simulateDisconnect()`". The test instead uses a `List<ConnectionStatus>` accumulator and checks `contains(ConnectionStatus.disconnected)` after the fact. This works today because `simulateDisconnect()` emits synchronously, but it violates the documented pattern, bypasses the timing contract that `expectLater` enforces (it would catch cases where the emission never arrives), and is inconsistent with MOCK-03 which uses `containsAllInOrder`. The `contains` check also cannot distinguish whether `disconnected` was emitted _in response to_ `simulateDisconnect()` versus being left over from a prior `connecting`/`connected` transition.

**Fix:**
```dart
// Set up expectation BEFORE calling simulateDisconnect()
final disconnectedFuture = expectLater(
  mock.connectionStatus,
  emits(ConnectionStatus.disconnected),
);
mock.simulateDisconnect();
async.flushMicrotasks();
await disconnectedFuture;
```

---

### WR-04: MOCK-02 battery boundary is brittle — off-by-one tick risk

**File:** `test/ble/mock_ble_manager_test.dart:62-70`
**Issue:** The test reads `initialBattery` from `packets.first` after elapasing one extra 100ms tick (line 62). At that point `_tickCount == 1`. It then elapses 10000ms, firing 100 more ticks, bringing `_tickCount` to 101. The battery decrements at `_tickCount == 100`, so the final battery is 84 and `84 < 85` passes. However, the 300ms connect delay interacts with the tick timer start: `_startTicker()` is called after the `Future.delayed` resolves, so `_tickCount` resets to 0 inside `connect()` before the ticker starts. The test relies on exact tick count arithmetic that is implicit rather than documented. If the connect delay is adjusted or the battery drain interval (`% 100`) is changed, this test fails without an obvious error message. The assertion message at line 72 helps, but the test design is fragile.

**Fix:** Either assert that `finalBattery <= initialBattery - 1` with an explicit comment explaining the arithmetic, or restructure to elapse exactly `10_000ms` from the point the ticker starts and assert the exact expected value:
```dart
// After 100 ticks (10s), battery decrements exactly once: 85 → 84
expect(finalBattery, equals(84),
    reason: 'After 100 ticks battery should be 84 (started at 85, -1 per 100 ticks)');
```

---

### WR-05: `sendCommand()` mutates angle state when disconnected

**File:** `lib/ble/mock_ble_manager.dart:90-93`
**Issue:** `sendCommand()` zeroes `_angleX` or `_angleY` regardless of connection state. If called while disconnected (e.g. a UI button does not properly gate on connection status), the mutation persists silently. When the device reconnects, `connect()` also resets both angles to 0.0, so the contamination is masked in a normal reconnect flow — but if `sendCommand()` is called for only one axis while disconnected and then only `kCmdZeroY` triggers a reconnect path without `connect()` being called, `_angleX` retains the stale-zeroed value. More concretely: there is no way for a caller to know that `sendCommand()` has no effect when not connected; the method should either guard on connection state or document that calling it while disconnected is explicitly a no-op.

**Fix:**
```dart
@override
Future<void> sendCommand(int commandByte) async {
  // No-op when not connected — real BLE characteristic writes require a connection.
  if (_ticker == null) return;
  if (commandByte == kCmdZeroX) _angleX = 0.0;
  if (commandByte == kCmdZeroY) _angleY = 0.0;
}
```

Using `_ticker == null` as a proxy for "connected" is a reasonable heuristic in the mock since the ticker is started on connect and stopped on disconnect.

---

## Info

### IN-01: Magic number `85` for initial battery has no named constant

**File:** `lib/ble/mock_ble_manager.dart:30`
**Issue:** The initial battery value `85` is an unexplained magic number. The plan references it as "started at 85" but no named constant exists (compare `kCmdZeroX`, `kCmdZeroY` in `ble_protocol.dart`). If the initial battery is ever changed for testing, callers must find and update the literal in the field declaration and the test comment at line 66.

**Fix:** Add a private constant: `static const int _kInitialBattery = 85;` and use it in the field initializer.

---

### IN-02: `flutter_blue_plus`, `go_router`, `wakelock_plus`, and `permission_handler` absent from `pubspec.yaml`

**File:** `pubspec.yaml:30-38`
**Issue:** The `CLAUDE.md` stack table lists `flutter_blue_plus: 2.3.5`, `go_router: 17.3.0`, `wakelock_plus: latest`, and `permission_handler: 12.0.3` as required stack packages. None appear in `pubspec.yaml`. These are needed for Phases 3 and 4 (providers, UI, router, wakelock). The pubspec does not match the stated architecture. Phase 2 scope does not require them, but the gap should be closed before Phase 3 execution begins to avoid a mid-phase dependency conflict.

**Fix:** Add all four packages to `dependencies` in `pubspec.yaml` before Phase 3 starts:
```yaml
dependencies:
  flutter_blue_plus: ^2.3.5
  flutter_riverpod: ^3.3.1
  go_router: ^17.3.0
  permission_handler: ^12.0.3
  wakelock_plus: ^1.0.0
```

---

### IN-03: `environment.sdk` lower bound requires Dart 3.12.1 — verify CI channel compatibility

**File:** `pubspec.yaml:22`
**Issue:** `sdk: ^3.12.1` requires Dart SDK 3.12.1 or higher. Dart 3.12 was released in mid-2025. If the CI pipeline uses `flutter channel stable` with a pinned older toolchain, this constraint will reject the build. This is not a code defect but a deployment risk.

**Fix:** Confirm the CI Flutter/Dart version satisfies this constraint, or relax to `sdk: ^3.5.0` if the codebase does not use any Dart 3.12-specific language features.

---

_Reviewed: 2026-06-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
