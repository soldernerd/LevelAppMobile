---
phase: 06-app-icon
fixed_at: 2026-06-06T00:00:00Z
fix_scope: critical_warning
findings_in_scope: 3
fixed: 3
skipped: 0
iteration: 1
status: all_fixed
---

# Phase 06: Code Review Fix Report

**Fixed:** 2026-06-06T00:00:00Z
**Fix Scope:** critical_warning (Critical + Warning)
**Findings in Scope:** 3
**Fixed:** 3
**Skipped:** 0
**Status:** all_fixed

## Fixes Applied

### WR-01 — `min_sdk_android` aligned to project minSdkVersion 24

**File:** `pubspec.yaml:105`
**Fix:** Changed `min_sdk_android: 21` → `min_sdk_android: 24`
**Commit:** b4730af

The value was 3 versions below the declared project minimum (24), which
would cause `flutter_launcher_icons` to generate dead legacy mipmap PNG
fallbacks for API levels 21–23 that can never be served on this build.

---

### WR-02 — Added missing `ic_launcher_round.xml` adaptive icon variant

**File:** `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml` (created)
**Fix:** Created the file as a sibling of `ic_launcher.xml` with identical content
**Commit:** ff67822

Without this file, circular-icon launchers (Pixel Launcher, Samsung One UI)
fell back to legacy density-bucket square PNG crops which appear clipped in
a circular mask. The new file mirrors `ic_launcher.xml` exactly.

---

### WR-03 — Removed deprecated iOS icon sizes from Contents.json

**File:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`
**Fix:** Removed 6 deprecated entries: `57x57@1x`/`@2x` (iphone), `50x50@1x`/`@2x` (ipad), `72x72@1x`/`@2x` (ipad)
**Commit:** d2e158d

These sizes target iOS 6/7 devices (iPhone 3GS, non-retina iPad) that are
no longer supported. Xcode emits an "unassigned children" warning for each
removed entry on every clean build. The remaining set satisfies App Store
requirements and all modern device targets.

---

## Skipped (Info — out of scope for critical_warning fix)

- **IN-01:** `flutter_launcher_icons` caret constraint — low-risk dev-dependency, no action needed
- **IN-02:** `flutter_blue_plus` absent from dependencies — expected WP1 state, action deferred to WP2

---

_Fixed: 2026-06-06T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Fix Scope: critical_warning_
