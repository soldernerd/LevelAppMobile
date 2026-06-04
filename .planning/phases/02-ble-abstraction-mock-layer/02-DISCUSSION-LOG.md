# Phase 2: BLE Abstraction + Mock Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 02-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 2-ble-abstraction-mock-layer
**Areas discussed:** Scan mock behaviour, sendCommand behaviour

---

## Gray Area Selection

| Area | Selected for discussion |
|------|------------------------|
| Mock data feel (tick rate, step size, bounds, battery drain) | No — deferred to Claude / ARCHITECTURE.md defaults |
| Scan mock behaviour | ✓ |
| sendCommand behaviour | ✓ |

---

## Scan Mock Behaviour

### Device count

| Option | Description | Selected |
|--------|-------------|----------|
| One device (Recommended) | Matches real use case — one inclinometer. Simple scan screen. | ✓ |
| Two or three devices | Tests list UI with multiple entries and RSSI sorting | |
| You decide | Use whatever count makes scan screen look realistic | |

**User's choice:** One device
**Notes:** Single device matches real-world usage. No need for multi-device scan list complexity in WP1.

### Scan timing

| Option | Description | Selected |
|--------|-------------|----------|
| After a short delay (~500ms) (Recommended) | More realistic — exercises "scanning…" state before device appears | ✓ |
| Immediately (no delay) | Simpler — device list populates instantly on scan start | |

**User's choice:** ~500ms delay
**Notes:** The delay exercises the scanning state so Phase 4 can test the loading indicator.

### Device name

| Option | Description | Selected |
|--------|-------------|----------|
| 'Inclinometer' (Recommended) | Matches likely real hardware broadcast name | ✓ |
| 'SolderNerd-01' / 'SolderNerd-02' | Matches package name com.soldernerd branding | |
| You decide | Any placeholder name | |

**User's choice:** 'Inclinometer'

---

## sendCommand Behaviour

### Zero command effect

| Option | Description | Selected |
|--------|-------------|----------|
| Reset _angleX or _angleY to 0.0 (Recommended) | Makes UI immediately testable — angle snaps to 0° after tap | ✓ |
| Silently accept (no-op) | sendCommand ignores the byte. Zero buttons appear broken during Phase 4 | |

**User's choice:** Reset angle to 0.0
**Notes:** End-to-end command path verification requires the mock to actually respond.

### Post-disconnect statePackets

| Option | Description | Selected |
|--------|-------------|----------|
| Ticker stops immediately (Recommended) | statePackets goes silent. Correctly exercises CONN-05 stale-data indicator | ✓ |
| Ticker keeps running briefly (1–2 more ticks) | More realistic BLE buffer drain, but complicates Phase 3 stale-data tests | |

**User's choice:** Stop immediately
**Notes:** Clean stop simplifies Phase 3 provider testing for the stale-data requirement.

---

## Claude's Discretion

- **Mock data parameters** — Tick interval (100ms), angle step size (±0.1°/tick), angle bounds (±45°), battery drain (1% per 10 seconds, start at 85%), connect delay (300ms per CLAUDE.md). User deferred all to ARCHITECTURE.md defaults / project constraints.
- **`_tickCount` counter** for battery drain implementation — exact approach up to Claude.
- **Angle reset on reconnect** — whether `_angleX`/`_angleY` reset to 0.0 when `connect()` is called again after a disconnect — up to Claude.

## Deferred Ideas

None — discussion stayed within phase scope.
