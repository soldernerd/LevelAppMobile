---
phase: 03-riverpod-provider-layer
reviewed: 2026-06-05T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - lib/models/device_state.dart
  - lib/providers/device_provider.dart
  - test/providers/connection_notifier_test.dart
  - test/providers/instrument_data_provider_test.dart
  - pubspec.yaml
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-06-05T00:00:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Five files were reviewed covering the Riverpod provider layer, BLE models, and associated tests. The implementation is largely coherent and correctly addresses the keepAlive, broadcast-stream, and stale-data requirements from CLAUDE.md. However, two correctness blockers were found: a missing package dependency that will cause build failure, and a race condition in `instrumentDataProvider` that can silently miss the first null sentinel. Three additional warnings cover a keepAlive leak, a scan-results rebuild fragility, and an untested state-machine transition.

---

## Critical Issues

### CR-01: `flutter_blue_plus` and `mock_ble_manager`-depended packages absent from `pubspec.yaml`

**File:** `pubspec.yaml:30-39`
**Issue:** `pubspec.yaml` lists only `flutter_riverpod` and `wakelock_plus` as runtime dependencies. The production and test code import `package:inclinometer/ble/mock_ble_manager.dart`, which itself imports `package:inclinometer/ble/ble_manager.dart`. While those are internal package paths, any WP2 swap to `flutter_blue_plus` requires it to be declared. More critically, `go_router` (required by CLAUDE.md architecture and referenced in the roadmap) is entirely absent from `pubspec.yaml`. `permission_handler` is also absent despite being listed as a required stack package in CLAUDE.md. The app as declared will fail to compile when those packages are referenced.

**Fix:** Add all stack packages declared in CLAUDE.md to `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^3.3.1
  flutter_blue_plus: ^2.3.5
  permission_handler: ^12.0.3
  go_router: ^17.3.0
  wakelock_plus: ^1.6.1
```

---

### CR-02: `instrumentDataProvider` subscribes to a broadcast stream that may already have emitted the null sentinel before the subscription is established

**File:** `lib/providers/device_provider.dart:176-178`
**Issue:** `instrumentDataProvider` is a `StreamProvider` that calls `ref.watch(connectionNotifierProvider.notifier).instrumentStream`. `instrumentStream` is a **broadcast** stream. If `ConnectionNotifier` has already been built and a disconnect/null sentinel was emitted before the `StreamProvider` subscribes (e.g., `connectionNotifierProvider` was read first, a disconnect happened before `instrumentDataProvider` was first read), the null sentinel is silently dropped. The `StreamProvider` will then be stuck in `AsyncLoading` instead of `AsyncData(null)`, meaning the UI will never see the stale-data indicator. Broadcast streams do not replay past events to late subscribers — this is the PITFALL-3 noted in the tests but not guarded against at the provider level.

**Fix:** Use a `BehaviorSubject` (from `rxdart`) or switch `_packetController` to a stream with replay for the last event. Alternatively, seed the `StreamProvider` with an initial value:
```dart
final instrumentDataProvider = StreamProvider<DeviceState?>((ref) async* {
  // Yield null immediately so the provider never stalls in AsyncLoading.
  yield null;
  yield* ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});
```
This guarantees the stale-data indicator is active from the moment the provider is created, and avoids the silent race.

---

## Warnings

### WR-01: `ref.keepAlive()` link is closed in `onDispose`, making keepAlive self-defeating

**File:** `lib/providers/device_provider.dart:52-53`
**Issue:** `build()` calls `final link = ref.keepAlive()` and then immediately registers `ref.onDispose(link.close)`. Calling `link.close()` in `onDispose` cancels the keepAlive. But `onDispose` fires when the provider *is being disposed*, so the keepAlive was already ineffective. The intended semantics of `keepAlive` is that the provider is never auto-disposed as long as the link is open. Registering `link.close` in `onDispose` is a no-op at best and confusing at worst — it cannot prevent the disposal that already triggered `onDispose`. The net result is that `keepAlive` offers no protection; if all listeners drop, Riverpod may dispose the notifier and tear down the BLE session.

