# Inclinometer BLE App — WP1 Scaffold

## What This Is

A Flutter mobile companion app for a custom-built precision inclinometer instrument intended for machine shop use (levelling machines, checking flatness, setting up workpieces). The app connects to the instrument over BLE and acts as a wireless remote UI — replacing the physical rotary encoders with touch controls and mirroring instrument state on the phone screen. WP1 builds the complete app scaffold with animated mock data so WP2 is purely BLE wiring with no structural changes.

## Core Value

A connected phone screen that shows live angle readings and lets the user zero each axis — everything else is secondary.

## Requirements

### Validated

- [x] GitHub self-update — validated in Phase 7 (automated checks passed; device UAT pending)

### Active

- [ ] Scan screen with live BLE device list (name + RSSI), filtered to named devices, scan state (idle/scanning/error), tap to connect
- [ ] Instrument screen showing angle_x and angle_y (float, degrees, large readable text) and battery level (0–100%)
- [ ] Zero X and Zero Y buttons on instrument screen
- [ ] Mock BLE layer producing animated random-walk values for angle_x, angle_y, and battery
- [ ] Connection state machine: connecting → connected → disconnected with disconnect button
- [ ] Auto-reconnect stub wired in (structure in place, not active in WP1)
- [ ] BLE protocol stub with state packet definition (9 bytes: float32 + float32 + uint8) and command constants (ZERO_X=0x01, ZERO_Y=0x02)
- [ ] GATT UUIDs defined as named constants (placeholder values)
- [ ] Android runtime permissions (BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION) via permission_handler
- [ ] iOS Info.plist bluetooth usage description (cross-platform scaffold, not tested in WP1)
- [ ] System default theme (light/dark follows platform)

### Out of Scope

- Real BLE characteristic reads/writes — WP2 only
- iOS runtime testing — scaffold in place but WP1 is Android-only
- Custom visual theme / instrument skin — deferred
- Settings screen, calibration UI, history logging — not in WP1

## Context

- **Instrument hardware**: Murata SCL3300-D01 MEMS tilt sensor, STM32G0B1 MCU, 400×240 monochrome memory LCD, RN4871 BLE 5.0 module. Hardware not yet complete — hence mock-first approach.
- **BLE protocol**: State packet is `[angle_x: float32LE][angle_y: float32LE][battery: uint8]` = 9 bytes. Commands are single-byte writes. GATT UUIDs are placeholder until hardware is finalized.
- **Package name**: `com.soldernerd.inclinometer`
- **Mock data**: Random walk — small random increments per tick on angle_x and angle_y, battery level slowly draining.
- **Environment**: Machine shop — readability matters. Large angle readout text is a priority.

## Constraints

- **Tech stack**: Flutter/Dart, flutter_blue_plus, riverpod, permission_handler, go_router — fixed, no alternatives
- **Folder structure**: Defined in spec (`lib/ble/`, `lib/models/`, `lib/ui/`, `lib/providers/`) — maintain this layout
- **WP1 boundary**: No real BLE calls. Mock layer must be swappable for real layer in WP2 with minimal changes — design the abstraction accordingly
- **Platform**: Android primary. iOS scaffold required but not tested in WP1.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Mock-first scaffold (WP1/WP2 split) | BLE hardware not yet complete; avoids blocking UI work | — Pending |
| Random walk mock data | More realistic than static; avoids sine wave periodicity | — Pending |
| riverpod for state management | Handles async BLE stream + connection state cleanly | — Pending |
| go_router for navigation | Declarative routing; connection state can drive route guards | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-07 — Phase 7 complete (GitHub self-update, all 7 phases shipped)*
