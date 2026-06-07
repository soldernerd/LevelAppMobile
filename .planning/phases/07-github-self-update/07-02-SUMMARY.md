---
phase: 07-github-self-update
plan: "02"
subsystem: service-layer
tags: [update-service, dio, open_filex, package_info_plus, shared_preferences, permissions, tdd]
dependency_graph:
  requires: [07-01]
  provides: [UpdateInfo, UpdateService.checkForUpdate, UpdateService.downloadApk, UpdateService.installApk, UpdateService.skipVersion]
  affects: [lib/services/update_service.dart, test/update_service_test.dart]
tech_stack:
  added: []
  patterns: [static-method service convention, catch-all silent-fail, integer-per-segment semver, @visibleForTesting test bridge]
key_files:
  created: [lib/services/update_service.dart, test/update_service_test.dart]
  modified: [linux/flutter/generated_plugins.cmake, macos/Flutter/GeneratedPluginRegistrant.swift, windows/flutter/generated_plugins.cmake]
decisions:
  - "open_filex used (not open_file_plus) — drop-in substitute approved in 07-01"
  - "_isNewer exposed as isNewerForTest via @visibleForTesting bridge so unit tests call through the public surface"
  - "downloadApk and installApk implemented in the initial service write rather than as a separate Task 2 edit"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-07"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
  files_created: 2
---

# Phase 7 Plan 2: UpdateService Implementation Summary

**One-liner:** Created `lib/services/update_service.dart` with `UpdateInfo` model and static `UpdateService` (GitHub API check, integer-per-segment semver comparison, SharedPreferences skip persistence, dio download with progress, permission_handler + open_filex install flow) plus six-case unit test suite covering the non-lexicographic version comparison (UPD-01).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Add failing unit tests for _isNewer | 36a1589 | test/update_service_test.dart |
| 1 (GREEN) | Implement UpdateInfo + UpdateService.checkForUpdate | 0949839 | lib/services/update_service.dart |
| 2 | downloadApk + installApk (included in GREEN commit) | 0949839 | lib/services/update_service.dart |
| chore | Generated plugin registrants | 0dce86e | linux/flutter/generated_plugins.cmake, macos/Flutter/GeneratedPluginRegistrant.swift, windows/flutter/generated_plugins.cmake |

## Deviations from Plan

### Task 2 folded into Task 1 GREEN commit

**Found during:** Task 1 GREEN phase
**Issue:** The plan action for Task 1 says "Leave downloadApk and installApk as stubs OR implement them now if convenient — Task 2 verifies them." Since all necessary patterns were in scope (Pattern 2 dio.download, Pattern 6 REQUEST_INSTALL_PACKAGES, Pattern 7 open_file_plus/open_filex), implementing the complete service in one pass was the efficient choice.
**Effect:** Task 2 verification criteria (grep checks, flutter analyze) were run against the already-complete implementation; all passed.
**Commit:** 0949839

### open_filex import (carried from 07-01)

The PATTERNS.md skeleton used `package:open_file_plus/open_file_plus.dart` and `OpenFile.open()`, but 07-01 approved `open_filex` as the substitute. All references updated to `package:open_filex/open_filex.dart` and `OpenFilex.open()` per the 07-01 SUMMARY deviation note.

## TDD Gate Compliance

| Gate | Commit | Status |
|------|--------|--------|
| RED (test/) | 36a1589 | PASS — tests failed before implementation existed |
| GREEN (feat/) | 0949839 | PASS — all 6 tests pass after implementation |
| REFACTOR | skipped | No cleanup needed — implementation was clean on first pass |

## Known Stubs

None — all four public methods (`checkForUpdate`, `downloadApk`, `installApk`, `skipVersion`) are fully implemented.

## Threat Surface Scan

No new network endpoints or auth paths beyond what is documented in the plan's threat model.

- T-07-03: `tag_name` is only parsed by `replaceFirst('v', '')` and `_isNewer`; never used as a filename (APK path hardcoded as `app-release.apk`). Non-numeric segments default to 0 via `int.tryParse`. No injection surface.
- T-07-04: dio uses HTTPS by default; TLS cert validation is on.
- T-07-06: 10-second send/receive timeout on API GET; entire checkForUpdate wrapped in catch-all returning null.

## Self-Check: PASSED

- lib/services/update_service.dart: FOUND
- test/update_service_test.dart: FOUND
- Commit 36a1589: FOUND (RED gate)
- Commit 0949839: FOUND (GREEN gate)
- flutter test: 6/6 PASS
- flutter analyze: No issues found
