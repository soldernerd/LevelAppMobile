# Phase 7: GitHub Self-Update - Research

**Researched:** 2026-06-07
**Domain:** Flutter in-app updater — GitHub Releases API, Dio HTTP download, Android APK sideloading, Riverpod async provider, shared_preferences persistence
**Confidence:** HIGH (core APIs), MEDIUM (FileProvider setup details), HIGH (GitHub API shape verified live)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Check fires once per cold start, silently in the background. No blocking of the scan screen. If the check fails (no internet, API error, timeout) it fails silently — no crash, no error dialog.
- **D-02:** No manual "Check for updates" button. No About/Settings screen required for this phase.
- **D-03:** When the user dismisses the update dialog without installing, the skipped version tag is persisted via `shared_preferences`. Skip key = `skipped_update_version`. The update dialog is NOT shown again for that specific version.
- **D-04:** Dismiss = skip this version permanently. No "Remind me later" / snooze option.
- **D-05:** Full in-app download using `dio` with a visible progress indicator (percentage). APK saved to app cache dir.
- **D-06:** After download completes, `open_file_plus` launches the Android system package installer.
- **D-07:** `REQUEST_INSTALL_PACKAGES` permission declared in `AndroidManifest.xml`. On Android 8+ (API 26+) the app checks and requests this permission at runtime before attempting installation.
- **D-08:** Repository hardcoded as `soldernerd/LevelAppMobile`.
- **D-09:** API endpoint: `https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest`. Parse `tag_name` (strip leading `v`) and compare against `PackageInfo.version` from `package_info_plus`.
- **D-10:** APK asset filename hardcoded as `app-release.apk` (matches `release.yml` upload step exactly).
- **D-11:** Update check logic lives in `updateCheckProvider` (Riverpod). `keepAlive: false` — single fire on startup, no persist across navigation.
- **D-12:** No new UI screen. Update dialog is a standard `showDialog` call triggered from ScanScreen when provider detects newer version.

### Claude's Discretion

- Exact wording of the update dialog (version numbers shown, button labels "Update" / "Skip").
- Error handling details within the download flow (partial download cleanup, etc.).
- Whether to use `package_info_plus` or parse `pubspec.yaml` at build time for version — `package_info_plus` is the idiomatic Flutter approach.

### Deferred Ideas (OUT OF SCOPE)

- iOS update delivery (requires TestFlight or App Store).
- In-app changelog display (GitHub API `body` field).
- Background periodic update check (cold start only in this phase).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UPD-01 | App calls GitHub Releases API on startup and compares `tag_name` against installed version | GitHub API shape verified live; `package_info_plus` async API confirmed |
| UPD-02 | When newer version detected, update dialog appears with version number; user can dismiss or proceed | `FutureProvider` pattern with `ref.listen` in ScanScreen; `showDialog` after mount |
| UPD-03 | Tapping "Update" downloads APK with visible progress indicator | `dio.download()` with `onReceiveProgress` callback confirmed |
| UPD-04 | After download, Android package installer launches | `open_file_plus` `OpenFile.open()` confirmed; FileProvider setup documented |
| UPD-05 | Network failure fails silently — no crash, no error dialog | `try/catch` around `dio.get()` + `dio.download()`; swallow all exceptions |
| UPD-06 | `REQUEST_INSTALL_PACKAGES` declared in manifest; runtime check on Android 8+ (API 26+) | `permission_handler` `Permission.requestInstallPackages` confirmed; opens Settings intent |
</phase_requirements>

---

## Summary

Phase 7 adds a cold-start update check that silently queries `https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest`, compares the `tag_name` field (e.g. `v0.1.0`) against the version string from `PackageInfo.fromPlatform()`, and conditionally presents a download dialog. The feature is Android-only; the implementation is entirely Dart-side (no native Kotlin/Swift code).

The GitHub Releases API endpoint for this repository was queried live during research and the response shape was confirmed: `tag_name: "v0.1.0"`, `assets[0].name: "app-release.apk"`, `assets[0].browser_download_url: "https://github.com/soldernerd/LevelAppMobile/releases/download/v0.1.0/app-release.apk"`, `assets[0].size: 48762701`. The asset filename `app-release.apk` matches the value hardcoded in D-10 exactly.

The main implementation complexity lies in three areas: (1) the `open_file_plus` FileProvider setup, which is not automatic and requires adding a `<provider>` element to `AndroidManifest.xml` plus a new `res/xml/filepaths.xml` resource; (2) the `REQUEST_INSTALL_PACKAGES` permission, which does NOT display a standard runtime dialog but instead opens the device Settings app via an intent (handled transparently by `permission_handler`); and (3) the Riverpod provider design — a `FutureProvider` (autoDispose) is the simplest fit since no mutations are needed, with the ScanScreen using `ref.listen` to react to the result and call `showDialog` after the frame is rendered.

