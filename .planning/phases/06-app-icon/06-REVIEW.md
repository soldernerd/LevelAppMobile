---
phase: 06-app-icon
reviewed: 2026-06-06T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - pubspec.yaml
  - android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  - android/app/src/main/res/values/colors.xml
  - ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-06-06T00:00:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Four text/config files were reviewed for the phase-6 app icon addition. The
`flutter_launcher_icons` flat-format config in `pubspec.yaml` is structurally
correct for v0.14.x. The Android adaptive icon XML and colors file are valid.
The iOS `Contents.json` is well-formed. Three warnings were identified: a
`min_sdk_android` value that conflicts with the project's declared minimum SDK,
a missing `ic_launcher_round.xml` adaptive icon variant, and legacy iOS icon
sizes that will produce Xcode build warnings on every clean build.

## Warnings

### WR-01: `min_sdk_android` conflicts with project minSdkVersion

**File:** `pubspec.yaml:105`
**Issue:** `flutter_launcher_icons` is configured with `min_sdk_android: 21`,
but `CLAUDE.md` specifies `minSdkVersion 24` as the project minimum. When
`flutter_launcher_icons` respects this key it generates legacy mipmap PNG
fallbacks for API levels 21-23, adding dead assets that will never be served.
More critically, if the intent was to ensure adaptive icons are always used
(API 26+), the field is redundant and misleading; if it was meant to match the
real minimum SDK it is wrong by three versions.

**Fix:** Align the value with the actual project minimum:
```yaml
min_sdk_android: 24
```

---

### WR-02: Missing `ic_launcher_round.xml` adaptive icon variant

**File:** `android/app/src/main/res/mipmap-anydpi-v26/` (directory)
**Issue:** Android supports a separate `ic_launcher_round` resource for
launchers that display circular icons (Pixel Launcher, Samsung One UI, etc.).
`flutter_launcher_icons` generates this file when adaptive icons are enabled,
but only `ic_launcher.xml` exists in `mipmap-anydpi-v26/`. Without
`ic_launcher_round.xml`, circular-icon launchers fall back to the legacy
density-bucket PNGs in `mipmap-*/`, which are square crops and will appear
clipped or poorly scaled in a circular mask.

**Fix:** Add `ic_launcher_round.xml` as a sibling of `ic_launcher.xml` with
the same content (or re-run `flutter pub run flutter_launcher_icons` and verify
it is emitted). The file content should be identical to `ic_launcher.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="16%" />
  </foreground>
</adaptive-icon>
```

---

### WR-03: Legacy iOS icon sizes generate Xcode build warnings every build

**File:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json:1`
**Issue:** `Contents.json` declares icon sizes that have been deprecated or
removed from the iOS Human Interface Guidelines and are no longer needed by
the App Store or modern device targets:
- `57x57@1x` and `57x57@2x` — iPhone 3GS / iPhone 4 (iOS 6/7 only)
- `50x50@1x` and `50x50@2x` — iPad 2 / iPad mini 1 (non-retina)
- `72x72@1x` and `72x72@2x` — iPad 1-3 (pre-retina)

Xcode emits an "unassigned children" or "unexpected file" warning for each
size that Xcode's validator no longer recognizes as required. While not a
build failure, these warnings appear on every clean build and obscure
legitimate warnings.

**Fix:** Remove the six deprecated entries from the `images` array. The
minimal modern set that satisfies the App Store and all supported device sizes
is: 20×20 @2×/@3× (iPhone notification), 29×29 @1×/@2×/@3×, 40×40
@1×/@2×/@3×, 60×60 @2×/@3× (iPhone home screen), iPad equivalents at
supported densities, 76×76 @1×/@2×, 83.5×83.5 @2×, and 1024×1024 @1×
(ios-marketing). Re-running `flutter_launcher_icons` after removing the
deprecated sizes from its config (or updating to a newer template) will
regenerate a clean set.

---

## Info

### IN-01: `flutter_launcher_icons` version uses caret constraint, not a pin

**File:** `pubspec.yaml:55`
**Issue:** `flutter_launcher_icons: ^0.14.4` allows resolution to any
`0.14.x` patch release. The phase description calls for pinning to `0.14.4`.
In a `dev_dependency` used only at code-generation time this is low risk, but
a future `0.14.5` patch could silently change generated output.

**Fix:** Pin the version if reproducible generation is required:
```yaml
flutter_launcher_icons: 0.14.4
```

---

### IN-02: `flutter_blue_plus` absent from dependencies

**File:** `pubspec.yaml:30-41`
**Issue:** `flutter_blue_plus` is listed as the primary BLE package in
`CLAUDE.md` (version 2.3.5) but is not present in `dependencies`. This is
likely a pre-existing WP1 scaffold state (mock BLE, no real package needed
yet), but it is worth flagging so WP2 does not encounter a surprising missing
dependency.

**Fix:** No action required for WP1. When starting WP2, add:
```yaml
flutter_blue_plus: 2.3.5
```

---

_Reviewed: 2026-06-06T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
