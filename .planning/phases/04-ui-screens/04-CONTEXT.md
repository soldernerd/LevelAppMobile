# Phase 4: UI Screens - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the scan screen and instrument screen as Flutter widgets consuming the Phase 3 Riverpod providers. All `ConnectionStatus` states, data states (live and stale), and navigation paths must be exercisable against the mock layer. No new providers, no new BLE logic — UI only.

</domain>

<decisions>
## Implementation Decisions

### Instrument Screen Layout
- **D-01:** Angle values stacked vertically — `angle_x` row on top, `angle_y` row below. Each row contains the axis label, the value, and its corresponding Zero button inline.
- **D-02:** Angle readout font size: very large (~72–96sp). Should dominate the screen, readable across a workbench.
- **D-03:** Zero X and Zero Y buttons sit inline with their respective angle row (not grouped at the bottom). Pairing between value and its Zero action is visually obvious.
- **D-04:** Battery level displayed in the AppBar (icon + percentage). Never competes with the angle readout.

### Scan Screen Layout
- **D-05:** Scan start/stop control is a FAB (Floating Action Button). Standard Android pattern, thumb-reachable.
- **D-06:** Scan state chip (idle / scanning / error) displayed as a small colored chip in the AppBar area — below/alongside the screen title. Not a full-width banner.
- **D-07:** Each device row shows: device name (prominent) + RSSI signal-strength icon + raw dBm value. Standard `ListTile` layout — no custom density needed.

### Stale Data Indicator
- **D-08:** On unexpected disconnect, the instrument readout fades to ~40% opacity. Values remain readable for reference but are clearly not live. The connection chip in the AppBar turns red simultaneously.
- **D-09:** Connection state chip (green/amber/red) lives in the AppBar on the instrument screen. Always visible, never overlaps the readout.
- **D-10:** On disconnect, the app stays on the instrument screen — it does NOT auto-navigate back to the scan screen. Last measurement stays visible (matches instrument/oscilloscope conventions). User navigates back manually or via a reconnect action.

### Zero X/Y Button Feedback
- **D-11:** Zero X and Zero Y buttons fire silently — no snackbar, no animation. The angle readout updating from the new zero is the implicit confirmation. Matches hardware instrument behavior.
- **D-12:** Zero buttons are disabled (greyed out, non-tappable) when `ConnectionStatus` is not `connected`. Prevents user confusion about unconfirmed commands.
- **D-13:** A debug button to trigger `simulateDisconnect()` is visible in the instrument screen AppBar, but only in debug builds (`kDebugMode`). Label: "Sim. Disconnect" (overflow menu or icon). Allows manual exercise of the stale-data path without a test harness.

### Claude's Discretion
- Exact color values for the connection chip states (green/amber/red) — standard Material colors are fine.
- Monospaced font choice for angle values — any system monospace or `fontFeatures: [FontFeature.tabularFigures()]` on the default font satisfies INST-07.
- Number of decimal places for angle display — Claude picks what looks right (e.g. 2dp).
- Animation duration / curve for opacity transition on stale state — subtle is fine.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — Full requirement list. Phase 4 covers: SCAN-01–05, INST-01–07, CONN-04. These are the acceptance criteria.

### Architecture Constraints
- `CLAUDE.md` — Architecture constraints: no `flutter_blue_plus` import in `lib/ui/`; `abstract class BleManager` interface; `keepAlive` on BLE providers.

### Provider API (what UI widgets must consume)
- `lib/providers/device_provider.dart` — `connectionNotifierProvider` (ConnectionStatus), `scanResultsProvider` (List<ScannedDevice>), `instrumentDataProvider` (StreamProvider<DeviceState?> — null = stale). Read this before implementing any widget.
- `lib/models/device_state.dart` — `DeviceState` (angleX, angleY, battery), `ScannedDevice` (id, name, rssi), `ConnectionStatus` enum (idle, scanning, connecting, connected, disconnecting, disconnected, error, reconnecting).
- `lib/ble/ble_manager.dart` — `BleManager` interface methods: `startScan()`, `stopScan()`, `connect(deviceId)`, `disconnect()`, `sendCommand(byte)`. UI calls these through the notifier, not directly.
- `lib/ble/ble_protocol.dart` — Command constants `ZERO_X = 0x01`, `ZERO_Y = 0x02`.

### Mock Layer
- `lib/ble/mock_ble_manager.dart` — Has `simulateDisconnect()` debug method. Must be cast from `BleManager` to `MockBleManager` to call it in debug mode.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `connectionNotifierProvider` exposes `.startScan()`, `.stopScan()`, `.connect()`, `.disconnect()` — all scan/connection actions go through this.
- `instrumentDataProvider` is a `StreamProvider<DeviceState?>` — use `ref.watch(instrumentDataProvider)` and handle `AsyncValue.data(null)` as the stale sentinel.
- `scanResultsProvider` returns `List<ScannedDevice>` — rebuild-triggers are wired via `connectionNotifierProvider` watch inside the provider.

### Established Patterns
- `ConnectionStatus` is the canonical state enum — use it for all chip colors and button enable/disable logic.
- Stale data = `instrumentDataProvider` emits `DeviceState?` where null means disconnected/error. Do NOT compare against `ConnectionStatus` for stale detection — use the null value from the stream.
- `bleManagerProvider` must never be imported directly in `lib/ui/` — all interaction goes through `connectionNotifierProvider.notifier` methods.

### Integration Points
- New files: `lib/ui/scan_screen.dart`, `lib/ui/instrument_screen.dart` (possibly `lib/ui/widgets/` for extracted components).
- `main.dart` will be completed in Phase 5 (go_router, ProviderScope). Phase 4 screens should be runnable standalone via `runApp(ProviderScope(...))` for development, but the final wiring is Phase 5.

</code_context>

<specifics>
## Specific Ideas

- Machine-shop context: the primary use case is reading angle values across a workbench. Large text (72–96sp) is a hard requirement, not a preference.
- The instrument UI should feel like a precision instrument display, not a generic mobile app. Minimal chrome, maximum data density.
- `simulateDisconnect()` debug button should only appear in `kDebugMode` — never ship in release builds.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 4-UI Screens*
*Context gathered: 2026-06-05*
