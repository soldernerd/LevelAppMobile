# Phase 6: App Icon — Context

**Gathered:** 2026-06-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Add the custom app launcher icon (torpedo level graphic, matching the desktop LevelApp) to the Flutter inclinometer app for Android and iOS. The icon source lives in the sibling LevelApp repository. This phase uses `flutter_launcher_icons` to generate all required sizes from a single source PNG.

</domain>

<decisions>
## Implementation Decisions

### Source Icon
- **D-01:** Use `Square310x310Logo_620.png` (620×620 px) from the desktop LevelApp icon set — highest-resolution version of the same design, renders crisply at all Android/iOS launcher sizes. (The 256px version is acceptable fallback but 620px is preferred.)
- **D-02:** Copy source to `assets/icon/app_icon.png` inside the Flutter project before running the generator. This keeps the generator config path-stable and repo-local.
- **D-03:** Source file location (external): `C:\Users\lfaes\OneDrive\VisualStudio\LevelApp\docs\Icons\Square310x310Logo_620.png`

### Tooling
- **D-04:** Use `flutter_launcher_icons` as a dev dependency — add to `dev_dependencies` in `pubspec.yaml` and add a `flutter_icons:` config block. Run via `dart run flutter_launcher_icons`. This generates all Android mipmap sizes and the iOS `AppIcon.appiconset` automatically.
- **D-05:** No manual placement of mipmap PNGs — the generator handles all sizes (`mipmap-mdpi` through `mipmap-xxxhdpi` and iOS 1024×1024).

### Android Adaptive Icon
- **D-06:** Enable adaptive icon with the full source PNG as foreground and `#0d0a05` (the dark brownish-black sampled from the icon background) as the `adaptive_icon_background` color. This gives correct Android 8+ behavior — the level graphic sits on a matching solid-color layer — without needing a separate foreground-only asset.
- **D-07:** `min_sdk_android: 21` (matches project `minSdkVersion 24`). No legacy fallback needed below 21.

### iOS
- **D-08:** Use the same source PNG for iOS. The icon has a fully opaque background (no alpha), which satisfies the App Store requirement. No separate iOS-specific asset needed.
- **D-09:** iOS `remove_alpha_channel: true` in generator config as a safety measure (redundant given the icon has no alpha, but avoids any rejection risk).

### Claude's Discretion
- Exact `flutter_launcher_icons` package version — use latest stable at time of implementation (check `pub.dev`).
- `image_path` config key vs platform-specific keys — single `image_path` with `adaptive_icon_foreground` override is sufficient; no need for separate `image_path_android`/`image_path_ios`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Config
- `.planning/ROADMAP.md` — Phase 6 not yet in roadmap; plan should add it
- `pubspec.yaml` — existing dev_dependencies and flutter: section structure to match

### Source Assets
- External source: `C:\Users\lfaes\OneDrive\VisualStudio\LevelApp\docs\Icons\Square310x310Logo_620.png` — 620×620 px source icon
- Target copy path: `assets/icon/app_icon.png` (create `assets/icon/` directory in Flutter project root)

### Existing Android Icon Structure
- `android/app/src/main/res/mipmap-*/` — existing mipmap folders (currently contain Flutter default icon; will be overwritten by generator)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `android/app/src/main/res/mipmap-*` folders already exist — `flutter_launcher_icons` writes directly into these; no directory creation needed
- `pubspec.yaml` already has a `dev_dependencies:` section — add `flutter_launcher_icons` there

### Established Patterns
- Dev dependencies use `^` version pinning (see `flutter_lints: ^6.0.0`, `fake_async: ^1.3.3`) — follow same pattern
- No `assets:` section exists in `pubspec.yaml` yet — add `assets/icon/` entry under `flutter:` if the generator needs the file declared (check generator docs; some versions don't require it)

### Integration Points
- This phase is purely asset/config work — no Dart code changes
- `android/app/src/main/AndroidManifest.xml` references `@mipmap/ic_launcher` — generator targets this name by default; no manifest change needed

</code_context>

<specifics>
## Specific Ideas

- Icon design: torpedo level with green bubble indicator on dark (`#0d0a05`) background with amber/orange border — same visual identity as the desktop app, appropriate for a precision instrument app
- The icon already has rounded corners baked into the artwork — on Android the launcher further clips to an adaptive shape (circle/squircle), so the level graphic will be clearly visible in the center

</specifics>

<deferred>
## Deferred Ideas

- WP2 BLE wiring — user mentioned this as the next major work package after the icon; belongs in a separate milestone
- iOS runtime testing / TestFlight distribution — out of scope for WP1; deferred to later milestone

</deferred>

---

*Phase: 6-App Icon*
*Context gathered: 2026-06-06*
