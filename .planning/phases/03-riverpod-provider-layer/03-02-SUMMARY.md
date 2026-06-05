---
phase: 03-riverpod-provider-layer
plan: "02"
subsystem: providers
tags: [riverpod, connection-state-machine, wakelock, stream-provider, null-sentinel]
completed: "2026-06-05"
duration_minutes: 10
tasks_completed: 2
tasks_total: 2
requirements_satisfied: [CONN-01, CONN-02, CONN-03, CONN-05, CONN-06, SYS-01]

dependency_graph:
  requires:
    - 03-01 (ConnectionStatus.reconnecting enum value, wakelock_plus dependency)
  provides:
    - connectionNotifierProvider (ConnectionNotifier state machine)
    - scanResultsProvider (derived scan results list)
    - instrumentDataProvider (StreamProvider<DeviceState?> with null sentinel)
  affects:
    - Phase 4 UI screens (consume all three providers)
    - Phase 5 wiring (ProviderScope.overrides, go_router refreshListenable)

tech_stack:
  added: []
  patterns:
    - Notifier<ConnectionStatus> with StreamSubscription in build()
    - ref.keepAlive() in build() for BLE session persistence
    - StreamController<T?>.broadcast() for multi-subscriber null sentinel stream
    - isClosed guard before every emit (established from MockBleManager CR-02)
    - state = state; reassignment to trigger Provider rebuilds (Pitfall-1 resolved)
    - try/catch inside statePackets listener (Pitfall-5 / T-03-02 / T-03-03)

key_files:
  created: []
  modified:
    - lib/providers/device_provider.dart

key_decisions:
  - instrumentDataProvider uses StreamProvider<DeviceState?> not StreamProvider<StatePacket?> — StatePacket.parse() returns DeviceState (plan interface spec deviation auto-fixed)
  - state = state; reassignment used for scanResultsProvider rebuild trigger (ref.notifyListeners() not available in Riverpod 3.3.1 Notifier — A1 resolved)
  - WakelockPlus.disable() also called in ref.onDispose safety handler for unexpected teardown

metrics:
  duration: 10 minutes
  completed_date: "2026-06-05"
---

# Phase 3 Plan 02: Provider Layer Implementation Summary

**One-liner:** Full Riverpod provider layer in device_provider.dart — ConnectionNotifier state machine with keepAlive, wakelock, null sentinel, and auto-reconnect stub, plus scanResultsProvider and instrumentDataProvider.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Implement ConnectionNotifier with state machine, wakelock, null sentinel | c9b0e1c | lib/providers/device_provider.dart |
| 2 | Declare scanResultsProvider and instrumentDataProvider | c9b0e1c | lib/providers/device_provider.dart |

## Outcome

`lib/providers/device_provider.dart` now exports the full provider layer for Phase 4 UI consumption:

1. **`connectionNotifierProvider`** — `NotifierProvider<ConnectionNotifier, ConnectionStatus>` owning the complete 8-state machine (idle → scanning → connecting → connected → disconnecting → disconnected → error → reconnecting). Keeps itself alive via `ref.keepAlive()` in `build()` to survive navigation.

2. **`scanResultsProvider`** — `Provider<List<ScannedDevice>>` derived from `ConnectionNotifier.scannedDevices`. Uses `ref.watch(connectionNotifierProvider)` as a rebuild trigger; actual list held in notifier.

3. **`instrumentDataProvider`** — `StreamProvider<DeviceState?>` backed by `ConnectionNotifier._packetController`. Null values indicate stale data after disconnect/error (D-05/D-06).

Key invariants implemented:
- `_autoReconnectEnabled = false` stub with `reconnecting` state transition (D-07/D-08)
- `WakelockPlus.enable()` on connected; `WakelockPlus.disable()` on disconnected/error and onDispose (D-09, SYS-01)
- `isClosed` guard on every `_packetController.add()` call (T-03-05)
- `try/catch` around `StatePacket.parse()` swallows parse errors without rethrowing (T-03-02, T-03-03)

## Verification

- `flutter analyze lib/providers/device_provider.dart` — no issues
- `flutter test` — all 10 tests pass (5 protocol + 5 mock BLE manager)
- `grep -c 'flutter_blue_plus'` → 0
- `grep -c '_autoReconnectEnabled = false'` → 1
- `grep -c '_packetController.add(null)'` → 1

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] instrumentDataProvider type corrected from StatePacket? to DeviceState?**
- **Found during:** Task 1 — flutter analyze reported `The argument type 'DeviceState' can't be assigned to the parameter type 'StatePacket?'`
- **Issue:** The plan's interface spec listed `StatePacket.parse` return type as `StatePacket`, but the actual implementation in `ble_protocol.dart` returns `DeviceState`. The `StreamController` and `instrumentDataProvider` types were written as `StreamProvider<StatePacket?>` per the plan spec.
- **Fix:** Changed `StreamController<StatePacket?>.broadcast()` to `StreamController<DeviceState?>.broadcast()`, getter return type to `Stream<DeviceState?>`, and `instrumentDataProvider` to `StreamProvider<DeviceState?>`.
- **Files modified:** lib/providers/device_provider.dart
- **Commit:** c9b0e1c

## Known Stubs

- `_autoReconnectEnabled = false` — auto-reconnect logic is written but permanently disabled in WP1. WP2 activates by setting to `true`. This is intentional per D-07 and does not prevent the plan goal (Phase 4 UI can exercise all states via MockBleManager.simulateDisconnect()).

## Threat Flags

None — all threat model mitigations from the plan's STRIDE register were implemented:
- T-03-02/T-03-03: try/catch inside statePackets listener
- T-03-05: isClosed guard on every emit

## Self-Check: PASSED

- lib/providers/device_provider.dart — exists, 156 lines added
- Commit c9b0e1c exists in git log
- `flutter analyze` — no issues
- `flutter test` — all 10 tests pass
- File contains `static const bool _autoReconnectEnabled = false;`
- File contains `_packetController.add(null)`
- File contains `WakelockPlus.enable()` and `WakelockPlus.disable()`
- File does NOT contain `flutter_blue_plus`
- File does NOT contain `StateNotifierProvider`
