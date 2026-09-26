# Leveltronic BLE App

Flutter/Dart companion app for the custom "Leveltronic" precision level
instrument (STM32G0B1 / RN4871). The scaffold was built mock-first (phases
1–7); real BLE is now wired against the REV B firmware.

**Package:** `com.soldernerd.inclinometer`
**Platform:** Android primary (iOS scaffold included, not tested)

## Device reality (REV B firmware, fw 0.10.x, `master`)

The firmware is `InclinationMeterFirmware` (repo also named "WylerLeveltronic").
See its `docs/api-reference.md` for the authoritative contract.

- **Transport:** RN4871 **Transparent UART** — a raw byte stream, *not* plain
  GATT state/command characteristics. It carries framed **API v2** packets:
  `[OPCODE 2B LE][LEN 2B LE][PAYLOAD][CRC16 2B LE]`, CRC-16/CCITT-FALSE over
  `OPCODE+LEN+PAYLOAD`. See `lib/ble/api_v2.dart`.
- **GATT:** service `49535343-FE7D-4AE5-8FA9-9FAFD205E455`; write requests to
  `…8841-…`; enable notifications on `…1E4D-…`. Advertises as
  `Leveltronic-<last 2 MAC bytes>`.
- **Live readings = displacement, not a single tilt angle.** The instrument
  measures two capacitive sensors (S1/S2), mm, via a WP10 analog front-end +
  demod. `RealBleManager` subscribes `Environmental` (0x5/0x00), `Device
  status` (0x5/0x01), `Raw displacement` (0x5/0x03) and the `dispOk`
  measurement (0x4/0x0D) at connect, and merges them into `DeviceState`.
  `displacementS1Mm`/`displacementS2Mm` are only meaningful while
  `displacementOk` is true (the demod is running) — `RealBleManager` confirms/
  starts it on connect (`_ensureDemodRunning`, `Commands 0x1/0x01`).
- **Zero calibration** (`Commands 0x1/0x06`) is the classic 180° reversal
  test: EXECUTE payload `1` (step 1, measure), rotate, EXECUTE payload `2`
  (step 2, measure + persist new offset to the instrument's own EEPROM).
  Not subscribable — poll `GET Raw data 0x7/0x03` for phase/progress. Driven
  by `ZeroCalibrationNotifier` (`lib/providers/measurement_provider.dart`) /
  `ZeroCalibrationScreen`.
- **Triggered precision measurement** (`Commands 0x1/0x07`) averages up to 64
  quality-good batches per sensor (~3.2 s typical, 4 s ceiling) and reports
  one repeatable value — not written to EEPROM. Poll `GET Raw data 0x7/0x04`.
  Driven by `PrecisionMeasurementNotifier` / `PrecisionMeasurementScreen`.
- Both triggered flows use `RealBleManager._request()` — a per-opcode
  `Completer` map correlating a GET/EXECUTE to its response, distinct from
  the fire-and-forget subscription-push path (`_pushHandlers`). Polling lives
  in the Riverpod notifiers (`Timer.periodic`, ~200 ms), not in the manager.

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

## Distribution / build flavors

Two Android product flavors (dimension `distribution`, same `applicationId`):

| Flavor | Channel | Self-update | Manifest extras |
|--------|---------|-------------|-----------------|
| `github` | GitHub Releases sideload (default) | active | `INTERNET`, `REQUEST_INSTALL_PACKAGES`, `FileProvider` (from `android/app/src/github/`) |
| `play` | Google Play | compiled out | none |

- `flutter run` / `flutter build` **require `--flavor github` or `--flavor play`**
  once flavors exist. `flutter test` / `flutter analyze` do not.
- `kSelfUpdateEnabled` (`lib/config/build_flavor.dart`) is `appFlavor != 'play'`
  — a compile-time const, so the updater tree-shakes out of the Play binary.
  Host/unit-test builds have no flavor ⇒ treated as `github`.
- CI (`ci.yml`, push to `main`): builds the `github` APK (renamed to
  `app-release.apk` for the self-updater), publishes the GitHub release, and
  builds the `play` AAB as a workflow artifact (`play-release-aab`). Wire a
  `PLAY_SERVICE_ACCOUNT_JSON` secret + `r0adkll/upload-google-play` to publish
  to Play directly.

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
