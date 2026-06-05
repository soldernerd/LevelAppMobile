---
phase: "04"
plan: "03"
subsystem: ui
tags: [instrument-screen, ble, flutter, riverpod, animation]
dependency_graph:
  requires: [04-01]
  provides: [InstrumentScreen]
  affects: [lib/ui/instrument_screen.dart]
tech_stack:
  added: []
  patterns:
    - ConsumerWidget with ref.watch at top of build()
    - AnimatedOpacity for stale-data fade (300ms/easeOut)
    - hasValue stale detection pattern (Pitfall 1 avoided)
    - kDebugMode guard for debug-only controls
    - Safe is-cast for MockBleManager.simulateDisconnect()
    - Exhaustive switch expressions for ConnectionStatus chip mapping
key_files:
  created:
    - lib/ui/instrument_screen.dart
  modified: []
decisions:
  - "Used `dataAsync.hasValue && dataAsync.value == null` for stale detection per Pitfall 1 from RESEARCH.md"
  - "Unicode minus (U+2212) used in _formatAngle for typographic correctness"
  - "Zero button onPressed set to null (not a no-op lambda) for correct Material disabled state"
  - "Battery indicator hidden when deviceState is null — avoids showing stale percentage"
metrics:
  duration: "15 minutes"
  completed: "2026-06-05"
  tasks_completed: 1
  tasks_total: 1
  files_changed: 1
---

# Phase 4 Plan 03: InstrumentScreen — Full Implementation Summary

Implements `InstrumentScreen` — the core measurement display shown after BLE connection — replacing the Wave 1 stub with full angle readouts, battery indicator, connection chip, Zero buttons, stale-data animation, and debug controls.

## What Was Built

`lib/ui/instrument_screen.dart` — ConsumerWidget + private `_AngleRow` helper delivering INST-02 through INST-07 and CONN-04.

Key components:

- **Angle readout block:** Two `_AngleRow` widgets with 80sp/w700 text, `FontFeature.tabularFigures()`, and `±NNN.NN°` format. Wrapped in `AnimatedOpacity` (0.40 stale / 1.0 live, 300ms easeOut).
- **Stale detection:** `dataAsync.hasValue && dataAsync.value == null` correctly distinguishes `AsyncData(null)` (disconnected sentinel) from `AsyncLoading` (initial state before connection). Using `valueOrNull == null` alone would conflate the two.
- **DISCONNECTED label:** `Text('DISCONNECTED')` in red (0xFFD32F2F, letterSpacing 1.5) appears below faded readout when stale.
- **AppBar actions:** Battery icon + percentage (hidden when null), connection chip (always visible, 8-state color map), and debug "Sim. Disconnect" button (kDebugMode only).
- **Zero buttons:** Inline with each angle row; `onPressed` is `null` (not a no-op) when `status != ConnectionStatus.connected` — gives correct Material disabled appearance. Commands route through `connectionNotifierProvider.notifier.sendCommand(kCmdZeroX/Y)`.
- **Debug button:** `if (kDebugMode)` guard; safe `is MockBleManager` cast before calling `simulateDisconnect()`. No `flutter_blue_plus` import in `lib/ui/`.
- **Disconnect button:** `OutlinedButton` with red border/text, visible when connected/connecting/reconnecting.

## Deviations from Plan

None — plan executed exactly as written.

## Verification

- `flutter analyze lib/ui/instrument_screen.dart` — no issues
- `flutter test` — 31 tests passed (0 failures, 0 regressions)

## Self-Check: PASSED

- `lib/ui/instrument_screen.dart` exists: FOUND
- Commit `1498458` exists: FOUND
- Contains `FontFeature.tabularFigures()`: FOUND
- Contains `fontSize: 80`: FOUND
- Contains `isStale ? 0.40 : 1.0`: FOUND
- Contains `Duration(milliseconds: 300)` and `Curves.easeOut`: FOUND
- Contains `kCmdZeroX` and `kCmdZeroY`: FOUND
- Contains `if (kDebugMode)`: FOUND
- Contains `if (mgr is MockBleManager) mgr.simulateDisconnect()`: FOUND
- Contains `dataAsync.hasValue && dataAsync.value == null`: FOUND
- No `flutter_blue_plus` import: CONFIRMED

## Known Stubs

None — all data sources wired. Battery and angle values come from `instrumentDataProvider` (live mock stream). No placeholder text or hardcoded empty values in the rendered UI.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. `bleManagerProvider` access in debug button is type-gated (`is MockBleManager`) and compile-gated (`kDebugMode`) per T-04-04 / T-04-06 mitigations in the plan threat register.
