---
phase: 07-github-self-update
plan: "01"
subsystem: platform-config
tags: [dependencies, android, fileprovider, permissions, pubspec]
dependency_graph:
  requires: []
  provides: [open_filex, dio, package_info_plus, shared_preferences, path_provider, android-fileprovider, android-internet-permission, android-install-packages-permission]
  affects: [pubspec.yaml, AndroidManifest.xml, filepaths.xml]
tech_stack:
  added: [dio ^5.9.2, package_info_plus ^10.1.0, shared_preferences ^2.5.5, path_provider ^2.1.5, open_filex ^4.5.0]
  patterns: [FileProvider cache-path mapping, tools:replace manifest-merger guard]
key_files:
  created: [android/app/src/main/res/xml/filepaths.xml]
  modified: [pubspec.yaml, android/app/src/main/AndroidManifest.xml]
decisions:
  - "Package T-07-SC gate resolved: using open_filex (drop-in substitute for open_file_plus) — approved by user/orchestrator"
  - "App version aligned from 1.0.0+1 to 0.1.0+1 so updater fires when a newer GitHub release is published (Pitfall 6)"
metrics:
  duration: "~5 minutes"
  completed: "2026-06-07"
  tasks_completed: 2
  tasks_total: 3
  files_modified: 3
  files_created: 1
---

# Phase 7 Plan 1: Add Update Dependencies and Android Platform Config Summary

**One-liner:** Added five Dart dependencies (dio, package_info_plus, shared_preferences, path_provider, open_filex), aligned app version to 0.1.0+1, and extended AndroidManifest.xml with REQUEST_INSTALL_PACKAGES + INTERNET permissions and a merge-conflict-safe FileProvider pointing at a new res/xml/filepaths.xml cache-path resource.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Verify open_file_plus package legitimacy (checkpoint) | (resolved by orchestrator — no commit) | — |
| 2 | Add dependencies and align pubspec version | be61eb1 | pubspec.yaml, pubspec.lock |
| 3 | Add Android permissions, FileProvider, and filepaths.xml | 8e5338e | AndroidManifest.xml, res/xml/filepaths.xml |

## Deviations from Plan

### Package Substitution (Task 1 checkpoint resolution)

**Package T-07-SC gate resolved: using open_filex (drop-in substitute for open_file_plus) — approved by user/orchestrator.**

- `open_file_plus` was flagged [SUS] in the Package Legitimacy Audit: unverified pub.dev publisher, ~2 years stale
- `open_filex` is the explicitly recommended drop-in substitute with the same `OpenFile.open()` API shape
- Resolved version: open_filex 4.7.0 (resolved by pub from `^4.5.0` constraint)
- The PATTERNS.md import snippet (`package:open_file_plus/open_file_plus.dart`) must be updated to `package:open_filex/open_filex.dart` in Plan 07-02

### Pre-existing Lint Warnings

`flutter analyze` reported 2 pre-existing issues in `test/ui/instrument_screen_test.dart` (unnecessary_import of `dart:ui`, unused_import of `ble_protocol.dart`) — both from Phase 4 commits. No new errors introduced. Out of scope per CLAUDE.md deviation rules.

## Known Stubs

None — this plan is pure configuration (pubspec, manifest, XML resource). No stub data or placeholder text.

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns beyond what is documented in the plan's threat model. The FileProvider `cache-path path="."` exposes only the app's private cache directory (not external storage) — disposition: accept (T-07-01).

## Self-Check: PASSED

- pubspec.yaml: FOUND
- AndroidManifest.xml: FOUND
- filepaths.xml: FOUND
- Commit be61eb1: FOUND
- Commit 8e5338e: FOUND
