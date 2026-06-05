# Requirements — Inclinometer BLE App WP1

**Scope:** WP1 scaffold only. No real BLE characteristic reads/writes.
**Last updated:** 2026-06-04 after initialization + research

---

## v1 Requirements

### Scan Screen

- [ ] **SCAN-01**: User can initiate and stop a BLE scan via a scan button
- [ ] **SCAN-02**: Scan screen displays a live list of discovered devices showing device name and RSSI
- [ ] **SCAN-03**: Device list is filtered to named devices only (unnamed/unnamed BLE peripherals hidden)
- [ ] **SCAN-04**: Scan screen displays current scan state (idle / scanning / error) at all times
- [ ] **SCAN-05**: User can tap a device in the list to initiate a connection

### Instrument Screen

- [ ] **INST-01**: Instrument screen is shown after a successful connection and is the root while connected
- [ ] **INST-02**: Instrument screen displays angle_x in degrees as a large, readable float value
- [ ] **INST-03**: Instrument screen displays angle_y in degrees as a large, readable float value
- [ ] **INST-04**: Instrument screen displays battery level as a percentage (0–100%)
- [ ] **INST-05**: User can trigger Zero X via a dedicated button (sends ZERO_X command)
- [ ] **INST-06**: User can trigger Zero Y via a dedicated button (sends ZERO_Y command)
- [ ] **INST-07**: Angle values are rendered with monospaced/tabular numerals to prevent layout jitter at high update rates

### Connection Management

- [x] **CONN-01**: App implements a connection state machine with states: idle, scanning, connecting, connected, disconnecting, disconnected, error
- [x] **CONN-02**: User can disconnect from the instrument via a disconnect button on the instrument screen
- [x] **CONN-03**: Auto-reconnect stub is structurally in place (backoff logic wired, not activated in WP1)
- [ ] **CONN-04**: A connection state chip (e.g. green/amber/red) is always visible on the instrument screen
- [x] **CONN-05**: When BLE disconnects unexpectedly, the instrument screen visually indicates stale data (e.g. greyed-out readout or disconnected badge) — last-known values are never shown as live after disconnect
- [x] **CONN-06**: While auto-reconnect stub is active, a "Reconnecting…" state is shown (amber) rather than silence

### Permissions (Android)

