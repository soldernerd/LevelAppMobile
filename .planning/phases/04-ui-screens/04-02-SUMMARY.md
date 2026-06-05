---
phase: 04-ui-screens
plan: "02"
subsystem: ui
tags: [scan-screen, main-entry-point, riverpod-bugfix, tdd, wave-2]
dependency_graph:
  requires: [04-01-SUMMARY]
  provides: [ScanScreen, Phase4-main.dart, instrument_screen-stub]
  affects:
    - lib/ui/scan_screen.dart
    - lib/ui/instrument_screen.dart
    - lib/main.dart
    - lib/providers/device_provider.dart
    - test/ui/scan_screen_test.dart
tech_stack:
  added: []
  patterns:
    - ConsumerWidget with ref.watch at top of build()
    - ref.listen for navigation side-effects (post-frame push)
    - _scanRevisionProvider counter for Riverpod equality-bypass
    - addTearDown(ble.dispose) pattern for widget tests with async mock timers
key_files:
  created:
    - lib/ui/scan_screen.dart
    - lib/ui/instrument_screen.dart
  modified:
    - lib/main.dart
    - lib/providers/device_provider.dart
    - test/ui/scan_screen_test.dart
decisions:
  - stub InstrumentScreen created to satisfy scan_screen.dart compilation (plan 04-03 replaces it)
  - _scanRevisionProvider counter replaces state=state workaround (Riverpod 3 suppresses identical enum notifications)
  - ble.dispose() called explicitly in connect test body to drain Future.delayed 300ms timer before test ends
metrics:
  duration: "~45 min"
  completed: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 4 Plan 02: ScanScreen + Phase 4 main.dart Summary

**One-liner:** ScanScreen ConsumerWidget with FAB/chip/device-list per UI-SPEC, plus Phase 4 standalone main.dart using MockBleManager override; fixed Riverpod scan-result rebuild bug via revision counter.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| RED | Failing widget tests for ScanScreen | da7d525 | test/ui/scan_screen_test.dart |
| 1 | Build ScanScreen (GREEN) | 1afeb8c | lib/ui/scan_screen.dart, lib/ui/instrument_screen.dart (stub), lib/providers/device_provider.dart, test/ui/scan_screen_test.dart |
| 2 | Create Phase 4 standalone main.dart | 770808f | lib/main.dart |

## Verification Results

- `dart analyze lib/ui/scan_screen.dart` — no issues
- `dart analyze lib/main.dart` — no issues
- `flutter test test/ui/scan_screen_test.dart` — 7 tests passed (SCAN-01 through SCAN-05)
- `flutter test` (full suite) — 31 tests passed, no regressions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worktree behind main by 36 commits**
- **Found during:** Start of execution
- **Issue:** Worktree did not have Phase 3 or Phase 4 plan-01 commits
- **Fix:** `git merge main --no-edit` fast-forward
- **Commit:** fast-forward merge (no separate hash)

**2. [Rule 1 - Bug] `state = state` does not trigger Riverpod listener notifications**
- **Found during:** Task 1 — widget test confirmed device list never updated during scan
- **Issue:** `Notifier.state = state` with identical enum value is suppressed by Riverpod 3's equality check (`previous == next`). The Phase 3 comment "RESOLVED: A1" was incorrect — `state = state` does NOT notify listeners for same-value enums.
- **Fix:** Added `_ScanRevisionNotifier` (internal counter) and `_scanRevisionProvider`. `ConnectionNotifier.build()` scan subscription now calls `ref.read(_scanRevisionProvider.notifier).increment()` instead of `state = state`. `scanResultsProvider` watches `_scanRevisionProvider` as rebuild trigger. `startScan()` resets the counter.
- **Files modified:** lib/providers/device_provider.dart
- **Commit:** 1afeb8c

**3. [Rule 3 - Blocking] instrument_screen.dart does not exist (needed by scan_screen.dart)**
- **Found during:** Task 1 — plan 04-03 (wave 2 parallel) creates InstrumentScreen but scan_screen.dart imports it
- **Issue:** Cannot compile scan_screen.dart without InstrumentScreen
- **Fix:** Created `lib/ui/instrument_screen.dart` as a minimal stub (Scaffold with placeholder text). Plan 04-03 replaces this entirely.
- **Files modified:** lib/ui/instrument_screen.dart (created)
- **Commit:** 1afeb8c

**4. [Rule 1 - Bug] Widget test timer management for MockBleManager**
- **Found during:** Task 1 — testWidgets assertion "A Timer is still pending"
- **Issue:** MockBleManager's `Future.delayed(300ms)` in `connect()` and 100ms periodic ticker are not cancelled by widget tree disposal
- **Fix:** `addTearDown(ble.dispose)` in `buildHarness()` for most tests; explicit `ble.dispose()` call before test body ends in the connect test (where the 300ms delay and ticker must be drained in sequence)
- **Files modified:** test/ui/scan_screen_test.dart
- **Commit:** 1afeb8c

## Known Stubs

- `lib/ui/instrument_screen.dart` — placeholder Scaffold; will be fully implemented by plan 04-03. Does not affect plan 02 goals.

## Threat Flags

None — no new network endpoints, auth paths, file access, or schema changes introduced. All UI input goes through `connectionNotifierProvider.notifier` per the threat model.

## Self-Check: PASSED

- `lib/ui/scan_screen.dart` — exists, contains `ScanScreen extends ConsumerWidget` ✓
- `lib/ui/instrument_screen.dart` — exists (stub) ✓
- `lib/main.dart` — contains `bleManagerProvider.overrideWithValue(MockBleManager())` ✓
- `lib/main.dart` — contains `home: const ScanScreen()` ✓
- `lib/main.dart` — contains Phase 4 temporary comment ✓
- `lib/providers/device_provider.dart` — contains `_scanRevisionProvider` ✓
- No `flutter_blue_plus` import in lib/ui/ ✓
- Commit da7d525 (RED) — exists ✓
- Commit 1afeb8c (GREEN) — exists ✓
- Commit 770808f (Task 2) — exists ✓
- flutter test full suite: 31 tests passed ✓
