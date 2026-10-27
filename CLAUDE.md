# Leveltronic BLE App

Flutter/Dart companion app for the custom "Leveltronic" precision level
instrument (STM32G0B1 / RN4871). The scaffold was built mock-first (phases
1–7); real BLE is now wired against the REV B firmware.

**Package:** `com.soldernerd.inclinometer`
**Version:** 0.3.x — minor bumped for the multi-device architecture (CI: `major.minor` from `pubspec.yaml`, patch = git commit count)
**Platform:** Android primary (iOS scaffold included, not tested)

## Device reality (firmware 0.11+, API v3)

The firmware is `InclinationMeterFirmware` (repo also named "WylerLeveltronic").
**Protocol:** its `docs/api-v3-spec.md`; **every resource:** its
`docs/api-reference.md` (generated from `tools/api_spec.py`). The app speaks
API v3 only — the Leveltronic driver refuses anything else
(`IncompatibleFirmwareException`, shown on the scan screen).

- **Transport:** RN4871 **Transparent UART** — a raw byte stream carrying
  framed packets `[OPCODE 2B LE][LEN 2B LE][PAYLOAD][CRC16 2B LE]`,
  CRC-16/CCITT-FALSE. Service `49535343-FE7D-…`, write `…8841-…`, notify
  `…1E4D-…`; advertises as `Leveltronic-<last 2 MAC bytes>`. Max payload 122.
- **Layering (keep it):** shared and device-agnostic:
  `lib/ble/api_v3.dart` (framing, opcode scheme, status, System IDENTITY; pure
  Dart) → `device_link.dart` (`DeviceLink`: `request()` + `subscribe()`;
  `DeviceConnection` adds id / closed / close) → `BleManager` (scan +
  `open(id)`, any number of connections at once; `RealBleManager` over
  `flutter_blue_plus`, `MockBleManager` over `SimulatedPeripheral`s). Per
  device family, in `lib/devices/<device>/`: `protocol.dart` (resource ids +
  payload decoders) → `instrument_api.dart` (typed operations) →
  `live_feed.dart` (the always-on subscriptions) → providers → screens.
- **Multiple devices** (`lib/devices/device_driver.dart`): a `DeviceDriver`
  per family (id, advertised-name prefixes, `claims(ApiIdentity)`, `open()`,
  route tree at `/<id>`). `DeviceRegistry` (listed in `main.dart`) reads System
  IDENTITY `product` after connect and picks the driver, whose `DeviceSession`
  (`LeveltronicSession` = api + live feed) lives as long as the connection.
  `sessionsProvider` holds all open sessions; `activeSessionProvider` is the
  one the device screens show (`DeviceSwitcherButton` switches;
  `ActiveSessionRedirect` on each home screen follows it). A driver's
  providers read the session from `activeSessionProvider`. **Adding a
  device:** new `lib/devices/<x>/` with a driver + session, add it to the
  registry in `main.dart` — no change to transport, router or scan screen.
- **NeigMess2** (`lib/devices/neigmess2/`, API in its `docs/device_api.md`) is  the second driver: same framing/UUIDs, but API v2 — IDENTITY is the 19-byte  layout (`ApiIdentity.decode` handles both), no serial (labels fall back to  the BLE address tail), sensor values are *sensor units* not pF (`kUnitToPf`),  writes to the EEPROM on zero/clear/store/SET. It needs BLE writes of ≤ 20  bytes: `RealBleManager._send` chunks to the ATT MTU. The app does everything the keys and knobs do, so the instrument can be used without touching it: flip-test zero (`/neigmess2/zero`, follows Measurements 0x0A, Commands 0x05/0x06), calibration screen (`/neigmess2/calibration`: tilt trim, neutral Cn, zero/clear, store/recall). Angle offsets (stored, not applied by the device) are not exposed. Not implemented yet:  bulk transfers (raw stream) and the debug-log subscription (bulk chunks would  need their own push framing: `ApiFrame.looksLikePush` assumes `[seq][page]`).
- **Subscriptions, not polling.** `DeviceLink.subscribe` shares one device
  subscription between listeners and UNSUBSCRIBEs when the last leaves.
  Always on: Topics LIVE (event, ~4 Hz), STATUS (1 s), ENV (2 s). Per screen:
  Procedures ZERO_CAL / PRECISION (pushed on change and ~4 Hz while running),
  Topics SIGNAL_DIAG, Topics PHASOR_STREAM (phase calibration only). The only
  polls left are RTC (1 s) and HEALTH (5 s) on the "All values" screen, and a
  1 s fallback GET inside `PrecisionRun` if a push is lost.
- **Live readings** are tilt in **mm/m** (S1, S2, Diff = S1 − S2), valid while
  LIVE flags bit0 is set; bits 1/2 mark a sensor "doubtful" (vibration).
- **Service mode** gates every calibration write and the maintenance commands
  (ZERO_CAL, FACTORY_DEFAULTS, REBOOT_DFU, …) with status `0x0B`. It can only be
  switched on **at the instrument** (SETTINGS → Service mode, right knob twice);
  the app shows it (STATUS `service_mode`), can end it (SERVICE_END), and sends
  a cheap request every 30 s while a wizard is open
  (`serviceKeepAliveProvider`) because it ends after 10 minutes without one.
- **Zero Diff** is app-side (`tareProvider`, per serial in SharedPreferences):
  the firmware has no such function and moving S1_ZERO/S2_ZERO would change S1
  and S2 too.
- **Calibration wizards** (`lib/providers/*_cal_provider.dart`, math in
  `lib/calibration/calibration_math.dart`, all tested end to end against the
  simulator's known truth):
  - *Flip (zero)*: Commands ZERO_CAL step 1 → user turns 180° → step 2 →
    firmware stores the zero; the app shows zero before/after.
  - *Phase*: capture the phasor stream flat and with a tilt step; with
    `u = S/(A−B)` the direction of Δu is the sensor's signal phase (folded to
    ±90°, must be within ±45°). Independent of the stored phase and of the
    step size.
  - *Gain (k)*: two precision measurements (baseline, known shim);
    `kNew = kOld·|Δreading| / tilt`, tilt = shim ÷ edge × 1000 mm/m; then
    re-measures to prove it. Recommended order: phase → gain → zero.
- **Settings** page is data-driven from `lib/ble/api_catalog.dart`. Settings
  0x53 (max minutes at 100 %) is *optional*: it is reserved for the
  drift-probe branch and is hidden unless a GET answers.
- **Fake-async gotcha (tests):** never `await` a `StreamSubscription.cancel()`
  in code that tests drive with `fakeAsync` — its future is created in the
  root zone and never completes there. Use `unawaited(sub.cancel())`.
- **Poll/restart races** (earlier bug, now structural): wizard notifiers guard
  late async results with a `_gen` counter checked after every `await`;
  `RealBleManager.request` fails a superseded request for the same opcode and
  only removes its own completer. Keep both.

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
- Protocol framing lives in `lib/ble/api_v3.dart`, a device's payload decoders in
  `lib/devices/<device>/protocol.dart` (pure Dart, no BLE
  import, unit-tested in `test/ble/api_v3_test.dart`). `RealBleManager` owns
  packet reassembly; `LiveFeed` merges the topic subscriptions into
  `DeviceState?` for the providers.
- `instrumentDataProvider` emits `DeviceState?` — `null` is the stale-data
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
- Scan filters advertisements by the drivers' name prefixes (`Leveltronic`,
  `NeigMess2`); the modules do not advertise the 128-bit Transparent-UART
  service UUID. The driver is chosen after connect from IDENTITY `product`.
