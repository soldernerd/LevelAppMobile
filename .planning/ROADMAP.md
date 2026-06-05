# Roadmap — Inclinometer BLE App WP1

## Overview

5 phases | 36 requirements | Horizontal-layer build order

Each phase is a complete, testable technical layer. Phases 1–3 have no UI; correctness is verified through unit tests and stream inspection. Phases 4–5 produce a running app.

---

## Phases

- [x] **Phase 1: Data Models + Protocol Parser** — Define the wire format, typed packet model, command constants, GATT UUIDs, and BleManager interface contract
- [x] **Phase 2: BLE Abstraction + Mock Layer** — Implement MockBleManager producing animated random-walk streams behind the BleManager interface
- [x] **Phase 3: Riverpod Provider Layer** — Wire providers that expose connection state machine and live instrument data; no widgets yet (completed 2026-06-05)
- [ ] **Phase 4: UI Screens** — Build scan screen and instrument screen consuming providers; all states visible and navigable
- [x] **Phase 5: App Wiring + Platform Config** — main.dart, go_router, Android/iOS permissions, build.gradle SDK versions, wakelock (completed 2026-06-05)

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

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Models + Protocol Parser | 4/4 | Complete | 2026-06-04 |
| 2. BLE Abstraction + Mock Layer | 1/1 | Complete | 2026-06-04 |
| 3. Riverpod Provider Layer | 3/3 | Complete   | 2026-06-05 |
| 4. UI Screens | 0/4 | Not started | - |
| 5. App Wiring + Platform Config | 3/3 | Complete   | 2026-06-05 |
