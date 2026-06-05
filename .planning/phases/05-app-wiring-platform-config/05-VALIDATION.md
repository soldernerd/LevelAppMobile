---
phase: 5
phase_slug: 05-app-wiring-platform-config
created: 2026-06-05
---

# Validation Strategy — Phase 5: App Wiring + Platform Config

## Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) |
| Config file | none — flutter test runs without config file |
| Quick run command | `flutter test test/` |
| Full suite command | `flutter test` |

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| PERM-01 | AndroidManifest.xml declares BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION | file inspection | `grep -c "BLUETOOTH_SCAN" android/app/src/main/AndroidManifest.xml` | Verified by file diff |
| PERM-02 | Runtime BLE permission request via permission_handler | manual | — requires device/emulator | Verified on device |
| PERM-03 | Rationale dialog shown before system prompt | manual | — UI interaction | Verified on device |
| PERM-04 | Permanently denied → openAppSettings() | manual | — requires device state | Verified on device |
| PERM-05 | iOS Info.plist has NSBluetoothAlwaysUsageDescription | file inspection | `grep -c "NSBluetoothAlwaysUsageDescription" ios/Runner/Info.plist` | Verified by file diff |
| BUILD-01 | minSdk = 24 in build.gradle.kts | smoke | `grep "minSdk = 24" android/app/build.gradle.kts` | Source assertion |
| BUILD-02 | compileSdk = 35 in build.gradle.kts | smoke | `grep "compileSdk = 35" android/app/build.gradle.kts` | Source assertion |

## Sampling Rate

- **Per task commit:** `flutter test` (existing provider and model tests must remain green)
- **Per wave merge:** `flutter test` + manual device verification of permission flow
- **Phase gate:** All automated tests green + manual BLE permission flow verified on Android device/emulator before `/gsd:verify-work`

## Automated Smoke Checks

Run after Wave 1 and Wave 2 complete:

```bash
grep "minSdk = 24" android/app/build.gradle.kts
grep "compileSdk = 35" android/app/build.gradle.kts
grep -c "BLUETOOTH_SCAN" android/app/src/main/AndroidManifest.xml
grep -c "NSBluetoothAlwaysUsageDescription" ios/Runner/Info.plist
flutter test
flutter analyze lib/
```

## Manual Verification Items (UAT)

These require a physical Android device or emulator:

1. **Cold launch → rationale dialog** — App shows an app-provided rationale dialog (not the OS dialog) before the system BLE permission prompt appears. The dialog contains a plain-language explanation ("Bluetooth to connect to your inclinometer").
2. **Permission grant → scan screen** — After granting BLE permissions, the scan screen appears without error. The permission dialog does not appear again on subsequent cold launches.
3. **Permanently denied → inline banner** — After permanently denying BLE permissions, the scan screen shows an inline message (not a dialog) with an "Open Settings" button. Tapping "Open Settings" opens the Android app settings page.
4. **go_router guard** — Directly navigating to `/instrument` when not connected redirects to `/scan`.
5. **Post-connect navigation** — Tapping a device in the scan list triggers the connecting → connected flow, and the screen automatically transitions to `/instrument` via `context.go`.
6. **Disconnect does not eject** — Triggering `simulateDisconnect()` while on `/instrument` keeps the user on the instrument screen (stale data indicator from Phase 4 appears; no auto-redirect to `/scan`).

## Wave 0 Notes

- No new test files needed for Phase 5 — file changes are platform config (manifest, plist, gradle) and wiring (main.dart, scan_screen.dart).
- Existing test suite (provider tests, model tests, widget tests) must remain green throughout Phase 5 execution.
- Verify test baseline: `flutter test` green before starting Wave 1 execution.
