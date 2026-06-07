---
phase: 7
slug: github-self-update
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-07
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK) + test 1.31.0 |
| **Config file** | none (standard flutter test runner) |
| **Quick run command** | `flutter test test/update_service_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/update_service_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | UPD-06 | — | N/A | static analysis | `flutter analyze android/app/src/main/AndroidManifest.xml` | ✅ | ⬜ pending |
| 07-01-02 | 01 | 1 | — | — | N/A | compile | `flutter pub get && flutter analyze` | ✅ | ⬜ pending |
| 07-01-03 | 01 | 1 | — | — | N/A | compile | `flutter analyze` | ✅ | ⬜ pending |
| 07-02-01 | 02 | 2 | UPD-01, UPD-05 | — | silent fail on network error | unit | `flutter test test/update_service_test.dart` | ❌ W0 | ⬜ pending |
| 07-02-02 | 02 | 2 | UPD-03, UPD-04, UPD-06 | — | install permission check before installer | unit (partial) | `flutter analyze lib/services/update_service.dart` | ✅ | ⬜ pending |
| 07-03-01 | 03 | 3 | UPD-01, UPD-05 | — | N/A | compile | `flutter analyze lib/providers/update_provider.dart` | ❌ W0 | ⬜ pending |
| 07-03-02 | 03 | 3 | UPD-02, UPD-03 | — | dialog only when newer version detected | widget | `flutter test test/ui/scan_screen_test.dart` | ✅ | ⬜ pending |
| 07-03-03 | 03 | 3 | UPD-02 | — | N/A | widget | `flutter test test/ui/scan_screen_test.dart` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/update_service_test.dart` — unit tests for `_isNewer` (UPD-01), `checkForUpdate` silent fail (UPD-05); created in 07-02 Task 1
- [ ] `lib/providers/update_provider.dart` — created in 07-03 Task 1

*Existing infrastructure (`flutter_test`, `test` in dev_dependencies) covers all other phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| APK download with progress indicator | UPD-03 | `dio.download` requires a real network connection and 48 MB transfer | Run app on device; trigger update dialog; verify progress bar fills to 100% |
| Android package installer launches | UPD-04 | `OpenFile.open` requires Android runtime + installed app | After download, verify system installer sheet appears |
| REQUEST_INSTALL_PACKAGES opens Settings | UPD-06 | Permission opens Settings app (not dialog); requires Android 8+ device | Tap "Update" with permission denied; verify Settings opens to "Install unknown apps" |
| Silent fail on no internet | UPD-05 | Network state requires device flight mode | Enable flight mode; cold start app; verify no error dialog |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