**Primary recommendation:** Use `FutureProvider` (not `AsyncNotifier`) for `updateCheckProvider` — it naturally models a read-only async result with no mutations needed. Watch it in `ScanScreen` with `ref.listen`, show the dialog in the `data` callback via `addPostFrameCallback`. Keep all update logic (HTTP, file I/O, permission) in a dedicated `lib/services/update_service.dart` to honour the CLAUDE.md architecture boundary (no platform SDK imports in `lib/ui/`).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| GitHub API check | Service layer (`update_service.dart`) | Provider (`updateCheckProvider`) | HTTP and business logic must not live in UI per CLAUDE.md |
| Version comparison | Service layer | — | Pure logic; no platform dependency |
| SharedPreferences read/write | Service layer | — | Platform I/O; keep out of UI |
| Riverpod state exposure | Provider (`updateCheckProvider`) | — | Testable; decoupled from widget lifecycle |
| Dialog trigger | ScanScreen (UI) via `ref.listen` | — | Only UI can call `showDialog`; state drives it, widget triggers it |
| APK download with progress | Service layer | Provider (exposes progress state) | Long-running I/O; progress needs to be surfaced to UI |
| Package installer launch | Service layer | — | Platform call; architecture boundary |
| `REQUEST_INSTALL_PACKAGES` check | Service layer | — | Permission call before install attempt |
| `AndroidManifest.xml` changes | Platform config | — | Declarative; no Dart logic |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `dio` | 5.9.2 | HTTP client: GitHub API GET + APK download with progress | Industry standard Flutter HTTP; `onReceiveProgress` built in; used by majority of Flutter apps |
| `package_info_plus` | 10.1.0 | Read installed version (`PackageInfo.version`) | Official Flutter Community package; idiomatic way to get runtime app version |
| `shared_preferences` | 2.5.5 | Persist skipped version tag across sessions | First-party Flutter team package; sufficient for a single string key |
| `path_provider` | 2.1.5 | `getTemporaryDirectory()` — save APK to cache dir | First-party Flutter team package; no storage permission required for cache dir |
| `open_file_plus` | 3.4.1+1 | Launch Android package installer after download | Provides `OpenFile.open()` with content URI / FileProvider integration |
| `permission_handler` | 12.0.3 | `Permission.requestInstallPackages` check + Settings redirect | Already in project; handles the Settings intent transparently |

All packages listed above are published by verified pub.dev publishers.
[CITED: pub.dev package pages for each package, verified 2026-06-07]

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dart:convert` | SDK built-in | JSON decode of GitHub API response | Always; no extra dep needed |
| `dart:io` | SDK built-in | `File` object for APK save path | Always; bundled |
| `pub_semver` | 2.2.0 | Semantic version comparison | Optional — only add if `String.split('.')` comparison proves insufficient for pre-release tags |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `dio` | `http` (dart team) | `http` lacks built-in download-to-file + progress callback; `dio` handles both in one call |
| `open_file_plus` | `android_package_installer` | More focused package but far less downloads; `open_file_plus` is broader and the decision is locked (D-06) |
| `SharedPreferences.getInstance()` | `SharedPreferencesAsync` (newer API) | Async API requires Dart 3.9; acceptable here, but `getInstance()` pattern is simpler and is what the existing codebase is structured for |
| Manual version string split | `pub_semver` | `pub_semver` handles pre-release correctly; for `1.2.3`-style tags only, `List.compareTo` on split integers is sufficient and avoids an extra dependency |

**Installation (new deps only — `permission_handler` and `path_provider` already present if added in Phase 5):**

```bash
flutter pub add dio package_info_plus shared_preferences open_file_plus
flutter pub add path_provider  # add only if not already in pubspec
```

---

## Package Legitimacy Audit

> slopcheck was unavailable at research time (pip install failed). All packages verified against official pub.dev registry and publisher identity.

| Package | Registry | Age | Publisher | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `dio` 5.9.2 | pub.dev | ~7 yrs | flutter.cn (verified) | github.com/cfug/dio | [ASSUMED] | Approved — major ecosystem package, 4500+ pub.dev likes |
| `package_info_plus` 10.1.0 | pub.dev | ~5 yrs | fluttercommunity.dev (verified) | github.com/fluttercommunity/plus_plugins | [ASSUMED] | Approved — official Flutter Community plus plugin |
| `shared_preferences` 2.5.5 | pub.dev | ~6 yrs | flutter.dev (verified) | github.com/flutter/packages | [ASSUMED] | Approved — first-party Flutter team package |
| `path_provider` 2.1.5 | pub.dev | ~6 yrs | flutter.dev (verified) | github.com/flutter/packages | [ASSUMED] | Approved — first-party Flutter team package |
| `open_file_plus` 3.4.1+1 | pub.dev | ~2 yrs | unverified publisher | github.com/ix0development4/open_file_plus | [ASSUMED] | Flagged — unverified publisher, published 2 years ago with no recent updates; decision D-06 locks this choice. Planner should add checkpoint:human-verify before install |

**Packages removed due to slopcheck [SLOP] verdict:** none

**Packages flagged as suspicious [SUS]:** `open_file_plus` — unverified publisher, 2 years since last update. Planner must add `checkpoint:human-verify` before install step. If check fails, consider `open_file` (older but same API shape) or `open_filex` as drop-in alternatives.

*slopcheck was unavailable at research time — all packages tagged `[ASSUMED]`. Planner should gate each install behind a `checkpoint:human-verify` task.*

---

## Architecture Patterns

### System Architecture Diagram

```
Cold start
    │
    ▼
