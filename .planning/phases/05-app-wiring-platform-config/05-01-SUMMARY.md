---
phase: 05-app-wiring-platform-config
plan: 01
subsystem: platform-config
tags: [android, ios, permissions, build-config, ble]
dependency_graph:
  requires: []
  provides: [android-sdk-versions, android-ble-permissions, ios-ble-usage-description]
  affects: [flutter_blue_plus, permission_handler]
tech_stack:
  added: []
  patterns: [hardcoded-sdk-integers, neverForLocation-flag]
key_files:
  created: []
  modified:
    - android/app/build.gradle.kts
    - android/app/src/main/AndroidManifest.xml
    - ios/Runner/Info.plist
decisions:
  - "Used hardcoded integer literals for minSdk/compileSdk (not flutter.* delegates) per BUILD-01/BUILD-02"
  - "BLUETOOTH_SCAN decorated with neverForLocation to prevent OS from treating BLE scan as location source (T-05-01)"
  - "NSBluetoothAlwaysUsageDescription only — no NSBluetoothPeripheralUsageDescription (deprecated iOS 13+)"
metrics:
  duration: "5 minutes"
  completed: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 3
---

# Phase 05 Plan 01: Platform Configuration and BLE Permissions Summary

Android build SDK versions hardcoded to integers (minSdk=24, compileSdk=35) and all required BLE permissions declared in AndroidManifest.xml and Info.plist.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Harden build.gradle.kts SDK versions | 134ae3e | android/app/build.gradle.kts |
| 2 | Declare BLE permissions | e190985 | android/app/src/main/AndroidManifest.xml, ios/Runner/Info.plist |

## What Was Built

**Task 1 — build.gradle.kts SDK hardening:**
- `compileSdk = flutter.compileSdkVersion` replaced with `compileSdk = 35`
- `minSdk = flutter.minSdkVersion` replaced with `minSdk = 24`
- `targetSdk = flutter.targetSdkVersion` left unchanged (only min/compile were in scope)
- All other lines (ndkVersion, versionCode, versionName, buildTypes, compileOptions, kotlin block) untouched

**Task 2 — BLE permission declarations:**
- AndroidManifest.xml: five `uses-permission` elements inserted before `<application>` block
  - `BLUETOOTH_SCAN` with `usesPermissionFlags="neverForLocation"` (Android 12+)
  - `BLUETOOTH_CONNECT` (Android 12+)
  - `ACCESS_FINE_LOCATION` (required for BLE scanning on API 24-30)
  - `BLUETOOTH` with `maxSdkVersion="30"` (legacy compat)
  - `BLUETOOTH_ADMIN` with `maxSdkVersion="30"` (legacy compat)
- Info.plist: `NSBluetoothAlwaysUsageDescription` key/string inserted before closing `</dict>`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — this plan contains no Dart code or UI components.

## Threat Flags

None — all threat mitigations from the plan's threat model were applied:
- T-05-01 mitigated: `neverForLocation` flag on BLUETOOTH_SCAN prevents OS from treating BLE scan as location data source.

## Self-Check: PASSED

- `grep "minSdk = 24" android/app/build.gradle.kts` → 1 match
- `grep "compileSdk = 35" android/app/build.gradle.kts` → 1 match
- `grep "BLUETOOTH_SCAN" android/app/src/main/AndroidManifest.xml` → 1 match with neverForLocation
- `grep "BLUETOOTH_CONNECT" android/app/src/main/AndroidManifest.xml` → 1 match
- `grep "ACCESS_FINE_LOCATION" android/app/src/main/AndroidManifest.xml` → 1 match
- `grep "NSBluetoothAlwaysUsageDescription" ios/Runner/Info.plist` → 1 match
- `grep "android:label" android/app/src/main/AndroidManifest.xml` → "inclinometer" present (application block unchanged)
- `grep "NSBluetoothPeripheralUsageDescription" ios/Runner/Info.plist` → 0 matches (correct)
- Commits 134ae3e and e190985 exist in git log
