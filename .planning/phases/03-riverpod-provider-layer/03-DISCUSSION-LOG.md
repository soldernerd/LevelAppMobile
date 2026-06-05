# Phase 3: Riverpod Provider Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 03-riverpod-provider-layer
**Areas discussed:** Provider structure, Stale data signal, Auto-reconnect stub shape, Wakelock placement

---

## Provider Structure

### Q1: Connection + scan state machine ownership

| Option | Description | Selected |
|--------|-------------|----------|
| Single ConnectionNotifier | One Notifier<ConnectionStatus> drives the full state machine; scan results accumulate inside it | ✓ |
| Split: ScanNotifier + ConnectionNotifier | Two notifiers, more modular but requires cross-notifier sync | |

**User's choice:** Single ConnectionNotifier

### Q2: Instrument data provider type

| Option | Description | Selected |
|--------|-------------|----------|
| StreamProvider<StatePacket> | Parses bytes from statePackets stream; Riverpod manages lifecycle | ✓ |
| StateNotifier / Notifier with listen() | Subscribes internally, exposes via state | |
| AsyncNotifier<StatePacket> | Wraps each packet as async update; adds AsyncValue friction | |

**User's choice:** StreamProvider<StatePacket> (recommended)

### Q3: Scan results provider type

| Option | Description | Selected |
|--------|-------------|----------|
| Notifier inside ConnectionNotifier | Accumulates into List<ScannedDevice> as stream emits | ✓ |
| Separate StreamProvider<ScannedDevice> | Direct stream forward; UI must accumulate | |
| Separate Notifier<List<ScannedDevice>> | Dedicated ScanResultsNotifier | |

**User's choice:** Inside ConnectionNotifier (recommended)

---

## Stale Data Signal

### Q1: Signal mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Nullable StreamProvider<StatePacket?> | null = stale; non-null = live | ✓ |
| Wrapper type InstrumentReading(value, isStale) | Explicit but more types | |
| Separate isStaleProvider bool | Two providers to keep in sync | |

**User's choice:** Nullable StreamProvider<StatePacket?> (recommended)

### Q2: Who emits the null sentinel

| Option | Description | Selected |
|--------|-------------|----------|
| ConnectionNotifier controls a StreamController<StatePacket?> | adds(null) on disconnect | ✓ |
| StreamProvider rebuilds on ConnectionStatus change | ref.invalidateSelf() restarts as loading | |

**User's choice:** ConnectionNotifier controls the stream (recommended)

---

## Auto-Reconnect Stub Shape

### Q1: Disabled stub shape

| Option | Description | Selected |
|--------|-------------|----------|
| const bool _autoReconnectEnabled = false | Backoff logic written but guarded; WP2 flips to true | ✓ |
| Separate ReconnectNotifier, disabled by flag | Clean separation, but overhead for a no-op | |
| Commented-out reconnect block | Simpler, harder to test | |

**User's choice:** const bool constant in ConnectionNotifier (recommended)

### Q2: reconnecting state representation

| Option | Description | Selected |
|--------|-------------|----------|
| Add reconnecting to ConnectionStatus enum | First-class state, consistent with UI chip | ✓ |
| Separate isReconnecting bool | Avoids enum change but splits state | |

**User's choice:** Add to ConnectionStatus enum (recommended)

---

## Wakelock Placement

### Q1: Where to call WakelockPlus

| Option | Description | Selected |
|--------|-------------|----------|
| Side-effect inside ConnectionNotifier | All connection-driven side-effects in one place | ✓ |
| ref.listen in a WakelockNotifier | Clean separation, but a stateless side-effect notifier | |
| ref.listen in main.dart / ProviderScope | App-level listener, mixes Phase 5 concerns | |

**User's choice:** Side-effect inside ConnectionNotifier (recommended)

---

## Claude's Discretion

None — all areas had explicit user decisions.

## Deferred Ideas

None — discussion stayed within phase scope.
