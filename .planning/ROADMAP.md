# Roadmap — Inclinometer BLE App WP1

## Overview

6 phases | 36 requirements | Horizontal-layer build order

Each phase is a complete, testable technical layer. Phases 1–3 have no UI; correctness is verified through unit tests and stream inspection. Phases 4–5 produce a running app. Phase 6 adds the custom launcher icon.

---

## Phases

- [x] **Phase 1: Data Models + Protocol Parser** — Define the wire format, typed packet model, command constants, GATT UUIDs, and BleManager interface contract
- [x] **Phase 2: BLE Abstraction + Mock Layer** — Implement MockBleManager producing animated random-walk streams behind the BleManager interface
- [x] **Phase 3: Riverpod Provider Layer** — Wire providers that expose connection state machine and live instrument data; no widgets yet (completed 2026-06-05)
- [ ] **Phase 4: UI Screens** — Build scan screen and instrument screen consuming providers; all states visible and navigable
- [x] **Phase 5: App Wiring + Platform Config** — main.dart, go_router, Android/iOS permissions, build.gradle SDK versions, wakelock (completed 2026-06-05)
- [x] **Phase 6: App Icon** — Add custom torpedo-level launcher icon using flutter_launcher_icons; Android adaptive icon + iOS icon generated from a single 620×620 PNG source (completed 2026-06-06)
- [ ] **Phase 7: GitHub Self-Update** — App checks GitHub Releases on startup and offers to download + install the latest APK automatically, completing the CI/CD loop

---

## Phase Details

### Phase 1: Data Models + Protocol Parser
**Goal**: The wire format and interface contract are fully defined and parseable with no UI or BLE hardware required
**Depends on**: Nothing (first phase)
**Requirements**: PROT-01, PROT-02, PROT-03, PROT-04, ARCH-01, ARCH-02
**Success Criteria** (what must be TRUE):
  1. A unit test can construct a 9-byte list `[angle_x: float32LE][angle_y: float32LE][battery: uint8]` and `StatePacket.parse()` returns the correct typed values
  2. `ZERO_X = 0x01` and `ZERO_Y = 0x02` constants are importable and hold the correct values (verifiable in a test)
  3. Service UUID, state characteristic UUID, and command characteristic UUID are defined as named constants in `ble_protocol.dart` (placeholder strings, not null)
  4. `abstract class BleManager` declares the full interface; `MockBleManager implements BleManager` compiles without stub warnings — no concrete `RealBleManager` class exists yet
  5. No widget file and no `flutter_blue_plus` import exists anywhere in `lib/ui/` or `lib/providers/` (enforced by project structure)
**Plans**: 4 plans in 4 waves

**Wave 1**
- [x] 01-01-PLAN.md — Flutter project scaffold, pubspec.yaml dependencies, boilerplate wipe

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Data models (DeviceState, ScannedDevice, ConnectionStatus) and protocol parser (StatePacket, UUID/command constants)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-03-PLAN.md — BLE interface (abstract class BleManager) and Phase 1 stub (MockBleManager)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 01-04-PLAN.md — Provider stub (bleManagerProvider), finalized main.dart, round-trip unit tests

**Cross-cutting constraints:**
- No `flutter_blue_plus` import in `lib/ble/ble_manager.dart`, `lib/providers/`, or `lib/ui/` (Plans 01-02, 01-03, 01-04)
- `ByteData.sublistView(Uint8List.fromList(bytes))` — mandatory List<int>→TypedData conversion (Plan 01-02)

### Phase 2: BLE Abstraction + Mock Layer
**Goal**: MockBleManager produces realistic animated streams behind the BleManager interface; all mock behaviors are verifiable without running the app
**Depends on**: Phase 1
**Requirements**: MOCK-01, MOCK-02, MOCK-03, MOCK-04
**Success Criteria** (what must be TRUE):
  1. A unit test that listens to `MockBleManager.stateStream` for 1 second receives multiple `StatePacket` events where angle_x and angle_y values change by small increments each tick (random walk, bounded range)
  2. A unit test that listens to `MockBleManager.stateStream` for several seconds observes battery level drift (not constant)
  3. A unit test that calls `MockBleManager.connect()` receives a `connecting` state immediately and a `connected` state after approximately 300 ms
  4. A unit test that calls `MockBleManager.simulateDisconnect()` on a connected manager immediately emits a `disconnected` event on the connection state stream
**Plans**: 1 plan in 1 wave

