# Phase 4: UI Screens - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 5 (2 new screens + 1 modified provider + 1 new main.dart + 2 new test files)
**Analogs found:** 4 / 5 (no existing Flutter widget analogs; provider/model analogs are strong)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/ui/scan_screen.dart` | component (screen) | request-response + event-driven | `lib/ble/mock_ble_manager.dart` (stream consumption pattern) | partial — data flow match |
| `lib/ui/instrument_screen.dart` | component (screen) | streaming + request-response | `lib/providers/device_provider.dart` (StreamProvider consumption) | partial — data flow match |
| `lib/providers/device_provider.dart` | provider / service | request-response | self — add `sendCommand` method alongside existing `connect`/`disconnect` | exact — same file, same method shape |
| `main.dart` | config / entry-point | — | existing `test/providers/connection_notifier_test.dart` (ProviderScope + MockBleManager override) | role-match — same override wiring |
| `test/ui/scan_screen_test.dart` | test | request-response | `test/providers/connection_notifier_test.dart` | role-match |
| `test/ui/instrument_screen_test.dart` | test | streaming | `test/providers/instrument_data_provider_test.dart` | role-match |

---

## Pattern Assignments

### `lib/ui/scan_screen.dart` (component, request-response + event-driven)

**Analog:** `lib/providers/device_provider.dart` — provider consumption and action-dispatch patterns

**Imports pattern** — copy and adapt:
```dart
// lib/ui/scan_screen.dart — imports block
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/models/device_state.dart';   // ConnectionStatus, ScannedDevice
import 'package:inclinometer/providers/device_provider.dart'; // connectionNotifierProvider, scanResultsProvider
```

**Provider watch pattern** — from `lib/providers/device_provider.dart` lines 167–170:
```dart
// Derived provider re-reads from notifier on each state change.
// Same pattern in ScanScreen: ref.watch triggers rebuild on scan results change.
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(connectionNotifierProvider); // rebuild trigger on state change
  return ref.read(connectionNotifierProvider.notifier).scannedDevices;
});
```
In the widget: `ref.watch` for reactive data at top of `build()`; `ref.read(provider.notifier)` only inside `onPressed` callbacks (never `ref.watch` in callbacks).

**Action dispatch pattern** — from `lib/providers/device_provider.dart` lines 133–151:
```dart
// All actions delegate through the notifier, never call BleManager directly.
Future<void> startScan() async {
  await ref.read(bleManagerProvider).startScan();
}
Future<void> connect(String deviceId) async {
  await ref.read(bleManagerProvider).connect(deviceId);
}
```
In ScanScreen widget:
```dart
// FAB onPressed — ref.read, not ref.watch
onPressed: () => ref.read(connectionNotifierProvider.notifier).startScan(),
```

**State-driven UI pattern** — derive chip color/icon from `ConnectionStatus` enum.
`ConnectionStatus` is defined in `lib/models/device_state.dart` lines 4–13 (8 values: idle, scanning, connecting, connected, disconnecting, disconnected, error, reconnecting). Use exhaustive Dart 3 `switch` expression for chip color and label helpers.

**Device list filtering** — filter unnamed devices before `ListView.builder`:
```dart
final devices = ref.watch(scanResultsProvider)
    .where((d) => d.name.isNotEmpty)
    .toList();
```
`ScannedDevice` fields: `id` (String), `name` (String), `rssi` (int) — from `lib/models/device_state.dart` lines 42–63.

**RSSI icon mapping** — simple threshold function, no abstraction needed:
```dart
IconData _rssiIcon(int rssi) {
  if (rssi >= -60) return Icons.signal_wifi_4_bar;
  if (rssi >= -75) return Icons.network_wifi_3_bar;
  if (rssi >= -85) return Icons.network_wifi_2_bar;
  return Icons.network_wifi_1_bar;
}
```

---

### `lib/ui/instrument_screen.dart` (component, streaming)

**Analog:** `lib/providers/device_provider.dart` lines 176–178 — `StreamProvider<DeviceState?>` consumption

**Imports pattern**:
```dart
// lib/ui/instrument_screen.dart — imports block
import 'package:flutter/foundation.dart';       // kDebugMode (D-13)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/ble_protocol.dart';      // kCmdZeroX, kCmdZeroY
import 'package:inclinometer/ble/mock_ble_manager.dart';  // WP1-only cast for simulateDisconnect
import 'package:inclinometer/models/device_state.dart';   // DeviceState, ConnectionStatus
import 'package:inclinometer/providers/device_provider.dart';
// NOTE: mock_ble_manager.dart does NOT import flutter_blue_plus — no CLAUDE.md violation.
```

**StreamProvider consumption + stale detection** — from `lib/providers/device_provider.dart` lines 176–178:
```dart
// instrumentDataProvider emits DeviceState? — null is the stale sentinel (D-05/D-06).
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) {
  return ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});
