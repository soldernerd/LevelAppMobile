# Phase 1: Data Models + Protocol Parser - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers the pure Dart foundation: typed data models (`DeviceState`, `ScannedDevice`, `ConnectionStatus`), the BLE wire protocol (`StatePacket.parse()`, `StatePacket.encode()`, command constants, GATT UUID constants) in `ble_protocol.dart`, and the `abstract class BleManager` interface with a compile-passing `MockBleManager` stub. No UI, no BLE hardware calls, no mock behavior (random-walk logic is Phase 2). Phase 1 also creates the Flutter project scaffold via `flutter create`.

</domain>

<decisions>
## Implementation Decisions

### Flutter Project Scaffold
- **D-01:** Phase 1 starts by running `flutter create --org com.soldernerd --project-name inclinometer .` in the project root (in-place, no subdirectory). This creates `pubspec.yaml`, `lib/`, `android/`, `ios/`, and `test/` alongside existing planning docs.
- **D-02:** Generated counter app boilerplate is wiped after `flutter create`. Phase 1 replaces `lib/main.dart` with a minimal stub and creates a proper `test/` structure from scratch.

### Protocol Parser
- **D-03:** `StatePacket.encode()` is included in Phase 1 alongside `parse()`. encode/parse are inverses; having both in `ble_protocol.dart` enables round-trip unit tests within Phase 1 and keeps `ble_protocol.dart` complete before Phase 2 needs it for MockBleManager.

### Model Equality
- **D-04:** `DeviceState` and `ScannedDevice` implement `==` and `hashCode` manually. No additional packages (equatable, freezed) are added. The models have 3–4 fields each — manual implementation is straightforward and avoids expanding the dependency footprint.

### MockBleManager Scope in Phase 1
- **D-05:** Phase 1 includes a `MockBleManager` stub — all abstract methods from `BleManager` are implemented with minimal bodies (throw `UnimplementedError` or return empty streams). This satisfies ARCH-01's success criterion "compiles without stub warnings". The actual random-walk behavior is Phase 2's responsibility.

### Claude's Discretion
- Error handling in `StatePacket.parse()`: the architecture doc shows `assert(bytes.length == 9, ...)`. Use Dart assertions for length check — appropriate for a dev-time protocol where malformed packets indicate a bug, not a user error.
- Placement of `MockBleManager`: same file as `ble_manager.dart` or separate `mock_ble_manager.dart` — Claude decides based on file length.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §BLE Protocol — PROT-01 through PROT-04: wire format, command constants, UUIDs, parse() spec
- `.planning/REQUIREMENTS.md` §Architecture — ARCH-01, ARCH-02: BleManager interface contract and UI isolation rule

### Architecture & Design
- `.planning/research/ARCHITECTURE.md` — BleManager abstract class definition, file responsibilities, data flow (bytes→model), build order. The code samples in this file are the canonical design for `ble_manager.dart`, `ble_protocol.dart`, and `device_state.dart`.
- `.planning/research/STACK.md` — Flutter/Dart package versions, Riverpod 3.x breaking changes (Ref subtypes removed, autoDispose default, equality via ==), flutter_blue_plus 2.x API notes relevant to the interface design.

### Project Config
- `.planning/PROJECT.md` — Package name `com.soldernerd.inclinometer`, WP1/WP2 split rationale, folder structure constraint (`lib/ble/`, `lib/models/`, `lib/ui/`, `lib/providers/`)
- `CLAUDE.md` — Architecture constraints (no flutter_blue_plus in ui/ or providers/, `keepAlive: true` on BLE providers, Riverpod 3.x Notifier/AsyncNotifier only)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — brand new Flutter project, no existing Dart code.

### Established Patterns
- After `flutter create .`, the generated code (counter app) is wiped. Phase 1 establishes the project's conventions from scratch.

### Integration Points
- `lib/models/device_state.dart` — produced by Phase 1, consumed by every subsequent phase
- `lib/ble/ble_protocol.dart` — produced by Phase 1, consumed by Phase 2 (MockBleManager.statePackets uses encode()) and Phase 3 (providers map statePackets via StatePacket.parse())
- `lib/ble/ble_manager.dart` + stub `MockBleManager` — produced by Phase 1, Phase 2 fills in the implementation

</code_context>

<specifics>
## Specific Ideas

- The BleManager interface in `.planning/research/ARCHITECTURE.md` is the canonical design — downstream agents should follow it exactly unless a breaking change is discovered during implementation.
- The `StatePacket` round-trip test (encode a known float pair → parse the bytes → verify values round-trip) is the natural Phase 1 unit test and doubles as a check that float32 endianness is correct.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-data-models-protocol-parser*
*Context gathered: 2026-06-04*