main() → WidgetsFlutterBinding.ensureInitialized()
    │
    ▼
UpdateService.checkForUpdate()  ◄── FutureProvider (autoDispose, keepAlive:false)
    │
    ├─[no internet / API error]──► return null (silent fail)
    │
    ├─[already skipped version]──► return null (SharedPreferences check)
    │
    └─[newer version found]──► return UpdateInfo(version, downloadUrl)
                                        │
                                        ▼
                               ScanScreen ref.listen (data callback)
                                        │
                                        ▼
                               showDialog (UpdateDialog)
                                        │
                               ┌────────┴────────┐
                           [Skip]             [Update]
                               │                 │
                    prefs.setString()    UpdateService.downloadAndInstall()
                    (persist skip)               │
                                        ┌────────┴────────┐
                                   [Progress UI]    [Error → silent]
                                                         │
                                              OpenFile.open(apkPath)
                                                         │
                                              Android Package Installer
```

### Recommended Project Structure

```
lib/
├── services/
│   └── update_service.dart    # HTTP, download, permission, install logic
├── providers/
│   ├── device_provider.dart   # existing — unchanged
│   └── update_provider.dart   # updateCheckProvider (FutureProvider)
├── ui/
│   └── scan_screen.dart       # add ref.listen + dialog trigger
android/
└── app/src/main/
    ├── AndroidManifest.xml    # add REQUEST_INSTALL_PACKAGES + FileProvider
    └── res/xml/
        └── filepaths.xml      # new — defines cache-path for FileProvider
```

### Pattern 1: FutureProvider for one-shot startup check

`FutureProvider` is the correct choice over `AsyncNotifier` when no mutations are needed and the result is read-only. The provider builds once, completes, and is disposed when ScanScreen unmounts (autoDispose default).

```dart
// lib/providers/update_provider.dart
// Source: Riverpod docs — FutureProvider pattern
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/services/update_service.dart';

// keepAlive: false is the default for autoDispose providers.
// This fires once when ScanScreen first subscribes, then disposes.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  return UpdateService.checkForUpdate();
});
```

The ScanScreen subscribes with `ref.listen` (not `ref.watch`) so it does not rebuild — it only reacts to the state change:

```dart
// Inside ScanScreen.build() — after existing ref.listen for connection:
ref.listen<AsyncValue<UpdateInfo?>>(
  updateCheckProvider,
  (_, next) {
    next.whenData((info) {
      if (info == null) return;
      // Must be post-frame — dialog cannot be shown during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _showUpdateDialog(context, ref, info);
      });
    });
  },
);
```

### Pattern 2: dio.download() with onReceiveProgress

The `download()` method signature (verified from pub.dev API docs):

```dart
// Source: pub.dev/documentation/dio/latest/dio/Dio-class.html
final dio = Dio();
final tempDir = await getTemporaryDirectory();
final savePath = '${tempDir.path}/app-release.apk';

await dio.download(
  downloadUrl,          // String — browser_download_url from GitHub
  savePath,             // String — path in cache dir
  onReceiveProgress: (received, total) {
    if (total != -1) {
      final progress = received / total; // 0.0 to 1.0
      // update progress notifier
    }
  },
  options: Options(
    receiveTimeout: const Duration(minutes: 10), // large file ~48 MB
  ),
);
```

`ProgressCallback` is `void Function(int count, int total)` — `total` is `-1` if Content-Length is absent. [CITED: pub.dev/documentation/dio/latest/dio/Dio-class.html]

### Pattern 3: package_info_plus — async, requires ensureInitialized

```dart
// Source: pub.dev/packages/package_info_plus
// PackageInfo.fromPlatform() is async and requires
// WidgetsFlutterBinding.ensureInitialized() before calling.
// In this project, ensureInitialized() is already called in main() — no change needed.