```
In the widget:
```dart
final dataAsync = ref.watch(instrumentDataProvider);
// CRITICAL: hasValue distinguishes AsyncData(null) [stale] from AsyncLoading [not yet connected].
// Do NOT use valueOrNull == null alone — that conflates loading with disconnected (Pitfall 1).
final isStale = dataAsync.hasValue && dataAsync.value == null;
final deviceState = dataAsync.valueOrNull; // DeviceState? — null during load or stale
```

**Stale opacity pattern** — `AnimatedOpacity` manages its own implicit animation; no `StatefulWidget` needed:
```dart
AnimatedOpacity(
  opacity: isStale ? 0.40 : 1.0,
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeOut,
  child: _AngleReadoutBlock(...),
)
```

**Zero button enable/disable** — gate solely on `ConnectionStatus.connected` per D-12:
```dart
ElevatedButton(
  onPressed: status == ConnectionStatus.connected
      ? () => ref.read(connectionNotifierProvider.notifier).sendCommand(kCmdZeroX)
      : null,  // null = disabled (greyed out)
  child: const Text('Zero X'),
)
```
`kCmdZeroX = 0x01`, `kCmdZeroY = 0x02` — from `lib/ble/ble_protocol.dart` lines 11–12.

**Debug button with MockBleManager cast** — from `lib/ble/mock_ble_manager.dart` lines 108–113:
```dart
// simulateDisconnect() is NOT on BleManager interface — requires concrete cast.
void simulateDisconnect() {
  _stopTicker();
  if (!_statusController.isClosed) {
    _statusController.add(ConnectionStatus.disconnected);
  }
}
```
In widget (only in `kDebugMode`):
```dart
if (kDebugMode) ...[
  TextButton(
    onPressed: () {
      final mgr = ref.read(bleManagerProvider);
      if (mgr is MockBleManager) mgr.simulateDisconnect();
    },
    child: const Text('Sim. Disconnect'),
  ),
]
```

**Angle formatting helper** — helper function, no abstraction class:
```dart
String _formatAngle(double value) {
  final sign = value >= 0 ? '+' : '−'; // Unicode minus U+2212
  final abs = value.abs();
  return '$sign${abs.toStringAsFixed(2).padLeft(6, '0')}°';
  // Examples: +012.34°  −003.00°  +000.00°
  // padLeft(6, '0') pads "3.00" → "003.00" (NNN.NN format)
}
```

**Tabular numerals for angle readout** — per INST-07:
```dart
TextStyle(
  fontSize: 80,
  fontWeight: FontWeight.w700,
  fontFeatures: [FontFeature.tabularFigures()],
  fontFamily: 'monospace', // or omit; tabularFigures on system font is sufficient
)
```
`FontFeature` is in `dart:ui` — no import needed when using `package:flutter/material.dart`.

**Chip color helper** — exhaustive switch over all 8 `ConnectionStatus` values:
```dart
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
```

---

### `lib/providers/device_provider.dart` — `sendCommand` addition (provider, request-response)

**Analog:** existing `connect`, `disconnect`, `stopScan` methods in `lib/providers/device_provider.dart` lines 133–151. The new method follows exactly the same delegation pattern.

**Core pattern** — lines 144–151 (copy this shape verbatim):
```dart
/// Initiates connection to the device with [deviceId].
Future<void> connect(String deviceId) async {
  await ref.read(bleManagerProvider).connect(deviceId);
}

/// Disconnects from the currently connected device.
Future<void> disconnect() async {
  await ref.read(bleManagerProvider).disconnect();
}
```

**New method to add** (after `disconnect()`, before closing brace of `ConnectionNotifier`):
```dart
/// Sends a command byte to the instrument via [BleManager].
///
/// Used by Zero X / Zero Y buttons in InstrumentScreen.
/// Keeps [BleManager] access out of [lib/ui/] per CLAUDE.md architecture rule.
Future<void> sendCommand(int commandByte) async {
  await ref.read(bleManagerProvider).sendCommand(commandByte);
}
```
`BleManager.sendCommand(int commandByte)` exists at `lib/ble/ble_manager.dart` line 24.

---

### `main.dart` (config, entry-point)

**Analog:** `test/providers/connection_notifier_test.dart` lines 15–22 — `ProviderContainer` / `ProviderScope` with `bleManagerProvider.overrideWithValue(MockBleManager())`.

**Override wiring pattern** — from `test/providers/connection_notifier_test.dart` lines 15–21:
```dart
ProviderContainer buildContainer(MockBleManager mock) {
  final container = ProviderContainer(
    overrides: [bleManagerProvider.overrideWithValue(mock)],
  );
  addTearDown(container.dispose);
  addTearDown(mock.dispose);
  return container;
}
```
In `main.dart` use `ProviderScope` (widget tree) instead of `ProviderContainer` (test):
```dart
// main.dart (Phase 4 temporary — replaced entirely in Phase 5 by go_router version)
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

