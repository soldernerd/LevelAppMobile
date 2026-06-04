# Phase 2: BLE Abstraction + Mock Layer - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 replaces every `UnimplementedError` stub in `MockBleManager` with real streaming behaviour driven by `StreamController.broadcast()` and a `Timer`. No UI, no Riverpod providers, no flutter_blue_plus — only `lib/ble/mock_ble_manager.dart` changes. Phase 2 delivers MOCK-01 through MOCK-04: animated random-walk streams that Phases 3 and 4 can build against without real hardware.

Out of scope for Phase 2: any Riverpod provider wiring, connection state machine in providers (Phase 3), UI screens (Phase 4), real BLE reads/writes (WP2).

</domain>

<decisions>
## Implementation Decisions

### Mock Data Parameters (Claude's discretion — user deferred to defaults)
- **D-01:** Tick interval: 100ms (`Timer.periodic(Duration(milliseconds: 100), ...)`). 10 Hz is fast enough for smooth UI updates and consistent with the ARCHITECTURE.md sketch.
- **D-02:** Angle step per tick: `(Random().nextDouble() - 0.5) * 0.2` — ±0.1° per tick. Matches the ARCHITECTURE.md sketch. Produces a convincing random-walk feel at 10 Hz.
- **D-03:** Angle bounds: ±45°. Clamp `_angleX` and `_angleY` to the range [-45.0, 45.0] so the mock doesn't drift to absurd values during extended Phase 4 development sessions.
- **D-04:** Battery: starts at 85%, drains 1% every 10 seconds (1 tick = 100ms → decrement every 100 ticks). Minimum 0%. This exercises MOCK-02 (slowly drifting battery) without draining in seconds.
- **D-05:** Connect delay: **300ms** (`Future.delayed(const Duration(milliseconds: 300))`). CLAUDE.md is the authoritative constraint ("~300ms delay"). The ARCHITECTURE.md sketch value of 600ms is a draft — CLAUDE.md overrides it.

### Scan Mock Behaviour
- **D-06:** `startScan()` emits exactly **one** `ScannedDevice` after a ~500ms delay. A single device matches the real use case (one inclinometer). The delay exercises the "scanning…" state so Phase 4 can show a loading indicator before the device appears.
- **D-07:** Mock device: `ScannedDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'Inclinometer', rssi: -65)`. Fixed ID and RSSI — easy to update when real hardware provides the actual values.
- **D-08:** `stopScan()` cancels the pending scan timer (if scan hasn't fired yet) and adds no more `ScannedDevice` events. The `scanResults` stream stays open (it's broadcast — consumers may reconnect).

### sendCommand Behaviour
- **D-09:** `sendCommand(kCmdZeroX)` (0x01) resets `_angleX = 0.0`. `sendCommand(kCmdZeroY)` (0x02) resets `_angleY = 0.0`. This makes the Zero buttons immediately observable in Phase 4 — the angle readout snaps to 0.0° after tap.
- **D-10:** Unknown command bytes are silently no-op (no throw, no log). WP1 only has two commands; defensive handling avoids breaking debug builds if new commands are tested.

### Disconnect Behaviour
- **D-11:** `simulateDisconnect()` cancels the ticker immediately and adds `ConnectionStatus.disconnected` to `_statusController`. `statePackets` goes silent instantly — the ticker stops before the next scheduled tick fires.
- **D-12:** After `simulateDisconnect()`, the `MockBleManager` is in a logically "disconnected" state. Calling `connect()` again must work — the ticker restarts from the current angle values (no reset).
- **D-13:** `disconnect()` (user-initiated) follows the same path as `simulateDisconnect()` but also emits `ConnectionStatus.disconnecting` before `ConnectionStatus.disconnected`, matching the connection state machine contract.

### Resource Management
- **D-14:** `dispose()` cancels the ticker, cancels any pending scan timer, and closes all three `StreamController`s (`_scanController`, `_statusController`, `_packetController`). Called by Riverpod when the provider is torn down.

