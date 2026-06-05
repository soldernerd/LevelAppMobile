# Phase 3: Riverpod Provider Layer - Research

**Researched:** 2026-06-05
**Domain:** Riverpod 3.x state management, BLE connection state machine, stream lifecycle
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Single `ConnectionNotifier extends Notifier<ConnectionStatus>` owns the full `idle → scanning → connecting → connected → disconnecting → disconnected → error → reconnecting` state machine. Scan results accumulate inside it as `List<ScannedDevice>`.
- **D-02:** Instrument data is exposed as `StreamProvider<StatePacket?>` — parses bytes from `BleManager.statePackets` using `StatePacket.parse()`. Riverpod manages stream lifecycle; UI watches with `ref.watch()`.
- **D-03:** Scan results are exposed as a field/derived provider from `ConnectionNotifier`, not a separate `StreamProvider<ScannedDevice>`. The notifier accumulates devices into a list as the `scanResults` stream emits.
- **D-04:** `bleManagerProvider` already exists in `device_provider.dart` with the `keepAlive` pattern. Phase 3 adds `ConnectionNotifier`, scan results provider, and instrument data provider to that same file.
- **D-05:** `StreamProvider<StatePacket?>` — nullable `StatePacket`. On disconnect, `ConnectionNotifier` controls a `StreamController<StatePacket?>` and adds `null`, signalling stale. The UI checks: if `null` → show stale indicator; if non-null → show live data.
- **D-06:** `ConnectionNotifier` is the single authority responsible for emitting the `null` sentinel into the stream on disconnect/error transitions.
- **D-07:** `static const bool _autoReconnectEnabled = false;` inside `ConnectionNotifier`. Backoff/retry logic is written but guarded by this constant. WP2 activates by setting it to `true`.
- **D-08:** Add `reconnecting` to the `ConnectionStatus` enum in `device_state.dart`. `ConnectionNotifier` transitions to `ConnectionStatus.reconnecting` when the disabled stub "would" fire.
- **D-09:** `WakelockPlus.enable()` / `WakelockPlus.disable()` are called as side-effects directly inside `ConnectionNotifier` state transitions — `connected` → enable, `disconnected`/`error` → disable.

### Claude's Discretion

None documented.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CONN-01 | Connection state machine with states: idle, scanning, connecting, connected, disconnecting, disconnected, error | `ConnectionNotifier extends Notifier<ConnectionStatus>` owns the full machine; `reconnecting` state added per D-08 |
| CONN-02 | User can disconnect from the instrument via a disconnect button | `ConnectionNotifier.disconnect()` public method wrapping `bleManager.disconnect()` |
| CONN-03 | Auto-reconnect stub is structurally in place (backoff logic wired, not activated) | `_autoReconnectEnabled = false` guard per D-07; `reconnecting` state per D-08 |
| CONN-05 | Stale data indicator — last-known values never shown as live after disconnect | Null-sentinel `StreamProvider<StatePacket?>` per D-05/D-06 |
| CONN-06 | "Reconnecting…" state shown (amber) while auto-reconnect stub active | `reconnecting` added to `ConnectionStatus` enum per D-08 |
| SYS-01 | Screen-on lock acquired when connected; released on disconnect | `WakelockPlus.enable/disable` as side-effects inside `ConnectionNotifier` per D-09 |
</phase_requirements>

---

## Summary

Phase 3 wires the Riverpod provider layer that sits between the `BleManager` interface (Phase 2) and the UI (Phase 4). All app state — connection status, accumulated scan results, live instrument data, and the stale-data sentinel — is managed by two providers: `ConnectionNotifier` (a `Notifier<ConnectionStatus>`) and `instrumentDataProvider` (a `StreamProvider<StatePacket?>`). No widgets are built in this phase; all outputs are verifiable via provider tests using a `ProviderContainer` and `MockBleManager`.