**Navigation** — inside `ScanScreen`, after `connect()` brings status to `ConnectionStatus.connected`, use `Navigator.push` (Phase 5 replaces with go_router). Do NOT auto-pop on disconnect (D-10).

---

### `test/ui/scan_screen_test.dart` and `test/ui/instrument_screen_test.dart` (test)

**Analog:** `test/providers/connection_notifier_test.dart` — full file pattern for imports, `ProviderContainer`/`ProviderScope`, `MockBleManager` injection, and `fakeAsync`.

**Imports pattern** — from `test/providers/connection_notifier_test.dart` lines 1–9:
```dart
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
```
For widget tests add:
```dart
import 'package:flutter/material.dart';
import 'package:inclinometer/ui/scan_screen.dart';    // or instrument_screen.dart
```

**ProviderScope widget test harness** — standard pattern (no existing analog in codebase yet; use this):
```dart
await tester.pumpWidget(
  ProviderScope(
    overrides: [
      bleManagerProvider.overrideWithValue(MockBleManager()),
    ],
    child: const MaterialApp(home: ScanScreen()),
  ),
);
```

**Container helper** — from `test/providers/connection_notifier_test.dart` lines 15–22:
```dart
ProviderContainer buildContainer(MockBleManager mock) {
  final container = ProviderContainer(
    overrides: [bleManagerProvider.overrideWithValue(mock)],
  );
  addTearDown(container.dispose);
  addTearDown(mock.dispose);
  return container;
}
```

**Flutter binding init** — from `test/providers/connection_notifier_test.dart` line 29:
```dart
setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
```
Required for `WakelockPlus` platform channel calls invoked inside `ConnectionNotifier`.

---

## Shared Patterns

### Provider Access Rule (CLAUDE.md enforcement)
**Source:** `lib/ble/ble_manager.dart` lines 1–26; `lib/providers/device_provider.dart` lines 21–23
**Apply to:** All files in `lib/ui/`

Never import `flutter_blue_plus` or call `BleManager` methods directly from `lib/ui/`. All actions go through `connectionNotifierProvider.notifier`. The only permitted exception is the `kDebugMode` cast to `MockBleManager` for `simulateDisconnect()`, which does not involve `flutter_blue_plus`.

```dart
// CORRECT — in widget onPressed:
ref.read(connectionNotifierProvider.notifier).startScan()

// WRONG — direct BleManager access from UI (CLAUDE.md violation):
ref.read(bleManagerProvider).startScan()
```

### ref.watch vs ref.read rule
**Source:** `lib/providers/device_provider.dart` lines 55, 135, 144
**Apply to:** Both screen widgets

```dart
// ref.watch — top of build(), reactive data (triggers rebuilds):
final status = ref.watch(connectionNotifierProvider);
final dataAsync = ref.watch(instrumentDataProvider);
final devices = ref.watch(scanResultsProvider);

// ref.read — inside callbacks only (no rebuild needed):
onPressed: () => ref.read(connectionNotifierProvider.notifier).startScan(),
```

### MockBleManager dispose pattern
**Source:** `test/providers/connection_notifier_test.dart` lines 19–21
**Apply to:** All test files

```dart
addTearDown(container.dispose);
addTearDown(mock.dispose);
```
`MockBleManager.dispose()` closes all three stream controllers — from `lib/ble/mock_ble_manager.dart` lines 116–122.

### ConnectionStatus exhaustive switch
**Source:** `lib/models/device_state.dart` lines 4–13 (all 8 enum values)
**Apply to:** `scan_screen.dart`, `instrument_screen.dart` chip color helpers

All 8 values must be covered: `idle`, `scanning`, `connecting`, `connected`, `disconnecting`, `disconnected`, `error`, `reconnecting`. Dart 3 exhaustive switch enforces this at compile time.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/ui/scan_screen.dart` | component | request-response | No existing Flutter widget files in `lib/ui/` — project has no screen widgets yet |
| `lib/ui/instrument_screen.dart` | component | streaming | Same — first screen widgets in project |

For these files the RESEARCH.md code examples (tagged `[ASSUMED]`) are the best available reference, combined with the existing provider/model API shapes confirmed by reading the source files above.

---

## Metadata

**Analog search scope:** `lib/ble/`, `lib/models/`, `lib/providers/`, `test/`
**Files scanned:** 7 source files read in full
**Pattern extraction date:** 2026-06-05
