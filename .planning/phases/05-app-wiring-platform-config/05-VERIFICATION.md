---
phase: 05-app-wiring-platform-config
verified: 2026-06-05T00:00:00Z
status: human_needed
score: 13/13 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Cold-launch on Android API 24+ device or emulator — confirm rationale dialog appears before system Bluetooth permission prompt"
    expected: "AlertDialog titled 'Bluetooth Permission' appears first; after tapping Continue the system BLE prompt appears; granting permissions proceeds to scan screen without error"
    why_human: "permission_handler platform channel requires a real Android runtime; cannot be verified with flutter test"
  - test: "Deny BLE permissions permanently (deny twice or via app settings) — confirm inline banner appears on scan screen"
    expected: "Dark-red banner with text 'Bluetooth permission is permanently denied. Open Settings to grant access.' and an 'Open Settings' button that opens system app settings"
    why_human: "isPermanentlyDenied state requires actual Android permission flow; not reproducible in unit tests"
  - test: "Navigate to /instrument directly (e.g. deep-link or back-press from scan screen after connecting then disconnecting) while not connected — confirm redirect to /scan"
    expected: "Router redirect intercepts navigation attempt to /instrument and sends user to /scan"
    why_human: "go_router redirect behavior requires a running app with real navigation stack; widget tests use a mocked router"
---

# Phase 5: App Wiring + Platform Config Verification Report

**Phase Goal:** The app boots correctly on Android with a complete main.dart, go_router navigation, runtime permission flow, and correct build.gradle SDK settings; iOS scaffold is structurally in place
**Verified:** 2026-06-05
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | build.gradle.kts declares minSdk = 24 as hardcoded integer | VERIFIED | Line 22: `minSdk = 24`; no `flutter.minSdkVersion` present |
| 2 | build.gradle.kts declares compileSdk = 35 as hardcoded integer | VERIFIED | Line 9: `compileSdk = 35`; no `flutter.compileSdkVersion` present |
| 3 | AndroidManifest.xml declares BLUETOOTH_SCAN with neverForLocation | VERIFIED | Line 2: `android:usesPermissionFlags="neverForLocation"` |
| 4 | AndroidManifest.xml declares BLUETOOTH_CONNECT and ACCESS_FINE_LOCATION | VERIFIED | Lines 3–4 present before `<application>` block |
| 5 | iOS Info.plist contains NSBluetoothAlwaysUsageDescription | VERIFIED | Line 69–70 with non-empty string value |
| 6 | go_router /instrument guard redirects to /scan when not connected | VERIFIED | `lib/main.dart` lines 31–35: `state.matchedLocation == '/instrument' && ... != ConnectionStatus.connected` returns `'/scan'` |
| 7 | No refreshListenable in router (D-04) | VERIFIED | `grep refreshListenable lib/main.dart` returns only a comment — no actual usage |
| 8 | ProviderContainer carries MockBleManager override; ProviderScope uses container injection (D-07) | VERIFIED | `_container` declared with `overrides: [bleManagerProvider.overrideWithValue(MockBleManager())]`; `UncontrolledProviderScope(container: _container, ...)` used (semantically equivalent to `parent: _container`) |
| 9 | ThemeData.dark() only (D-05) | VERIFIED | `lib/main.dart` line 77: `theme: ThemeData.dark()` — no light/adaptive theme |
| 10 | WP2 swap point documented | VERIFIED | Comment on lines 13–14: "WP2 swap point: replace MockBleManager() with RealBleManager() here." |
| 11 | PERM-02: App imports permission_handler and requests permissions | VERIFIED | `lib/ui/scan_screen.dart` imports `permission_handler`; `_requestBlePermissionsIfNeeded` calls `permissions.request()` |
| 12 | PERM-03: Rationale AlertDialog shown before .request() | VERIFIED | `scan_screen.dart` lines 233–248: `showDialog` with AlertDialog before `permissions.request()` call |
| 13 | PERM-04: Permanently denied shows inline banner with openAppSettings() | VERIFIED | `scan_screen.dart` lines 113, 264–284: `_buildPermissionDeniedBanner()` with `TextButton(onPressed: openAppSettings, ...)` |