**Wave 1**
- [x] 02-01-PLAN.md — fake_async dev dep, test scaffold, full MockBleManager implementation, test assertions for MOCK-01 through MOCK-04

### Phase 3: Riverpod Provider Layer
**Goal**: All app state (connection state machine, live instrument data, auto-reconnect stub) is managed by providers and observable without any UI
**Depends on**: Phase 2
**Requirements**: CONN-01, CONN-02, CONN-03, CONN-05, CONN-06, SYS-01
**Success Criteria** (what must be TRUE):
  1. The connection state machine provider cycles through `idle → scanning → connecting → connected → disconnecting → disconnected` and `error` states; each transition is reachable by calling provider methods (verifiable via provider test or widget test harness)
  2. A disconnect triggered by `simulateDisconnect()` causes the instrument data provider to emit a stale-data indicator (a flag or nullable type) rather than silently continuing to emit the last live values
  3. The auto-reconnect stub provider exists with backoff logic wired; it does not initiate any reconnection attempt in WP1 (a flag or disabled constant controls this, verifiable in code inspection or test)
  4. The wakelock provider acquires the screen lock when the connection state transitions to `connected` and releases it on `disconnected` (verifiable by mocking `wakelock_plus` in a test or by running the app and observing screen behavior)
  5. When the mock manager enters a reconnecting state (amber/stub), the provider exposes a distinct `reconnecting` state value separate from `disconnected`
**Plans**: 3 plans in 3 waves

**Wave 1**
- [x] 03-01-PLAN.md — Add reconnecting enum value + wakelock_plus dependency

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 03-02-PLAN.md — ConnectionNotifier, scanResultsProvider, instrumentDataProvider

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 03-03-PLAN.md — Provider test suite (CONN-01 through CONN-06, SYS-01)

### Phase 4: UI Screens
**Goal**: A running app shows the scan screen and instrument screen with all data states and navigation paths working end-to-end against the mock layer
**Depends on**: Phase 3
**Requirements**: SCAN-01, SCAN-02, SCAN-03, SCAN-04, SCAN-05, INST-01, INST-02, INST-03, INST-04, INST-05, INST-06, INST-07, CONN-04
**Success Criteria** (what must be TRUE):
  1. On the scan screen, tapping the scan button starts a scan; the state chip changes from "idle" to "scanning"; discovered mock devices appear as a list showing name and RSSI; unnamed peripherals are not shown
  2. Tapping a device in the list navigates to the instrument screen; the connection state chip shows "connecting" briefly then "connected" (green); angle_x, angle_y, and battery percentage are all visible with live-updating values
  3. Angle values are displayed in a monospaced/tabular numeral font; repeated screen updates do not cause layout shift of surrounding widgets
  4. Tapping "Zero X" or "Zero Y" on the instrument screen fires the corresponding command through the provider (the mock acknowledges it; value resets or confirms in the UI)
  5. Triggering `simulateDisconnect()` (via a debug button or test) causes the instrument screen readout to visually grey out or show a disconnected badge — last values are not shown as live data
**Plans**: 4 plans in 3 waves

**Wave 1**
- [x] 04-01-PLAN.md — sendCommand addition to ConnectionNotifier + test/ui/ scaffold files

**Wave 2** *(blocked on Wave 1 completion — parallel pair)*
- [x] 04-02-PLAN.md — ScanScreen ConsumerWidget + Phase 4 temporary main.dart
- [x] 04-03-PLAN.md — InstrumentScreen ConsumerWidget with stale animation + debug button

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 04-04-PLAN.md — Widget test suites for scan_screen_test.dart and instrument_screen_test.dart

