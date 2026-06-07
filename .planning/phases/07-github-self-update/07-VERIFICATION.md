---
phase: 07-github-self-update
verified: 2026-06-07T00:00:00Z
status: human_needed
score: 6/6 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Cold start on a real Android device with network access — observe that the update dialog appears when a newer GitHub release exists"
    expected: "An AlertDialog appears naming the new release version with Skip and Update buttons; tapping Update downloads the APK and shows a LinearProgressIndicator, then launches the Android package installer"
    why_human: "Full end-to-end path requires a real device, a real GitHub release tag newer than 0.1.0, and network connectivity — cannot be verified with grep or widget tests alone"
  - test: "Cold start with no network / airplane mode"
    expected: "App loads normally with no error dialog, no crash — update check fails silently"
    why_human: "Network failure path requires a real device in airplane mode to confirm the catch-all silent-fail behaves correctly at runtime"
  - test: "Tap Skip on the update dialog; force-kill and relaunch the app"
    expected: "The update dialog does NOT reappear for the same version tag on the second cold start"
    why_human: "SharedPreferences persistence across process restarts requires a real device; widget tests cannot simulate process restart"
  - test: "Tap Update, observe progress indicator animating, then verify the Android package installer opens"
    expected: "LinearProgressIndicator shows percentage rising from 0% to 100% as download progresses; after download the Android 'Do you want to install this app?' installer screen appears"
    why_human: "APK download progress and installer launch require a real device and a real downloadable APK asset on GitHub"
  - test: "On Android 8+ (API 26) with REQUEST_INSTALL_PACKAGES not yet granted, tap Update"
    expected: "Android opens the 'Install unknown apps' Settings page for the app; after granting permission and returning, the installer launches"
    why_human: "Permission.requestInstallPackages.request() opens Settings (not a dialog) on API 26+ — this Settings redirection cannot be simulated in a widget test"
---

# Phase 7: GitHub Self-Update Verification Report

**Phase Goal:** App checks GitHub Releases on startup, compares installed version against latest release, and offers to download + install the APK when a newer version exists.
**Verified:** 2026-06-07
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| #  | Truth                                                                                                           | Status     | Evidence                                                                                                                                                           |
|----|-----------------------------------------------------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1  | On startup the app calls the GitHub releases/latest endpoint and compares `tag_name` against `PackageInfo`     | VERIFIED   | `_apiUrl` constant in `update_service.dart` line 20; `dio.get(_apiUrl, ...)` in `checkForUpdate()`; `PackageInfo.fromPlatform()` version read at line 72          |
| 2  | When a newer version is detected an AlertDialog appears showing the new version number with Skip/Update actions | VERIFIED   | `_showUpdateDialog` in `scan_screen.dart` lines 333–416; `ref.listen(updateCheckProvider, ...)` wiring at lines 64–75; UPD-02 widget test asserts `AlertDialog`, `9.9.9`, `Skip`, `Update` buttons |
| 3  | Tapping "Update" downloads the APK from `assets[].browser_download_url` with a visible progress indicator      | VERIFIED   | `UpdateService.downloadApk` uses `dio.download` with `onReceiveProgress` and `total > 0` guard (lines 113–122); `LinearProgressIndicator` rendered in dialog (lines 359–361); `UpdateService.downloadApk` called from `Update` button handler (lines 395–399) |
| 4  | After a successful download the Android package installer launches                                              | VERIFIED   | `UpdateService.installApk` calls `OpenFilex.open(apkPath)` after `Permission.requestInstallPackages` check (lines 132–144 of `update_service.dart`); called from dialog `Update` handler at line 399 |
| 5  | Network failure / unreachable GitHub API fails silently — no crash, no error dialog                            | VERIFIED   | Entire `checkForUpdate()` body wrapped in `try { ... } catch (_) { return null; }` (lines 53–98); `updateCheckProvider` returns `null` which causes `ref.listen` `whenData` guard to return early |
| 6  | `REQUEST_INSTALL_PACKAGES` declared in `AndroidManifest.xml`; runtime permission requested on Android 8+ (API 26+) | VERIFIED | `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />` at line 8 of `AndroidManifest.xml`; `Permission.requestInstallPackages.status` + `.request()` in `installApk` (lines 134–138 of `update_service.dart`) |

