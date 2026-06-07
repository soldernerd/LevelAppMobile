# Phase 7: GitHub Self-Update - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Add an in-app updater that silently checks the `soldernerd/LevelAppMobile` GitHub Releases API on every cold start, compares the latest release tag against the installed version, and — when a newer version exists — offers to download the signed APK in-app and launch the Android package installer. This closes the CI/CD loop: push a `v*.*.*` tag → release workflow publishes `app-release.apk` → running app self-offers the update on next launch.

Android only. iOS is out of scope (sideloading blocked by platform).

</domain>

<decisions>
## Implementation Decisions

### Update Check Trigger
- **D-01:** Check fires once per cold start, silently in the background. No blocking of the scan screen. If the check fails (no internet, API error, timeout) it fails silently — no crash, no error dialog.
- **D-02:** No manual "Check for updates" button. No About/Settings screen required for this phase.

### Dismiss / Skip Behavior
- **D-03:** When the user dismisses the update dialog without installing, the skipped version tag is persisted (e.g. via `shared_preferences`). The update dialog is NOT shown again for that specific version. When a newer version is released, the dialog appears again.
- **D-04:** There is no "Remind me later" / snooze option — dismiss = skip this version permanently.

### Download and Install Flow
- **D-05:** Full in-app download using `dio` with a visible progress indicator (percentage). APK is saved to the app's cache directory.
- **D-06:** After download completes, `open_file_plus` (or equivalent) launches the Android system package installer.
- **D-07:** `REQUEST_INSTALL_PACKAGES` permission is declared in `AndroidManifest.xml`. On Android 8+ (API 26+) the app checks and requests this permission at runtime before attempting installation.

### GitHub Integration
- **D-08:** Repository is hardcoded as `soldernerd/LevelAppMobile` — private single-purpose tool, no need for `dart-define` injection.
- **D-09:** API endpoint: `https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest`. Parse `tag_name` (strip leading `v`) and compare against `PackageInfo.version` from `package_info_plus`.
- **D-10:** APK asset filename is hardcoded as `app-release.apk` — matches the existing `release.yml` upload step exactly.

### Architecture
- **D-11:** Update check logic lives in a Riverpod provider (e.g. `updateCheckProvider`) so it's testable and lifecycle-managed. Provider is `keepAlive: false` — single fire on startup, no need to persist across navigation.
- **D-12:** No new UI screen required. Update dialog is a standard `showDialog` call triggered from the scan screen (or app root) when the provider detects a newer version.

### Claude's Discretion
- Exact wording of the update dialog (version numbers shown, button labels "Update" / "Skip").
- Error handling details within the download flow (partial download cleanup, etc.).
- Whether to use `package_info_plus` or parse `pubspec.yaml` at build time for version — `package_info_plus` is the idiomatic Flutter approach.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### CI/CD Workflow (defines APK asset name and release structure)
- `.github/workflows/release.yml` — Release workflow: triggers on `v*.*.*` tags, uploads `app-release.apk` from `build/app/outputs/flutter-apk/`. The asset filename and path are the ground truth for D-10.

### Requirements
- `.planning/REQUIREMENTS.md` — Phase 7 covers UPD-01 through UPD-06. These are the acceptance criteria.

### Architecture Constraints
- `CLAUDE.md` — Stack table and architecture constraints; Riverpod 3.x `Notifier`/`AsyncNotifier` patterns; `keepAlive` rules for providers.

### Existing Platform Files (read before modifying)
- `android/app/src/main/AndroidManifest.xml` — Add `REQUEST_INSTALL_PACKAGES` permission here.
- `pubspec.yaml` — Current version `1.0.0+1`; add `package_info_plus`, `dio`, `open_file_plus`, `shared_preferences` dependencies here.

### Existing Provider Patterns
- `lib/providers/device_provider.dart` — Reference for Riverpod `Notifier` provider structure used throughout the app.
- `lib/main.dart` — App entry point; update check provider should be initialized here or triggered from the root widget.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `connectionNotifierProvider` in `lib/providers/device_provider.dart` — reference implementation for a Riverpod `Notifier` with async side effects; follow the same pattern for `updateCheckProvider`.
- `ProviderScope.overrides` in `lib/main.dart` — established injection point; no changes needed for this phase.

### Established Patterns
- `Notifier`/`AsyncNotifier` — all providers in this project use this pattern (Riverpod 3.3.1). `StateNotifierProvider` is banned.
- `ThemeData.dark()` — dark theme only; any update dialog must use the existing dark theme.
- No imports of platform SDKs in `lib/ui/` or `lib/providers/` — update logic must stay in a dedicated provider/service layer.

### Integration Points
- App startup (root `ConsumerWidget` or `main.dart`) — trigger the update check provider here, once, after the widget tree is mounted.
- `ScanScreen` — most natural place to show the update dialog (it's the app's home screen); watch the update provider and call `showDialog` when a new version is detected.
- `android/app/src/main/AndroidManifest.xml` — add `REQUEST_INSTALL_PACKAGES` alongside the existing BLE permissions.

</code_context>

<specifics>
## Specific Ideas

- The CI/CD motivation is explicit: this feature exists to close the loop — tag → build → self-update. The user should never need to manually sideload an APK after the first install.
- Version comparison must handle the `v` prefix in GitHub tag names (e.g. `v1.2.0` → `1.2.0`) before comparing with `PackageInfo.version`.
- Skip-version persistence key suggestion: `skipped_update_version` in `shared_preferences`, storing the last-skipped tag string.

</specifics>

<deferred>
## Deferred Ideas

- iOS update delivery — not possible via sideloading; would require TestFlight or App Store. Deferred to a future milestone.
- In-app changelog display (show release notes from GitHub API `body` field) — nice-to-have; out of scope for this phase.
- Background periodic update check (not just cold start) — out of scope; cold start is sufficient for this tool's usage pattern.

</deferred>

---

*Phase: 7-GitHub Self-Update*
*Context gathered: 2026-06-07*
