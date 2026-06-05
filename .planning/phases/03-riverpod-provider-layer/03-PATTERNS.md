# Phase 3: Riverpod Provider Layer - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 4 (2 modified, 2 new)
**Analogs found:** 4 / 4

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/providers/device_provider.dart` | provider | event-driven + request-response | `lib/providers/device_provider.dart` (existing stub) | exact (extension) |
| `lib/models/device_state.dart` | model | — | `lib/models/device_state.dart` (existing) | exact (one-line addition) |
| `test/providers/connection_notifier_test.dart` | test | event-driven | `test/ble/mock_ble_manager_test.dart` | role-match |
| `test/providers/instrument_data_provider_test.dart` | test | streaming | `test/ble/mock_ble_manager_test.dart` | role-match |

---

## Pattern Assignments

### `lib/models/device_state.dart` — add `reconnecting` to enum (model, no data flow)

**Analog:** `lib/models/device_state.dart` (read-only reference)

**Existing enum pattern** (lines 4–12):
```dart
enum ConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnecting,
  disconnected,
  error,
}
```

**Change required:** append `reconnecting,` after `error,`. No other changes to this file.

---

### `lib/providers/device_provider.dart` — full provider layer (provider, event-driven)

**Analog:** `lib/providers/device_provider.dart` (existing stub, lines 1–18)
**Secondary analog for stream lifecycle:** `lib/ble/mock_ble_manager.dart` (StreamController patterns)

**Existing imports pattern** (lines 1–3):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/ble_manager.dart';
```

**New imports to add** (append to import block):
```dart
import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
```

**Existing root provider pattern** (lines 16–18 — do not modify):
```dart
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});
```

**keepAlive pattern from RESEARCH.md** — copy into `ConnectionNotifier.build()`:
```dart
@override
ConnectionStatus build() {
  final link = ref.keepAlive(); // prevents auto-dispose while BLE session active
  ref.onDispose(link.close);   // allow disposal on explicit teardown
  // ... subscriptions follow
  return ConnectionStatus.idle;
}
```

**StreamController broadcast pattern** — copy from `lib/ble/mock_ble_manager.dart` lines 23–25:
```dart
// broadcast() — multi-subscriber safe; no "already listened" error
final _packetController = StreamController<StatePacket?>.broadcast();
```

**isClosed guard pattern** — copy from `mock_ble_manager.dart` lines 57–59 and lines 76–77:
```dart
if (!_packetController.isClosed) {
  _packetController.add(...);
}
```

**onDispose / subscription cancellation pattern** — modelled on `mock_ble_manager.dart` lines 116–122:
```dart
ref.onDispose(() {
  statusSub.cancel();
  scanSub.cancel();
  packetSub.cancel();
  _packetController.close();
  WakelockPlus.disable(); // safety: release lock if provider is torn down
});
```

**NotifierProvider declaration** (new — no existing analog, use RESEARCH.md pattern):
```dart
final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);
```

**scanResultsProvider derived from notifier** (new — no existing analog, use RESEARCH.md Pattern 3):
```dart
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  ref.watch(connectionNotifierProvider); // rebuild trigger on state change
  return ref.read(connectionNotifierProvider.notifier).scannedDevices;
});
```

**instrumentDataProvider as StreamProvider** (new — no existing analog, use RESEARCH.md Pattern 2):
```dart
final instrumentDataProvider = StreamProvider<StatePacket?>((ref) {
  return ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});
```

**ref.read in action methods** — use `ref.read`, never `ref.watch`, inside methods called outside `build()`. No existing project analog; this is a Riverpod 3 constraint from CLAUDE.md and RESEARCH.md.

---

### `test/providers/connection_notifier_test.dart` (test, event-driven)

**Analog:** `test/ble/mock_ble_manager_test.dart`

**Import pattern** (lines 1–9):
```dart
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
```

**New imports for provider tests** (add):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/device_provider.dart';
```

**Test group + fakeAsync pattern** (lines 10–17 and throughout):
```dart
void main() {
  group('ConnectionNotifier', () {
    test('description', () {
      fakeAsync((async) {
        // arrange
        final mock = MockBleManager(random: Random(0));
        // ... test body using async.elapse + async.flushMicrotasks
        mock.dispose();
      });
    });
  });
}
```

**ProviderContainer setup pattern for Riverpod tests** (no existing project analog — use RESEARCH.md + Riverpod docs):
```dart
final container = ProviderContainer(
  overrides: [
    bleManagerProvider.overrideWithValue(mock),
  ],
);
addTearDown(container.dispose);
```

**stream-subscribe-before-emit pattern** (established in `mock_ble_manager_test.dart` lines 17–20 and 84–86):
```dart
// Subscribe BEFORE triggering emissions (PITFALL-2: broadcast streams don't buffer)
mock.connectionStatus.listen(statuses.add);