**Score:** 6/6 truths verified

---

### Required Artifacts

| Artifact                                              | Expected                                                              | Status     | Details                                                                                              |
|-------------------------------------------------------|-----------------------------------------------------------------------|------------|------------------------------------------------------------------------------------------------------|
| `lib/services/update_service.dart`                    | UpdateInfo model + UpdateService with 4 static methods                | VERIFIED   | 175 lines; `class UpdateInfo` at line 25; `class UpdateService` at line 46; all 4 methods present and substantive |
| `test/update_service_test.dart`                       | Unit tests for version comparison (UPD-01)                            | VERIFIED   | 37 lines; 6 test cases in group `UPD-01: Version comparison logic`; includes non-lexicographic `1.10.0 > 1.9.0` case |
| `lib/providers/update_provider.dart`                  | `updateCheckProvider` FutureProvider<UpdateInfo?> autoDispose         | VERIFIED   | 23 lines; `FutureProvider<UpdateInfo?>` defined at line 21; no `keepAlive()` call; package-qualified imports only |
| `lib/ui/scan_screen.dart`                             | `ref.listen` on `updateCheckProvider` + `_showUpdateDialog`           | VERIFIED   | `ref.listen<AsyncValue<UpdateInfo?>>(updateCheckProvider, ...)` at lines 64–75; `_showUpdateDialog` helper at lines 333–416 |
| `test/ui/scan_screen_test.dart`                       | UPD-02 widget test with `updateCheckProvider.overrideWith`            | VERIFIED   | Group `UPD-02: Update dialog` at line 213; `updateCheckProvider.overrideWith` with `UpdateInfo(tagName: 'v9.9.9', ...)` |
| `android/app/src/main/AndroidManifest.xml`            | `REQUEST_INSTALL_PACKAGES` + `INTERNET` permissions + FileProvider    | VERIFIED   | Both permissions at lines 8–9; FileProvider element at lines 41–51 with `tools:replace` merger guards; `xmlns:tools` on root |
| `android/app/src/main/res/xml/filepaths.xml`          | `<cache-path name="apk_cache" path="." />`                            | VERIFIED   | File exists; single `<cache-path name="apk_cache" path="." />` child of `<paths>` root              |
| `pubspec.yaml`                                        | `dio`, `package_info_plus`, `shared_preferences`, `path_provider`, `open_filex`; version `0.1.0+1` | VERIFIED | All 5 deps present (lines 37–46); `open_filex: ^4.5.0` used (substitute approved in 07-01); `version: 0.1.0+1` at line 19 |

---

### Key Link Verification

| From                               | To                                            | Via                                               | Status   | Details                                                                                                                         |
|------------------------------------|-----------------------------------------------|---------------------------------------------------|----------|---------------------------------------------------------------------------------------------------------------------------------|
| `lib/services/update_service.dart` | GitHub releases API                           | `dio.get` to `releases/latest`                    | WIRED    | `_apiUrl` constant (line 20) used in `dio.get(...)` at line 55                                                                  |
| `lib/services/update_service.dart` | Android package installer                     | `OpenFilex.open(apkPath)`                         | WIRED    | `await OpenFilex.open(apkPath)` at line 143                                                                                     |
| `lib/providers/update_provider.dart` | `UpdateService.checkForUpdate`              | `FutureProvider` body                             | WIRED    | `return UpdateService.checkForUpdate()` at line 22                                                                              |
| `lib/ui/scan_screen.dart`          | `updateCheckProvider`                         | `ref.listen` + `addPostFrameCallback`             | WIRED    | `ref.listen<AsyncValue<UpdateInfo?>>(updateCheckProvider, ...)` at lines 64–75; `addPostFrameCallback` at line 70               |
| `lib/ui/scan_screen.dart`          | `UpdateService.downloadApk / installApk / skipVersion` | Dialog button handlers                  | WIRED    | `UpdateService.skipVersion` at line 386; `UpdateService.downloadApk` at line 395; `UpdateService.installApk` at line 399       |
| `android/app/src/main/AndroidManifest.xml` | `android/app/src/main/res/xml/filepaths.xml` | `android:resource="@xml/filepaths"` meta-data | WIRED | `android:resource="@xml/filepaths"` at line 49 of `AndroidManifest.xml`                                                        |