- [ ] **PERM-01**: `AndroidManifest.xml` declares `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and `ACCESS_FINE_LOCATION` permissions
- [x] **PERM-02**: App requests runtime BLE permissions via `permission_handler` before initiating any scan
- [x] **PERM-03**: Permission request includes a rationale dialog shown before the system permission prompt
- [x] **PERM-04**: App handles the permanently-denied case by directing the user to `openAppSettings()` with an explanation
- [ ] **PERM-05**: iOS `Info.plist` includes a Bluetooth usage description string (cross-platform scaffold; not tested in WP1)

### Mock BLE Layer

- [ ] **MOCK-01**: `MockBleManager` produces animated angle_x and angle_y values via random walk (small increments per tick, bounded range)
- [ ] **MOCK-02**: `MockBleManager` produces a slowly drifting battery level (0–100%, random walk)
- [ ] **MOCK-03**: `MockBleManager.connect()` simulates a ~300 ms delay before resolving to `connected`, exercising the `connecting` UI state
- [ ] **MOCK-04**: `MockBleManager` exposes a `simulateDisconnect()` debug method that fires an involuntary disconnect event, exercising the stale-data indicator and router redirect guard

### BLE Protocol

- [ ] **PROT-01**: `ble_protocol.dart` defines the 9-byte state packet structure: `[angle_x: float32LE][angle_y: float32LE][battery: uint8]`
- [ ] **PROT-02**: `ble_protocol.dart` defines command byte constants: `ZERO_X = 0x01`, `ZERO_Y = 0x02`
- [ ] **PROT-03**: `ble_protocol.dart` defines GATT UUIDs (service UUID, state characteristic UUID, command characteristic UUID) as named constants with placeholder values
- [ ] **PROT-04**: `StatePacket.parse(List<int> bytes)` parses a raw byte list into a typed `StatePacket` using `ByteData.getFloat32` with `Endian.little`

### Architecture

- [ ] **ARCH-01**: BLE layer is defined as `abstract class BleManager`; `MockBleManager` implements it for WP1. The swap to `RealBleManager` in WP2 is a single `ProviderScope.overrides` change in `main.dart` — no UI, provider, or model files change.
- [ ] **ARCH-02**: UI widgets never import `flutter_blue_plus` directly; all BLE access is through providers that consume the `BleManager` interface

### Platform / Build

- [ ] **BUILD-01**: `minSdkVersion` set to 24 in `build.gradle` (Flutter 3.44+ engine minimum; flutter_blue_plus documented minimum of 21 is superseded)
- [ ] **BUILD-02**: `compileSdkVersion` set to 35 (required by `permission_handler` 12.x)

### System Behavior

- [x] **SYS-01**: Screen-on lock acquired via `wakelock_plus` when connected; released on disconnect — screen never sleeps mid-measurement

---

## v2 Requirements (Deferred)

Features to be addressed in WP2 (real BLE wiring) or a future milestone:

- Real BLE characteristic reads, notifications, and writes (WP2)
- Auto-reconnect activation (WP2 — stub wired in WP1)
- Stale GATT service re-discovery after reconnect (WP2 — `discoverServices()` on every reconnect)
- iOS runtime testing and permission handling (WP2+)
- Remembered device / skip-scan reconnect on relaunch
- Hold / Freeze reading
- Units toggle (degrees / mm·m⁻¹ / %)
- Session log and CSV export
- 2D bubble level display
- Custom visual theme / instrument skin

---

## Out of Scope

- Cloud sync, accounts, remote logging — local precision tool only
- User-facing calibration UI — zero function covers the legitimate need
- Real-time graphing / history charts — not required for machine shop use case
- Android < API 24 — dropped by Flutter 3.44 engine
- iOS testing in WP1 — scaffold only

---

## Traceability

*Updated by roadmap agent — 2026-06-04*

| REQ-ID | Phase | Status |
|--------|-------|--------|
| PROT-01 | Phase 1 — Data Models + Protocol Parser | Pending |
| PROT-02 | Phase 1 — Data Models + Protocol Parser | Pending |
| PROT-03 | Phase 1 — Data Models + Protocol Parser | Pending |
| PROT-04 | Phase 1 — Data Models + Protocol Parser | Pending |
| ARCH-01 | Phase 1 — Data Models + Protocol Parser | Pending |
| ARCH-02 | Phase 1 — Data Models + Protocol Parser | Pending |
| MOCK-01 | Phase 2 — BLE Abstraction + Mock Layer | Pending |
| MOCK-02 | Phase 2 — BLE Abstraction + Mock Layer | Pending |
| MOCK-03 | Phase 2 — BLE Abstraction + Mock Layer | Pending |
| MOCK-04 | Phase 2 — BLE Abstraction + Mock Layer | Pending |
| CONN-01 | Phase 3 — Riverpod Provider Layer | Complete |
| CONN-02 | Phase 3 — Riverpod Provider Layer | Complete |
| CONN-03 | Phase 3 — Riverpod Provider Layer | Complete |
| CONN-05 | Phase 3 — Riverpod Provider Layer | Complete |
| CONN-06 | Phase 3 — Riverpod Provider Layer | Complete |
| SYS-01 | Phase 3 — Riverpod Provider Layer | Complete |
| SCAN-01 | Phase 4 — UI Screens | Pending |
| SCAN-02 | Phase 4 — UI Screens | Pending |
| SCAN-03 | Phase 4 — UI Screens | Pending |
| SCAN-04 | Phase 4 — UI Screens | Pending |
| SCAN-05 | Phase 4 — UI Screens | Pending |
| INST-01 | Phase 4 — UI Screens | Pending |
| INST-02 | Phase 4 — UI Screens | Pending |
| INST-03 | Phase 4 — UI Screens | Pending |
| INST-04 | Phase 4 — UI Screens | Pending |
| INST-05 | Phase 4 — UI Screens | Pending |
| INST-06 | Phase 4 — UI Screens | Pending |
| INST-07 | Phase 4 — UI Screens | Pending |
| CONN-04 | Phase 4 — UI Screens | Pending |
| PERM-01 | Phase 5 — App Wiring + Platform Config | Pending |
| PERM-02 | Phase 5 — App Wiring + Platform Config | Complete |
| PERM-03 | Phase 5 — App Wiring + Platform Config | Complete |
| PERM-04 | Phase 5 — App Wiring + Platform Config | Complete |
| PERM-05 | Phase 5 — App Wiring + Platform Config | Pending |
| BUILD-01 | Phase 5 — App Wiring + Platform Config | Pending |
| BUILD-02 | Phase 5 — App Wiring + Platform Config | Pending |
