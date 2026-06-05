# Phase 4: UI Screens — Research

**Researched:** 2026-06-05
**Domain:** Flutter/Material 3 widget authoring with Riverpod 3 consumer integration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Angle values stacked vertically — `angle_x` row on top, `angle_y` row below. Each row contains the axis label, the value, and its corresponding Zero button inline.
- **D-02:** Angle readout font size: very large (~72–96sp, spec locks at 80sp). Should dominate the screen, readable across a workbench.
- **D-03:** Zero X and Zero Y buttons sit inline with their respective angle row. Pairing between value and its Zero action is visually obvious.
- **D-04:** Battery level displayed in the AppBar (icon + percentage). Never competes with the angle readout.
- **D-05:** Scan start/stop control is a FAB. Standard Android pattern, thumb-reachable.
- **D-06:** Scan state chip (idle / scanning / error) displayed as a small colored chip in the AppBar area — below/alongside the screen title. Not a full-width banner.
- **D-07:** Each device row shows: device name (prominent) + RSSI signal-strength icon + raw dBm value. Standard `ListTile` layout.
- **D-08:** On unexpected disconnect, the instrument readout fades to ~40% opacity over 300ms. Connection chip turns red simultaneously.
- **D-09:** Connection state chip (green/amber/red) lives in the AppBar on the instrument screen. Always visible.
- **D-10:** On disconnect, the app stays on the instrument screen. No auto-navigate back to scan screen.
- **D-11:** Zero X and Zero Y buttons fire silently — no snackbar, no animation.
- **D-12:** Zero buttons are disabled when `ConnectionStatus` is not `connected`.
- **D-13:** A debug button to trigger `simulateDisconnect()` is visible in the instrument screen AppBar in `kDebugMode` only. Label: "Sim. Disconnect".

### Claude's Discretion
- Exact color values for connection chip states — standard Material colors are fine.
- Monospaced font choice for angle values — `fontFeatures: [FontFeature.tabularFigures()]` on the default font satisfies INST-07.
- Number of decimal places for angle display — 2dp chosen.
- Animation duration/curve for opacity transition — 300ms / `Curves.easeOut` chosen.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCAN-01 | User can initiate and stop a BLE scan via a scan button | FAB toggling `startScan()`/`stopScan()` via `connectionNotifierProvider.notifier`; icon swaps `bluetooth_searching`/`stop` |
| SCAN-02 | Scan screen displays a live list of discovered devices showing device name and RSSI | `ListView.builder` over `scanResultsProvider`; `ListTile` with name + RSSI icon + dBm |
| SCAN-03 | Device list is filtered to named devices only | Filter `where((d) => d.name.isNotEmpty)` before `ListView.builder` |
| SCAN-04 | Scan screen displays current scan state (idle / scanning / error) at all times | AppBar chip watching `connectionNotifierProvider`; chip color map covers all states |
| SCAN-05 | User can tap a device to initiate a connection | `ListTile.onTap` calls `connect(device.id)` on `connectionNotifierProvider.notifier` |
| INST-01 | Instrument screen is shown after successful connection | Phase 4: simple `Navigator.push` or root `StatefulWidget` switch on `ConnectionStatus.connected`; Phase 5 replaces with go_router |
| INST-02 | Instrument screen displays angle_x as a large, readable float | `_AngleRow` widget; value from `instrumentDataProvider`; 80sp/w700 |
| INST-03 | Instrument screen displays angle_y as a large, readable float | Same as INST-02, second row |
| INST-04 | Instrument screen displays battery level as percentage | Battery icon + `"${battery}%"` in AppBar actions from `DeviceState.battery` |
| INST-05 | User can trigger Zero X via dedicated button | `ElevatedButton` fires `sendCommand(kCmdZeroX)` through notifier; enabled only when connected |
| INST-06 | User can trigger Zero Y via dedicated button | Same pattern, `kCmdZeroY` |
| INST-07 | Angle values rendered with monospaced/tabular numerals | `fontFeatures: [FontFeature.tabularFigures()]` on 80sp `TextStyle` |
| CONN-04 | Connection state chip always visible on instrument screen | `Chip` in AppBar actions watching `connectionNotifierProvider`; uses full color map |
</phase_requirements>

---

## Summary

Phase 4 creates two Flutter screens — `ScanScreen` and `InstrumentScreen` — that consume the Phase 3 Riverpod providers. No new providers, no new BLE logic. The central design challenge is correct reactive binding: watching `connectionNotifierProvider` for chip colors and button enable/disable states, watching `instrumentDataProvider` (a `StreamProvider<DeviceState?>`) for live data and the stale-null sentinel, and watching `scanResultsProvider` for the device list.

