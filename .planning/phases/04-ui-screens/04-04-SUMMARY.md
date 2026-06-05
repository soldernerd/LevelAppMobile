---
phase: 04-ui-screens
plan: "04"
subsystem: ui-tests
tags:
  - flutter-test
  - widget-tests
  - scan-screen
  - instrument-screen
  - riverpod
dependency_graph:
  requires:
    - 04-02
    - 04-03
  provides:
    - widget-test coverage for all 13 Phase 4 requirements
  affects:
    - test/ui/scan_screen_test.dart
    - test/ui/instrument_screen_test.dart
tech_stack:
  added: []
  patterns:
    - ProviderScope.overrides with MockBleManager injection
    - _FixedStatusNotifier for deterministic ConnectionStatus in tests
    - setSurfaceSize(1400x900) to prevent RenderFlex overflow from 80sp readout
    - pump(Duration) instead of pumpAndSettle() on unbounded streams
    - StreamController<DeviceState?> injection for stale-data tests
key_files:
  created: []
  modified:
    - test/ui/scan_screen_test.dart
    - test/ui/instrument_screen_test.dart
decisions:
  - Used setSurfaceSize(1400x900) inside each testWidgets to prevent RenderFlex overflow from 80sp angle readout; setSurfaceSize must be called within a test, not setUp/tearDown (assertion: inTest)
  - _FixedStatusNotifier overrides ConnectionNotifier.build() to return a fixed status, enabling isolated connection state tests without triggering real BLE logic
  - _singleStateStream() helper emits one DeviceState and keeps the controller open, avoiding premature stream closure in tests
  - Stale AnimatedOpacity test uses pump(400ms) to allow the 300ms animation duration to complete before asserting opacity
metrics:
  duration: "approx 25 minutes"
  completed_date: "2026-06-05"
  tasks_completed: 2
  files_modified: 2
---

# Phase 4 Plan 04: Widget Test Suites Summary

Replaced placeholder scaffolds in both UI test files with complete widget test suites covering all 13 Phase 4 requirement IDs.

## What Was Built

Full widget test coverage for ScanScreen (8 tests, SCAN-01 through SCAN-05 + INST-01) and InstrumentScreen (9 tests, INST-02 through INST-07 + CONN-04 + stale state + disabled buttons).

## Tasks Completed

### Task 1: scan_screen_test.dart (commit 8a83144)

Replaced the 7-test scaffold with a new 8-test suite covering:

- SCAN-01: FAB shows `Icons.bluetooth_searching` when idle; shows `Icons.stop` when scanning
- SCAN-02: Device list renders device name and dBm trailing text after 600ms scan
- SCAN-03: Unnamed devices (name: '') filtered from list; only named devices show as ListTile
- SCAN-04: Chip label reads 'Idle' by default; reads 'Scanning' with `_FixedStatusNotifier(ConnectionStatus.scanning)` override
- SCAN-05: Tapping ListTile calls `connect()` and transitions status to 'Connecting...'
- INST-01: ScanScreen navigates to InstrumentScreen after MockBleManager.connect() resolves to connected

### Task 2: instrument_screen_test.dart (commit 75d9d37)

Replaced the 1-test placeholder with a 9-test suite covering:

- INST-02+03: Angle text '+012.34°' and '−003.00°' visible; Text.style.fontSize == 80.0
- INST-04: Battery percentage '75%' visible in AppBar actions
- INST-05: 'Zero X' ElevatedButton onPressed is non-null when connected
- INST-06: 'Zero Y' ElevatedButton onPressed is non-null when connected
- INST-07: `textWidget.style?.fontFeatures` contains `FontFeature.tabularFigures()`
- CONN-04 (x2): 'Connected' chip visible when status=connected; 'Disconnected' chip visible when status=disconnected
- Stale state: `AnimatedOpacity.opacity == 0.40` and 'DISCONNECTED' text present after `controller.add(null)`
- Disabled state: Both Zero X and Zero Y buttons have `onPressed == null` when status=disconnected

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RenderFlex overflow causing test failures**
- **Found during:** Task 2 first run
- **Issue:** The `_AngleRow` widget's Row with 80sp angle text overflowed in the default 800x600 test surface, causing Flutter to throw an assertion error that failed the tests
- **Fix:** Added `_setWideSurface(tester)` helper calling `tester.binding.setSurfaceSize(const Size(1400, 900))` at the start of each testWidgets; also registers tearDown to reset to null. setUp/tearDown approach was rejected because `setSurfaceSize` asserts `inTest` — it must be called from within a test callback.
- **Files modified:** `test/ui/instrument_screen_test.dart`
- **Commit:** 75d9d37

**2. [Rule 3 - Blocking] `Override` is not an exported type in flutter_riverpod**
- **Found during:** Task 2 first compile
- **Issue:** `final overrides = <Override>[...]` wouldn't compile because `Override` is not exported from the riverpod public API
- **Fix:** Changed to `final overrides = [...]` (inferred list type)
- **Files modified:** `test/ui/instrument_screen_test.dart`
- **Commit:** 75d9d37

## Known Stubs

None. All tests exercise real widget behavior through the MockBleManager injection pattern.

## Self-Check

- [x] `test/ui/scan_screen_test.dart` exists and contains 8 named tests
- [x] `test/ui/instrument_screen_test.dart` exists and contains 9 named tests
- [x] Commit 8a83144 exists (scan_screen_test.dart)
- [x] Commit 75d9d37 exists (instrument_screen_test.dart)
- [x] All scan tests verified passing (flutter test test/ui/scan_screen_test.dart: 8 passed)
- [x] All instrument tests verified passing (flutter test test/ui/instrument_screen_test.dart: 9 passed)
- [x] Full test suite (flutter test) passes — no regressions in test/ble/ or test/providers/

**3. [Rule 1 - Bug] INST-01 test timed out using direct `await ble.connect()`**
- **Found during:** Task 1 INST-01 test execution
- **Issue:** `await ble.connect()` inside testWidgets blocked indefinitely because `Future.delayed(300ms)` in MockBleManager uses the test zone's fake timer scheduler, which doesn't advance automatically when awaited directly from outside the widget tree
- **Fix:** Changed INST-01 to trigger navigation via the realistic UI flow: tap FAB → scan → tap device tile. Added `setSurfaceSize(1400x900)` to INST-01 since it now renders InstrumentScreen after navigation.
- **Files modified:** `test/ui/scan_screen_test.dart`
- **Commit:** 06dece3

## Self-Check: PASSED
