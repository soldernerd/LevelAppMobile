---
phase: 04-ui-screens
reviewed: 2026-06-05T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/main.dart
  - lib/providers/device_provider.dart
  - lib/ui/instrument_screen.dart
  - lib/ui/scan_screen.dart
  - test/ui/instrument_screen_test.dart
  - test/ui/scan_screen_test.dart
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-06-05
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Six files reviewed — two production UI screens, one provider module, one entry point, and two test files. The core logic is broadly sound: the architecture constraint (no `flutter_blue_plus` import in `lib/ui/`) is honoured, `Notifier`/`AsyncNotifier` is used correctly, and `keepAlive` is wired. However, two correctness bugs were found: a navigation loop that fires on every rebuild while `connected`, and a stale-data false-positive caused by conflating `AsyncLoading` with "no data yet". Four warnings cover missing error propagation, a Riverpod anti-pattern, an architecture violation (direct `MockBleManager` cast in production UI), and a `_singleStateStream` resource leak in tests.

---

## Critical Issues

### CR-01: `ref.listen` navigation fires on every `connected` rebuild, not just on transition

**File:** `lib/ui/scan_screen.dart:24-29`

**Issue:** `ref.listen` receives `(prev, next)` and the guard is `if (next == ConnectionStatus.connected)`. On the *first* `connected` event `prev` is `connecting` so the push fires correctly. But if the provider notifies again while still `connected` (e.g. a scan-revision counter increment or any other rebuild trigger re-evaluates the outer `build()` method and the listen is re-registered), a second `Navigator.push` will stack a duplicate `InstrumentScreen`. In practice, the `ref.listen` call inside `ConsumerWidget.build` is re-registered on each build, so any provider rebuild while `connected` that re-runs `build` (e.g. `scanResultsProvider` updating) will re-trigger the listener with `prev == connected, next == connected`, which the current guard does NOT prevent.

The guard must check that the previous state was not already `connected`:

```dart
ref.listen(connectionNotifierProvider, (prev, next) {
  if (next == ConnectionStatus.connected &&
      prev != ConnectionStatus.connected) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InstrumentScreen()),
    );
  }
});
```

---

### CR-02: `_formatAngle` pads the wrong field — integer portion can overflow 3 digits silently

**File:** `lib/ui/instrument_screen.dart:208`

**Issue:** The expression is:

```dart
'$sign${abs.toStringAsFixed(2).padLeft(6, '0')}°'
```

`toStringAsFixed(2)` on `abs` produces a string like `"3.00"` (4 chars) or `"12.34"` (5 chars) or `"123.45"` (6 chars). `padLeft(6, '0')` pads the entire decimal string to 6 characters, so `"3.00"` → `"003.00"` and `"12.34"` → `"012.34"`. That is correct for values < 100.

However, `DeviceState.angleX/angleY` are unbounded `double` values — `StatePacket.parse` places no range constraint on the parsed float, and `MockBleManager._startTicker` clamps to `±45°`, but WP2 real BLE data arrives unclamped. If `abs >= 100` the string `"123.45"` is already 6 chars and `padLeft` is a no-op — the result is `"+123.45°"` which breaks the fixed-width layout. At `abs >= 1000` it produces `"+1000.00°"` and the readout overflows the `Row`.

More critically, if the firmware sends `NaN` or `Infinity` (valid IEEE 754 floats parsed by `getFloat32`), `toStringAsFixed` throws a `RangeError` on `NaN` and produces `"Infinity"` for infinity, which then renders garbage. `StatePacket.parse` does not guard against non-finite floats.

Fix: add a finite-value check in `StatePacket.parse` and clamp or reject out-of-range angles, OR add a guard in `_formatAngle`:

```dart
String _formatAngle(double value) {
  if (!value.isFinite) return '  ---.--°';
  final clamped = value.clamp(-999.99, 999.99);
  final sign = clamped >= 0 ? '+' : '−';
  final abs = clamped.abs();
  return '$sign${abs.toStringAsFixed(2).padLeft(6, '0')}°';
}
```

---

## Warnings

### WR-01: Architecture violation — direct `MockBleManager` cast in production UI widget

**File:** `lib/ui/instrument_screen.dart:66-67`

**Issue:**

```dart
final mgr = ref.read(bleManagerProvider);
if (mgr is MockBleManager) mgr.simulateDisconnect();
```

This is inside `lib/ui/instrument_screen.dart`, which imports `package:inclinometer/ble/mock_ble_manager.dart`. CLAUDE.md states "No `flutter_blue_plus` import in `lib/ui/`" as the architecture constraint, and the broader intent is that `lib/ui/` must not reach through the provider abstraction to concrete BLE types. `MockBleManager` is a concrete BLE implementation; importing it into a production UI file couples the UI layer to the mock and means the mock is included in the release binary.

The button is already gated by `kDebugMode`, so it is dead code in release builds, but the import and the `is MockBleManager` cast remain compiled into debug builds and violate the layering rule.

Fix: expose `simulateDisconnect()` through the provider (e.g. add a `debugSimulateDisconnect()` method on `ConnectionNotifier` that performs the `is MockBleManager` check internally), then call it from the UI with no direct mock import.

---

### WR-02: `connect()` errors are silently swallowed — UI never reflects connection failure

