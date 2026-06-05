---
phase: 04-ui-screens
verified: 2026-06-05T00:00:00Z
status: human_needed
score: 13/13 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Launch app on Android emulator or device, scan for mock device, tap to connect, verify InstrumentScreen renders angle values and battery indicator visually"
    expected: "InstrumentScreen shows large angle readouts (80sp), battery icon and percentage, connection chip in AppBar, Zero X and Zero Y buttons"
    why_human: "Visual layout, font rendering, and widget sizing cannot be fully verified by grep or headless widget tests alone"
  - test: "Tap 'Sim. Disconnect' debug button in InstrumentScreen AppBar while connected"
    expected: "Angle readout fades to ~40% opacity, DISCONNECTED label appears in red below the readout, connection chip turns red"
    why_human: "AnimatedOpacity transition is verified in widget tests but visual smoothness and label legibility require a running app"
  - test: "Verify FAB is absent when app is in connecting/connected/disconnecting/reconnecting states on a real device"
    expected: "FAB not visible in those states; only visible when idle, scanning, disconnected, or error"
    why_human: "State transitions through the connecting → connected chain involve real timing that headless tests approximate with pump(Duration)"
---

# Phase 4: UI Screens Verification Report

**Phase Goal:** A running app shows the scan screen and instrument screen with all data states and navigation paths working end-to-end against the mock layer
**Verified:** 2026-06-05
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ScanScreen renders with a FAB, AppBar scan-state chip, and device list | VERIFIED | `lib/ui/scan_screen.dart` lines 43–91: Scaffold with AppBar (Chip at bottom), FAB with `showFab` guard, `_buildBody` delegate |
| 2 | FAB icon is `bluetooth_searching` when idle and `stop` when scanning | VERIFIED | Line 87: `Icon(isScanning ? Icons.stop : Icons.bluetooth_searching)` — test SCAN-01 passes |
| 3 | Device list filters unnamed devices and shows name + RSSI icon + dBm for named devices | VERIFIED | Lines 19–21: `.where((d) => d.name.isNotEmpty).toList()`; ListTile at lines 149–173 with icon, name, dBm trailing — test SCAN-03 passes |
| 4 | Tapping a list tile calls `connectionNotifierProvider.notifier.connect(device.id)` | VERIFIED | Lines 164–169: `onTap` delegates to `ref.read(connectionNotifierProvider.notifier).connect(device.id)` — test SCAN-05 passes |
| 5 | When `connectionNotifierProvider` reaches `connected`, `Navigator.push` brings `InstrumentScreen` into view | VERIFIED | Lines 26–33: `ref.listen` pushes `InstrumentScreen` when `next == ConnectionStatus.connected && prev != connected` — test INST-01 passes |
| 6 | `InstrumentScreen` shows `angle_x` and `angle_y` at 80sp/w700 with tabular figures | VERIFIED | `lib/ui/instrument_screen.dart` line 175–180: `fontSize: 80`, `fontWeight: FontWeight.w700`, `fontFeatures: [FontFeature.tabularFigures()]` — test INST-02+03 and INST-07 pass |
| 7 | Battery icon + percentage shown in AppBar | VERIFIED | Lines 41–49: `if (deviceState != null)` renders battery icon and `'${deviceState.battery}%'` — test INST-04 passes |
| 8 | Connection chip with correct color always visible in AppBar (CONN-04) | VERIFIED | Lines 51–59: `Chip` with `_chipColor(status)` and `_chipLabel(status)` unconditionally rendered — test CONN-04 passes |
| 9 | Zero X and Zero Y buttons inline with angle rows; disabled when not connected | VERIFIED | Lines 95–99, 103–109: `onZero` is `null` unless `status == ConnectionStatus.connected`; passed to `_AngleRow.onZero` — test INST-05/06 disabled state passes |
| 10 | Angle readout fades to 40% opacity over 300ms when `instrumentDataProvider` emits null | VERIFIED | Lines 86–89: `AnimatedOpacity(opacity: isStale ? 0.40 : 1.0, duration: Duration(milliseconds: 300), curve: Curves.easeOut)` — stale opacity test passes |
| 11 | DISCONNECTED label appears below faded readout when stale | VERIFIED | Lines 114–125: `if (isStale)` renders `Text('DISCONNECTED')` — test verifies `findsOneWidget` after null stream event |
| 12 | Debug "Sim. Disconnect" button visible only in `kDebugMode` | VERIFIED | Lines 64–74: `if (kDebugMode)` guards `TextButton` that calls `connectionNotifierProvider.notifier.debugSimulateDisconnect()` |
| 13 | `ConnectionNotifier.sendCommand(int commandByte)` delegates to `BleManager.sendCommand` | VERIFIED | `lib/providers/device_provider.dart` lines 176–182: `Future<void> sendCommand(int commandByte) async { await ref.read(bleManagerProvider).sendCommand(commandByte); }` |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/ui/scan_screen.dart` | ScanScreen ConsumerWidget | VERIFIED | 229 lines; `class ScanScreen extends ConsumerWidget`; no `flutter_blue_plus` import |
| `lib/ui/instrument_screen.dart` | InstrumentScreen ConsumerWidget with `_AngleRow` | VERIFIED | 252 lines; `class InstrumentScreen extends ConsumerWidget`; `class _AngleRow extends StatelessWidget`; `FontFeature.tabularFigures()` present |
| `lib/providers/device_provider.dart` | `sendCommand` method on `ConnectionNotifier` | VERIFIED | Lines 176–182: `Future<void> sendCommand(int commandByte) async` present; `debugSimulateDisconnect()` also added (architecture improvement) |
| `test/ui/scan_screen_test.dart` | Widget tests for SCAN-01 through SCAN-05 and INST-01 | VERIFIED | 8 tests, all named by requirement ID, all pass |
| `test/ui/instrument_screen_test.dart` | Widget tests for INST-02 through INST-07 and CONN-04 | VERIFIED | 9 tests, all named by requirement ID, all pass |
| `main.dart` | Phase 4 standalone entry point with `MockBleManager` override | VERIFIED | Contains `bleManagerProvider.overrideWithValue(MockBleManager())` and `home: const ScanScreen()` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scan_screen.dart` | `connectionNotifierProvider` | `ref.watch` / `ref.read(notifier)` | WIRED | Line 18: `ref.watch(connectionNotifierProvider)`; Lines 77–86: `ref.read(notifier).stopScan()` / `startScan()` |
| `scan_screen.dart` | `scanResultsProvider` | `ref.watch` | WIRED | Lines 19–21: `ref.watch(scanResultsProvider).where(...).toList()` |
| `instrument_screen.dart` | `instrumentDataProvider` | `ref.watch` | WIRED | Line 22: `ref.watch(instrumentDataProvider)` |
| `instrument_screen.dart` | `connectionNotifierProvider.notifier.sendCommand` | `ElevatedButton.onPressed` | WIRED | Lines 96–99, 103–109: `sendCommand(kCmdZeroX)` / `sendCommand(kCmdZeroY)` |
| `instrument_screen.dart` | `MockBleManager.simulateDisconnect` | `kDebugMode` + notifier delegation | WIRED | Line 68: calls `debugSimulateDisconnect()` on notifier; notifier does the `is MockBleManager` cast at line 191 of `device_provider.dart` — cleaner than plan's direct cast |
| `test/ui/scan_screen_test.dart` | `ScanScreen` | `ProviderScope` + `pumpWidget` | WIRED | Lines 28–33 harness; `pumpWidget` calls throughout |
| `test/ui/instrument_screen_test.dart` | `InstrumentScreen` | `ProviderScope` + `pumpWidget` | WIRED | Lines 27–44 `buildInstrumentApp` harness; `pumpWidget` throughout |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `scan_screen.dart` | `devices` (scan results) | `scanResultsProvider` → `ConnectionNotifier.scannedDevices` → `manager.scanResults` stream | Yes — `MockBleManager.scanResults` emits real `ScannedDevice` events; tests confirm `ListTile` and dBm text appear | FLOWING |
| `instrument_screen.dart` | `dataAsync` (angle + battery) | `instrumentDataProvider` → `ConnectionNotifier.instrumentStream` → `manager.statePackets` → `StatePacket.parse` | Yes — `MockBleManager.statePackets` emits parsed bytes; tests confirm `'+012.34°'` and `'75%'` render | FLOWING |
| `instrument_screen.dart` | `status` (connection state) | `connectionNotifierProvider` → `manager.connectionStatus` stream | Yes — `MockBleManager.connectionStatus` emits real state transitions; CONN-04 tests confirm chip labels | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `flutter test test/ui/` passes (17 tests) | `flutter test test/ui/ --reporter=expanded` | 17 passed, 0 failed | PASS |
| Full suite regression check (40 tests) | `flutter test --reporter=expanded` | 40 passed, 0 failed | PASS |
| Static analysis — no issues | `flutter analyze lib/ui/instrument_screen.dart lib/ui/scan_screen.dart lib/providers/device_provider.dart` | "No issues found!" | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SCAN-01 | 04-02, 04-04 | User can initiate and stop a BLE scan via a scan button | SATISFIED | FAB present; `startScan`/`stopScan` wired; test SCAN-01 passes |
| SCAN-02 | 04-02, 04-04 | Scan screen displays a live list of discovered devices with name and RSSI | SATISFIED | `ListView.builder` with name + dBm trailing; test SCAN-02 passes |
| SCAN-03 | 04-02, 04-04 | Device list filtered to named devices only | SATISFIED | `.where((d) => d.name.isNotEmpty)` in `build()`; test SCAN-03 passes |
| SCAN-04 | 04-02, 04-04 | Scan screen displays current scan state at all times | SATISFIED | `Chip` in `AppBar.bottom` with exhaustive `_chipLabel`; test SCAN-04 passes |
| SCAN-05 | 04-02, 04-04 | User can tap a device to initiate a connection | SATISFIED | `ListTile.onTap` calls `connect(device.id)`; test SCAN-05 passes |
| INST-01 | 04-02, 04-04 | Instrument screen shown after successful connection | SATISFIED | `ref.listen` pushes `InstrumentScreen` on `connected`; test INST-01 passes |
| INST-02 | 04-03, 04-04 | Instrument screen displays `angle_x` in degrees as large float | SATISFIED | `_AngleRow` with `fontSize: 80`; `_formatAngle` format `+NNN.NN°`; test INST-02 passes |
| INST-03 | 04-03, 04-04 | Instrument screen displays `angle_y` in degrees as large float | SATISFIED | Same `_AngleRow` for Y axis; test INST-03 passes |
| INST-04 | 04-03, 04-04 | Instrument screen displays battery level as percentage | SATISFIED | AppBar actions: `'${deviceState.battery}%'`; test INST-04 passes |
| INST-05 | 04-01, 04-03, 04-04 | User can trigger Zero X (sends ZERO_X command) | SATISFIED | `sendCommand(kCmdZeroX)` wired; `ConnectionNotifier.sendCommand` delegates to `BleManager`; test INST-05 passes |
| INST-06 | 04-01, 04-03, 04-04 | User can trigger Zero Y (sends ZERO_Y command) | SATISFIED | `sendCommand(kCmdZeroY)` wired; test INST-06 passes |
| INST-07 | 04-03, 04-04 | Angle values rendered with tabular numerals | SATISFIED | `fontFeatures: [FontFeature.tabularFigures()]` in `_AngleRow` TextStyle; test INST-07 passes |
| CONN-04 | 04-03, 04-04 | Connection state chip always visible on instrument screen | SATISFIED | `Chip` unconditionally in `AppBar.actions`; tests CONN-04 (x2) pass |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/ui/instrument_screen.dart` | 62–68 | Plan specified `if (mgr is MockBleManager) mgr.simulateDisconnect()` directly in UI; implementation routes through `debugSimulateDisconnect()` on notifier | INFO — deviation from plan, but architecturally superior | Stronger CLAUDE.md compliance: `MockBleManager` import is absent from `lib/ui/` entirely |

No `TBD`, `FIXME`, `XXX`, placeholder strings, or empty stub returns found in modified files.

### Human Verification Required

#### 1. Visual Rendering on Device

**Test:** Launch the app on an Android emulator or physical device. Scan, connect to the mock "Inclinometer" device, observe InstrumentScreen.
**Expected:** 80sp angle readout in ±NNN.NN° format is legible; battery icon and percentage appear in AppBar; connection chip shows "Connected" in green; Zero X and Zero Y buttons are enabled; font rendering uses tabular figures (digits do not shift horizontally as values change).
**Why human:** Flutter widget tests validate widget-tree properties but cannot verify visual font rendering, pixel-level overflow on real screen densities, or perceived readability.

#### 2. Stale-Data Animation on Real Device

**Test:** While connected, tap "Sim. Disconnect" in the AppBar debug button.
**Expected:** Angle readout smoothly fades to ~40% opacity over 300ms; "DISCONNECTED" label appears in red below the readout; connection chip turns red with label "Disconnected"; Disconnect button disappears.
**Why human:** AnimatedOpacity target and duration are confirmed by widget test, but the visual smoothness of the transition and legibility of the DISCONNECTED label require a running app.

#### 3. FAB Visibility in Connecting / Connected States

**Test:** Tap a device to connect. Observe the FAB during the ~300ms connecting state and after reaching connected.
**Expected:** FAB disappears while connecting and while connected; it reappears after disconnecting.
**Why human:** State transitions happen in ~300ms timing windows; headless tests use `pump(Duration)` to approximate but do not verify real-time UI responsiveness.

### Gaps Summary

No gaps. All 13 requirement IDs have passing widget tests and are verified in the codebase. One notable deviation from plan 04-03 (simulateDisconnect implementation) was an architectural improvement, not a regression.

---

_Verified: 2026-06-05_
_Verifier: Claude (gsd-verifier)_