### Phase 5: App Wiring + Platform Config
**Goal**: The app boots correctly on Android with a complete main.dart, go_router navigation, runtime permission flow, and correct build.gradle SDK settings; iOS scaffold is structurally in place
**Depends on**: Phase 4
**Requirements**: PERM-01, PERM-02, PERM-03, PERM-04, PERM-05, BUILD-01, BUILD-02
**Success Criteria** (what must be TRUE):
  1. Cold-launching the app on Android API 24+ presents a rationale dialog before the system Bluetooth permission prompt; granting permissions proceeds to the scan screen without error
  2. If Bluetooth permissions are permanently denied, the app shows an explanation and a button that opens the system app settings page
  3. `AndroidManifest.xml` contains `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and `ACCESS_FINE_LOCATION` declarations; `build.gradle` shows `minSdkVersion 24` and `compileSdkVersion 35`
  4. iOS `Info.plist` contains a Bluetooth usage description string (inspectable in the file; no iOS runtime test required in WP1)
  5. go_router redirects the user to the scan screen if the connection state is not `connected` and they attempt to access the instrument screen directly (route guard is exercised by navigating back from the instrument screen)
**Plans**: 3 plans in 2 waves

**Wave 1** *(parallel pair — no shared files)*
- [x] 05-01-PLAN.md — Android/iOS platform config: build.gradle.kts SDK versions + AndroidManifest.xml BLE permissions + Info.plist Bluetooth usage description
- [x] 05-02-PLAN.md — Add go_router + permission_handler to pubspec; add blePermissionPermanentlyDeniedProvider to device_provider.dart

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 05-03-PLAN.md — Production main.dart (ProviderContainer + GoRouter + RouterNotifier + permission check) + ScanScreen go_router navigation + inline denied banner

### Phase 6: App Icon
**Goal**: The custom torpedo-level launcher icon is visible on Android and iOS home screens; all platform sizes generated from a single 620×620 PNG source via flutter_launcher_icons with correct Android adaptive icon config
**Depends on**: Phase 5
**Requirements**: (none — this phase has no REQ-IDs; success is verified by observable icon on device)
**Success Criteria** (what must be TRUE):
  1. `flutter_launcher_icons` is added to `dev_dependencies` in `pubspec.yaml` with a `flutter_icons:` config block pointing to `assets/icon/app_icon.png`
  2. `assets/icon/app_icon.png` exists in the Flutter project (620×620 PNG copied from LevelApp)
  3. Running `dart run flutter_launcher_icons` succeeds without errors and overwrites all `mipmap-*` PNGs under `android/app/src/main/res/`
  4. `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` exists and references an adaptive foreground/background config
  5. iOS `AppIcon.appiconset` is populated with the generated icon set (not the Flutter default blue swirl)
**Plans**: 1 plan in 1 wave

**Wave 1**
- [x] 06-01-PLAN.md — Copy source PNG to assets/icon/, add flutter_launcher_icons dev dep + flutter_icons: config to pubspec.yaml, run dart run flutter_launcher_icons

### Phase 7: GitHub Self-Update
**Goal**: The app checks GitHub Releases on startup, compares the release tag against the installed version, and offers to download + install the latest APK — completing the CI/CD loop so users always run the current build
**Depends on**: Phase 5 (App Wiring)
**Requirements**: UPD-01, UPD-02, UPD-03, UPD-04, UPD-05, UPD-06
**Success Criteria** (what must be TRUE):
  1. On startup the app calls `https://api.github.com/repos/{owner}/{repo}/releases/latest` and compares `tag_name` (semver) against the version from `PackageInfo.fromPlatform()`
  2. When a newer version is detected an update dialog appears showing the new version number; the user can dismiss (skip this session) or proceed
  3. Tapping "Update" downloads the APK from the release's `assets[].browser_download_url` with a visible progress indicator (percentage or progress bar)
  4. After a successful download the Android package installer launches and presents the standard install prompt
  5. When the device has no internet connection or the GitHub API is unreachable the update check fails silently — no crash, no error dialog
  6. `REQUEST_INSTALL_PACKAGES` is declared in `AndroidManifest.xml`; the app requests the permission at runtime on Android 8+ (API 26+) before attempting installation
**Plans**: 3 plans in 3 waves

**Wave 1**
- [x] 07-01-PLAN.md — Add dio/package_info_plus/shared_preferences/path_provider/open_file_plus deps + version alignment (0.1.0+1); AndroidManifest REQUEST_INSTALL_PACKAGES + INTERNET + FileProvider; filepaths.xml (incl. package legitimacy checkpoint)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 07-02-PLAN.md — UpdateService (GitHub API check, integer-segment version compare, dio download with progress, REQUEST_INSTALL_PACKAGES runtime check, installer launch) + unit tests

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 07-03-PLAN.md — updateCheckProvider FutureProvider + ScanScreen update dialog (Skip persists / Update downloads with progress) + widget test

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Models + Protocol Parser | 4/4 | Complete | 2026-06-04 |
| 2. BLE Abstraction + Mock Layer | 1/1 | Complete | 2026-06-04 |
| 3. Riverpod Provider Layer | 3/3 | Complete   | 2026-06-05 |
| 4. UI Screens | 0/4 | Not started | - |
| 5. App Wiring + Platform Config | 3/3 | Complete   | 2026-06-05 |
| 6. App Icon | 1/1 | Complete | 2026-06-06 |
| 7. GitHub Self-Update | 2/3 | In Progress|  |