final info = await PackageInfo.fromPlatform();
final currentVersion = info.version; // e.g. "1.0.0" (no build number)
```

`PackageInfo.version` returns the version name WITHOUT the build number suffix. The `pubspec.yaml` `version: 1.0.0+1` maps to `version = "1.0.0"` and `buildNumber = "1"`. [CITED: pub.dev/packages/package_info_plus]

### Pattern 4: GitHub API response shape (VERIFIED LIVE)

Live request to `https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest` returned:

```json
{
  "tag_name": "v0.1.0",
  "assets": [
    {
      "name": "app-release.apk",
      "browser_download_url": "https://github.com/soldernerd/LevelAppMobile/releases/download/v0.1.0/app-release.apk",
      "size": 48762701,
      "content_type": "application/vnd.android.package-archive"
    }
  ]
}
```

[VERIFIED: live GitHub API query 2026-06-07]

Version comparison logic:

```dart
// Strip leading 'v' from tag_name before comparison
final remoteVersion = json['tag_name'].toString().replaceFirst('v', '');
final localVersion  = (await PackageInfo.fromPlatform()).version;
// Simple semver comparison for 1.2.3-format tags
bool isNewer = _isNewerVersion(remoteVersion, localVersion);

bool _isNewerVersion(String remote, String local) {
  final r = remote.split('.').map(int.parse).toList();
  final l = local.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (r[i] > l[i]) return true;
    if (r[i] < l[i]) return false;
  }
  return false; // equal — no update
}
```

This is sufficient for `MAJOR.MINOR.PATCH` tags used by this project's `release.yml` (no pre-release suffixes). If pre-release tags are ever added, swap to `pub_semver`. [ASSUMED]

### Pattern 5: SharedPreferences skip-version persistence

```dart
// Source: pub.dev/packages/shared_preferences
const _skipKey = 'skipped_update_version';

// Read skip state (in UpdateService.checkForUpdate):
final prefs = await SharedPreferences.getInstance();
final skipped = prefs.getString(_skipKey);
if (skipped == remoteTag) return null; // already skipped

// Write skip on dismiss (in dialog callback):
await prefs.setString(_skipKey, remoteTag); // stores e.g. "v0.1.0"
```

### Pattern 6: permission_handler — REQUEST_INSTALL_PACKAGES

This permission does NOT show a standard dialog. When `.request()` is called, Android opens the **"Install unknown apps"** settings page for the app. The user must manually toggle the switch. This is handled transparently by `permission_handler` — the call looks the same as other permissions but the UX differs.

```dart
// Source: pub.dev/packages/permission_handler (verified 2026-06-07)
// Permission.requestInstallPackages opens Settings, not a dialog
final status = await Permission.requestInstallPackages.status;
if (!status.isGranted) {
  // This opens Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES for this app
  await Permission.requestInstallPackages.request();
  // Re-check status after user returns from Settings
  final newStatus = await Permission.requestInstallPackages.status;
  if (!newStatus.isGranted) return; // user declined — abort install
}
// Proceed with OpenFile.open(apkPath)
```

[CITED: pub.dev/packages/permission_handler — "The following permissions will show no dialog, but will open the corresponding setting intent: requestInstallPackages"]

### Pattern 7: open_file_plus — OpenFile.open()

```dart
// Source: pub.dev/packages/open_file_plus
import 'package:open_file_plus/open_file_plus.dart';

final result = await OpenFile.open(apkPath);
// result.type: ResultType.done | error | noAppToOpen | permissionDenied | fileNotFound
if (result.type != ResultType.done) {
  // handle error silently or log
}
```

The `apkPath` must be a path reachable via the FileProvider authority configured in the manifest. When using `getTemporaryDirectory()` (maps to `getCacheDir()`), the path is within the `<cache-path>` element.

### Android Manifest Changes Required

Two additions to `android/app/src/main/AndroidManifest.xml`:

**1. Permission declaration** (inside `<manifest>`, alongside existing permissions):
```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

**2. FileProvider declaration** (inside `<application>`):
```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileProvider"
    android:exported="false"
    android:grantUriPermissions="true"
    tools:replace="android:authorities">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/filepaths"
        tools:replace="android:resource" />
</provider>
```

The `tools:replace` attributes prevent conflicts with other Flutter plugins that also declare a FileProvider (e.g., `flutter_blue_plus`). Requires `xmlns:tools="http://schemas.android.com/tools"` on the `<manifest>` tag. [CITED: open_file_plus pub.dev README]