mock.connect('AA:BB:CC:DD:EE:FF');
async.elapse(const Duration(milliseconds: 300));
async.flushMicrotasks();
```

**containsAllInOrder assertion pattern** (lines 92–95):
```dart
expect(
  statuses,
  containsAllInOrder([ConnectionStatus.connecting, ConnectionStatus.connected]),
);
```

---

### `test/providers/instrument_data_provider_test.dart` (test, streaming)

**Analog:** `test/ble/mock_ble_manager_test.dart` (same test harness conventions)

All patterns are identical to `connection_notifier_test.dart` above. Key additions specific to this file:

**Null sentinel assertion pattern** (no existing project analog — new for Phase 3):
```dart
// After simulateDisconnect, instrumentDataProvider must emit null
// (stale sentinel per D-05/D-06)
expect(
  instrumentValues,
  contains(null),
  reason: 'instrumentDataProvider must emit null sentinel after disconnect',
);
```

**AsyncValue unwrap pattern for StreamProvider** (no existing project analog):
```dart
// Access StreamProvider value inside test via container.read
final asyncVal = container.read(instrumentDataProvider);
// asyncVal is AsyncValue<StatePacket?> — unwrap with .value, .asData, or .when
```

---

## Shared Patterns

### StreamController.broadcast() — multi-subscriber safe stream
**Source:** `lib/ble/mock_ble_manager.dart` lines 23–25
**Apply to:** `_packetController` inside `ConnectionNotifier`
```dart
final _packetController = StreamController<StatePacket?>.broadcast();
```

### isClosed guard before emit
**Source:** `lib/ble/mock_ble_manager.dart` lines 57–59, 76–77, 110–112
**Apply to:** every `_packetController.add()` call in `ConnectionNotifier`
```dart
if (!_packetController.isClosed) {
  _packetController.add(value);
}
```

### ref.onDispose for subscription cleanup
**Source:** `lib/ble/mock_ble_manager.dart` `dispose()` method lines 116–122 (structural pattern — Riverpod equivalent)
**Apply to:** `ConnectionNotifier.build()` — all `StreamSubscription.cancel()` and `StreamController.close()` calls
```dart
ref.onDispose(() {
  sub.cancel();
  _packetController.close();
});
```

### fakeAsync + flushMicrotasks for async BLE tests
**Source:** `test/ble/mock_ble_manager_test.dart` lines 22–26
**Apply to:** all `test/providers/` test files
```dart
fakeAsync((async) {
  mock.connect('AA:BB:CC:DD:EE:FF');
  async.elapse(const Duration(milliseconds: 300)); // fires 300ms mock delay
  async.flushMicrotasks();                         // resolves Future.delayed continuation
});
```

### Import path convention (`package:inclinometer/...`)
**Source:** `lib/providers/device_provider.dart` lines 3, `lib/ble/mock_ble_manager.dart` lines 4–6
**Apply to:** all new files
```dart
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
```

### No flutter_blue_plus import in providers
**Source:** CLAUDE.md constraint + `lib/ble/ble_manager.dart` line 1 (no flutter_blue_plus import)
**Apply to:** `lib/providers/device_provider.dart` — import only `BleManager`, never concrete flutter_blue_plus types

---

## No Analog Found

No files in this phase are entirely without precedent. All patterns have at least a structural partial-match. Files referencing `wakelock_plus`, `ProviderContainer`, and `NotifierProvider` declarations have no existing project analog — the planner should use the RESEARCH.md code examples for those specific sections.

| Concern | Reason | Use Instead |
|---------|--------|-------------|
| `ProviderContainer` in tests | No existing provider tests in codebase yet | RESEARCH.md Validation Architecture section + Riverpod docs |
| `NotifierProvider` declaration | First `Notifier` in project | RESEARCH.md "Verified: ConnectionNotifier provider declaration" |
| `WakelockPlus.enable/disable` calls | New dependency, not yet in codebase | RESEARCH.md "Verified: wakelock_plus API" |
| `ref.keepAlive()` in build() | Not used anywhere yet | RESEARCH.md "Verified: keepAlive in Notifier.build()" |

---

## Metadata

**Analog search scope:** `lib/`, `test/`
**Files scanned:** 6 (device_provider.dart, device_state.dart, ble_manager.dart, mock_ble_manager.dart, ble_protocol.dart, mock_ble_manager_test.dart)
**Pattern extraction date:** 2026-06-05
