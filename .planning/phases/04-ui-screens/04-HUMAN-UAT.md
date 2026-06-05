---
status: partial
phase: 04-ui-screens
source: [04-VERIFICATION.md]
started: 2026-06-05T00:00:00Z
updated: 2026-06-05T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Visual rendering — 80sp tabular font, chip colors, layout on device
expected: Angle readout dominates the instrument screen at ~80sp. Chip shows green when connected, amber when connecting/reconnecting, red when disconnected. Layout fits without overflow on a standard Android device (e.g. Pixel 6 or emulator at 1080×2400).
result: [pending]

### 2. Stale animation smoothness — 300ms fade-to-40% transition
expected: On tapping "Sim. Disconnect" (visible in debug builds in the AppBar), the angle readout smoothly fades to ~40% opacity over 300ms. The "DISCONNECTED" label appears. Values remain visible but clearly not live.
result: [pending]

### 3. FAB visibility timing — disappears correctly during connecting window
expected: After tapping a device in the scan list, the FAB disappears (ConnectionStatus transitions to connecting) within ~300ms while the mock delay runs. The connection chip in scan screen (if visible) reflects "Connecting". FAB reappears if navigation to InstrumentScreen doesn't fire.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