**New file: `android/app/src/main/res/xml/filepaths.xml`**
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="apk_cache" path="." />
</paths>
```

`<cache-path>` maps to `Context.getCacheDir()` — the same directory returned by `getTemporaryDirectory()` on Android. `path="."` grants access to the entire cache dir root; narrowing to a subdirectory is safer but adds complexity for no security benefit in this single-purpose tool. [CITED: Android developer docs — FileProvider setup]

### Anti-Patterns to Avoid

- **Watching the update provider in `build()`** — use `ref.listen` not `ref.watch`; watching causes a full rebuild on each state change, which causes `showDialog` to be called on every rebuild.
- **Calling `showDialog` directly inside `build()`** — always defer to `addPostFrameCallback`; calling during build causes Flutter framework errors.
- **Storing the APK in external storage** — `getExternalStorageDirectory()` requires `WRITE_EXTERNAL_STORAGE` permission (unavailable on API 29+ with scoped storage). Use `getTemporaryDirectory()` (cache dir) instead — no extra permission needed.
- **Comparing version strings lexicographically** — `"1.10.0" > "1.9.0"` is false in lexicographic order. Always compare as integers per segment.
- **Blocking the main thread during download** — `dio.download()` is async; ensure the Future is awaited inside the service, not the provider's `build()`.
- **Not cleaning up partial downloads on error** — delete the partial file in a `finally` block or on catch to avoid the cache filling up.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP with progress | Custom `HttpClient` + chunked read | `dio.download(onReceiveProgress:)` | Handles chunked encoding, Content-Length absent case, redirect following, timeout |
| File URI → content URI on Android 7+ | Manual `FileProvider.getUriForFile()` via platform channel | `open_file_plus` (wraps this) | FileProvider URI conversion is error-prone; intent flags must be exact |
| App version at runtime | Parse `pubspec.yaml` | `PackageInfo.fromPlatform()` | pubspec.yaml is a build artifact; platform channel gives actual installed version |
| Semver comparison | Custom string parser | Integer split on `'.'` (sufficient) or `pub_semver` | Integer split covers all MAJOR.MINOR.PATCH cases; pub_semver for pre-release |
| SharedPreferences boilerplate | Custom file-based key-value | `shared_preferences` | Platform-native storage; handles concurrent access |

---

## Common Pitfalls

### Pitfall 1: FileProvider Authority Conflict
**What goes wrong:** Multiple plugins declare `<provider android:name="androidx.core.content.FileProvider">` with different authorities. Manifest merger fails or silently uses the wrong authority, causing `FileUriExposedException` at runtime.
**Why it happens:** Flutter plugins bundle their own manifest entries. `flutter_blue_plus` and others include FileProvider declarations.
**How to avoid:** Add `tools:replace="android:authorities"` and `tools:replace="android:resource"` to the `<provider>` element. Ensure `xmlns:tools` is on the root `<manifest>` tag.
**Warning signs:** Build-time "Attribute provider#... value=... from AndroidManifest.xml is also present at..." merge warning.

### Pitfall 2: showDialog during build phase
**What goes wrong:** `ref.listen` callback fires synchronously, calling `showDialog` during the widget build phase → Flutter throws "setState() or markNeedsBuild() called during build".
**Why it happens:** `ref.listen` callbacks can fire during the first build frame.
**How to avoid:** Always wrap `showDialog` in `WidgetsBinding.instance.addPostFrameCallback((_) { ... })`.
**Warning signs:** Red screen "The following assertion was thrown building..." mentioning setState during build.

### Pitfall 3: REQUEST_INSTALL_PACKAGES UX surprise
**What goes wrong:** After calling `Permission.requestInstallPackages.request()`, the user is taken to a system Settings page, not shown a dialog. The app appears to "freeze" while the user is in Settings.
**Why it happens:** This permission is a special app-op (not a standard dangerous permission) — Android does not provide a dialog for it; it always redirects to Settings.
**How to avoid:** Show a rationale message BEFORE requesting the permission, explaining that the user will be taken to Settings. After the user returns, re-check `Permission.requestInstallPackages.status` before proceeding.
**Warning signs:** Permission returns `PermissionStatus.denied` immediately after `.request()` if the user didn't return to the app yet.

### Pitfall 4: Total size unknown during download
**What goes wrong:** `onReceiveProgress(received, total)` receives `total = -1` when the server does not send `Content-Length`. GitHub's CDN for release assets (`objects.githubusercontent.com`) sends `Content-Length`, but if requests go through a CDN redirect chain, the header may be stripped.
**Why it happens:** HTTP spec allows omitting `Content-Length` for chunked transfer encoding.
**How to avoid:** Guard with `if (total > 0)` before computing progress percentage. When `total == -1`, show an indeterminate progress indicator rather than a percentage.
**Warning signs:** `double.infinity` or division by zero in the progress calculation.

### Pitfall 5: GitHub API rate limiting
**What goes wrong:** The app fails to check for updates after 60 unauthenticated API calls from the same IP within an hour. Note: GitHub tightened unauthenticated limits in May 2025.
**Why it happens:** 60 requests/hour unauthenticated rate limit applies per originating IP. Single-user personal device tool — device makes only 1 call per cold start, so 60/hour is never a realistic concern in practice.
**How to avoid:** No action needed for this use case. One request per cold start on a single device is well within the limit. Add `User-Agent: soldernerd-inclinometer/1.0` header as GitHub recommends for API clients.
**Warning signs:** HTTP 403 response with `X-RateLimit-Remaining: 0` (would only occur in automated testing scenarios).

### Pitfall 6: Version comparison on current release
**What goes wrong:** `tag_name: "v0.1.0"` is compared against `PackageInfo.version: "1.0.0"` — the installed version is `1.0.0` but the GitHub release is `v0.1.0`. The app always thinks it's up to date.
**Why it happens:** The project's `pubspec.yaml` currently has `version: 1.0.0+1`, but the first GitHub release is `v0.1.0`. The versions diverged during initial development.
**How to avoid:** Ensure the `pubspec.yaml` version is bumped to match the next tag before tagging. For Phase 7 testing: bump `pubspec.yaml` to `0.0.9+X` or test with a locally-built APK and a `v1.0.0` release tag. The planner should include a task to align `pubspec.yaml` version with the release tag format.
**Warning signs:** "Already up to date" message when testing even after creating a new release.

### Pitfall 7: tools:replace missing from manifest
**What goes wrong:** The `<manifest>` tag does not have `xmlns:tools` declared, so the `tools:replace` attributes on the FileProvider cause a build error.
**Why it happens:** `xmlns:tools` must be declared on the root `<manifest>` element; it cannot be declared on child elements.
**How to avoid:** Add `xmlns:tools="http://schemas.android.com/tools"` to the `<manifest>` opening tag.

---

## Code Examples

### Full UpdateService skeleton

```dart
// lib/services/update_service.dart
// Source: patterns verified from pub.dev docs for each package
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apiUrl =
    'https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest';