---

### Data-Flow Trace (Level 4)

| Artifact                   | Data Variable    | Source                          | Produces Real Data                                                    | Status    |
|----------------------------|------------------|---------------------------------|-----------------------------------------------------------------------|-----------|
| `lib/ui/scan_screen.dart`  | `info` (UpdateInfo) | `updateCheckProvider` → `UpdateService.checkForUpdate()` → GitHub API | Yes — `checkForUpdate` performs a real `dio.get` call, parses JSON, compares versions; only returns real `UpdateInfo` when GitHub has a newer release | FLOWING   |
| `lib/providers/update_provider.dart` | `UpdateInfo?` | `UpdateService.checkForUpdate()` | Yes — delegates directly to the real service method | FLOWING |

---

### Behavioral Spot-Checks

Step 7b skipped for the live GitHub API call and device installer paths (require a running device and real network). The unit-testable behavior (version comparison) is covered by the test suite documented below.

| Behavior                                   | Command                                                       | Result                                         | Status |
|--------------------------------------------|---------------------------------------------------------------|------------------------------------------------|--------|
| `_isNewer` returns true for patch increment | `flutter test test/update_service_test.dart` (6 assertions)  | 6/6 pass per 07-02-SUMMARY TDD gate            | PASS (documented; cannot re-run in this environment) |
| UPD-02 widget test: dialog appears with version | `flutter test test/ui/scan_screen_test.dart`           | 9/9 pass per 07-03-SUMMARY self-check          | PASS (documented; cannot re-run in this environment) |