The architectural pattern is straightforward: `ConnectionNotifier` reads `bleManagerProvider` via `ref.read` in its action methods, subscribes to `bleManager.connectionStatus` stream in `build()` via a `StreamSubscription` registered with `ref.onDispose`, and manages a `StreamController<StatePacket?>` that it feeds null sentinels into on disconnect/error. The `instrumentDataProvider` maps `bleManager.statePackets` to `StatePacket?` via a simple stream transform.

One new dependency is required: `wakelock_plus` (currently at 1.6.1). The `ConnectionStatus` enum in `device_state.dart` requires a one-line addition of `reconnecting`. All other contracts are already in place from Phases 1 and 2.

**Primary recommendation:** Implement `ConnectionNotifier` as a `Notifier<ConnectionStatus>` that subscribes to `bleManager.connectionStatus` once in `build()`, accumulates scan results, exposes public action methods, and owns wakelock side-effects. Let `StreamProvider<StatePacket?>` handle the instrument data lifecycle independently.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Connection state machine | Provider Layer | BLE Layer (raw events) | Notifier transforms raw BLE events into app-level states |
| Scan result accumulation | Provider Layer | BLE Layer (raw stream) | Notifier buffers `ScannedDevice` entries; BLE layer just emits them |
| Instrument data parsing | Provider Layer | BLE Protocol (parse) | `StreamProvider` maps raw bytes via `StatePacket.parse()`; parsing logic is in `ble_protocol.dart` |
| Stale data signal | Provider Layer | — | `ConnectionNotifier` injects null sentinel; no BLE layer involvement |
| Wakelock side-effects | Provider Layer | — | Called directly inside `ConnectionNotifier` state transitions |
| Auto-reconnect stub | Provider Layer | — | Logic lives inside `ConnectionNotifier`, gated by `_autoReconnectEnabled` |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_riverpod | ^3.3.1 | Provider framework | Already in pubspec; project constraint |
| wakelock_plus | ^1.6.1 | Screen-on lock | Required by SYS-01; official Flutter community package [VERIFIED: pub.dev] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dart:async | SDK | `StreamController`, `StreamSubscription` | Managing the nullable instrument data stream and scan subscription |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Notifier<ConnectionStatus>` | `AsyncNotifier` | `AsyncNotifier` adds loading/error wrapping not needed here — state is always synchronous |
| `StreamProvider<StatePacket?>` | `Notifier` with manual subscription | `StreamProvider` gives Riverpod lifecycle for free; manual subscription in another `Notifier` would duplicate that work |
| Null sentinel for stale data | `sealed class InstrumentData` wrapper | Null sentinel is simpler and pattern-matches cleanly in Phase 4 UI |

**Installation (new dependency only):**
```bash
flutter pub add wakelock_plus
```

**Version verification:** [VERIFIED: pub.dev] `wakelock_plus` 1.6.1 published approximately 20 days ago. [ASSUMED] exact pub.dev URL verified at https://pub.dev/packages/wakelock_plus.

---

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| wakelock_plus | pub.dev | ~2 yrs | High (Flutter community org) | github.com/fluttercommunity/wakelock_plus | Not run (pub.dev) | Approved — official Flutter community package |

**Packages removed due to slopcheck [SLOP] verdict:** none

**Packages flagged as suspicious [SUS]:** none

*slopcheck targets npm/PyPI; this is a pub.dev package. Legitimacy assessed via Flutter community organization ownership and pub.dev verified publisher status.*

---

## Architecture Patterns

### System Architecture Diagram

```
MockBleManager (Phase 2)
  │
  ├── connectionStatus: Stream<ConnectionStatus>
  │     └──► ConnectionNotifier.build()
  │               subscribes via StreamSubscription
  │               → state transitions (idle/scanning/connecting/connected/disconnecting/disconnected/error/reconnecting)
  │               → accumulates scanResults: List<ScannedDevice>
  │               → side-effects: WakelockPlus.enable/disable
  │               → injects null into _packetController on disconnect/error
  │
  ├── scanResults: Stream<ScannedDevice>
  │     └──► ConnectionNotifier.build()
  │               accumulates into _scannedDevices list
  │
  └── statePackets: Stream<List<int>>
        └──► instrumentDataProvider (StreamProvider<StatePacket?>)
                  .map((bytes) => StatePacket.parse(bytes))
                  merged with _nullSentinelController (injected by ConnectionNotifier)

