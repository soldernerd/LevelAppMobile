---
phase: 07-github-self-update
reviewed: 2026-06-07T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - android/app/src/main/AndroidManifest.xml
  - android/app/src/main/res/xml/filepaths.xml
  - lib/providers/update_provider.dart
  - lib/services/update_service.dart
  - lib/ui/scan_screen.dart
  - pubspec.yaml
  - test/ui/scan_screen_test.dart
  - test/update_service_test.dart
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-06-07
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 7 adds a GitHub Releases self-update flow: a `UpdateService` static service, a `FutureProvider` wrapper, an update dialog in `ScanScreen`, and the necessary Android manifest / FileProvider additions. The overall architecture follows the project conventions (static service, ref.listen + postFrameCallback, silent-fail posture). Two blockers were found: a use-after-dispose on `ValueNotifier` when the download dialog is dismissed externally while a download is running, and an over-broad `FileProvider` path exposure that allows any cached file to be shared with the installer activity. Four warnings cover a missing Dio `connectTimeout`, a session-permanent suppression of the update dialog on unmount, an un-guarded `tagName.replaceFirst` that fails silently on non-`v`-prefixed tags, and a test coverage gap. Three info items round out the review.

---

## Critical Issues

### CR-01: ValueNotifier used after dispose — download callback writes to disposed notifier

**File:** `lib/ui/scan_screen.dart:395-414`

**Issue:** `progressNotifier` and `downloadingNotifier` are disposed at lines 414-415 immediately after `showDialog` returns. However, when the user taps "Update", `UpdateService.downloadApk` is launched as an `async` call inside the `onPressed` callback (line 395). The dialog can be dismissed externally (Android back gesture, OS low-memory kill of activity, navigation from another `ref.listen`) while the download `Future` is still in flight. After external dismissal `showDialog` returns and `progressNotifier.dispose()` is called, but the `onReceiveProgress` callback passed to `downloadApk` at line 397 — `(p) => progressNotifier.value = p` — continues to fire as bytes arrive. Writing `.value` on a disposed `ValueNotifier` throws an assertion error in debug mode and produces undefined behavior in profile/release.

**Fix:**
Add a cancelled flag or check `ctx.mounted` / a separate `bool _disposed` before writing to the notifiers. The simplest safe pattern:

```dart
// In the Update onPressed callback, capture the notifiers before they can be
// disposed, and guard writes with a mounted check:
TextButton(
  onPressed: () async {
    downloadingNotifier.value = true;
    bool dialogStillOpen = true;
    try {
      final path = await UpdateService.downloadApk(
        info.downloadUrl,
        (p) {
          if (dialogStillOpen) progressNotifier.value = p;
        },
      );
      await UpdateService.installApk(path);
    } catch (_) {
      // UPD-05: fail-quiet
    } finally {
      dialogStillOpen = false;
      if (ctx.mounted) Navigator.of(ctx).pop();
    }
  },
  child: const Text('Update'),
),
```

