---
phase: 04-ui-screens
plan: "01"
subsystem: providers + test-infrastructure
tags: [sendCommand, test-scaffold, riverpod, wave-1]
dependency_graph:
  requires: [03-03-SUMMARY]
  provides: [ConnectionNotifier.sendCommand, test/ui/ scaffold]
  affects: [lib/providers/device_provider.dart, test/ui/]
tech_stack:
  added: []
  patterns: [ConnectionNotifier delegation pattern, ProviderScope widget test harness]
key_files:
  created:
    - test/ui/scan_screen_test.dart
    - test/ui/instrument_screen_test.dart
  modified:
    - lib/providers/device_provider.dart
decisions:
  - sendCommand delegates through ConnectionNotifier to keep BleManager out of lib/ui/ per CLAUDE.md
  - Test scaffold files omit screen imports intentionally — screen widgets are Wave 2 work
metrics:
  duration: "~5 min"
  completed: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 4 Plan 01: Scaffold — sendCommand + test/ui/ directory Summary

**One-liner:** Added `sendCommand(int commandByte)` to `ConnectionNotifier` and created `test/ui/` with ProviderScope widget-test scaffolds that compile and pass without screen widgets.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Add sendCommand to ConnectionNotifier | 7ba9581 | lib/providers/device_provider.dart |
| 2 | Create test/ui/ scaffold files | 0f278a8 | test/ui/scan_screen_test.dart, test/ui/instrument_screen_test.dart |

## Verification Results

- `flutter analyze lib/providers/device_provider.dart` — no issues
- `flutter test test/ui/` — 2 tests passed
- `flutter test` (full suite) — 25 tests passed, no regressions

## Deviations from Plan

**1. [Rule 3 - Blocking] Worktree branch was behind main by 22 commits**
- **Found during:** Task 1 — worktree had Phase 2 stub of device_provider.dart (19 lines)
- **Issue:** Worktree was spawned before Phase 3 commits landed on main; the worktree branch did not have the full ConnectionNotifier implementation
- **Fix:** `git merge main --no-edit` fast-forwarded the worktree branch to include Phase 3 work
- **Files modified:** All Phase 3 + Phase 4 planning files brought in via fast-forward merge
- **Commit:** merge commit (fast-forward, no separate hash)

## Known Stubs

- `test/ui/scan_screen_test.dart` — placeholder test (`expect(true, isTrue)`) intentionally pending Wave 2 (SCAN-01 through SCAN-05 assertions will replace it in plan 04-04)
- `test/ui/instrument_screen_test.dart` — placeholder test intentionally pending Wave 2 (INST-01 through INST-07, CONN-04 assertions will replace it in plan 04-04)

These stubs are by design — screen widgets do not exist yet. They will be resolved in plan 04-04.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundary changes introduced.

## Self-Check: PASSED

- `lib/providers/device_provider.dart` — contains `Future<void> sendCommand(int commandByte) async {` ✓
- `test/ui/scan_screen_test.dart` — exists, contains `ScanScreen — scaffold` ✓
- `test/ui/instrument_screen_test.dart` — exists, contains `InstrumentScreen — scaffold` ✓
- Commit 7ba9581 — exists ✓
- Commit 0f278a8 — exists ✓