ConnectionNotifier public API:
  startScan() → ref.read(bleManagerProvider).startScan()
  stopScan()  → ref.read(bleManagerProvider).stopScan()
  connect(id) → ref.read(bleManagerProvider).connect(id)
  disconnect()→ ref.read(bleManagerProvider).disconnect()

scanResultsProvider (Provider<List<ScannedDevice>>)
  └──► reads ConnectionNotifier.scannedDevices
```

### Recommended Project Structure

```
lib/
├── models/
│   └── device_state.dart        # Add `reconnecting` to ConnectionStatus enum
├── ble/
│   ├── ble_manager.dart         # No changes
│   ├── ble_protocol.dart        # No changes (StatePacket.parse used by provider)
│   └── mock_ble_manager.dart    # No changes
└── providers/
    └── device_provider.dart     # Add ConnectionNotifier, scanResultsProvider,
                                 # instrumentDataProvider to existing file
test/
└── providers/
    └── connection_notifier_test.dart   # New: Wave 0 test file
```

### Pattern 1: ConnectionNotifier subscribes to BLE stream in build()

**What:** Subscribe to `bleManager.connectionStatus` stream once in `build()`, update `state` on each event, cancel with `ref.onDispose`.

**When to use:** Any `Notifier` that must react to external stream events without becoming an `AsyncNotifier`.

```dart
// Source: riverpod.dev/docs/whats_new + github.com/rrousselGit/riverpod/discussions/1993
class ConnectionNotifier extends Notifier<ConnectionStatus> {
  static const bool _autoReconnectEnabled = false;

  final _packetController = StreamController<StatePacket?>.broadcast();
  final _scannedDevices = <ScannedDevice>[];

  Stream<StatePacket?> get instrumentStream => _packetController.stream;
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  @override
  ConnectionStatus build() {
    final manager = ref.read(bleManagerProvider);

    // Subscribe to connection status stream
    final statusSub = manager.connectionStatus.listen(_handleStatusEvent);
    // Subscribe to scan results stream
    final scanSub = manager.scanResults.listen((device) {
      if (!_scannedDevices.contains(device)) {
        _scannedDevices.add(device);
        // force listener rebuild via state reassignment if needed
        ref.notifyListeners();
      }
    });
    // Subscribe to state packets — forward to shared controller
    final packetSub = manager.statePackets.listen((bytes) {
      if (!_packetController.isClosed) {
        _packetController.add(StatePacket.parse(bytes));
      }
    });

    ref.onDispose(() {
      statusSub.cancel();
      scanSub.cancel();
      packetSub.cancel();
      _packetController.close();
    });

    return ConnectionStatus.idle;
  }

  void _handleStatusEvent(ConnectionStatus status) {
    state = status;
    if (status == ConnectionStatus.connected) {
      WakelockPlus.enable();
    } else if (status == ConnectionStatus.disconnected ||
               status == ConnectionStatus.error) {
      WakelockPlus.disable();
      if (!_packetController.isClosed) {
        _packetController.add(null); // D-05/D-06: stale sentinel
      }
      if (_autoReconnectEnabled) {
        state = ConnectionStatus.reconnecting; // D-08
        // backoff/retry logic here (WP2 activates)
      }
    }
  }

  Future<void> startScan() async {
    _scannedDevices.clear();
    await ref.read(bleManagerProvider).startScan();
  }

  Future<void> stopScan() async {
    await ref.read(bleManagerProvider).stopScan();
  }

  Future<void> connect(String deviceId) async {
    await ref.read(bleManagerProvider).connect(deviceId);
  }

  Future<void> disconnect() async {
    await ref.read(bleManagerProvider).disconnect();
  }
}