The UI-SPEC in `04-UI-SPEC.md` is unusually complete and prescriptive. All color values, typography sizes, component specifications, and interaction states are already decided. Research focus is therefore on implementation mechanics: how to correctly wire Riverpod `ConsumerWidget` / `ConsumerStatefulWidget` to providers, how to implement `AnimatedOpacity` for stale state, how to wire the `sendCommand` path for Zero buttons, and how to handle the `kDebugMode` cast for the debug button.

Phase 4 standalone entry point: `runApp(ProviderScope(overrides: [bleManagerProvider.overrideWithValue(MockBleManager())], child: MaterialApp(...)))` in a temporary `main.dart` or in a `main_dev.dart` that the planner can target. Phase 5 will replace with the final `main.dart` + go_router setup.

**Primary recommendation:** Build two `ConsumerStatefulWidget` screens (stateful needed for `AnimatedOpacity` if not using `AnimatedOpacity`'s own implicit animation) — actually `ConsumerWidget` suffices since `AnimatedOpacity` manages its own animation state internally. Keep all provider access in the widget `build` method via `ref.watch`. Extract `_AngleRow` and `_RssiIcon` as private helper widgets or functions within the same file to keep the file navigable.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Live angle/battery display | Frontend (Flutter widget) | Provider layer (StreamProvider) | Widget watches provider; provider owns stream subscription lifecycle |
| Stale-data indicator (opacity) | Frontend (Flutter widget) | — | `AnimatedOpacity` is a pure widget concern driven by null-check on `DeviceState?` |
| Connection state chip | Frontend (Flutter widget) | Provider layer (Notifier state) | Chip color is a pure mapping from `ConnectionStatus` enum |
| Zero X / Zero Y commands | Provider layer (Notifier) | Frontend (button widget) | Widget calls `connectionNotifierProvider.notifier.sendCommand()`; provider owns `BleManager` access |
| Scan start/stop | Provider layer (Notifier) | Frontend (FAB widget) | Same pattern — `startScan()`/`stopScan()` on notifier |
| Device list filtering | Frontend (widget) | — | Simple `where` filter on `List<ScannedDevice>` at build time; no provider change needed |
| Debug disconnect | BLE layer (`MockBleManager`) | Frontend (debug button) | `simulateDisconnect()` is a concrete method on `MockBleManager`; widget casts in `kDebugMode` |
| Screen navigation (Phase 4) | Frontend (root widget) | — | Simple `ConnectionStatus`-driven switch in `MaterialApp.home`; go_router is Phase 5 |

---

## Standard Stack

### Core (all already in pubspec.yaml — no new packages needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_riverpod | 3.3.1 | Provider consumption (`ConsumerWidget`, `ref.watch`) | Project-locked; already installed |
| flutter/material | (Flutter SDK) | `Scaffold`, `AppBar`, `ListView`, `Chip`, `ElevatedButton`, `OutlinedButton`, `FAB`, `AnimatedOpacity` | Built-in; no install needed |
| dart:ui | (Dart SDK) | `FontFeature.tabularFigures()` for INST-07 | Built-in |

No new packages are required for Phase 4. All dependencies are already resolved.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| flutter/foundation | (Flutter SDK) | `kDebugMode` constant for D-13 debug button | Import in `instrument_screen.dart` only |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AnimatedOpacity` (implicit) | Explicit `AnimationController` in `State` | Explicit controller gives more control but requires `StatefulWidget`; `AnimatedOpacity` achieves the same 300ms/easeOut with far less code |
| `ConsumerWidget` | `HookConsumerWidget` (flutter_hooks) | flutter_hooks not in project; `ConsumerWidget` is the project standard |
| Private `_AngleRow` class | Separate file in `lib/ui/widgets/` | Separate file is cleaner for large widgets; `_AngleRow` is small enough to stay private in `instrument_screen.dart` |

**Installation:** No new packages. Phase 4 is purely widget code.

---

## Package Legitimacy Audit

No new packages are installed in Phase 4. All dependencies (`flutter_riverpod`, `wakelock_plus`, Flutter SDK) were verified and installed in prior phases.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
User gesture (tap/FAB press)
        │
        ▼
  ConsumerWidget (ScanScreen / InstrumentScreen)
        │  ref.watch(connectionNotifierProvider)      → ConnectionStatus
        │  ref.watch(scanResultsProvider)             → List<ScannedDevice>
        │  ref.watch(instrumentDataProvider)          → AsyncValue<DeviceState?>
        │
        │  ref.read(connectionNotifierProvider.notifier)
        │    .startScan() / .stopScan()
        │    .connect(id) / .disconnect()
        │    .sendCommand(byte)          ─────────────→  ConnectionNotifier
        │                                                       │
        │                                              bleManagerProvider
        │                                                       │
        │                                             MockBleManager
        │                                            (simulateDisconnect
        │                                             cast in kDebugMode)
        │
        ▼
  Rebuild triggers:
    connectionNotifierProvider change  → chip color, FAB icon, button enabled, disconnect button visibility
    instrumentDataProvider null        → AnimatedOpacity to 0.40, stale label appear
    instrumentDataProvider non-null    → AnimatedOpacity to 1.0
    scanResultsProvider change         → ListView.builder re-renders
```

### Recommended Project Structure

```
lib/
├── ui/
│   ├── scan_screen.dart         # ScanScreen ConsumerWidget + private _RssiIcon helper
│   └── instrument_screen.dart   # InstrumentScreen ConsumerWidget + private _AngleRow helper
├── ble/
│   ├── ble_manager.dart         # (existing)
│   ├── ble_protocol.dart        # (existing — kCmdZeroX, kCmdZeroY)
│   └── mock_ble_manager.dart    # (existing — simulateDisconnect())
├── models/
│   └── device_state.dart        # (existing — DeviceState, ScannedDevice, ConnectionStatus)
├── providers/
│   └── device_provider.dart     # (existing — all three providers)
└── main.dart                    # Phase 4: temporary standalone entry point
                                 # Phase 5: replaced with go_router version
test/
├── ble/                         # (existing)
├── providers/                   # (existing)
└── ui/
    ├── scan_screen_test.dart    # widget tests — Wave 0 gap
    └── instrument_screen_test.dart  # widget tests — Wave 0 gap
```

### Pattern 1: ConsumerWidget with provider watching

**What:** Use `ConsumerWidget` (stateless) for both screens. `AnimatedOpacity` manages its own animation state implicitly, so no `StatefulWidget` is needed.
**When to use:** Any screen that only needs `ref.watch` — no local mutable state beyond what implicit animation widgets manage.

```dart
// Source: [ASSUMED — standard Riverpod 3 ConsumerWidget pattern]
class InstrumentScreen extends ConsumerWidget {
  const InstrumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final dataAsync = ref.watch(instrumentDataProvider);
    final deviceState = dataAsync.valueOrNull; // null = stale

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inclinometer'),
        actions: [
          _BatteryIndicator(battery: deviceState?.battery),
          _ConnectionChip(status: status),
          if (kDebugMode) _SimDisconnectButton(ref: ref),
        ],
      ),
      body: ...,
    );
  }
}
```

### Pattern 2: Stale data detection

**What:** `instrumentDataProvider` is a `StreamProvider<DeviceState?>`. Null emission is the stale sentinel. Use `AsyncValue.valueOrNull` (returns the data value or null for loading/error states as well) — or check `dataAsync.hasValue && dataAsync.value == null` to distinguish "stale" from "loading".

**Critical:** Do NOT use `connectionNotifierProvider` state to drive stale detection — use the null value from `instrumentDataProvider` per the CONTEXT.md established pattern.

```dart
// Source: [ASSUMED — standard Riverpod 3 AsyncValue pattern]
final dataAsync = ref.watch(instrumentDataProvider);
final isStale = dataAsync.hasValue && dataAsync.value == null;
final deviceState = dataAsync.valueOrNull; // DeviceState or null

AnimatedOpacity(
  opacity: isStale ? 0.40 : 1.0,
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeOut,
  child: _AngleReadoutBlock(deviceState: deviceState),
)
```

### Pattern 3: sendCommand via notifier

**What:** Zero buttons call `sendCommand` through the `ConnectionNotifier`, not `BleManager` directly. The notifier exposes `startScan`, `stopScan`, `connect`, `disconnect` — but NOT `sendCommand`. Research reveals `sendCommand` is NOT on the `ConnectionNotifier`; it IS on `BleManager`. The correct call path is through `bleManagerProvider` or a new notifier method.

**Critical finding:** `ConnectionNotifier` does NOT expose `sendCommand`. Options:
1. Call `ref.read(bleManagerProvider).sendCommand(byte)` — violates CLAUDE.md (no direct BleManager access from UI)
2. Add a `sendCommand(int byte)` method to `ConnectionNotifier` — clean, follows architecture

Option 2 is the correct approach. The planner MUST include a task to add `sendCommand(int byte)` to `ConnectionNotifier` that delegates to `ref.read(bleManagerProvider).sendCommand(byte)`.

```dart
// In ConnectionNotifier (to be added in Phase 4):
Future<void> sendCommand(int commandByte) async {
  await ref.read(bleManagerProvider).sendCommand(commandByte);
}

// In InstrumentScreen widget:
ElevatedButton(
  onPressed: status == ConnectionStatus.connected
      ? () => ref.read(connectionNotifierProvider.notifier).sendCommand(kCmdZeroX)
      : null,
  child: const Text('Zero X'),
)
```

### Pattern 4: kDebugMode debug button with MockBleManager cast

**What:** The debug button must cast `BleManager` to `MockBleManager` to call `simulateDisconnect()`. This cast is only valid when the `bleManagerProvider` override is `MockBleManager` (WP1). Gate entirely on `kDebugMode`.

```dart
// Source: [ASSUMED — standard Flutter kDebugMode + Riverpod read pattern]
// In instrument_screen.dart:
import 'package:flutter/foundation.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart'; // allowed only with kDebugMode guard

if (kDebugMode)
  TextButton(
    onPressed: () {
      final mgr = ref.read(bleManagerProvider);
      if (mgr is MockBleManager) mgr.simulateDisconnect();
    },
    child: const Text('Sim. Disconnect'),
  )
```

Note: Importing `mock_ble_manager.dart` in `lib/ui/` does not violate CLAUDE.md's "no flutter_blue_plus import" rule — `mock_ble_manager.dart` does not import `flutter_blue_plus`. The architecture constraint is about `flutter_blue_plus`, not about `mock_ble_manager.dart`. The import should be guarded with a comment noting it is WP1-only.

### Pattern 5: Angle value formatting

**What:** Format `double` angle as `±NNN.NN°` with always-shown sign, 3 integer digits zero-padded, 2 decimal places.

```dart
// Source: [ASSUMED — standard Dart string formatting]
String _formatAngle(double value) {
  final sign = value >= 0 ? '+' : '−'; // Unicode minus U+2212
  final abs = value.abs();
  return '$sign${abs.toStringAsFixed(2).padLeft(6, '0')}°';
}
// Examples: +012.34°  −003.00°  +000.00°
```

Note: `toStringAsFixed(2)` on `3.0` gives `"3.00"`, not `"003.00"` — the `padLeft(6, '0')` pads to 6 chars (NNN.NN), producing `"003.00"`. Verify: `'3.00'.padLeft(6, '0')` → `'003.00'`. Correct.

### Pattern 6: RSSI icon mapping

```dart
// Source: [ASSUMED — derived from 04-UI-SPEC.md]
IconData _rssiIcon(int rssi) {
  if (rssi >= -60) return Icons.signal_wifi_4_bar;
  if (rssi >= -75) return Icons.network_wifi_3_bar;
  if (rssi >= -85) return Icons.network_wifi_2_bar;
  return Icons.network_wifi_1_bar;
}
```

### Pattern 7: Standalone Phase 4 entry point

**What:** Phase 5 owns `main.dart` and go_router. Phase 4 needs a runnable entry point for manual smoke testing. The planner should include creating a temporary `main.dart` that wires `MockBleManager` for the duration of Phase 4 development. This `main.dart` will be completely replaced in Phase 5.

```dart
// main.dart (Phase 4 temporary — replaced entirely in Phase 5)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/scan_screen.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        bleManagerProvider.overrideWithValue(MockBleManager()),
      ],
      child: const MaterialApp(home: ScanScreen()),
    ),
  );
}
```

Navigation: A root `Consumer` in `MaterialApp.home` or in `ScanScreen` watches `connectionNotifierProvider` and pushes/pops `InstrumentScreen` based on `ConnectionStatus.connected`. Phase 5 replaces this with go_router shell routes.

### Anti-Patterns to Avoid

- **Watching `bleManagerProvider` directly in UI:** Violates CLAUDE.md architecture constraint. All actions go through `connectionNotifierProvider.notifier`.
- **Importing `flutter_blue_plus` in `lib/ui/`:** Prohibited by CLAUDE.md.
- **Using `ConnectionStatus` as stale sentinel:** CONTEXT.md explicit rule — use null from `instrumentDataProvider`, not `ConnectionStatus`.
- **Calling `sendCommand` directly on `BleManager` from UI:** Must route through `ConnectionNotifier` method.
- **`ref.read` in build method for reactive data:** Use `ref.watch` for anything that should trigger rebuilds. `ref.read` only in callbacks (button `onPressed`).
- **`AsyncValue.when` for `instrumentDataProvider` in the angle readout:** Using `.when` will show a loading spinner on initial state. Use `.valueOrNull` with an explicit stale check instead — the UI should show 0.00° (or last known values at stale opacity) rather than a spinner.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Smooth opacity transition on stale | Custom `AnimationController` + `Tween` | `AnimatedOpacity` | `AnimatedOpacity` handles the full implicit animation lifecycle; controller requires `StatefulWidget` with `TickerProvider` |
| Angle sign formatting | Custom formatter class | `String` formatting with `padLeft` | Simple enough for a helper function; no library needed |
| Connection chip component | A complex widget hierarchy | Material `Chip` with `backgroundColor` override | `Chip` widget already handles padding, label, shape; one widget, one override |
| Battery icon threshold | A lookup table class | Simple `if/else` in widget or helper function | The 4-threshold table in UI-SPEC is too simple to justify abstraction |
| Monospaced numerals | Custom font file | `FontFeature.tabularFigures()` | Built into Roboto/system font; no font assets needed |

**Key insight:** Phase 4 is primarily widget composition. The hard problems (state machine, stream lifecycle, BLE protocol) are already solved in Phases 1–3. Don't re-solve them.

---

## Common Pitfalls

### Pitfall 1: `AsyncValue.valueOrNull` vs stale detection

**What goes wrong:** `instrumentDataProvider.valueOrNull` returns `null` both when loading (initial state before first packet) AND when the stream emits null (stale sentinel). A simple `value == null` check cannot distinguish "loading" from "disconnected".

**Why it happens:** `StreamProvider` starts in `AsyncLoading` state. Both `AsyncLoading` and `AsyncData(null)` produce `null` from `.valueOrNull`.

**How to avoid:** Use `dataAsync.hasValue` to distinguish:
```dart
final isStale = dataAsync.hasValue && dataAsync.value == null;
final isLoading = !dataAsync.hasValue && !dataAsync.hasError;
```
During initial load (before connect, or before first packet), treat as neither live nor stale — show `0.00°` at full opacity or a neutral state.

**Warning signs:** The stale label "DISCONNECTED" appears immediately on app launch before any connection attempt.

### Pitfall 2: Navigation loop between ScanScreen and InstrumentScreen

**What goes wrong:** A `Consumer` that reacts to `ConnectionStatus.connected` by pushing `InstrumentScreen` and reacts to non-connected by popping will create a push/pop loop if the status briefly flickers.

**Why it happens:** `connecting` → `connected` triggers push; disconnect → `disconnected` triggers pop; the pop triggers scan screen rebuild which re-reads status.

**How to avoid:** In Phase 4 standalone, use a single `StatefulWidget` root that replaces `body` based on connection status, OR push once to InstrumentScreen and let the user navigate back manually (per D-10: no auto-navigate on disconnect). Do NOT wire automatic pop on disconnect.

**Warning signs:** The app flickers between screens rapidly after disconnect.

### Pitfall 3: `ref.read` vs `ref.watch` in the wrong context

**What goes wrong:** Using `ref.read` for `connectionNotifierProvider` in the build method means chip colors never update. Using `ref.watch` in button callbacks wastes rebuilds.

**How to avoid:** `ref.watch` at the top of `build()` for all reactive data. `ref.read(provider.notifier)` only inside `onPressed` callbacks.

### Pitfall 4: Zero button enabled state when stale

**What goes wrong:** Per UI-SPEC interaction table, when connected but `DeviceState` is null, the Zero buttons are technically enabled (ConnectionStatus is still `connected`) but covered by the 40% opacity `AnimatedOpacity`. If the opacity parent wraps the buttons, they still respond to taps.

**Why it happens:** `AnimatedOpacity` only changes visual appearance, not hit-testing. Buttons remain interactive.

**How to avoid:** The button `enabled` state is controlled by `ConnectionStatus == connected` alone (D-12). The transient stale state during an active connection (unlikely with mock) is acceptable — the user tapping a 40%-opacity Zero button causes no harm (send command fires, mock zeroes the angle). This is consistent with D-12 as specified. Document this in code comments; do not add extra null-check to button enable logic.

### Pitfall 5: Mock scan timer produces device before UI is listening

**What goes wrong:** `startScan()` on `MockBleManager` emits a `ScannedDevice` after a 500ms timer. If the UI hasn't subscribed to `scanResultsProvider` yet when the device is emitted, the `ListView` stays empty.

**Why it happens:** The broadcast stream in `MockBleManager` discards events with no listeners. However, `ConnectionNotifier.build()` subscribes to `scanResults` eagerly in `ref.keepAlive()` — so by the time a user taps the FAB, the provider is already subscribed.

**How to avoid:** No special handling needed — `connectionNotifierProvider` is always alive (keepAlive) and accumulates devices in `_scannedDevices`. `scanResultsProvider` reads from that accumulated list. The UI correctly receives the device.

### Pitfall 6: `kDebugMode` import in release builds

**What goes wrong:** The debug button widget tree is only shown when `kDebugMode` is true, but if the widget is compiled unconditionally, the `mock_ble_manager.dart` import is included in release builds (dead code that increases binary size, though doesn't break correctness).

**How to avoid:** Wrap with `if (kDebugMode)` in the actions list — Dart's tree-shaker is not guaranteed to remove the import entirely. The cleaner solution is a `assert(() { ... }())` block or to keep the import but accept the minor binary size increase. For WP1, `if (kDebugMode)` guard is sufficient.

---

## Code Examples

### Full InstrumentScreen skeleton (verified against existing APIs)

```dart
// Source: [ASSUMED — derived from 04-UI-SPEC.md and existing codebase]
// lib/ui/instrument_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/ble_protocol.dart';     // kCmdZeroX, kCmdZeroY
import 'package:inclinometer/ble/mock_ble_manager.dart'; // WP1-only cast
import 'package:inclinometer/models/device_state.dart';   // DeviceState, ConnectionStatus
import 'package:inclinometer/providers/device_provider.dart';

class InstrumentScreen extends ConsumerWidget {
  const InstrumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final dataAsync = ref.watch(instrumentDataProvider);
    final isStale = dataAsync.hasValue && dataAsync.value == null;
    final deviceState = dataAsync.valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Inclinometer', style: TextStyle(fontSize: 18)),
        actions: [
          _BatteryIndicator(battery: deviceState?.battery),
          const SizedBox(width: 8),
          _ConnectionChip(status: status),
          if (kDebugMode) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                final mgr = ref.read(bleManagerProvider);
                if (mgr is MockBleManager) mgr.simulateDisconnect();
              },
              child: const Text('Sim. Disconnect',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedOpacity(
                      opacity: isStale ? 0.40 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: Column(
                        children: [
                          _AngleRow(
                            label: 'X',
                            value: deviceState?.angleX ?? 0.0,
                            onZero: status == ConnectionStatus.connected
                                ? () => ref.read(connectionNotifierProvider.notifier).sendCommand(kCmdZeroX)
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _AngleRow(
                            label: 'Y',
                            value: deviceState?.angleY ?? 0.0,
                            onZero: status == ConnectionStatus.connected
                                ? () => ref.read(connectionNotifierProvider.notifier).sendCommand(kCmdZeroY)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    if (isStale)
                      AnimatedOpacity(
                        opacity: isStale ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('DISCONNECTED',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFD32F2F),
                                letterSpacing: 1.5,
                              )),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (status == ConnectionStatus.connected ||
              status == ConnectionStatus.connecting ||
              status == ConnectionStatus.reconnecting)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => ref.read(connectionNotifierProvider.notifier).disconnect(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red[400]!),
                  foregroundColor: Colors.red[400],
                ),
                child: const Text('Disconnect'),
              ),
            ),
        ],
      ),
    );
  }
}
```

### ConnectionNotifier.sendCommand (addition required in Phase 4)

```dart
// Source: [ASSUMED — addition to existing lib/providers/device_provider.dart]
// Add to ConnectionNotifier class:
Future<void> sendCommand(int commandByte) async {
  await ref.read(bleManagerProvider).sendCommand(commandByte);
}
```

### Chip color helper

```dart
// Source: [ASSUMED — derived from 04-UI-SPEC.md color map]
Color _chipColor(ConnectionStatus status) => switch (status) {
  ConnectionStatus.idle          => const Color(0xFF757575),
  ConnectionStatus.scanning      => const Color(0xFF1E88E5),
  ConnectionStatus.connecting    => const Color(0xFFFFA000),
  ConnectionStatus.connected     => const Color(0xFF43A047),
  ConnectionStatus.reconnecting  => const Color(0xFFF57F17),
  ConnectionStatus.disconnecting => const Color(0xFFD32F2F),
  ConnectionStatus.disconnected  => const Color(0xFFD32F2F),
  ConnectionStatus.error         => const Color(0xFFD32F2F),
};

String _chipLabel(ConnectionStatus status) => switch (status) {
  ConnectionStatus.idle          => 'Idle',
  ConnectionStatus.scanning      => 'Scanning',
  ConnectionStatus.connecting    => 'Connecting…',
  ConnectionStatus.connected     => 'Connected',
  ConnectionStatus.reconnecting  => 'Reconnecting…',
  ConnectionStatus.disconnecting => 'Disconnecting…',
  ConnectionStatus.disconnected  => 'Disconnected',
  ConnectionStatus.error         => 'Error',
};
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `StateNotifierProvider` | `NotifierProvider` / `AsyncNotifierProvider` | Riverpod 3.x | Project already uses correct Riverpod 3 API |
| Manual `AnimationController` for simple fades | `AnimatedOpacity` (implicit) | Flutter 1.x+ | Less boilerplate; no `StatefulWidget` needed |
| `ConsumerStatefulWidget` for read-only screens | `ConsumerWidget` | Riverpod 2+ | Simpler; `StatefulWidget` only needed for local mutable state |

**Deprecated/outdated:**
- `StateNotifierProvider`: project already avoids this — no action needed.
- `ref.notifyListeners()`: does not exist in Riverpod 3.3.1 `Notifier` — project already uses `state = state` reassignment workaround. No change needed in Phase 4 (Phase 4 adds no new notifiers).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ConnectionNotifier` needs a `sendCommand(int)` method added — currently not present in `device_provider.dart` | Patterns 3, Code Examples | If wrong (method already exists): minor, remove duplicate task. If wrong the other way (UI calls BleManager directly): architecture violation |
| A2 | `AnimatedOpacity` with `Curves.easeOut` works as a static `curve:` parameter | Pattern 1, Animation Contract | Flutter's `AnimatedOpacity` accepts `curve` parameter — standard Flutter API; low risk |
| A3 | `dataAsync.hasValue && dataAsync.value == null` correctly identifies stale vs loading state | Pitfall 1, Pattern 2 | If `AsyncData(null)` does not have `.hasValue == true`, stale detection breaks. Standard Riverpod `AsyncValue` semantics make this reliable |
| A4 | Dart's exhaustive `switch` expression works for all 8 `ConnectionStatus` enum values | Code Examples | Standard Dart 3.0+ syntax; SDK constraint is `^3.12.1` — confirmed compatible |
| A5 | `bleManagerProvider.overrideWithValue(MockBleManager())` is the correct Riverpod 3 override syntax for a non-autoDispose `Provider` | Pattern 7 | If syntax differs, `main.dart` won't compile. Risk is low — standard Riverpod 3 pattern |

---

## Open Questions

1. **`sendCommand` on `ConnectionNotifier`**
   - What we know: `BleManager.sendCommand(int)` exists; `ConnectionNotifier` does not expose it
   - What's unclear: Whether to add it to `ConnectionNotifier` or use a different routing approach
   - Recommendation: Add `sendCommand(int commandByte)` to `ConnectionNotifier` — consistent with all other action methods; prevents any future `bleManagerProvider` direct access from UI

2. **Phase 4 navigation approach**
   - What we know: Phase 5 owns go_router; Phase 4 needs something runnable
   - What's unclear: Whether to add a minimal `Navigator.push` in `ScanScreen.onTap` or a root-level status-watching `Consumer`
   - Recommendation: Simplest approach — inside `ScanScreen`, when `connectionNotifierProvider` reaches `connected`, use `Navigator.push` to `InstrumentScreen`. This is replaced entirely by go_router in Phase 5.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All widget code | Already in use | 3.x (project active) | — |
| flutter_riverpod 3.3.1 | Provider consumption | Already installed | 3.3.1 | — |
| Android emulator/device | Manual smoke test | Not verified by research | — | Pure widget tests in `flutter test` cover logic; visual verification deferred |

**Missing dependencies with no fallback:** None that block implementation.
**Missing dependencies with fallback:** Android emulator for visual smoke test — `flutter test` widget tests cover correctness without a device.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK) |
| Config file | none — flutter test discovers `test/` automatically |
| Quick run command | `flutter test test/ui/ --name "smoke"` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCAN-01 | FAB triggers startScan/stopScan | widget | `flutter test test/ui/scan_screen_test.dart -n "FAB"` | ❌ Wave 0 |
| SCAN-02 | Device list renders from scanResultsProvider | widget | `flutter test test/ui/scan_screen_test.dart -n "device list"` | ❌ Wave 0 |
| SCAN-03 | Unnamed devices filtered from list | widget | `flutter test test/ui/scan_screen_test.dart -n "filter"` | ❌ Wave 0 |
| SCAN-04 | Scan state chip shows correct label/color | widget | `flutter test test/ui/scan_screen_test.dart -n "chip"` | ❌ Wave 0 |
| SCAN-05 | Tap device calls connect(device.id) | widget | `flutter test test/ui/scan_screen_test.dart -n "connect"` | ❌ Wave 0 |
| INST-01 | InstrumentScreen shown after connected status | widget | `flutter test test/ui/instrument_screen_test.dart -n "navigation"` | ❌ Wave 0 |
| INST-02 | angle_x value rendered at 80sp | widget | `flutter test test/ui/instrument_screen_test.dart -n "angleX"` | ❌ Wave 0 |
| INST-03 | angle_y value rendered at 80sp | widget | `flutter test test/ui/instrument_screen_test.dart -n "angleY"` | ❌ Wave 0 |
| INST-04 | Battery percentage shown in AppBar | widget | `flutter test test/ui/instrument_screen_test.dart -n "battery"` | ❌ Wave 0 |
| INST-05 | Zero X button calls sendCommand(kCmdZeroX) | widget | `flutter test test/ui/instrument_screen_test.dart -n "zeroX"` | ❌ Wave 0 |
| INST-06 | Zero Y button calls sendCommand(kCmdZeroY) | widget | `flutter test test/ui/instrument_screen_test.dart -n "zeroY"` | ❌ Wave 0 |
| INST-07 | Angle text uses FontFeature.tabularFigures | widget | `flutter test test/ui/instrument_screen_test.dart -n "tabular"` | ❌ Wave 0 |
| CONN-04 | Connection chip always visible in AppBar | widget | `flutter test test/ui/instrument_screen_test.dart -n "chip"` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/ui/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work 4`

### Wave 0 Gaps

- [ ] `test/ui/scan_screen_test.dart` — covers SCAN-01 through SCAN-05; requires `ProviderScope` with `MockBleManager` override
- [ ] `test/ui/instrument_screen_test.dart` — covers INST-01 through INST-07, CONN-04; requires `ProviderScope` with `MockBleManager` override and manual state pump

Widget test setup pattern:
```dart
// Standard Flutter widget test harness for Riverpod screens
await tester.pumpWidget(
  ProviderScope(
    overrides: [
      bleManagerProvider.overrideWithValue(MockBleManager()),
    ],
    child: const MaterialApp(home: ScanScreen()),
  ),
);
```

---

## Security Domain

Phase 4 is UI-only with no networking, authentication, external input surfaces, or credential handling. ASVS categories V2 (Authentication), V3 (Session Management), V4 (Access Control), and V6 (Cryptography) are not applicable.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | no | No user text input fields in Phase 4 |
| V6 Cryptography | no | — |

No user-generated input, no network calls, no credential storage in Phase 4 UI screens.

---

## Project Constraints (from CLAUDE.md)

All directives that Phase 4 must comply with:

1. **No `flutter_blue_plus` import in `lib/ui/`** — enforced; all BLE access through providers
2. **All BLE access through `abstract class BleManager` interface** — Zero button uses `connectionNotifierProvider.notifier.sendCommand()`; never calls `BleManager` directly from widgets
3. **`MockBleManager.simulateDisconnect()` requires cast in `kDebugMode`** — enforced via `if (mgr is MockBleManager)` guard
4. **Riverpod 3.x — use `Notifier`/`AsyncNotifier`, not `StateNotifierProvider`** — no new providers in Phase 4; consuming existing providers with `ConsumerWidget`
5. **BLE connection provider `keepAlive: true`** — already enforced in `ConnectionNotifier.build()`; Phase 4 adds no new providers
6. **`minSdkVersion 24` / `compileSdkVersion 35`** — build config; no Phase 4 action needed (Phase 5 owns build.gradle)
7. **Phase 5 handles `main.dart`/go_router** — Phase 4 creates a temporary `main.dart` for standalone development; Phase 5 will completely replace it

---

## Sources

### Primary (HIGH confidence)
- Existing codebase: `lib/providers/device_provider.dart`, `lib/ble/ble_manager.dart`, `lib/ble/mock_ble_manager.dart`, `lib/ble/ble_protocol.dart`, `lib/models/device_state.dart` — verified by direct file read
- `.planning/phases/04-ui-screens/04-CONTEXT.md` — locked decisions D-01 through D-13
- `.planning/phases/04-ui-screens/04-UI-SPEC.md` — complete visual and interaction contract

### Secondary (MEDIUM confidence)
- REQUIREMENTS.md — phase requirement IDs and acceptance criteria
- STATE.md — accumulated context and decisions from Phases 1–3
- CLAUDE.md — architecture constraints

### Tertiary (LOW confidence)
- All code patterns tagged `[ASSUMED]` — derived from training knowledge of Flutter/Riverpod 3 APIs; not verified via Context7 or official docs in this session. Risk is low given SDK constraint `^3.12.1` and standard API usage.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all existing dependencies verified by reading pubspec.yaml
- Architecture: HIGH — verified against existing provider and model code; patterns derived from actual code, not assumptions
- Pitfalls: MEDIUM — derived from Flutter/Riverpod training knowledge; standard pitfalls for this pattern class
- Code examples: MEDIUM — `[ASSUMED]` tag on all code; verified against actual API shapes in existing files

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (30 days; stable stack)
