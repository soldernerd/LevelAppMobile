# Phase 6: App Icon — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-06
**Phase:** 6-app-icon
**Areas discussed:** Icon tooling approach, Android adaptive icon

---

## Icon Tooling Approach

| Option | Description | Selected |
|--------|-------------|----------|
| `flutter_launcher_icons` package | Dev dep + pubspec config, generates all sizes automatically — standard Flutter practice | ✓ |
| Manual placement | Copy PNG into mipmap-* folders by hand | |

**User's choice:** No preference — Claude decided
**Notes:** `flutter_launcher_icons` chosen as it is the standard Flutter approach, requires no manual resizing, and handles both Android adaptive and iOS formats from a single source image.

---

## Android Adaptive Icon

| Option | Description | Selected |
|--------|-------------|----------|
| Flat (PNG as-is) | Use source PNG directly, no adaptive layers | |
| Adaptive with full-bleed foreground | Full PNG as foreground layer + matching dark background color (`#0d0a05`) | ✓ |

**User's choice:** No preference — Claude decided
**Notes:** Adaptive approach chosen because Android 8+ devices expect adaptive icons. No separate foreground-only asset exists or was requested, so the full PNG is used as the foreground with a background color sampled from the icon's own background. This gives correct adaptive masking behavior while reusing the single available source asset.

---

## Claude's Discretion

- `flutter_launcher_icons` package version — use latest stable at implementation time
- `image_path` config structure — single `image_path` key with adaptive overrides is sufficient
- Background color exact value (`#0d0a05`) — sampled from icon preview; planner/executor may fine-tune if needed

## Deferred Ideas

- WP2 real BLE wiring — next major milestone after WP1 icon addition
- iOS App Store submission setup — deferred beyond WP1 scope