final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
  // keepAlive handled by bleManagerProvider; this notifier survives while
  // its subscriptions to the manager remain active
);
```

### Pattern 2: instrumentDataProvider as StreamProvider

**What:** Wrap the `ConnectionNotifier`'s shared `StreamController` as a `StreamProvider<StatePacket?>` so Riverpod manages subscription lifecycle for the UI.

```dart
// Source: riverpod.dev StreamProvider docs
final instrumentDataProvider = StreamProvider<StatePacket?>((ref) {
  return ref.watch(connectionNotifierProvider.notifier).instrumentStream;
});
```

**Alternative approach** if the `StreamController` pattern introduces coupling: derive directly from `bleManagerProvider.statePackets` and let `ConnectionNotifier` push nulls into a separate sentinel provider. Both approaches work; the `StreamController` approach from D-05/D-06 is locked.

### Pattern 3: scanResultsProvider derived from ConnectionNotifier

```dart
// Source: D-03 decision — field exposure pattern
final scanResultsProvider = Provider<List<ScannedDevice>>((ref) {
  // Watch connection notifier to re-evaluate when state changes.
  // Actual device list is held inside the notifier.
  ref.watch(connectionNotifierProvider); // rebuild trigger
  return ref.read(connectionNotifierProvider.notifier).scannedDevices;
});
```

**Note on ref.notifyListeners():** In Riverpod 3.x, `Notifier` state changes are the trigger for listener rebuilds. For a `List<ScannedDevice>` field that is not part of the notifier's `state` type, the notifier must either (a) re-assign `state` to trigger rebuilds (e.g., by using a wrapper state class), or (b) call `ref.notifyListeners()` if that API is available. Confirm the `ref.notifyListeners()` API availability in `flutter_riverpod 3.3.1` before use. [ASSUMED — needs verification against 3.3.1 changelog.]

**Safer alternative:** Make scan results part of a compound state class so that list mutations trigger normal state reassignment — avoids any `notifyListeners` API dependency.

### Anti-Patterns to Avoid

- **`ref.watch()` for action dispatch:** Use `ref.read(bleManagerProvider)` inside action methods (`connect`, `disconnect`, etc.) — not `ref.watch`. `ref.watch` in non-`build` context is a lint error in Riverpod 3.
- **`StateNotifierProvider`:** Banned by CLAUDE.md. All state uses `Notifier`/`AsyncNotifier`.
- **Importing `flutter_blue_plus` in providers:** CLAUDE.md constraint. Providers only import `BleManager` interface, never the concrete flutter_blue_plus types.
- **Closing `_packetController` before `ref.onDispose`:** The `StreamProvider` watching `instrumentStream` will receive a done event and emit `AsyncValue.loading` rather than showing the last null. Always close the controller only in `ref.onDispose`.
- **Multiple subscriptions to broadcast stream:** `MockBleManager` uses eager broadcast controllers — safe for multiple listeners. Do not use `.asBroadcastStream()` wrapper on an already-broadcast stream (no-op but confusing).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Screen-on lock | Custom platform channel | `wakelock_plus` | Handles all Android/iOS lifecycle edge cases; NDK/API level compatibility |
| Stream lifecycle management | Manual `dispose()` tracking | `ref.onDispose()` | Riverpod guarantees cleanup order; manual dispose risks use-after-free on hot-reload |
| Stale data sentinel | Separate boolean `isStaleProvider` | Nullable `StatePacket?` in stream | Single source of truth; UI pattern-matches on null; avoids race between two providers |

**Key insight:** Riverpod 3.x `Notifier.build()` + `ref.onDispose()` is the correct subscription lifecycle hook — do not add a `dispose()` method to the `Notifier` class; Riverpod does not call it.

---

## Common Pitfalls

### Pitfall 1: ref.notifyListeners() API availability

**What goes wrong:** `Notifier` in Riverpod 3.x may not expose `ref.notifyListeners()` publicly, causing a compile error when trying to signal that a mutable list field changed without reassigning `state`.

**Why it happens:** Riverpod's design is that state changes are the signal. Mutable fields not in `state` don't trigger rebuilds automatically.

**How to avoid:** Use a compound state object or re-assign `state` for any mutable data that UI must react to. For `scannedDevices`, the safest approach is to hold scan results as an immutable list in state (or a wrapper class) so that `state = state.copyWith(...)` triggers normal rebuild propagation.

**Warning signs:** `scanResultsProvider` rebuilds inconsistently in tests — devices appear in the notifier but the provider returns stale list.

### Pitfall 2: StreamSubscription in build() called multiple times

**What goes wrong:** If `connectionNotifierProvider` is not `keepAlive`, Riverpod may rebuild the notifier on navigation — each rebuild opens new subscriptions, leading to duplicate state transitions.

**Why it happens:** Riverpod 3 auto-disposes providers by default when no listeners remain.

**How to avoid:** Either (a) keep the notifier alive while the BLE manager is alive (link lifecycle via `ref.watch(bleManagerProvider)` in build — if manager teardown triggers notifier teardown, subscriptions close cleanly), or (b) add `keepAlive: true` behavior via `ref.keepAlive()` inside `build()`. Review whether `connectionNotifierProvider` needs explicit keepAlive given that Phase 5 adds `go_router` navigation.

**Warning signs:** State resets to `idle` when navigating away from scan screen — symptom of unintended notifier rebuild.

### Pitfall 3: null sentinel emitted before statePackets subscription is active

**What goes wrong:** `instrumentDataProvider` subscribes to `instrumentStream` lazily — if `ConnectionNotifier` emits the null sentinel before the `StreamProvider` has subscribed, the UI misses the stale signal.

**Why it happens:** Broadcast stream + lazy `StreamProvider` initialization means the null event is emitted before any listener is attached.

**How to avoid:** The `_packetController` is a broadcast stream which does not buffer events. Ensure the null sentinel is emitted in the `_handleStatusEvent` callback (triggered by the BLE disconnect event) which happens after initial UI subscription, not during `build()`. During build(), both the `StreamProvider` and the notifier initialize in the same frame.

**Warning signs:** Tests that call `simulateDisconnect()` see `instrumentDataProvider` still showing a non-null `DeviceState` rather than transitioning to `null`.

### Pitfall 4: Calling async BLE methods without guarding controller closure

**What goes wrong:** `connect()` awaits a 300 ms delay (from `MockBleManager`); if the notifier is disposed during the await, the `_packetController.add()` call throws "sink is closed".

**Why it happens:** Async gap between action start and BLE event arrival — the notifier may be disposed mid-flight during tests.

**How to avoid:** Always guard: `if (!_packetController.isClosed) { ... }` before emitting to the packet controller. This pattern is already established in `MockBleManager` (see `CR-02` comments in Phase 2).

### Pitfall 5: Riverpod 3 automatic retry for failing providers

**What goes wrong:** If `instrumentDataProvider` (StreamProvider) throws during `StatePacket.parse()`, Riverpod 3 will automatically retry, potentially creating a retry storm at 10 Hz (mock packet rate).

**Why it happens:** Riverpod 3 enables automatic retries for failing providers by default.

**How to avoid:** Wrap `StatePacket.parse()` in a try/catch inside the stream map, converting errors to null or logging them. Do not let parse errors propagate as unhandled stream errors.

---

## Code Examples

### Verified: ConnectionNotifier provider declaration

```dart
// Source: riverpod.dev/docs/whats_new (Riverpod 3.x — no AutoDispose prefix)
final connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);
```

### Verified: keepAlive in Notifier.build()

```dart
// Source: Riverpod 3 migration guide — keepAlive pattern
@override
ConnectionStatus build() {
  final link = ref.keepAlive(); // prevents auto-dispose while scan/connect active
  ref.onDispose(link.close);    // allow disposal on explicit teardown
  // ... subscriptions
  return ConnectionStatus.idle;
}
```

**Note:** `ref.keepAlive()` returns a `KeepAliveLink`; calling `link.close()` allows the provider to be auto-disposed again. Only keep alive while a session is active if truly needed; otherwise, let Riverpod manage the lifecycle.

### Verified: StreamProvider with nullable type

```dart
// Source: pub.dev/documentation/riverpod/latest/riverpod/StreamProvider-class.html
final instrumentDataProvider = StreamProvider<StatePacket?>((ref) {
  final notifier = ref.watch(connectionNotifierProvider.notifier);
  return notifier.instrumentStream;
});
```

### Verified: wakelock_plus API

```dart
// Source: pub.dev/packages/wakelock_plus
import 'package:wakelock_plus/wakelock_plus.dart';