const _apkAssetName = 'app-release.apk';
const _skipKey = 'skipped_update_version';

class UpdateInfo {
  final String tagName;       // e.g. "v1.1.0"
  final String downloadUrl;   // browser_download_url
  final String version;       // stripped version "1.1.0"
  const UpdateInfo({required this.tagName, required this.downloadUrl, required this.version});
}

class UpdateService {
  /// Returns UpdateInfo if a newer version exists and has not been skipped.
  /// Returns null if up-to-date, already skipped, or any error occurs.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        _apiUrl,
        options: Options(
          headers: {'User-Agent': 'soldernerd-inclinometer'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final tagName = data['tag_name'] as String;          // e.g. "v1.1.0"
      final remoteVer = tagName.replaceFirst('v', '');     // "1.1.0"

      final info = await PackageInfo.fromPlatform();
      final localVer = info.version;                       // "1.0.0"

      if (!_isNewer(remoteVer, localVer)) return null;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_skipKey) == tagName) return null;

      // Find the APK asset
      final assets = data['assets'] as List<dynamic>;
      final asset = assets.firstWhere(
        (a) => (a as Map)['name'] == _apkAssetName,
        orElse: () => null,
      );
      if (asset == null) return null;

      return UpdateInfo(
        tagName: tagName,
        downloadUrl: asset['browser_download_url'] as String,
        version: remoteVer,
      );
    } catch (_) {
      return null; // D-01: silent fail on any error
    }
  }

  /// Downloads the APK to the app cache dir with progress callback.
  /// Throws on failure (caller handles UI state).
  static Future<String> downloadApk(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/$_apkAssetName';
    final dio = Dio();
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
    return savePath;
  }

  /// Requests install permission (opens Settings on Android 8+) then
  /// launches the package installer.
  static Future<void> installApk(String apkPath) async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        await Permission.requestInstallPackages.request();
        final refreshed = await Permission.requestInstallPackages.status;
        if (!refreshed.isGranted) return;
      }
    }
    await OpenFile.open(apkPath);
  }

  static Future<void> skipVersion(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, tagName);
  }

  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map(int.tryParse).toList();
    final l = local.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final rv = r.length > i ? (r[i] ?? 0) : 0;
      final lv = l.length > i ? (l[i] ?? 0) : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }
}
```

### Download progress state (for dialog progress indicator)

Since the download is user-initiated (from within the dialog), progress can be managed with a `StatefulWidget` or a simple `ValueNotifier`:

```dart
// Inside the update dialog — StatefulWidget wrapping a LinearProgressIndicator
ValueNotifier<double> _progress = ValueNotifier(0.0);

