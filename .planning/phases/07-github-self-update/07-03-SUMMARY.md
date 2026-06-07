---
phase: 07-github-self-update
plan: "03"
subsystem: ui-provider
tags: [update-provider, scan-screen, riverpod, futureprovider, dialog, download-progress, widget-test]
dependency_graph:
  requires: [07-02]
  provides: [updateCheckProvider, _showUpdateDialog, UPD-02 widget test]
  affects: [lib/providers/update_provider.dart, lib/ui/scan_screen.dart, test/ui/scan_screen_test.dart]
tech_stack:
  added: []
  patterns:
    - FutureProvider autoDispose (D-11, read-only one-shot check)
    - ref.listen (not ref.watch) to avoid rebuild on provider state change
    - addPostFrameCallback deferred showDialog (Pitfall 2 guard)
    - file-scope bool guard (_updateDialogShown) for T-07-08 DoS mitigation
    - ValueNotifier<double> + ValueListenableBuilder for dialog-internal progress
    - @visibleForTesting reset helper for file-scope state between tests
    - updateCheckProvider.overrideWith in all test ProviderScopes to prevent Dio network calls
key_files:
  created: [lib/providers/update_provider.dart]
  modified: [lib/ui/scan_screen.dart, test/ui/scan_screen_test.dart]
decisions:
  - "ref.listen (not ref.watch) on updateCheckProvider — prevents ScanScreen rebuild on each provider state transition"
  - "_updateDialogShown file-scope bool mirrors _blePermissionsRequested pattern — prevents T-07-08 DoS from repeated dialog on rebuild"
  - "ValueNotifier<double> + ValueListenableBuilder used inside dialog — avoids StatefulWidget for transient download-progress state"
  - "ValueNotifier<bool> downloadingNotifier switches dialog content from choice view to progress view after Update tap"
  - "barrierDismissible: false on update dialog — forces explicit Skip or Update action; prevents accidental dismiss with accidental back tap"
  - "resetUpdateDialogShownForTest() @visibleForTesting exposed to allow widget tests to reset file-scope guard between runs"
  - "buildHarness extended with optional updateResult param (defaults null) — all existing tests override updateCheckProvider to prevent network calls in test environment"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-07"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 2
  files_created: 1
---

# Phase 7 Plan 3: Update Dialog UI Summary

**One-liner:** Wired `updateCheckProvider` (FutureProvider, autoDispose, D-11) into ScanScreen via `ref.listen` + `addPostFrameCallback`, presenting a one-time AlertDialog naming the release version with Skip (persists tag via `UpdateService.skipVersion`) and Update (downloads APK with `LinearProgressIndicator` then installs) actions; extended ScanScreen widget tests with UPD-02 assertion and overrode `updateCheckProvider` in all test harnesses to prevent network calls.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create updateCheckProvider FutureProvider | 972fa96 | lib/providers/update_provider.dart |
| 2 | Add update dialog trigger and download flow to ScanScreen | bda2a3d | lib/ui/scan_screen.dart |
| 3 | Extend ScanScreen widget test + fix existing test harnesses | a571a87 | lib/ui/scan_screen.dart, test/ui/scan_screen_test.dart |

## Deviations from Plan

### Auto-fix: override updateCheckProvider in all existing test ProviderScopes

**Rule 1 — Bug (breaks existing tests)**
**Found during:** Task 3 test run
**Issue:** Adding `ref.listen(updateCheckProvider, ...)` to `ScanScreen.build()` caused all existing tests to register a Dio HTTP call (pending timer) because none of the existing test harnesses overrode `updateCheckProvider`. Tests failed with "Pending timers" assertion.
**Fix:** 
- Extended `buildHarness` with an optional `updateResult` parameter defaulting to null; always adds `updateCheckProvider.overrideWith((ref) async => null)` to the ProviderScope overrides.
- Added `updateCheckProvider.overrideWith((ref) async => null)` to three inline ProviderScope instances in SCAN-03, SCAN-04, SCAN-05 tests.
**Files modified:** test/ui/scan_screen_test.dart, lib/ui/scan_screen.dart (resetUpdateDialogShownForTest)
**Commit:** a571a87

### Auto-add: @visibleForTesting reset helper

**Rule 2 — Missing critical functionality (tests cannot reset file-scope guard)**
**Found during:** Task 3
**Issue:** `_updateDialogShown` is a file-scope bool that persists across widget tests within the same test process. Without a reset mechanism, a test triggering the dialog would permanently set the guard, silently preventing any subsequent test in the same run from seeing the dialog.
**Fix:** Added `resetUpdateDialogShownForTest()` annotated with `@visibleForTesting` to `scan_screen.dart`, called in the UPD-02 `setUp` block.
**Files modified:** lib/ui/scan_screen.dart
**Commit:** a571a87

## Known Stubs

None — the update dialog is fully wired: `updateCheckProvider` delegates to the real `UpdateService.checkForUpdate()`, Skip calls `UpdateService.skipVersion()`, Update calls `UpdateService.downloadApk()` then `UpdateService.installApk()` with live `LinearProgressIndicator` progress.

## Threat Surface Scan

No new network endpoints beyond what was documented in the plan's threat model. The dialog renders `info.version` (a public release tag string) with no injection surface.

- T-07-07: `info.version` is displayed in dialog content — only the public version number from the GitHub API `tag_name` field (leading `v` stripped). No secrets or tokens exposed.
- T-07-08: `_updateDialogShown` file-scope guard + `ref.listen` (not `ref.watch`) ensure exactly one dialog per session. Implemented as designed.

## Self-Check: PASSED

- lib/providers/update_provider.dart: FOUND
- lib/ui/scan_screen.dart: FOUND (modified)
- test/ui/scan_screen_test.dart: FOUND (modified)
- Commit 972fa96 (Task 1): FOUND
- Commit bda2a3d (Task 2): FOUND
- Commit a571a87 (Task 3): FOUND
- flutter analyze lib/providers/update_provider.dart lib/ui/scan_screen.dart: No issues found
- flutter test test/ui/scan_screen_test.dart: 9/9 PASS (including UPD-02)
- flutter test (full suite): 50/50 PASS