Then remove the `.dispose()` calls from after `showDialog` (the notifiers are GC'd when the closure goes out of scope, which is safe because `ValueNotifier` does not hold OS resources).

---

### CR-02: FileProvider path exposes entire cache directory — over-broad URI grant

**File:** `android/app/src/main/res/xml/filepaths.xml:3`

**Issue:** `<cache-path name="apk_cache" path="." />` maps the FileProvider root to the entire `getCacheDir()` (`.`). Any file in the cache directory — including Dio's own HTTP cache, SharedPreferences temp files written by other plugins, or any other framework-generated cache content — can be served as a content URI to the package installer activity. On Android, `grantUriPermissions="true"` in the manifest means any activity that receives the URI gets `READ_URI_PERMISSION`. While the installer only reads the explicit URI provided by `OpenFilex.open()`, the over-broad path declaration is a security hygiene failure: a path-traversal in any future call to `FileProvider.getUriForFile()` could expose unintended files. The principle of least privilege requires scoping the path to the subdirectory used for APK downloads only.

**Fix:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="apk_cache" path="apk_downloads/" />
</paths>
```

And update `downloadApk` to write into that subdirectory:
```dart
static Future<String> downloadApk(String url, void Function(double) onProgress) async {
  final dir = await getTemporaryDirectory();
  final apkDir = Directory('${dir.path}/apk_downloads');
  await apkDir.create(recursive: true);
  final savePath = '${apkDir.path}/$_apkAssetName';
  // ... rest unchanged
}
```

---

## Warnings

### WR-01: Missing Dio connectTimeout — cold-start check can hang for minutes

**File:** `lib/services/update_service.dart:55-62`

**Issue:** The `Options` passed to `dio.get()` sets `receiveTimeout` and `sendTimeout` (both 10 s) but omits `connectTimeout`. Dio's default `connectTimeout` is `null` (no timeout). On Android, if the device has a route to the IP but the host is firewalled or drops SYN packets, the OS TCP stack retries for 75 seconds or longer before reporting ECONNREFUSED/ETIMEDOUT. During this window the `updateCheckProvider` `FutureProvider` stays in `AsyncLoading` state. `ref.listen` in `ScanScreen` receives no `whenData` callback, which is harmless, but the provider holds a Dart `Isolate` timer for the full OS timeout duration — much longer than the intended 10 seconds.

**Fix:**
```dart
options: Options(
  headers: {'User-Agent': 'soldernerd-inclinometer'},
  connectTimeout: const Duration(seconds: 10),   // add this
  receiveTimeout: const Duration(seconds: 10),
  sendTimeout: const Duration(seconds: 10),
),
```

---

### WR-02: _updateDialogShown set before context.mounted check — permanently suppresses dialog on unmount

**File:** `lib/ui/scan_screen.dart:68-73`

**Issue:** `_updateDialogShown = true` is assigned at line 69 before the `addPostFrameCallback` fires and before the `context.mounted` guard at line 71 is evaluated. If the widget is unmounted between the provider resolving and the post-frame callback executing (e.g., user navigates to `/instrument` immediately after app start), `context.mounted` is false, `_showUpdateDialog` is never called, but `_updateDialogShown` remains `true` for the process lifetime (file-scope variable). On the next navigation back to `ScanScreen`, the `FutureProvider` is autoDisposed and recreated, fires again, and `ref.listen` fires again — but the guard at line 68 (`if (_updateDialogShown) return`) blocks the dialog permanently. The user never sees the update prompt for this session.

**Fix:** Move the guard assignment inside the `context.mounted` branch:
```dart
ref.listen<AsyncValue<UpdateInfo?>>(
  updateCheckProvider,
  (_, next) {
    next.whenData((info) {
      if (info == null || _updateDialogShown) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        _updateDialogShown = true;   // set only when dialog will actually show
        _showUpdateDialog(context, ref, info);
      });
    });
  },
);
```

---

### WR-03: tagName.replaceFirst('v', '') silently corrupts non-standard tags

**File:** `lib/services/update_service.dart:70`

**Issue:** `tagName.replaceFirst('v', '')` strips the first occurrence of the lowercase letter `v` anywhere in the string. For a tag like `"release-v0.1.1"` the result is `"release-0.1.1"`, and `_isNewer` will parse `"release"` as segment 0 (via `int.tryParse` → `0`), yielding an incorrect version comparison. More subtly, `replaceFirst` replaces the first `v` regardless of position — a tag `"v0.1v1"` becomes `"0.1v1"`. While the soldernerd repository likely uses strict `vX.Y.Z` tags, this is a fragile assumption.

**Fix:**
```dart
// Strip leading 'v' only when it's the first character
final remoteVer = tagName.startsWith('v') ? tagName.substring(1) : tagName;
```

---

### WR-04: No tests for checkForUpdate, downloadApk, installApk, or skipVersion

**File:** `test/update_service_test.dart`

**Issue:** The test file only exercises `_isNewer` via the `@visibleForTesting` bridge (6 cases). The four public methods of `UpdateService` that perform HTTP, filesystem, and permission I/O — `checkForUpdate`, `downloadApk`, `installApk`, `skipVersion` — have zero test coverage. In particular:
- The skip-version round-trip (write then suppress) is untested.
- The asset-not-found path in `checkForUpdate` (line 88) is untested.
- The `total == -1` guard in `downloadApk` (line 119) is untested.
- The permission-denied silent-abort path in `installApk` (line 138) is untested.

These methods require a mock HTTP client (e.g., `MockAdapter` for Dio) and mock `SharedPreferences`. Adding these tests would catch regressions when WP2 or future phases modify the service.

**Fix:** Add a test group using `DioAdapter` / `HttpMock` to stub the GitHub API response and verify `checkForUpdate` return values for: newer version available, same version, skipped version, missing APK asset, and network error. Add a test for `skipVersion` using `SharedPreferences.setMockInitialValues`.

---

## Info

### IN-01: @visibleForTesting bridge exposes internal logic — test-only API in production code

**File:** `lib/services/update_service.dart:159-161`

**Issue:** `isNewerForTest` is a `@visibleForTesting` public method that delegates to the private `_isNewer`. This is a common Flutter pattern but it leaks an API surface into the compiled production binary that exists solely to support unit tests. Dart's `@visibleForTesting` annotation is advisory only — it does not prevent calls from non-test code at runtime.

**Fix:** Consider using Dart's `package:test` visibility or moving `_isNewer` to a `@visibleForTesting` top-level function in a separate `ble_protocol`-style file. If the current approach is acceptable per project conventions, this item can be deferred.

---

### IN-02: File-scope mutable globals require explicit test reset — test hygiene coupling

**File:** `lib/ui/scan_screen.dart:16,23,27-29`

**Issue:** `_blePermissionsRequested` and `_updateDialogShown` are file-scope mutable globals. `resetUpdateDialogShownForTest()` is exported with `@visibleForTesting` to allow tests to reset `_updateDialogShown`, but `_blePermissionsRequested` has no equivalent reset function. Tests that exercise the BLE permission flow after a previous test has set `_blePermissionsRequested = true` will silently skip the permission rationale dialog. Currently this does not affect any test in the suite because no test exercises the rationale dialog path — but it is a latent fragility.

**Fix:** Add `resetBlePermissionsRequestedForTest()` mirroring the existing `resetUpdateDialogShownForTest()` pattern, or restructure to use `ProviderScope`-scoped state instead of file-scope globals (requires converting to `StatefulWidget` or a provider).

---

### IN-03: Dio instance created per call — no connection reuse

**File:** `lib/services/update_service.dart:54, 113`

**Issue:** `checkForUpdate` and `downloadApk` each create a new `Dio()` instance. A shared instance would allow HTTP connection reuse (keep-alive). This is a minor inefficiency — the two calls happen sequentially with a user interaction between them, so connection reuse is unlikely in practice. Noted for completeness; does not affect correctness.

**Fix:** Extract a module-level `static final _dio = Dio()` or pass a `Dio` instance as a parameter (improves testability for WR-04 as well).

---

_Reviewed: 2026-06-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