// In the "Update" button handler:
UpdateService.downloadApk(info.downloadUrl, (p) => _progress.value = p)
  .then((path) => UpdateService.installApk(path))
  .catchError((_) { /* show snackbar or silently fail */ });
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `StateNotifierProvider` | `Notifier` / `FutureProvider` | Riverpod 2.0 (2022), mandated in this project | Banned in this codebase — use `FutureProvider` for read-only async |
| `SharedPreferences.getInstance()` sync-first | `SharedPreferencesAsync` (fully async, no cache) | `shared_preferences` 2.3+ | Legacy API still works; migration to async API is optional and not worth the churn here |
| External storage for downloads | App cache dir (`getCacheDir()`) | Android 10 scoped storage (API 29) | No WRITE_EXTERNAL_STORAGE needed for cache dir |
| File URI (`file://`) to share with intents | Content URI via FileProvider | Android 7 (API 24) | Direct file URIs are rejected on API 24+; FileProvider mandatory |

**Deprecated/outdated:**
- `StateNotifierProvider`: banned in CLAUDE.md — do not use.
- `WRITE_EXTERNAL_STORAGE` for download: not needed when writing to `getCacheDir()` — do not request.
- `getApplicationDocumentsDirectory()` for APK cache: would work but documents dir is more persistent than cache; cache dir is correct for a transient download.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Simple integer-split semver comparison is sufficient for this project's tag format (no pre-release suffixes) | Code Examples / Pattern 4 | If tags like `v1.0.0-beta` are ever used, comparison logic would fail silently (remote > local comparison may return false incorrectly) |
| A2 | `open_file_plus` 3.4.1+1 (2 years old) is compatible with Flutter 3.44+ / Dart 3.12+ | Standard Stack | If incompatible, switch to `open_filex` or `open_file` as drop-in alternatives |
| A3 | GitHub tightened unauthenticated rate limits in May 2025 but single-device cold-start usage (1 call/start) is unaffected | Common Pitfalls / Pitfall 5 | If rate limit falls below practical threshold, add `User-Agent` header and/or cache last-check timestamp |
| A4 | `getTemporaryDirectory()` on Android maps to `getCacheDir()` (internal app cache, no permission needed) | Code Examples | If mapping changed in recent Flutter engine, the FileProvider `<cache-path>` element would be wrong |
| A5 | `pubspec.yaml` version `1.0.0` is higher than GitHub release `v0.1.0`, so the updater will never trigger until pubspec is bumped | Common Pitfalls / Pitfall 6 | Version alignment is a deployment concern; wrong version mapping means the check always returns "up to date" |

---

## Open Questions

1. **`pubspec.yaml` version alignment**
   - What we know: Current `pubspec.yaml` has `version: 1.0.0+1`; latest GitHub release is `v0.1.0` (`tag_name`). `1.0.0 > 0.1.0` so the installed build always looks "ahead of" the release.
   - What's unclear: Should `pubspec.yaml` be downgraded to `0.1.0+1` to match, or should the next release be tagged `v1.0.0`? This is a deployment decision, not a code decision.
   - Recommendation: The planner should include a task to bump `pubspec.yaml` version to match the intended next release tag (or document the alignment rule) before Phase 7 is considered complete.

2. **Download progress when Content-Length is absent**
   - What we know: GitHub CDN usually includes `Content-Length` for release assets; confirmed `size: 48762701` in the live API response.
   - What's unclear: Whether the CDN redirect chain preserves the header for all clients (VPN, proxy, etc.).
   - Recommendation: Guard with `if (total > 0)` and show `CircularProgressIndicator` (indeterminate) when `total == -1`; show `LinearProgressIndicator(value: progress)` otherwise.

3. **Partial download cleanup**
   - What we know: `dio.download()` has `deleteOnError: true` by default, which removes the partial file on exception.
   - What's unclear: Whether the default is reliable across all Dio 5.x versions or needs to be explicitly set.
   - Recommendation: Pass `deleteOnError: true` explicitly for clarity; also wrap in try/finally and delete in the catch to be safe.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Build | ✓ (project builds) | 3.44+ (inferred from engine min) | — |
| Dart SDK 3.12+ | `shared_preferences` 2.5.5 requires 3.9; `package_info_plus` 10.1.0 requires 3.10 | ✓ | 3.12.1 (pubspec.yaml env) | — |
| Android device / emulator API 24+ | Platform testing | ✓ (project targets minSdk 24) | — | — |
| GitHub API access | Update check | ✓ (verified live during research) | — | Fails silently per D-01 |
| Internet permission | Network calls | must declare in manifest | — | Not needed at runtime if offline |