**Score:** 13/13 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `android/app/build.gradle.kts` | SDK version declarations | VERIFIED | minSdk=24, compileSdk=35 as integer literals |
| `android/app/src/main/AndroidManifest.xml` | Android BLE permission declarations | VERIFIED | BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION, plus legacy API<30 entries |
| `ios/Runner/Info.plist` | iOS Bluetooth usage description | VERIFIED | NSBluetoothAlwaysUsageDescription with non-empty string |
| `lib/main.dart` | Production entry point with go_router, ProviderContainer, permission check | VERIFIED | WidgetsFlutterBinding.ensureInitialized, _container, _router, UncontrolledProviderScope |
| `lib/providers/device_provider.dart` | blePermissionPermanentlyDeniedProvider | VERIFIED | Line 244: `StateProvider<bool>((ref) => false)` |
| `lib/ui/scan_screen.dart` | go_router navigation + permission inline UI | VERIFIED | context.go('/instrument'), _buildPermissionDeniedBanner(), _requestBlePermissionsIfNeeded |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/main.dart (_container)` | `blePermissionPermanentlyDeniedProvider` | `_container.read(...notifier).state =` | WIRED | Lines 62–63 in main.dart write permanently-denied cold-start result |
| `lib/ui/scan_screen.dart` | go_router /instrument route | `context.go('/instrument')` | WIRED | Lines 41 in scan_screen.dart |
| `lib/ui/scan_screen.dart` | `blePermissionPermanentlyDeniedProvider` | `ref.watch(blePermissionPermanentlyDeniedProvider)` | WIRED | Line 33 in scan_screen.dart |
| `lib/main.dart` | `lib/ui/scan_screen.dart` | GoRoute path='/scan' builder | WIRED | Lines 40–42 in main.dart |
| `lib/main.dart` | `lib/ui/instrument_screen.dart` | GoRoute path='/instrument' builder | WIRED | Lines 43–45 in main.dart |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 43 flutter tests pass | `flutter test --no-pub` | 43 passed, 0 failed | PASS |
| minSdk is hardcoded integer 24 | grep in build.gradle.kts | `minSdk = 24` found, no flutter delegate | PASS |
| compileSdk is hardcoded integer 35 | grep in build.gradle.kts | `compileSdk = 35` found, no flutter delegate | PASS |
| BLUETOOTH_SCAN has neverForLocation | grep in AndroidManifest.xml | Flag present on line 2 | PASS |
| NSBluetoothAlwaysUsageDescription present | grep in Info.plist | Key+value present on lines 69–70 | PASS |
| No refreshListenable in main.dart | grep | Only appears in a comment — no functional use | PASS |
| blePermissionPermanentlyDeniedProvider uses StateProvider<bool> | grep in device_provider.dart | Declaration confirmed on line 244 | PASS |
| context.go('/instrument') used (not Navigator.push) | grep in scan_screen.dart | Found on line 41; Navigator.of(context).push absent | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BUILD-01 | 05-01 | minSdkVersion 24 in build.gradle | SATISFIED | `minSdk = 24` integer literal confirmed |
| BUILD-02 | 05-01 | compileSdkVersion 35 in build.gradle | SATISFIED | `compileSdk = 35` integer literal confirmed |
| PERM-01 | 05-01 | AndroidManifest BLE permission declarations | SATISFIED | All three permissions present with correct flags |
| PERM-02 | 05-02, 05-03 | Runtime permission request via permission_handler | SATISFIED | `permissions.request()` called in _requestBlePermissionsIfNeeded |
| PERM-03 | 05-03 | Rationale dialog before system prompt | SATISFIED | AlertDialog shown before permissions.request() |
| PERM-04 | 05-03 | Permanently denied inline banner with openAppSettings | SATISFIED | _buildPermissionDeniedBanner with openAppSettings confirmed |
| PERM-05 | 05-01 | iOS Info.plist Bluetooth usage description | SATISFIED | NSBluetoothAlwaysUsageDescription present |

---

### Anti-Patterns Found

None found. No TBD, FIXME, XXX, placeholder, or stub markers in the modified files. The two TODO comments in build.gradle.kts (applicationId guidance and signing config note) are pre-existing Flutter scaffold comments unrelated to this phase's changes and reference official documentation links.

---

### Human Verification Required

#### 1. Android Cold-Launch Permission Rationale Flow (PERM-02, PERM-03)

**Test:** Cold-launch the app on an Android API 24+ device or emulator (ensure Bluetooth permissions are not yet granted). Observe what appears before the system permission prompt.
**Expected:** The app's own AlertDialog titled "Bluetooth Permission" appears first with the message "This app needs Bluetooth to scan for and connect to your inclinometer instrument." and a "Continue" button. After tapping Continue, the Android system Bluetooth permission dialog appears. After granting, the scan screen loads without error.
**Why human:** permission_handler platform channels require a real Android runtime process. The flutter test harness mocks the platform, so isPermanentlyDenied and the dialog flow cannot be exercised in automated tests.

#### 2. Permanently Denied Banner (PERM-04)

**Test:** Deny BLE permissions permanently (deny twice or revoke via Android Settings > Apps > Inclinometer > Permissions). Relaunch the app.
**Expected:** The scan screen shows the dark-red banner at the top: "Bluetooth permission is permanently denied. Open Settings to grant access." with an "Open Settings" button. Tapping the button opens the Android system app settings page for the inclinometer app.
**Why human:** isPermanentlyDenied is only true after the OS records two consecutive denials — not reproducible in unit tests without a real Android runtime.

#### 3. go_router /instrument Route Guard (SC-5)

**Test:** Connect to a mock device (navigates to /instrument). Then trigger simulateDisconnect via the debug button. Attempt to navigate back to /instrument (e.g. Android back then navigate forward, or use deep-link `go('/instrument')` from a dev tool while not connected).
**Expected:** The router intercepts the navigation attempt and redirects to /scan. The user never sees the instrument screen data while not connected.
**Why human:** go_router redirect behavior requires the full widget tree and navigation stack; the widget tests use a simplified router setup that does not exercise the redirect callback in integration.

---

### Gaps Summary

No automated gaps found. All 13 must-have truths are verified by code inspection. All 43 tests pass. Three human verification items remain that require a physical Android device or emulator to confirm the permission flow and router guard behave correctly at runtime. These are expected per ROADMAP.md Phase 5 success criteria 1–2 and 5, which explicitly describe device-observable behaviors.

---

_Verified: 2026-06-05T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
