# Leveltronic BLE App

Flutter/Dart companion app for the custom "Leveltronic" precision level
instrument (STM32G0B1 / RN4871). The scaffold was built mock-first (phases
1–7); real BLE is now wired against the REV B firmware.

**Package:** `com.soldernerd.inclinometer`
**Platform:** Android primary (iOS scaffold included, not tested)

## Device reality (REV B firmware, `master`)

The firmware is `InclinationMeterFirmware` (repo also named "WylerLeveltronic").
See its `docs/api-reference.md` for the authoritative contract.

- **Transport:** RN4871 **Transparent UART** — a raw byte stream, *not* plain
  GATT state/command characteristics. It carries framed **API v2** packets:
  `[OPCODE 2B LE][LEN 2B LE][PAYLOAD][CRC16 2B LE]`, CRC-16/CCITT-FALSE over
  `OPCODE+LEN+PAYLOAD`. See `lib/ble/api_v2.dart`.
- **GATT:** service `49535343-FE7D-4AE5-8FA9-9FAFD205E455`; write requests to
  `…8841-…`; enable notifications on `…1E4D-…`. Advertises as
  `Leveltronic-<last 2 MAC bytes>`.
- **Data the app uses:** topic groups `Environmental` (0x5/0x00) and
  `Device status` (0x5/0x01), subscribed at connect. Yields battery mV / SoC /
  state, on-board + external + BME280 temperature, humidity, pressure,
  USB/charge flags.
- **No tilt.** REV B has no angle output (analog-AFE tilt math is unfinished;
  the REV A SCL3300 path was removed). `DeviceState.angleX/angleY` stay null
  and the instrument screen shows a permanent "not available" placeholder.
  Wiring a future firmware tilt Measurement resource is a small change in
  `RealBleManager._dispatch` + `_merge`.
- **No zero command** in this firmware build.

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

- `abstract class BleManager` (`lib/ble/ble_manager.dart`) — all BLE access
  goes through this interface. `flutter_blue_plus` is imported **only** in
  `lib/ble/real_ble_manager.dart`; never in `lib/ui/` or `lib/providers/`.
- The concrete manager is chosen once, in `main.dart`, via
  `ProviderScope`/`ProviderContainer` override — `RealBleManager()` for
  hardware, `MockBleManager()` to run/test without a device.
- Protocol framing + decoders live in `lib/ble/api_v2.dart` (pure Dart, no BLE
  import, unit-tested in `test/ble/api_v2_test.dart`). `RealBleManager` owns
  packet reassembly and the topic-group merge; providers just forward
  `DeviceState?`.
- `BleManager.deviceStream` emits `DeviceState?` — `null` is the stale-data
  sentinel on disconnect/error. Never render last-known values as live.
- Riverpod 3.x — use `Notifier`/`AsyncNotifier`, not `StateNotifierProvider`
  (legacy).
- BLE connection provider needs `keepAlive: true` — it must not tear down on
  navigation.
- `flutter_blue_plus` `device.connect()` requires `license:` — `License.nonprofit`
  is used (hobby project); a commercial FBP license is needed for for-profit use.

## Stack

| Package | Version | Note |
|---------|---------|------|
| flutter_blue_plus | 2.3.5 | Commercial license required for 15+ employees |
| flutter_riverpod | 3.3.1 | Notifier/AsyncNotifier only; keepAlive for BLE providers |
| permission_handler | 12.0.3 | Requires compileSdkVersion 35 |
| go_router | 17.3.0 | refreshListenable bridge needed for Riverpod providers |
| wakelock_plus | latest | Acquire on connected, release on disconnected |

**Build:** `minSdkVersion 24` / `compileSdkVersion 35`

## Constraints

- Mock `connect()` simulates a ~300 ms delay (exercises the `connecting` state)
  and `MockBleManager.simulateDisconnect()` drives the stale-data + router
  redirect path.
- Full Android 12+ runtime permission flow (`BLUETOOTH_SCAN` /
  `BLUETOOTH_CONNECT`, rationale dialog before the system prompt).
- Stale-data indicator required — never show last-known values as live after
  disconnect.
- Scan filters advertisements by the `Leveltronic` name prefix (the module
  does not advertise the 128-bit Transparent-UART service UUID).