**Fix:** Remove `ref.onDispose(link.close)`. If intentional teardown is desired in a specific condition (e.g., explicit logout), call `link.close()` at that point instead. The `onDispose` cleanup for subscriptions and `_packetController` is correct and should be kept:
```dart
@override
ConnectionStatus build() {
  final link = ref.keepAlive(); // hold open; never close via onDispose
  // ... subscriptions ...
  ref.onDispose(() {
    statusSub.cancel();
    scanSub.cancel();
    packetSub.cancel();
    _packetController.close();
    WakelockPlus.disable().catchError((_) {});
    // Do NOT call link.close() here
  });
  return ConnectionStatus.idle;
}
```

---

### WR-02: `scanResultsProvider` uses `state = state` to force a rebuild — fragile and relies on undocumented Riverpod internals

**File:** `lib/providers/device_provider.dart:67-68`
**Issue:** When a new scanned device is found, the code does `state = state` with a comment acknowledging this relies on Riverpod 3.3.1 behaviour. However, in Riverpod 3.x, a `Notifier` performs equality checking before triggering rebuilds. If `ConnectionStatus` is an enum (value-equal by identity), `state = state` with the same value will be deduplicated and may **not** trigger a rebuild, meaning `scanResultsProvider` will not update. This is a known pitfall — the comment itself cites "RESOLVED: A1" but the resolution relies on `state = state` triggering a rebuild, which is not guaranteed by the Riverpod public API for equal values.

**Fix:** Move `_scannedDevices` out of the `Notifier` and into its own `Notifier<List<ScannedDevice>>`. Alternatively, model `ConnectionNotifier`'s state as a compound object (e.g., a `ConnectionState` record holding `ConnectionStatus` + a scan-result counter) so a genuine state change occurs when devices are added:
```dart
// Quick workaround: track device count as part of state
// Better: dedicated ScanResultsNotifier
```

---

### WR-03: `connect()` test verifies `connecting → connected` but never tests the `scanning → connecting` guard in the state machine

**File:** `test/providers/connection_notifier_test.dart:92-116`
**Issue:** The test at line 92 (`connected → disconnected after disconnect`) calls `connect()` directly without calling `startScan()` first. This means the state machine is exercised in the sequence `idle → connecting → connected → disconnected`, skipping the `scanning` state. If `ConnectionNotifier` or `MockBleManager` adds a guard that requires `scanning` before `connecting`, this test will silently pass in WP1 but fail in WP2 when real BLE enforces the scan-first requirement. The test coverage does not represent the real expected usage sequence.

**Fix:** Add a test that enforces the full expected sequence: `startScan()` → `connect()` → `disconnect()`. The existing test at line 57 does this partially but does not cover the complete disconnect path. A dedicated test for the full happy path would catch regression.

---

## Info

### IN-01: `ble_protocol.dart` UUID placeholders will cause GATT discovery failure in WP2

**File:** `lib/ble/ble_protocol.dart:6-8`
**Issue:** `kServiceUuid`, `kStateCharUuid`, and `kCommandCharUuid` all contain literal placeholder tokens `XXXX`, `YYYY`, `ZZZZ`. These are valid-looking strings that will silently fail GATT discovery in WP2 because the UUIDs will not match any real service. There is no compile-time or runtime guard (e.g., an `assert` that UUIDs match a UUID regex) to catch this before WP2 integration.

**Fix:** Add a comment or `assert` at the point of use to make the placeholder status explicit:
```dart
// TODO(WP2): Replace XXXX/YYYY/ZZZZ with real firmware UUIDs before WP2.
assert(!kServiceUuid.contains('XXXX'), 'Replace placeholder UUIDs before WP2');
```

---

### IN-02: `ignore: unused_import` suppression in test file masks a real unused import

**File:** `test/providers/instrument_data_provider_test.dart:12`
**Issue:** `ble_protocol.dart` is imported and immediately suppressed with `// ignore: unused_import`. The comment says it is "imported for DeviceState type assertions in comments", but `DeviceState` is actually provided by `device_state.dart` (already imported via `device_provider.dart`). This import adds noise and the suppression comment may mask a real linter finding. Unused imports in test files reduce clarity.

**Fix:** Remove the `ble_protocol.dart` import from this test file entirely.

---

_Reviewed: 2026-06-05T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
