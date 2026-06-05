---
phase: 04-ui-screens
fixed_at: 2026-06-05T00:00:00Z
review_path: .planning/phases/04-ui-screens/04-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-06-05
**Source review:** `.planning/phases/04-ui-screens/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (2 Critical, 4 Warning)
- Fixed: 6
- Skipped: 0

---

## Fixed Issues

### CR-01: `ref.listen` navigation fires on every `connected` rebuild

**Files modified:** `lib/ui/scan_screen.dart`
**Commit:** `c7d8752`
**Applied fix:** Added `prev != ConnectionStatus.connected` guard to the `ref.listen` callback. The `Navigator.push` now only fires when the status transitions *into* `connected` from a non-connected prior state, not on every provider rebuild while already connected.

---

### CR-02: `_formatAngle` NaN/Infinity/overflow

**Files modified:** `lib/ui/instrument_screen.dart`
**Commit:** `fd52dbb`
**Applied fix:** Added `if (!value.isFinite) return '  ---.--°';` guard at the top of `_formatAngle` to handle NaN and Infinity from raw BLE data. Added `value.clamp(-999.99, 999.99)` before formatting so values ≥ 100° or ≤ -100° do not break the fixed-width layout.

---

### WR-01: Architecture violation — direct `MockBleManager` cast in production UI

**Files modified:** `lib/providers/device_provider.dart`, `lib/ui/instrument_screen.dart`
**Commit:** `22e7613`
**Applied fix:** Added `ConnectionNotifier.debugSimulateDisconnect()` to `device_provider.dart`, which imports `MockBleManager` and performs the `is MockBleManager` check internally. Removed `mock_ble_manager.dart` import from `instrument_screen.dart` and updated the debug button to call `connectionNotifierProvider.notifier.debugSimulateDisconnect()` instead.

---

### WR-02: Fire-and-forget async calls — UI never reflects connection failure

**Files modified:** `lib/providers/device_provider.dart`, `lib/ui/scan_screen.dart`
**Commit:** `d0fff09`
**Applied fix:** Added `try/catch` in `ConnectionNotifier.connect()`, `startScan()`, and `stopScan()` — each catches exceptions and sets `state = ConnectionStatus.error` so failures surface in the UI. Wrapped the three fire-and-forget call sites in `scan_screen.dart` (FAB `onPressed` for start/stop scan, device tile `onTap`) with minimal `async` closures that `await` the returned `Future`.

---

### WR-03: `scanResultsProvider` uses `ref.read` inside a `Provider`

**Files modified:** `lib/providers/device_provider.dart`
**Commit:** `182bda1`
**Applied fix:** Changed `ref.read(connectionNotifierProvider.notifier)` to `ref.watch(connectionNotifierProvider.notifier)` in `scanResultsProvider`. This establishes a proper Riverpod dependency so `scanResultsProvider` is invalidated and re-evaluated if `connectionNotifierProvider` is ever recreated (e.g. in tests that rebuild `ProviderScope`), preventing stale device list reads.

---

### WR-04: `_singleStateStream` leaks a `StreamController` in tests

**Files modified:** `test/ui/instrument_screen_test.dart`
**Commit:** `0599070`
**Applied fix:** Replaced the `StreamController`-based helper with an `async*` generator function. The generator yields the single event and closes the stream automatically when the function body completes, eliminating the leaked controller. The `dart:async` import was retained because `StreamController` is still used in the stale-state test at line 201.

---

## Skipped Issues

None — all findings were fixed.

---

## Post-fix Verification

- `flutter analyze lib/ui/scan_screen.dart` — no issues
- `flutter analyze lib/ui/instrument_screen.dart` — no issues
- `flutter analyze lib/providers/device_provider.dart` — no issues
- `flutter analyze test/ui/instrument_screen_test.dart` — 2 pre-existing info/warning (unused imports unrelated to these fixes)
- `flutter test` — **40/40 tests passed**

---

_Fixed: 2026-06-05_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