### Claude's Discretion
- `_tickCount` counter for battery drain (increment each tick, decrement battery every 100 ticks) — implementation detail, Claude decides the exact approach.
- Whether `_angleX` and `_angleY` reset to 0.0 when `connect()` is called again after disconnect — Claude decides (resetting on reconnect feels natural).
- RSSI value for the mock device (-65) — arbitrary placeholder, easily changed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Mock BLE Layer — MOCK-01 through MOCK-04: exact success criteria for the animated streams, battery drift, connect delay, and simulateDisconnect()
- `.planning/REQUIREMENTS.md` §Architecture — ARCH-01, ARCH-02: BleManager interface contract and UI isolation rule (both still in force)

### Architecture & Design
- `.planning/research/ARCHITECTURE.md` §MockBleManager implementation sketch — canonical StreamController.broadcast() + Timer pattern. D-05 overrides the 600ms connect delay shown in the sketch; use 300ms instead.
- `.planning/research/ARCHITECTURE.md` §BLE Abstraction Pattern — abstract class contract that MockBleManager must satisfy

### Existing Phase 1 Code (READ BEFORE WRITING)
- `lib/ble/mock_ble_manager.dart` — the Phase 1 stub to be replaced; all 9 interface members must remain overridden after Phase 2
- `lib/ble/ble_manager.dart` — the interface contract; never add flutter_blue_plus imports here
- `lib/ble/ble_protocol.dart` — `StatePacket.encode()` is used by the mock ticker to produce raw bytes; `kCmdZeroX` and `kCmdZeroY` constants are used in `sendCommand()`
- `lib/models/device_state.dart` — `ConnectionStatus` enum and `ScannedDevice` model used by the mock streams

### Project Config
- `CLAUDE.md` — Architecture constraints: `connect()` simulates ~300ms delay (D-05), `simulateDisconnect()` debug method required (D-11), no flutter_blue_plus in lib/ble/ abstract files
- `.planning/PROJECT.md` — Package name, WP1/WP2 split rationale, mock-first approach

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/ble/ble_protocol.dart` — `StatePacket.encode(ax, ay, battery)` produces the raw `List<int>` that `_packetController.add()` emits. Already tested and verified.
- `lib/ble/ble_protocol.dart` — `kCmdZeroX = 0x01`, `kCmdZeroY = 0x02` — use these constants in `sendCommand()` rather than raw literals.
- `lib/models/device_state.dart` — `ConnectionStatus` enum (7 values), `ScannedDevice` model.

### Established Patterns
- All streams use `StreamController.broadcast()` — multiple Riverpod providers (Phase 3) will listen simultaneously; a single-subscription controller would throw on the second listener.
- `dispose()` closes all controllers — Riverpod's `keepAlive` provider calls `dispose()` on teardown; failing to close a controller leaks the stream.
- Phase 1 code review fixed `ScannedDevice.==` to use `id` only (not RSSI) — the mock device ID `'AA:BB:CC:DD:EE:FF'` will correctly deduplicate if emitted multiple times.

### Integration Points
- `MockBleManager.statePackets` → Phase 3 `deviceStateProvider: StreamProvider<DeviceState>` (maps bytes via `StatePacket.parse()`)
- `MockBleManager.connectionStatus` → Phase 3 `ConnectionNotifier` (drives connection state machine)
- `MockBleManager.scanResults` → Phase 3 `scanResultsProvider` (feeds Phase 4 scan screen list)
- Phase 2 is the ONLY change to `lib/ble/mock_ble_manager.dart` in WP1 — no other files change.

</code_context>

<specifics>
## Specific Ideas

- The `simulateDisconnect()` method is a debug/testing escape hatch. It should be clearly marked in the doc comment as WP1-only and not part of the `BleManager` interface — it lives on `MockBleManager` directly so only code that has a concrete `MockBleManager` reference can call it (e.g., a debug button in Phase 4 or a test helper).
- Battery drain is intentionally slow (1% per ~10 seconds) so it doesn't distract during Phase 4 development sessions. The unit test for MOCK-02 should listen for "several seconds" and observe at least one decrement.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 2-ble-abstraction-mock-layer*
*Context gathered: 2026-06-04*
