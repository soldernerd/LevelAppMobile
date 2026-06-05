---
phase: 05
status: findings
critical: 1
warning: 4
info: 3
---

# Phase 05 Code Review

**Reviewed:** 2026-06-05
**Depth:** standard
**Files Reviewed:** 8

## Summary

Phase 5 wires the production entry point, go_router navigation, permission flow, and platform BLE configuration. The implementation is generally sound — architecture constraints are respected (no flutter_blue_plus in ui/providers, UncontrolledProviderScope used correctly, no refreshListenable, keepAlive in place). However, one critical bug was found in the cold-start permission check in `main.dart` that can cause a false "permanently denied" state on first launch, and four warnings were identified covering logic gaps and robustness issues.

---

## Findings

### CRITICAL

#### CR-01: Cold-start permanently-denied check uses short-circuit OR before permissions are ever requested

**File:** `lib/main.dart:58–63`

**Issue:** On a fresh install, `Permission.bluetoothScan.isPermanentlyDenied` returns `true` on some Android versions before the user has ever seen the system permission prompt. The Android permission model treats "never asked" as indistinguishable from "permanently denied" via `isPermanentlyDenied` on certain API levels (notably API 29–30, and some OEM variants of API 31+). As a result, `blePermissionPermanentlyDeniedProvider` is set to `true` at cold start on a brand-new install, the permanently-denied banner appears immediately, and the rationale dialog in `ScanScreen` is still shown — but the "Open Settings" button is visible before the user has ever had a chance to grant permissions. On Android 12+ this is less of an issue, but the `||` short-circuit means that if `bluetoothScan` returns `true` (false positive), `bluetoothConnect` is never even checked.

More concretely: the correct Android API to distinguish "never asked" from "permanently denied" is to compare `shouldShowRequestPermissionRationale`. The `isPermanentlyDenied` getter in `permission_handler` maps to `!shouldShowRequestPermissionRationale && !isGranted`, which on a fresh install (before first request) returns `true` for `neverAskAgain = false AND not granted = true`.

This means the banner will appear on every fresh install until the user grants permissions, which is the opposite of the intended UX (D-02: only show banner when the OS permanently blocks the dialog).

**Fix:**

```dart
// In main():
if (Platform.isAndroid) {
  // Only set permanently denied if the permission was previously requested AND denied.
  // On a fresh install, isPermanentlyDenied returns true because the permission has
  // never been granted, but shouldShowRequestPermissionRationale is false too —
  // making it indistinguishable via isPermanentlyDenied alone.
  // Check isGranted first; if already granted, skip. Otherwise, only flag as
  // permanently denied if isDenied (not just "not granted") AND isPermanentlyDenied.
  final scanStatus = await Permission.bluetoothScan.status;
  final connectStatus = await Permission.bluetoothConnect.status;
  final permanentlyDenied =
      (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) &&
      !scanStatus.isGranted &&
      !connectStatus.isGranted;
  _container
      .read(blePermissionPermanentlyDeniedProvider.notifier)
      .state = permanentlyDenied;
}
```

Alternatively, defer this check entirely and rely only on `ScanScreen._requestBlePermissionsIfNeeded()` which runs the actual request and checks results after the system prompt.

---

### WARNING

#### WR-01: `_blePermissionsRequested` file-scope bool is never reset — rationale dialog blocked after hot restart in dev

**File:** `lib/ui/scan_screen.dart:14`

**Issue:** The file-scope `bool _blePermissionsRequested` persists for the entire Dart VM lifetime. In production this is intentional (session-scoped guard). However, because it is a module-level variable, it is shared across all `ProviderScope` instances in the same test run. Tests that rebuild `ScanScreen` after the first test has run will not trigger `_requestBlePermissionsIfNeeded`, silently skipping the permission flow. This caused test isolation failures in prior phases and could again if new tests are added.

More critically: if ScanScreen is rebuilt after a hot restart (which does not restart the Dart VM), the rationale dialog will never show again in the same session even if the user navigated away and returned. This is arguably intentional per D-01, but if the user denies the system prompt and later returns to the scan screen in the same session, the dialog will not re-appear to let them try again.

**Fix:** Consider using a `StatefulWidget` or a Riverpod `StateProvider` to scope this flag to the widget or app session, rather than module-level state. At minimum, document clearly that this is a test isolation hazard and reset the flag in `tearDown` in test files that test the dialog flow.

---

#### WR-02: `_container` is never disposed — ProviderContainer leaks on app exit

**File:** `lib/main.dart:15`

**Issue:** The top-level `_container` ProviderContainer is created but `_container.dispose()` is never called. In Flutter apps, `runApp` does not call any lifecycle hooks on exit, so the container — and the BLE manager, stream subscriptions, and wakelock — are never torn down cleanly. On Android, the OS kills the process, so this is not a runtime crash. However it means `ref.onDispose` callbacks in providers (including the wakelock release and StreamController close in `ConnectionNotifier`) never fire on graceful exit (e.g., BackNavigator on some OEM launchers, or on iOS which does have a graceful terminate path).