**File:** `lib/ui/scan_screen.dart:153-155`, `lib/providers/device_provider.dart:146-148`

**Issue:** `ConnectionNotifier.connect()` calls `bleManagerProvider.connect(deviceId)` and `await`s it, but the call site in `ScanScreen._buildDeviceList` is:

```dart
onTap: () => ref
    .read(connectionNotifierProvider.notifier)
    .connect(device.id),
```

The `Future` returned by `connect()` is not `await`ed and its error is not handled. If `connect()` throws (e.g. real BLE throws a `FlutterBluePlusException` in WP2, or anything unexpected), the exception becomes an unhandled `Future` error — it surfaces as an uncaught async exception in the console but produces no user-visible feedback and does not update `ConnectionStatus` to `error`.

Similarly, `startScan()` and `stopScan()` FAB callbacks in `scan_screen.dart:70-75` are fire-and-forget.

Fix: wrap async provider calls with error handling or use a dedicated `AsyncNotifier` error state:

```dart
onTap: () async {
  try {
    await ref.read(connectionNotifierProvider.notifier).connect(device.id);
  } catch (e) {
    // ConnectionNotifier should set state = ConnectionStatus.error on failure
  }
},
```

At minimum, `ConnectionNotifier.connect()` should catch its own errors and set `state = ConnectionStatus.error`.

---

### WR-03: `scanResultsProvider` uses `ref.read` inside a `Provider` — derived state is stale on first access

**File:** `lib/providers/device_provider.dart:194`

**Issue:**

```dart
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(_scanRevisionProvider); // rebuild trigger
  return ref.read(connectionNotifierProvider.notifier).scannedDevices;
});
```

`ref.read(connectionNotifierProvider.notifier)` inside a `Provider` body is a Riverpod anti-pattern. `ref.read` does not subscribe — it reads the notifier synchronously but establishes no dependency. If `connectionNotifierProvider` is not yet alive (first access race), `ref.read` initialises it but does not track its lifecycle relative to `scanResultsProvider`. The design works in practice only because `_scanRevisionProvider` serves as the rebuild trigger — but if `connectionNotifierProvider` is torn down and re-created (e.g. in tests that rebuild the `ProviderScope`), `ref.read` will silently grab the new notifier instance without `scanResultsProvider` being invalidated, potentially returning a stale or empty list.

Fix: use `ref.watch` on the notifier itself (accessing a getter), or restructure so `ConnectionNotifier` exposes scanned devices via its own state type rather than a side-channel list.

---

### WR-04: `_singleStateStream` leaks a `StreamController` in tests

**File:** `test/ui/instrument_screen_test.dart:54-58`

**Issue:**

```dart
Stream<DeviceState?> _singleStateStream(DeviceState state) {
  final controller = StreamController<DeviceState?>();
  controller.add(state);
  return controller.stream;
}
```

The `StreamController` is never closed and never registered with `addTearDown`. This leaves the controller open for the duration of the test. Flutter's test framework checks for unclosed streams in some configurations; more importantly, it holds references that prevent GC and can cause false-positive "pending timer" warnings in test output if the provider re-subscribes.

Fix: close the controller after adding the event, or register a teardown:

```dart
Stream<DeviceState?> _singleStateStream(DeviceState state) async* {
  yield state;
}
```

---

## Info

### IN-01: Duplicate `_chipColor` / `_chipLabel` implementations across two files

**File:** `lib/ui/instrument_screen.dart:220-245`, `lib/ui/scan_screen.dart:173-213`

**Issue:** Both `instrument_screen.dart` and `scan_screen.dart` define private top-level `_chipColor(ConnectionStatus)` and `_chipLabel(ConnectionStatus)` functions with identical logic and identical color values. This is copy-paste duplication. When `ConnectionStatus` gains a new variant (e.g. WP2 adds `bonding`), both copies must be updated or they diverge.

Fix: extract to a shared `lib/ui/connection_chip.dart` or `lib/ui/widgets/status_chip.dart` utility and import from both screens.

---

### IN-02: Placeholder UUIDs in `ble_protocol.dart` will silently pass wrong values to WP2

**File:** `lib/ble/ble_protocol.dart:6-8`

**Issue:**

```dart
const String kServiceUuid = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid = '0000ZZZZ-0000-1000-8000-00805f9b34fb';
```

These are not valid UUIDs (`XXXX`/`YYYY`/`ZZZZ` are literal placeholder strings). They are unused in WP1 (mock bypasses GATT), but they are exported constants. If WP2 imports them without replacing them, the GATT service discovery will fail silently or with a cryptic BLE error rather than a clear "wrong UUID" message. There is no `// TODO` or `assert` guard.

Fix: add a compile-time or runtime assertion, or a prominent `// TODO(WP2): replace with real firmware UUIDs` comment with a lint-suppression note so it surfaces in `dart analyze`.

---

### IN-03: `setUpAll(TestWidgetsFlutterBinding.ensureInitialized)` is redundant

**File:** `test/ui/instrument_screen_test.dart:61`, `test/ui/scan_screen_test.dart:35`

**Issue:** `testWidgets` already ensures the binding is initialized automatically before each test. Calling `ensureInitialized` in `setUpAll` is a no-op that adds noise and may mislead future maintainers into thinking explicit initialization is required.

Fix: remove both `setUpAll` calls.

---

_Reviewed: 2026-06-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