await WakelockPlus.enable();   // acquire screen-on lock
await WakelockPlus.disable();  // release screen-on lock
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `StateNotifierProvider` | `Notifier` / `NotifierProvider` | Riverpod 2.0 | StateNotifier deprecated; moved to legacy import in 3.0 |
| `AutoDisposeNotifier` | `Notifier` (autoDispose behavior via lint/default) | Riverpod 3.0 | `AutoDispose` prefix removed from public API |
| `FamilyNotifier` | `Notifier` (family arg as constructor field) | Riverpod 3.0 | No impact on this phase (no family providers needed) |
| Stream equality: `identical` | Stream equality: `==` | Riverpod 3.0 | `StatePacket` equality must be defined for proper change filtering |

**Deprecated/outdated:**
- `StateNotifierProvider`: replaced by `NotifierProvider`; in Riverpod 3 it lives in `package:hooks_riverpod/legacy.dart`. CLAUDE.md forbids its use.
- `wakelock` (original): superseded by `wakelock_plus` (same team, community maintained).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ref.notifyListeners()` is available on `Ref` inside `Notifier` in flutter_riverpod 3.3.1 | Architecture Patterns / Pattern 3 | Scan results provider won't rebuild when device list changes — must use compound state class instead |
| A2 | `wakelock_plus` 1.6.1 is compatible with `minSdkVersion 24` / `compileSdkVersion 35` | Standard Stack | Build failure or runtime crash on Android — highly unlikely given pub.dev description |
| A3 | `DeviceState` equality (generated `==` via `Object.hash`) is sufficient for Riverpod 3's `==`-based change filtering on `StreamProvider<StatePacket?>` | Common Pitfalls | UI may not update on genuinely changed data, or may over-update — verify `DeviceState.==` covers all fields |

**Note:** A3 is low risk — `DeviceState.==` was explicitly implemented in Phase 1 covering all three fields.

---

## Open Questions

1. **`ref.notifyListeners()` vs compound state for scan results**
   - What we know: `ConnectionNotifier` state type is `ConnectionStatus`, not `List<ScannedDevice>`; mutable list fields don't auto-trigger rebuilds.
   - What's unclear: Whether `Ref` in flutter_riverpod 3.3.1 exposes `notifyListeners()` — the Riverpod changelog is ambiguous.
   - Recommendation: Plan task to use a compound `ConnectionState` class (containing both `ConnectionStatus` and `List<ScannedDevice>`) as the notifier's state type. This eliminates the ambiguity entirely and is idiomatic Riverpod.

2. **`keepAlive` scope for `connectionNotifierProvider`**
   - What we know: `bleManagerProvider` is already expected to be kept alive (CLAUDE.md). Phase 5 adds `go_router` navigation.
   - What's unclear: Whether `connectionNotifierProvider` needs its own `keepAlive` or whether watching `bleManagerProvider` creates a sufficient dependency chain.
   - Recommendation: Add `ref.keepAlive()` in `build()` as a conservative measure; Phase 5 can revisit when the router is wired.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| flutter SDK | All providers | ✓ | ^3.x (pubspec env: sdk ^3.12.1) | — |
| flutter_riverpod | ConnectionNotifier, StreamProvider | ✓ | ^3.3.1 (pubspec) | — |
| wakelock_plus | SYS-01 | ✗ (not in pubspec yet) | 1.6.1 available | `flutter pub add wakelock_plus` |
| dart:async | StreamController, StreamSubscription | ✓ | SDK built-in | — |

**Missing dependencies with no fallback:** none

**Missing dependencies with fallback:** `wakelock_plus` — add via `flutter pub add wakelock_plus` as a Wave 0 task.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | test ^1.31.0 + fake_async ^1.3.3 (already in pubspec) |
| Config file | None — pure dart test runner |
| Quick run command | `flutter test test/providers/` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONN-01 | State machine transitions: idle→scanning→connecting→connected | unit | `flutter test test/providers/connection_notifier_test.dart` | ❌ Wave 0 |
| CONN-01 | State machine: connected→disconnecting→disconnected | unit | same | ❌ Wave 0 |
| CONN-01 | State machine: error state on unexpected disconnect | unit | same | ❌ Wave 0 |
| CONN-02 | `disconnect()` method transitions to disconnected | unit | same | ❌ Wave 0 |
| CONN-03 | `_autoReconnectEnabled = false` code inspection + reconnecting state emitted | unit | same | ❌ Wave 0 |
| CONN-05 | null emitted to `instrumentDataProvider` on disconnect | unit | same | ❌ Wave 0 |
| CONN-06 | `ConnectionStatus.reconnecting` exists in enum | unit | `flutter test test/providers/connection_notifier_test.dart` | ❌ Wave 0 |
| SYS-01 | Wakelock enabled on connected, disabled on disconnected | unit (mock WakelockPlus) | same | ❌ Wave 0 |

**Note on testing wakelock:** `WakelockPlus.enable/disable` are static methods. Tests should verify the state machine logic and trust the library for platform behavior. Consider a thin wrapper or dependency injection if unit-testing wakelock calls is required — but code inspection + manual verification is acceptable for WP1.

### Sampling Rate

- **Per task commit:** `flutter test test/providers/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/providers/connection_notifier_test.dart` — covers CONN-01, CONN-02, CONN-03, CONN-05, CONN-06
- [ ] `test/providers/instrument_data_provider_test.dart` — covers CONN-05 (null sentinel propagation)
- [ ] `models/device_state.dart` enum update — add `reconnecting` (required before provider tests compile)

---

## Security Domain

> `security_enforcement` not set to false in config.json — section included.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | BLE pairing is OS-managed; no app-level session tokens |
| V4 Access Control | no | — |
| V5 Input Validation | yes | `StatePacket.parse()` already validates packet length and battery range (Phase 1); provider wraps in try/catch |
| V6 Cryptography | no | — |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed BLE packet (wrong length or invalid battery byte) | Tampering | `StatePacket.parse()` throws `ArgumentError`; provider catches and maps to null |
| State machine race (concurrent connect/disconnect) | Tampering | Single `ConnectionNotifier` is the authority; sequential stream events serialize state transitions |

---

## Sources

### Primary (HIGH confidence)
- https://riverpod.dev/docs/whats_new — Riverpod 3.x changes, Notifier unification, `==` filtering, AutoDispose removal
- https://riverpod.dev/docs/3.0_migration — Breaking changes relevant to providers in this phase
- https://pub.dev/packages/wakelock_plus — Latest version (1.6.1), enable/disable API, Android compatibility
- https://pub.dev/documentation/riverpod/latest/riverpod/StreamProvider-class.html — StreamProvider API

### Secondary (MEDIUM confidence)
- https://github.com/rrousselGit/riverpod/discussions/1993 — StreamSubscription inside AsyncNotifier/Notifier build() pattern
- https://codewithandrea.com/articles/flutter-riverpod-async-notifier/ — Notifier/AsyncNotifier usage patterns
- https://github.com/fluttercommunity/wakelock_plus — Package source repo, Android notes

### Tertiary (LOW confidence)
- Training knowledge for Dart `StreamController.broadcast()` patterns and `ref.notifyListeners()` availability

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified on pub.dev
- Architecture: HIGH — locked decisions from CONTEXT.md, verified Riverpod 3 APIs
- Pitfalls: MEDIUM — several pitfalls verified against official migration guide; `ref.notifyListeners()` availability is ASSUMED
- Test patterns: HIGH — consistent with existing Phase 2 test patterns in this project

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (Riverpod 3.3.x is stable; wakelock_plus 1.6.1 is current)