**Fix:**

```dart
// Wrap the app widget and listen for app lifecycle events:
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _container.dispose();
    }
  }
}
// In main(), after ensureInitialized():
WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
```

---

#### WR-03: `disconnect()` in `ConnectionNotifier` does not catch errors — unhandled exception propagates to caller

**File:** `lib/providers/device_provider.dart:172–175`

**Issue:** `startScan()`, `stopScan()`, and `connect()` all wrap their BLE manager calls in `try/catch` and set `state = ConnectionStatus.error` on failure. `disconnect()` does not:

```dart
Future<void> disconnect() async {
  await ref.read(bleManagerProvider).disconnect();
}
```

If `BleManager.disconnect()` throws (e.g., device already disconnected, platform channel error), the exception propagates to the caller uncaught. No caller currently calls `disconnect()` with error handling, so this would surface as an unhandled async exception.

**Fix:**

```dart
Future<void> disconnect() async {
  try {
    await ref.read(bleManagerProvider).disconnect();
  } catch (e) {
    state = ConnectionStatus.error;
  }
}
```

---

#### WR-04: `ACCESS_FINE_LOCATION` declared without `maxSdkVersion` — granted unnecessarily on API 31+

**File:** `android/app/src/main/AndroidManifest.xml:4`

**Issue:** `ACCESS_FINE_LOCATION` is required for BLE scanning only on API < 31 (Android 12). On API 31+, `BLUETOOTH_SCAN` with `neverForLocation` replaces it. Without `maxSdkVersion="30"` on the `ACCESS_FINE_LOCATION` declaration, the system requests location permission on Android 12+ devices as well, which is unnecessary, confuses users, and may trigger Google Play policy review. The permission_handler code in `scan_screen.dart` correctly requests only `[bluetoothScan, bluetoothConnect]` on API >= 31, but the manifest declaration causes the permission to appear in the app's permission list regardless.

**Fix:**

```xml
<uses-permission
    android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
```

---

### INFO

#### IN-01: `build.gradle.kts` retains two boilerplate TODO comments from the Flutter template

**File:** `android/app/build.gradle.kts:18, 29`

**Issue:** Two `// TODO:` comments from the Flutter project template remain in the file. These are not functional bugs but represent stale scaffolding text.

**Fix:** Remove the TODO comment blocks, or replace them with project-specific notes if relevant.

---

#### IN-02: `device_provider.dart` imports `mock_ble_manager.dart` — couples provider layer to WP1 mock

**File:** `lib/providers/device_provider.dart:9`

**Issue:** `import 'package:inclinometer/ble/mock_ble_manager.dart'` appears in the provider file solely to support `debugSimulateDisconnect()`. While the method comment correctly notes this preserves the architecture constraint (UI never imports MockBleManager), the provider layer now has a compile-time dependency on the WP1 mock. If `MockBleManager` is moved or removed in WP2, this import must be updated even though the provider's core logic has not changed.

**Fix:** Consider making `debugSimulateDisconnect()` conditional on a compile-time flag (`kDebugMode`) and importing MockBleManager only in debug builds, or accept the coupling as intentional and document it clearly as a WP2 removal point.

---

#### IN-03: Test file `scan_screen_test.dart` has a `ble.dispose()` teardown double-registration in SCAN-03

**File:** `test/ui/scan_screen_test.dart:104–106`

**Issue:** The SCAN-03 test calls `addTearDown(ble.dispose)` explicitly at line 104, but the test does NOT use `buildHarness()` (which also calls `addTearDown(ble.dispose)`). This is correct as written. However, the `buildHarness()` helper is used in SCAN-01, SCAN-02, INST-01 and it registers `addTearDown(ble.dispose)` — but SCAN-05 also manually calls `ble.dispose()` at line 191 inside the test body before the test ends. This means SCAN-05's mock will be disposed twice: once inline at line 191, and once via the teardown registered in `buildHarness`... except SCAN-05 does NOT use `buildHarness()`. So the double-dispose risk is not present. The pattern is just inconsistent and could cause confusion for future test authors.

**Fix:** Standardize teardown: always use `buildHarness()` or always handle teardown explicitly, not a mix of both patterns across tests in the same file.

---

## Verdict

**One critical bug** (CR-01) must be fixed before this code ships: the cold-start `isPermanentlyDenied` check produces false positives on fresh installs, displaying the "Open Settings" denied banner prematurely. The four warnings should be addressed before production; WR-03 (unguarded `disconnect()`) and WR-04 (manifest location permission scope) are the highest priority among them.
