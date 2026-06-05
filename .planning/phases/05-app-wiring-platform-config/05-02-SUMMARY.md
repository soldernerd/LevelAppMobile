---
phase: 05-app-wiring-platform-config
plan: "02"
subsystem: dependencies-and-providers
tags: [pubspec, go_router, permission_handler, device_info_plus, riverpod, StateProvider]
dependency_graph:
  requires: []
  provides: [go_router, permission_handler, device_info_plus, blePermissionPermanentlyDeniedProvider]
  affects: [lib/providers/device_provider.dart, pubspec.yaml]
tech_stack:
  added: [go_router 17.3.0, permission_handler 12.0.3, device_info_plus ^13.1.0]
  patterns: [StateProvider (Riverpod legacy), flutter pub add]
key_files:
  modified:
    - pubspec.yaml
    - lib/providers/device_provider.dart
  created:
    - test/providers/ble_permission_provider_test.dart
decisions:
  - "Used flutter_riverpod/legacy.dart import for StateProvider — removed from main flutter_riverpod export in Riverpod 3.x"
metrics:
  duration: "~10 minutes"
  completed: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 05 Plan 02: Dependency Addition and Permission Provider Summary

## One-liner

Added go_router 17.3.0, permission_handler 12.0.3, device_info_plus via flutter pub add and declared `blePermissionPermanentlyDeniedProvider` as a `StateProvider<bool>` defaulting to false.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add go_router and permission_handler via flutter pub add | 2cf5575 | pubspec.yaml, pubspec.lock |
| 2 | Add blePermissionPermanentlyDeniedProvider to device_provider.dart | 9f11ad7 | lib/providers/device_provider.dart, test/providers/ble_permission_provider_test.dart |

## Decisions Made

- `StateProvider` is in `flutter_riverpod/legacy.dart` in Riverpod 3.x, not the main export. Added the legacy import rather than switching to a different provider type — the plan explicitly calls for `StateProvider<bool>` and the legacy import is the correct way to access it. This is the idiomatic path for simple mutable boolean state that Plan 05-03 will write/watch directly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added flutter_riverpod/legacy.dart import for StateProvider**
- **Found during:** Task 2 GREEN phase (compilation failure)
- **Issue:** Plan stated "StateProvider is already in scope via flutter_riverpod (imported on line 3)" — incorrect for Riverpod 3.x where StateProvider moved to `flutter_riverpod/legacy.dart`
- **Fix:** Added `import 'package:flutter_riverpod/legacy.dart';` to device_provider.dart
- **Files modified:** lib/providers/device_provider.dart
- **Commit:** 9f11ad7

## Known Stubs

None.

## Threat Flags

None. Both packages (go_router, permission_handler) confirmed from verified pub.dev publishers as documented in RESEARCH.md Package Legitimacy Audit.

## Self-Check: PASSED

- pubspec.yaml contains go_router, permission_handler, device_info_plus: confirmed
- lib/providers/device_provider.dart contains blePermissionPermanentlyDeniedProvider: confirmed
- test/providers/ble_permission_provider_test.dart exists: confirmed
- Commits 2cf5575, 0a9e76b, 9f11ad7 exist in git log: confirmed
- All 16 provider tests pass: confirmed
