---
phase: 03-riverpod-provider-layer
plan: "03"
subsystem: providers/tests
tags: [riverpod, test, connection-state-machine, null-sentinel, wakelock, fake-async]
completed: "2026-06-05"
duration_minutes: 15
tasks_completed: 2
tasks_total: 2
requirements_satisfied: [CONN-01, CONN-02, CONN-03, CONN-05, CONN-06, SYS-01]

dependency_graph:
  requires:
    - 03-02 (ConnectionNotifier, scanResultsProvider, instrumentDataProvider)
  provides:
    - test/providers/connection_notifier_test.dart (CONN-01, CONN-02, CONN-03, CONN-06)
    - test/providers/instrument_data_provider_test.dart (CONN-05, SYS-01)
  affects:
    - Phase 4 regression harness (13 provider tests already green before UI is built)

tech_stack:
  added: []
  patterns:
    - flutter_test + TestWidgetsFlutterBinding.ensureInitialized() for wakelock compatibility
    - ProviderContainer.overrides with bleManagerProvider.overrideWithValue(MockBleManager)
    - fakeAsync + elapse + flushMicrotasks for deterministic async BLE simulation
    - container.listen() to collect state transitions before triggering them
    - WakelockPlus.enable/disable wrapped with .catchError for test-env channel errors

key_files:
  created:
    - test/providers/connection_notifier_test.dart
    - test/providers/instrument_data_provider_test.dart
  modified:
    - lib/providers/device_provider.dart (WakelockPlus.enable/disable wrapped with .catchError)

key_decisions:
  - flutter_test used instead of package:test to allow TestWidgetsFlutterBinding.ensureInitialized() for wakelock compatibility
  - WakelockPlus.enable/disable wrapped with .catchError (not try/catch) because the platform channel exception arrives asynchronously — synchronous try/catch was insufficient
  - instrumentDataProvider stream subscribed via connectionNotifierProvider.notifier.instrumentStream (not via provider stream) to avoid async gap issues in fakeAsync

metrics:
  duration: 15 minutes
  completed_date: "2026-06-05"
---

# Phase 3 Plan 03: Provider Test Suite Summary

**One-liner:** Provider test suite with 13 new tests (8 + 5) proving all 6 Phase 3 requirements via ProviderContainer + MockBleManager in fakeAsync, with wakelock compatibility via TestWidgetsFlutterBinding.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | connection_notifier_test.dart — CONN-01/02/03/06 | 9829baa | test/providers/connection_notifier_test.dart, lib/providers/device_provider.dart |
| 2 | instrument_data_provider_test.dart — CONN-05/SYS-01 | 90f8f0c | test/providers/instrument_data_provider_test.dart |

## Outcome

Two provider test files covering all 6 Phase 3 requirements, all 23 tests pass (10 existing + 13 new):

**`test/providers/connection_notifier_test.dart`** — 8 tests:
- State machine: idle → scanning → connecting → connected → disconnected
- `containsAllInOrder([connecting, connected])` assertion confirmed
- disconnect() and simulateDisconnect() both reach disconnected
- Auto-reconnect stub: state is disconnected (not reconnecting) after simulateDisconnect
- `ConnectionStatus.reconnecting` enum value confirmed present
- `scanResultsProvider` accumulates devices during scan

**`test/providers/instrument_data_provider_test.dart`** — 5 tests:
- `DeviceState` values emitted during connected period
- Null sentinel emitted after simulateDisconnect (`collected.contains(null)` assertion)
- instrumentDataProvider initial state is AsyncLoading or AsyncData(null)
- SYS-01 observable proxy: connected state reached (WakelockPlus.enable called)
- SYS-01 observable proxy: disconnected state reached (WakelockPlus.disable called)

## Verification

- `flutter test test/providers/` — 13/13 tests pass
- `flutter test` — 23/23 total tests pass (10 existing + 13 new)
- `flutter analyze` — no issues
- `grep -c 'WakelockPlus.enable' lib/providers/device_provider.dart` → 1

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] WakelockPlus.catchError wrapper required (not try/catch)**
- **Found during:** Task 1 verification
- **Issue:** `WakelockPlus.enable/disable` returns a `Future<void>` where the platform channel error arrives asynchronously. Synchronous try/catch catches the call setup but not the channel response — causing `PlatformException(channel-error)` to propagate outside the try/catch boundary and fail tests.
- **Fix:** Replaced `try { WakelockPlus.enable(); } catch (_) {}` with `WakelockPlus.enable().catchError((_) {})` in all three call sites in `_handleStatusEvent` and `onDispose`. Also replaced test imports from `package:test/test.dart` with `package:flutter_test/flutter_test.dart` and added `setUpAll(TestWidgetsFlutterBinding.ensureInitialized)` to initialize the binding.
- **Files modified:** lib/providers/device_provider.dart
- **Commits:** 9829baa

## Known Stubs

None — all tests are fully wired. The `_autoReconnectEnabled = false` stub in device_provider.dart is intentional (WP1 constraint) and explicitly tested (the "no reconnecting state" assertion).

## Threat Flags

None — no new network endpoints, auth paths, or trust boundaries introduced by test files.

## Self-Check: PASSED

- test/providers/connection_notifier_test.dart — exists, 8 tests
- test/providers/instrument_data_provider_test.dart — exists, 5 tests
- Commit 9829baa exists in git log
- Commit 90f8f0c exists in git log
- `flutter test test/providers/` — all 13 pass
- `flutter test` — all 23 pass
- `flutter analyze` — no issues
- Files contain `ProviderContainer` with `bleManagerProvider.overrideWithValue`
- Files contain `containsAllInOrder([ConnectionStatus.connecting, ConnectionStatus.connected])`
- Files contain `collected.contains(null)` null sentinel assertion
- Files contain `ConnectionStatus.reconnecting` enum value assertion
- Files do NOT import `flutter_blue_plus`
