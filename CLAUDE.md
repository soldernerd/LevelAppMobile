# Inclinometer BLE App — WP1 Scaffold

Flutter/Dart companion app for a custom BLE precision inclinometer instrument. WP1 builds the full app scaffold with mock data; WP2 wires real BLE characteristics.

**Package:** `com.soldernerd.inclinometer`
**Platform:** Android primary (iOS scaffold included, not tested in WP1)

## Planning

- Project context: [`.planning/PROJECT.md`](.planning/PROJECT.md)
- Requirements: [`.planning/REQUIREMENTS.md`](.planning/REQUIREMENTS.md)
- Roadmap: [`.planning/ROADMAP.md`](.planning/ROADMAP.md)
- State: [`.planning/STATE.md`](.planning/STATE.md)
- Research: [`.planning/research/SUMMARY.md`](.planning/research/SUMMARY.md)

## GSD Workflow

This project uses the GSD planning system. Key commands:

```
/gsd:discuss-phase <N>   — gather context before planning a phase
/gsd:plan-phase <N>      — create execution plan for a phase
/gsd:execute-phase <N>   — execute all plans in a phase
/gsd:verify-work <N>     — verify phase deliverables against success criteria
/gsd:progress            — show current project state
```

Config: YOLO mode, standard granularity, parallel execution, research + plan-check + verifier enabled.

## Architecture Constraints

- `abstract class BleManager` — all BLE access goes through this interface. No `flutter_blue_plus` import in `lib/ui/` or `lib/providers/`.
- WP1 injects `MockBleManager` via `ProviderScope.overrides` in `main.dart`. WP2 swap = one line change.
- Byte parsing lives in `ble_protocol.dart` (`StatePacket.parse`, `ByteData.getFloat32`, `Endian.little`).
- Riverpod 3.x — use `Notifier`/`AsyncNotifier`, not `StateNotifierProvider` (legacy).
- BLE connection provider needs `keepAlive: true` — it must not tear down on navigation.

## Stack

| Package | Version | Note |
|---------|---------|------|
| flutter_blue_plus | 2.3.5 | Commercial license required for 15+ employees |
| flutter_riverpod | 3.3.1 | Notifier/AsyncNotifier only; keepAlive for BLE providers |
| permission_handler | 12.0.3 | Requires compileSdkVersion 35 |
| go_router | 17.3.0 | refreshListenable bridge needed for Riverpod providers |
| wakelock_plus | latest | Acquire on connected, release on disconnected |

**Build:** `minSdkVersion 24` / `compileSdkVersion 35`

## Key WP1 Constraints

- Mock `connect()` must simulate ~300ms delay (to exercise `connecting` state)
- Mock must expose `simulateDisconnect()` debug method (to exercise stale-data + router redirect)
- Full Android 12+ permission flow in WP1 — mock hides permission failures entirely
- Stale data indicator required — never show last-known values as live after disconnect