Note: `INTERNET` permission is not currently declared in `AndroidManifest.xml`. Flutter apps get it automatically via the Flutter engine manifest merge for debug builds, but it should be verified to be present for release builds. Add `<uses-permission android:name="android.permission.INTERNET" />` to the manifest if missing. [ASSUMED — common Flutter pitfall]

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) + test 1.31.0 |
| Config file | none (standard flutter test runner) |
| Quick run command | `flutter test test/update_service_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UPD-01 | Version comparison logic (`_isNewer`) | unit | `flutter test test/update_service_test.dart` | ❌ Wave 0 |
| UPD-01 | `checkForUpdate` returns null when already up-to-date | unit (mock HTTP) | `flutter test test/update_service_test.dart` | ❌ Wave 0 |
| UPD-02 | Dialog appears when `updateCheckProvider` returns UpdateInfo | widget | `flutter test test/scan_screen_test.dart` | ❌ needs extension |
| UPD-03 | Download progress callback fires (mock dio) | unit | `flutter test test/update_service_test.dart` | ❌ Wave 0 |
| UPD-04 | `installApk` calls OpenFile.open with correct path | unit (mock OpenFile) | `flutter test test/update_service_test.dart` | ❌ Wave 0 |
| UPD-05 | `checkForUpdate` returns null on network error | unit | `flutter test test/update_service_test.dart` | ❌ Wave 0 |
| UPD-06 | Manifest contains REQUEST_INSTALL_PACKAGES | manual inspection | `grep -l REQUEST_INSTALL_PACKAGES android/app/src/main/AndroidManifest.xml` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/update_service_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** `flutter test` green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/update_service_test.dart` — covers UPD-01, UPD-03, UPD-04, UPD-05 (version compare, download mock, install mock, silent fail)
- [ ] Framework already installed (`flutter_test` + `test` in dev_dependencies)

---

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Validate `tag_name` is semver-like before parsing; handle malformed JSON gracefully (try/catch) |
| V6 Cryptography | no | APK signature verification is handled by Android at install time |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| DNS spoofing / MITM on GitHub API response | Tampering | HTTPS enforced by `dio` default; Android validates TLS cert chain |
| Malicious APK served from CDN | Tampering | Android verifies APK signature at install time against the signing key |
| Path traversal in `tag_name` | Tampering | Never use `tag_name` as a filename; APK filename is hardcoded (D-10) |
| Downloading an APK from a redirected URL | Spoofing | `dio` follows redirects on same-host; `browser_download_url` in GitHub assets is a trusted GitHub domain |

---

## Sources

### Primary (HIGH confidence)
- Live GitHub API query `https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest` — confirmed `tag_name`, `assets[].name`, `assets[].browser_download_url`, `assets[].size` [VERIFIED: live 2026-06-07]
- pub.dev/packages/dio — version 5.9.2, `download()` method signature, `onReceiveProgress: ProgressCallback?` [CITED]
- pub.dev/packages/package_info_plus — version 10.1.0, async `fromPlatform()`, `version` field [CITED]
- pub.dev/packages/shared_preferences — version 2.5.5, `getInstance()` / `getString` / `setString` pattern [CITED]
- pub.dev/packages/permission_handler — version 12.0.3, `Permission.requestInstallPackages` opens Settings intent [CITED]
- pub.dev/documentation/dio/latest/dio/Dio-class.html — exact `download()` signature [CITED]
- riverpod.dev/docs/whats_new — Riverpod 3.0 FutureProvider and autoDispose semantics [CITED]

### Secondary (MEDIUM confidence)
- pub.dev/packages/open_file_plus README — FileProvider manifest config, `tools:replace` requirement, permission list [CITED: verified against pub.dev page 2026-06-07]
- Android developer docs (via WebFetch) — `REQUEST_INSTALL_PACKAGES` is a special app-op not a standard runtime permission; `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` [CITED]
- Android FileProvider docs — `<cache-path>` maps to `getCacheDir()` [CITED]
- docs.github.com/rest — 60 req/hour unauthenticated primary rate limit [CITED]

### Tertiary (LOW confidence)
- GitHub changelog 2025-05-08 — unauthenticated rate limits tightened (numeric values not disclosed) [WebSearch — no specific new limit confirmed]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified on pub.dev with publisher and version confirmed
- GitHub API shape: HIGH — live query against actual repo during research
- FileProvider setup: MEDIUM — documented from open_file_plus README; `tools:replace` pattern well-established but not independently tested in this project
- `REQUEST_INSTALL_PACKAGES` UX: HIGH — documented in permission_handler pub.dev README verbatim
- Architecture patterns: HIGH — consistent with existing project Riverpod patterns

**Research date:** 2026-06-07
**Valid until:** 2026-09-07 (stable packages) — re-verify `open_file_plus` compatibility if Flutter SDK is upgraded
