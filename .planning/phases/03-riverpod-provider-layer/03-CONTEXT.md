# Phase 3: Riverpod Provider Layer - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the Riverpod provider layer that exposes the full connection state machine and live instrument data. No widgets — all outputs are observable via provider tests or widget-test harnesses. Consumes `MockBleManager` through `bleManagerProvider`. Phase 4 will consume these providers to build the UI.

</domain>

<decisions>
## Implementation Decisions

### Provider Structure
- **D-01:** Single `ConnectionNotifier extends Notifier<ConnectionStatus>` owns the full `idle → scanning → connecting → connected → disconnecting → disconnected → error → reconnecting` state machine. Scan results accumulate inside it as `List<ScannedDevice>`.
- **D-02:** Instrument data is exposed as `StreamProvider<StatePacket?>` — parses bytes from `BleManager.statePackets` using `StatePacket.parse()`. Riverpod manages stream lifecycle; UI watches with `ref.watch()`.
- **D-03:** Scan results are exposed as a field/derived provider from `ConnectionNotifier`, not a separate `StreamProvider<ScannedDevice>`. The notifier accumulates devices into a list as the `scanResults` stream emits.
- **D-04:** `bleManagerProvider` already exists in `device_provider.dart` with the `keepAlive` pattern. Phase 3 adds `ConnectionNotifier`, scan results provider, and instrument data provider to that same file.

### Stale Data Signal
- **D-05:** `StreamProvider<StatePacket?>` — nullable `StatePacket`. On disconnect, `ConnectionNotifier` controls a `StreamController<StatePacket?>` and adds `null`, signalling stale. The UI checks: if `null` → show stale indicator; if non-null → show live data. "No data yet" (pre-first-packet) is also `null` but connection state disambiguates the cause.
- **D-06:** `ConnectionNotifier` is the single authority responsible for emitting the `null` sentinel into the stream on disconnect/error transitions.

### Auto-Reconnect Stub
- **D-07:** `static const bool _autoReconnectEnabled = false;` inside `ConnectionNotifier`. Backoff/retry logic is written but guarded by this constant. WP2 activates by setting it to `true`. Verifiable by code inspection.
- **D-08:** Add `reconnecting` to the `ConnectionStatus` enum in `device_state.dart`. `ConnectionNotifier` transitions to `ConnectionStatus.reconnecting` when the disabled stub "would" fire. Phase 4 UI maps this to the amber state chip (CONN-06).

### Wakelock
- **D-09:** `WakelockPlus.enable()` / `WakelockPlus.disable()` are called as side-effects directly inside `ConnectionNotifier` state transitions — `connected` → enable, `disconnected`/`error` → disable. All connection-driven side-effects live in one place.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Interface Contract
- `lib/ble/ble_manager.dart` — `abstract class BleManager` with `scanResults`, `connectionStatus`, `statePackets` streams and `startScan/stopScan/connect/disconnect/sendCommand` methods
- `lib/ble/mock_ble_manager.dart` — `MockBleManager` implementation; uses eager broadcast `StreamController`s (multi-subscriber safe); `simulateDisconnect()` is concrete-only (not on interface)
- `lib/ble/ble_protocol.dart` — `StatePacket.parse(List<int>)`, `ZERO_X`, `ZERO_Y`, UUID constants

### Models
- `lib/models/device_state.dart` — `ConnectionStatus` enum (needs `reconnecting` added), `DeviceState`, `ScannedDevice`

### Provider Stub
- `lib/providers/device_provider.dart` — existing `bleManagerProvider` stub; comment explicitly says "Phase 3 adds ConnectionNotifier, scanResultsProvider, and deviceStateProvider here"

### Requirements (Phase 3 scope)
- `.planning/REQUIREMENTS.md` — CONN-01, CONN-02, CONN-03, CONN-05, CONN-06, SYS-01

### Architecture Constraints
- `CLAUDE.md` — BLE connection provider must have `keepAlive: true`; use `Notifier`/`AsyncNotifier` only (no `StateNotifierProvider`); no `flutter_blue_plus` import in `lib/ui/` or `lib/providers/`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `StatePacket.parse(List<int>)` in `ble_protocol.dart` — ready to use inside the `StreamProvider<StatePacket?>` map
- `bleManagerProvider` in `device_provider.dart` — existing root provider; Phase 3 extends this file
- `ConnectionStatus` enum in `device_state.dart` — needs `reconnecting` added; all other states already present
- `ScannedDevice` model — `==` / `hashCode` identity is BLE address only (rssi excluded), safe to use in a `List`

### Established Patterns
- `Notifier<T>` / `AsyncNotifier<T>` only — no `StateNotifierProvider` (CLAUDE.md enforced)
- `MockBleManager` uses broadcast `StreamController`s — multiple providers can subscribe simultaneously without "stream already listened" errors
- `keepAlive: true` required on the BLE manager provider so it survives navigation

### Integration Points
- `ConnectionNotifier` will call `bleManagerProvider` methods (`startScan`, `connect`, `disconnect`)
- `StreamProvider<StatePacket?>` watches `bleManagerProvider.statePackets`
- Phase 4 UI will `ref.watch(connectionNotifierProvider)` for state chip + `ref.watch(instrumentDataProvider)` for readings
- Phase 5 will add `go_router` redirect guard watching `connectionNotifierProvider`

</code_context>

<specifics>
## Specific Ideas

- The null sentinel approach (D-05/D-06) is preferred over wrapper types or separate bool providers — keeps the instrument data as a single `StreamProvider<StatePacket?>` that Phase 4 pattern-matches on
- `_autoReconnectEnabled` constant (D-07) is the most explicit and code-inspectable approach; WP2 activation is a one-line change

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 3-Riverpod Provider Layer*
*Context gathered: 2026-06-05*