---

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` files declared or discovered for this phase. Step 7c: SKIPPED (no probes).

---

### Requirements Coverage

**Note:** UPD-01 through UPD-06 are referenced in PLAN frontmatter `requirements:` fields but are NOT formally defined in `.planning/REQUIREMENTS.md`. They are defined implicitly as the 6 Phase 7 Success Criteria in ROADMAP.md. The traceability table in REQUIREMENTS.md ends at BUILD-02 and does not include Phase 7 entries. This is a documentation gap only — the implementation satisfies all 6 criteria as verified above.

| Requirement | Source Plan | Description (from ROADMAP.md SC)                                        | Status          | Evidence                                                                 |
|-------------|-------------|-------------------------------------------------------------------------|-----------------|--------------------------------------------------------------------------|
| UPD-01      | 07-02       | Integer-per-segment version comparison (1.10.0 > 1.9.0)                | SATISFIED       | `_isNewer` in `update_service.dart` lines 163–173; 6-case unit test suite in `test/update_service_test.dart` |
| UPD-02      | 07-03       | Update dialog appears naming the new version with Skip/Update actions   | SATISFIED       | `_showUpdateDialog` in `scan_screen.dart`; UPD-02 widget test in `scan_screen_test.dart` line 219 |
| UPD-03      | 07-02, 07-03 | APK download with visible progress indicator                           | SATISFIED       | `downloadApk` with `onReceiveProgress` + `total > 0` guard; `LinearProgressIndicator` in dialog |
| UPD-04      | 07-02       | Android package installer launches after successful download            | SATISFIED       | `installApk` calls `OpenFilex.open(apkPath)` after permission check    |
| UPD-05      | 07-02       | Silent fail on network error — no crash, no error dialog                | SATISFIED       | `checkForUpdate` catch-all `catch (_) { return null; }` at line 95     |
| UPD-06      | 07-01, 07-02 | `REQUEST_INSTALL_PACKAGES` declared in manifest; runtime permission requested on Android 8+ | SATISFIED | Manifest line 8; `Permission.requestInstallPackages` in `installApk` lines 134–138 |

**Orphaned requirements:** REQUIREMENTS.md has no Phase 7 entries and no UPD-* IDs. This is a documentation gap: REQUIREMENTS.md was not updated to include Phase 7 requirements. Does not affect implementation correctness.

---

### Anti-Patterns Found

| File                                     | Line | Pattern           | Severity | Impact  |
|------------------------------------------|------|-------------------|----------|---------|
| No anti-patterns found in phase files    | —    | —                 | —        | —       |

Scanned: `lib/services/update_service.dart`, `lib/providers/update_provider.dart`, `lib/ui/scan_screen.dart`. No TBD/FIXME/XXX/HACK/PLACEHOLDER markers. No empty implementations. All `return null` instances are intentional logic gates (version check, skip check, missing asset, catch-all).

---

### Human Verification Required

The automated verification passes all 6 success criteria. The following behaviors require a real Android device to confirm the end-to-end runtime path:

#### 1. Update dialog on real device with newer GitHub release

**Test:** Install the app at version 0.1.0+1 on a physical Android device. Publish a GitHub release tagged `v0.1.1` (or higher) with an `app-release.apk` asset. Cold-launch the app.
**Expected:** An AlertDialog appears naming version `0.1.1` (or higher) with Skip and Update buttons within a few seconds of launch.
**Why human:** Requires a real GitHub release, real network, and a physical Android device. Widget test uses a mock provider.

#### 2. Silent fail on no network

**Test:** Enable airplane mode on an Android device, cold-launch the app.
**Expected:** App loads the scan screen normally, no error dialog, no crash.
**Why human:** Network failure path requires a physical device in airplane mode to confirm at runtime.

#### 3. Skip persists across process restarts

**Test:** With a newer version available, tap Skip in the update dialog. Force-kill the app (recent apps → swipe). Relaunch.
**Expected:** The update dialog does NOT reappear for the same version tag.
**Why human:** SharedPreferences persistence across process kills requires a real device; widget tests cannot simulate process restart.

#### 4. Download progress and installer launch

**Test:** With a newer version available, tap Update. Observe the download progress bar.
**Expected:** `LinearProgressIndicator` animates from 0% to 100%; after download completes the standard Android "Do you want to install this app?" screen appears.
**Why human:** APK download progress and installer launch require a real device and a downloadable APK asset.

#### 5. REQUEST_INSTALL_PACKAGES permission on Android 8+ (API 26)

**Test:** On a device running Android 8+ where the app does not yet have "Install unknown apps" permission, tap Update.
**Expected:** Android opens the "Install unknown apps" settings page for the app. After granting permission and returning, the installer launches.
**Why human:** `Permission.requestInstallPackages.request()` opens the Settings app on API 26+ — this system redirect cannot be tested with a widget test.

---

### Gaps Summary

No blocking gaps. All 6 phase success criteria are satisfied in the codebase. The 5 human verification items represent end-to-end runtime behaviors that require a physical Android device and are standard for any sideload/update implementation.

**Documentation gap (non-blocking):** `.planning/REQUIREMENTS.md` does not include UPD-01 through UPD-06 entries or a Phase 7 row in the traceability table. The ROADMAP.md Phase 7 section serves as the authoritative specification. Recommend updating REQUIREMENTS.md for long-term traceability, but this does not block the phase.

---

_Verified: 2026-06-07_
_Verifier: Claude (gsd-verifier)_
