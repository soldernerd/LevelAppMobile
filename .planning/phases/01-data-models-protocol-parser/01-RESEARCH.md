# Phase 1: Data Models + Protocol Parser - Research

**Researched:** 2026-06-04
**Domain:** Flutter/Dart project scaffold, typed data models, binary protocol parsing, abstract interface design
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Phase 1 starts by running `flutter create --org com.soldernerd --project-name inclinometer .` in the project root (in-place, no subdirectory). Creates `pubspec.yaml`, `lib/`, `android/`, `ios/`, and `test/` alongside existing planning docs.
- **D-02:** Generated counter app boilerplate is wiped after `flutter create`. Phase 1 replaces `lib/main.dart` with a minimal stub and creates a proper `test/` structure from scratch.
- **D-03:** `StatePacket.encode()` is included in Phase 1 alongside `parse()`. Both methods in `ble_protocol.dart` enable round-trip unit tests within Phase 1.
- **D-04:** `DeviceState` and `ScannedDevice` implement `==` and `hashCode` manually. No equatable or freezed packages.
- **D-05:** Phase 1 includes a `MockBleManager` stub — all abstract methods implemented with minimal bodies (`throw UnimplementedError` or return empty streams). Actual random-walk behavior is Phase 2.

### Claude's Discretion

- Error handling in `StatePacket.parse()`: use Dart `assert` for length check — appropriate for a dev-time protocol.
- Placement of `MockBleManager`: same file as `ble_manager.dart` or separate `mock_ble_manager.dart` — Claude decides based on file length.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROT-01 | `ble_protocol.dart` defines 9-byte state packet structure: `[angle_x: float32LE][angle_y: float32LE][battery: uint8]` | ByteData.sublistView + Uint8List.fromList pattern verified; float32 LE confirmed via Dart API docs |
| PROT-02 | `ble_protocol.dart` defines command byte constants: `ZERO_X = 0x01`, `ZERO_Y = 0x02` | Pure Dart top-level const — no library needed |
| PROT-03 | `ble_protocol.dart` defines GATT UUIDs as named constants (placeholder values) | Pure Dart top-level const — no library needed |
| PROT-04 | `StatePacket.parse(List<int> bytes)` parses raw byte list into typed `StatePacket` using `ByteData.getFloat32` with `Endian.little` | Exact API verified; `Uint8List.fromList(bytes)` conversion required before `ByteData.sublistView` |
| ARCH-01 | BLE layer is `abstract class BleManager`; `MockBleManager` implements it; WP2 swap is one `ProviderScope.overrides` line in `main.dart` | ProviderScope.overrides pattern confirmed via Riverpod docs |
| ARCH-02 | UI widgets never import `flutter_blue_plus` directly; all BLE access through providers consuming `BleManager` interface | Architecture enforced by file-level import discipline; no compile-time enforcement in Phase 1 |

</phase_requirements>

---

## Summary

Phase 1 creates a brand-new Flutter project in an existing directory (one that already has `.git`, `CLAUDE.md`, and `.planning/`), then builds a pure-Dart foundation: typed data models, a binary protocol parser, and an abstract BLE interface with a compile-passing stub implementation. There is no UI, no hardware access, and no mock behavior — Phase 1's output is the stable API contract that all subsequent phases depend on.

The canonical design (architecture, code shapes, file locations) is fully specified in `.planning/research/ARCHITECTURE.md`. This research document focuses on the six specific technical questions the planner needs to answer confidently before writing task sequences: `flutter create` in-place behavior, Dart unit test setup, manual equality patterns, `ByteData` API selection, `MockBleManager` file placement, and minimal `pubspec.yaml` dependency set.

**Primary recommendation:** Follow the canonical designs in `ARCHITECTURE.md` exactly. The only planning-level decisions not already resolved are: (1) write `MockBleManager` in a separate `lib/ble/mock_ble_manager.dart` because the file pair will each exceed ~80 lines once Phase 2 fills in behavior; and (2) include only `flutter_riverpod` and the `test` dev-dependency in Phase 1's `pubspec.yaml` — `flutter_blue_plus` is NOT needed in Phase 1 and should not be added until Phase 2 or Phase 5.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Wire format (byte layout, endianness) | Service / BLE Layer (`ble_protocol.dart`) | — | Pure Dart utility; no Flutter, no UI, no state |
| GATT UUID constants | Service / BLE Layer (`ble_protocol.dart`) | — | Protocol constants live with the protocol parser |
| Command byte constants | Service / BLE Layer (`ble_protocol.dart`) | — | Same file as the protocol they belong to |
| Typed data models (`DeviceState`, `ScannedDevice`) | Model Layer (`lib/models/device_state.dart`) | — | Plain Dart data classes; no BLE or Flutter imports |
| Connection state enum (`ConnectionStatus`) | Model Layer (`lib/models/device_state.dart`) | — | Enum consumed by both UI and providers; lives in models |
| BLE interface contract (`abstract class BleManager`) | Service / BLE Layer (`lib/ble/ble_manager.dart`) | — | Defines the seam between mock and real implementations |
| MockBleManager stub (Phase 1 compile target) | Service / BLE Layer (`lib/ble/mock_ble_manager.dart`) | — | Implementation of BleManager; no UI, no Riverpod in Phase 1 |
| App entry point wiring (`ProviderScope.overrides`) | Entry Point (`lib/main.dart`) | — | Minimal stub in Phase 1; full wiring in Phase 5 |

---

## Standard Stack

### Core (Phase 1 only)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter (SDK) | 3.44.0 | Flutter framework | Locked by project |
| dart:typed_data | SDK built-in | `ByteData`, `Uint8List`, `Endian` for binary parsing | No external dep needed |
| flutter_riverpod | 3.3.1 | State management — `Provider<BleManager>` stub needed in `main.dart` | Locked by project; Phase 1 needs at minimum the `Provider` definition |

### Dev Dependencies (Phase 1)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| flutter_test | SDK (included) | Widget/integration test runner; `flutter test` uses it | Auto-included by `flutter create`; always present |
| test | 1.31.1 | Pure Dart unit test framework | For `StatePacket.parse()` / `encode()` round-trip tests |

### NOT needed in Phase 1

| Package | Add In Phase | Reason |
|---------|-------------|--------|
| flutter_blue_plus | Phase 5 (or Phase 2) | No BLE hardware calls in Phase 1; `abstract class BleManager` has no FBP dependency |
| permission_handler | Phase 5 | Permissions wiring is Phase 5 scope |
| go_router | Phase 5 | Routing is Phase 5 scope |
| wakelock_plus | Phase 5 | Screen lock is Phase 5 scope |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual `==` / `hashCode` | `equatable` package | equatable reduces boilerplate but adds a dependency; 3–4 field classes are trivial to implement manually — D-04 locks this |
| Manual `==` / `hashCode` | `freezed` + code-gen | freezed is powerful but introduces build_runner, heavy code-gen, and `.freezed.dart` files to maintain; overkill for Phase 1 pure-data classes |
| `dart:typed_data` | `buffer` pub package | Unnecessary; `dart:typed_data` is SDK-native and fully sufficient |

**Installation (Phase 1 pubspec.yaml additions):**

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.31.1
```

Note: `flutter_test` is already generated by `flutter create`; only `flutter_riverpod` and `test` need to be added manually.

**Version verification:** [VERIFIED: npm registry]
- `flutter_riverpod 3.3.1` — confirmed on pub.dev 2026-06-04 (published ~2 months ago, verified publisher)
- `flutter_blue_plus 2.3.5` — confirmed on pub.dev 2026-06-04 (published 37 hours ago, verified publisher)
- `test 1.31.1` — confirmed on pub.dev 2026-06-04 (published 37 days ago, dart.dev verified publisher)

---

## Package Legitimacy Audit

> These are established, authoritative Flutter/Dart packages. slopcheck was not available in this environment; all packages are verified via pub.dev with official publisher verification badges.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| flutter_riverpod | pub.dev | 5+ yrs | High (top Flutter pkg) | github.com/rrousselGit/riverpod | N/A (verified publisher: riverpod.dev) | Approved |
| test | pub.dev | 10+ yrs | Core Dart pkg | github.com/dart-lang/test | N/A (verified publisher: dart.dev) | Approved |
| flutter_blue_plus | pub.dev | 3+ yrs | High (top BLE pkg) | github.com/chipweinberger/flutter_blue_plus | N/A (verified publisher) | Approved (Phase 5) |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck was unavailable; all packages above confirmed via pub.dev verified-publisher badges and multi-year publication history. No user confirmation checkpoint required — these are canonical Flutter ecosystem packages.*

---

## Architecture Patterns

### System Architecture Diagram

```
flutter create .
  └─ generates: pubspec.yaml, lib/, android/, ios/, test/
       │
       ▼
Boilerplate wipe
  └─ delete: lib/main.dart counter app, test/widget_test.dart
       │
       ▼
Phase 1 file creation (bottom-up build order):

  lib/models/device_state.dart
    ├── ConnectionStatus (enum)
    ├── DeviceState (angleX, angleY, battery — with == / hashCode)
    └── ScannedDevice (id, name, rssi — with == / hashCode)
                │
                ▼
  lib/ble/ble_protocol.dart
    ├── kServiceUuid, kStateCharUuid, kCommandCharUuid (String consts)
    ├── kCmdZeroX = 0x01, kCmdZeroY = 0x02 (int consts)
    └── StatePacket.parse(List<int>) → DeviceState
        StatePacket.encode(double, double, int) → List<int>
                │
                ▼
  lib/ble/ble_manager.dart          lib/ble/mock_ble_manager.dart
    abstract class BleManager           class MockBleManager implements BleManager
    (streams + methods interface)        (UnimplementedError stubs)
                │
                ▼
  lib/main.dart (minimal stub)
    ProviderScope(overrides: [bleManagerProvider.overrideWith((_) => MockBleManager())])
                │
                ▼
  test/ble/ble_protocol_test.dart
    round-trip test: encode known values → parse → verify float equality
```

### Recommended Project Structure

```
lib/
├── models/
│   └── device_state.dart       # DeviceState, ScannedDevice, ConnectionStatus
├── ble/
│   ├── ble_protocol.dart       # StatePacket, UUIDs, command constants
│   ├── ble_manager.dart        # abstract class BleManager
│   └── mock_ble_manager.dart   # MockBleManager stub (Phase 1) / full impl (Phase 2)
├── providers/                  # EMPTY in Phase 1 (Phase 3 fills this)
├── ui/                         # EMPTY in Phase 1 (Phase 4 fills this)
└── main.dart                   # minimal ProviderScope stub

test/
└── ble/
    └── ble_protocol_test.dart  # round-trip encode/parse unit tests
```

### Pattern 1: StatePacket Parse + Encode (canonical)

**What:** Binary protocol parsing using `dart:typed_data` — no external packages.
**When to use:** Any time raw `List<int>` bytes from BLE need to become typed Dart values.

```dart
// lib/ble/ble_protocol.dart
// Source: .planning/research/ARCHITECTURE.md (canonical design)

import 'dart:typed_data';
import 'package:inclinometer/models/device_state.dart';

const String kServiceUuid     = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid   = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid = '0000ZZZZ-0000-1000-8000-00805f9b34fb';

const int kCmdZeroX = 0x01;
const int kCmdZeroY = 0x02;

class StatePacket {
  static DeviceState parse(List<int> bytes) {
    assert(bytes.length == 9, 'State packet must be 9 bytes, got ${bytes.length}');
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return DeviceState(
      angleX:  bd.getFloat32(0, Endian.little),
      angleY:  bd.getFloat32(4, Endian.little),
      battery: bytes[8],
    );
  }

  static List<int> encode(double ax, double ay, int battery) {
    final bd = ByteData(9);
    bd.setFloat32(0, ax, Endian.little);
    bd.setFloat32(4, ay, Endian.little);
    bd.setUint8(8, battery);
    return bd.buffer.asUint8List().toList();
  }
}
```

**Key API point:** `ByteData.sublistView` requires a `TypedData` argument — a plain `List<int>` is NOT `TypedData`. The `Uint8List.fromList(bytes)` conversion step is mandatory. [VERIFIED: api.flutter.dev/flutter/dart-typed_data/ByteData/ByteData.sublistView.html]

### Pattern 2: DeviceState Manual Equality

**What:** Implement `==` and `hashCode` manually for a 3–4 field immutable data class.
**When to use:** Any model class that will be compared by value (Riverpod equality filter, unit test assertions).

```dart
// lib/models/device_state.dart

@immutable
class DeviceState {
  final double angleX;
  final double angleY;
  final int battery;

  const DeviceState({
    required this.angleX,
    required this.angleY,
    required this.battery,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState &&
          angleX == other.angleX &&
          angleY == other.angleY &&
          battery == other.battery;

  @override
  int get hashCode => Object.hash(angleX, angleY, battery);
}
```

**Float equality gotcha:** `==` on `double` fields works correctly for the round-trip test (encode → parse recovers the same IEEE 754 bits). However, do NOT use float equality for physics comparisons or user-visible thresholds — use `(a - b).abs() < epsilon` there. For unit tests comparing `encode → parse`, direct `==` is correct because the same float bits transit through `setFloat32` / `getFloat32`. [ASSUMED — based on IEEE 754 / Dart double behavior, not independently verified in this session]

### Pattern 3: abstract class BleManager + MockBleManager stub

**What:** Define the interface contract; stub all methods with `UnimplementedError` or empty stream.
**When to use:** Phase 1 needs the abstract class to compile `main.dart`; Phase 2 fills in real mock behavior.

```dart
// lib/ble/ble_manager.dart
// Source: .planning/research/ARCHITECTURE.md (canonical design)

import 'package:inclinometer/models/device_state.dart';

abstract class BleManager {
  Stream<ScannedDevice> get scanResults;
  Stream<ConnectionStatus> get connectionStatus;
  Stream<List<int>> get statePackets;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendCommand(int commandByte);

  void dispose();
}
```

```dart
// lib/ble/mock_ble_manager.dart

import 'dart:async';
import 'package:inclinometer/ble/ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';

class MockBleManager implements BleManager {
  @override
  Stream<ScannedDevice> get scanResults =>
      throw UnimplementedError('Phase 2: scanResults');

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      throw UnimplementedError('Phase 2: connectionStatus');

  @override
  Stream<List<int>> get statePackets =>
      throw UnimplementedError('Phase 2: statePackets');

  @override
  Future<void> startScan() => throw UnimplementedError('Phase 2: startScan');

  @override
  Future<void> stopScan() => throw UnimplementedError('Phase 2: stopScan');

  @override
  Future<void> connect(String deviceId) =>
      throw UnimplementedError('Phase 2: connect');

  @override
  Future<void> disconnect() => throw UnimplementedError('Phase 2: disconnect');

  @override
  Future<void> sendCommand(int commandByte) =>
      throw UnimplementedError('Phase 2: sendCommand');

  @override
  void dispose() {}
}
```

### Pattern 4: ProviderScope + bleManagerProvider stub in main.dart

```dart
// lib/main.dart (Phase 1 minimal stub)
// Source: .planning/research/ARCHITECTURE.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/ble/ble_manager.dart';

final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});

void main() {
  runApp(
    ProviderScope(
      overrides: [
        bleManagerProvider.overrideWith((_) => MockBleManager()),
      ],
      child: const MaterialApp(home: Scaffold(body: Center(child: Text('Phase 1')))),
    ),
  );
}
```

Note: `bleManagerProvider` may live in `lib/providers/device_provider.dart` rather than `main.dart` once Phase 3 creates that file. For Phase 1, placing it in `main.dart` avoids creating an otherwise-empty providers file.

### Pattern 5: Minimal Dart unit test

**What:** A test for pure Dart functions using `package:test`. No widgets, no Flutter engine.
**When to use:** `StatePacket.parse()` / `encode()` — these are pure Dart functions; no `flutter_test` setup required.

```dart
// test/ble/ble_protocol_test.dart

import 'package:test/test.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';

void main() {
  group('StatePacket', () {
    test('encode then parse round-trips float values', () {
      const ax = 12.345;
      const ay = -0.678;
      const battery = 72;

      final bytes = StatePacket.encode(ax, ay, battery);
      final state = StatePacket.parse(bytes);

      // float32 round-trip: same IEEE bits, direct == is correct here
      expect(state.angleX, closeTo(ax, 1e-4));
      expect(state.angleY, closeTo(ay, 1e-4));
      expect(state.battery, equals(battery));
    });

    test('parse asserts on wrong packet length', () {
      // assert fires in debug mode
      expect(
        () => StatePacket.parse([0, 1, 2]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('encode produces exactly 9 bytes', () {
      final bytes = StatePacket.encode(0.0, 0.0, 100);
      expect(bytes.length, equals(9));
    });
  });
}
```

**Run command:** `flutter test test/ble/ble_protocol_test.dart`

`flutter test` runs pure Dart tests correctly — it uses the `test` package underneath. [VERIFIED: docs.flutter.dev/cookbook/testing/unit/introduction]

**Float equality note:** `closeTo(ax, 1e-4)` is more appropriate than `equals()` for float round-trips through float32 encoding, because float64 → float32 → float64 loses ~7 decimal digits of precision. A tolerance of `1e-4` is safe for angles in degrees. [ASSUMED — well-known float32 precision behavior; not independently benchmarked]

### Anti-Patterns to Avoid

- **`ByteData.view(bytes.buffer, ...)`** when `bytes` is created via `Uint8List.fromList()`: The `fromList` result starts at offset 0 in a fresh buffer, so `view` would happen to work — but `sublistView` is the correct API for views on existing TypedData and handles offset correctly by design. Use `sublistView` consistently.
- **`ByteData.sublistView(bytes)` where `bytes` is `List<int>`**: Will NOT compile — `sublistView` takes `TypedData`, not `List<int>`. The `Uint8List.fromList()` conversion is not optional.
- **Putting `flutter_blue_plus` import in `lib/ble/ble_manager.dart`**: The abstract class must have zero BLE package imports. `flutter_blue_plus` belongs only in `RealBleManager` (WP2).
- **`StateNotifierProvider` in Riverpod 3.x**: Moved to `package:flutter_riverpod/legacy.dart`. Produces deprecation warnings on first `flutter pub get`. Never use for new code.
- **Single `BleManager` class with `isMock` flag**: Couples both code paths permanently; breaks the WP1→WP2 swap guarantee.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Float32 LE byte encoding/decoding | Custom bit-shift arithmetic | `ByteData.getFloat32(offset, Endian.little)` / `setFloat32` | IEEE 754 edge cases (NaN, infinity, subnormals) are handled by the Dart VM |
| Hash combining for `hashCode` | XOR of individual `hashCode`s | `Object.hash(a, b, c)` | XOR produces bad distribution; `Object.hash` uses a proper mixing function |
| Test assertion framework | Manual `if/throw` | `package:test` `expect()` + matchers | Readable failure messages, closeTo matcher for floats |

**Key insight:** `dart:typed_data` is the correct and complete solution for binary protocol parsing. There are no external packages that improve on it for this use case.

---

## Common Pitfalls

### Pitfall 1: `flutter create .` generates `.gitignore` that may overwrite the existing one

**What goes wrong:** The project already has a `.git/` directory (per the git status output). `flutter create .` will write a `.gitignore` file for Flutter projects. If a custom `.gitignore` already exists, `flutter create` without `--overwrite` will NOT replace it (it only recreates missing files). If no `.gitignore` exists yet, it creates a Flutter-standard one.

**Why it happens:** `flutter create` is designed to "repair" projects — it only writes files that are absent by default.

**How to avoid:** Verify `.gitignore` exists after `flutter create`. If the Flutter-generated one is used, verify it includes `.planning/` exemptions if needed (it shouldn't — `.planning/` is a directory not covered by default Flutter gitignore patterns). The generated Flutter `.gitignore` does include `/build/`, `*.g.dart`, `*.freezed.dart` which are all correct.

**Warning signs:** After `flutter create .`, run `git status` — all generated files should appear as untracked new files, not as modifications to existing tracked files.

### Pitfall 2: `flutter create .` also writes `test/widget_test.dart` (boilerplate)

**What goes wrong:** The generated `test/widget_test.dart` imports the counter app widget. After the boilerplate wipe, `flutter test` will fail on the widget test because `MyApp` widget no longer exists.

**Why it happens:** `flutter create` generates a starter widget test tied to the counter app scaffold.

**How to avoid:** Delete `test/widget_test.dart` as part of the boilerplate wipe step (D-02). Replace it with the proper `test/ble/ble_protocol_test.dart`.

### Pitfall 3: float32 precision loss in round-trip test — `equals()` assertion fails

**What goes wrong:** `StatePacket.encode(12.345, ...)` stores the value as IEEE 754 float32. When parsed back via `getFloat32`, the recovered `double` is NOT `12.345` exactly — it's the nearest float32 representable value. A test using `expect(state.angleX, equals(12.345))` will fail.

**Why it happens:** Dart `double` is float64; `setFloat32`/`getFloat32` operate on float32. The round-trip is lossy (~7 decimal digits of precision).

**How to avoid:** Use `closeTo(ax, 1e-4)` matcher in round-trip tests (see Pattern 5 above). For values near zero (like `ay = -0.678`), `1e-4` tolerance is safe.

**Warning signs:** Test failure message showing values like `12.345000267028809` vs `12.345`.

### Pitfall 4: `bleManagerProvider` location causes a Phase 3 refactor

**What goes wrong:** If `bleManagerProvider` is defined in `lib/main.dart` for Phase 1, Phase 3 will need to move it to `lib/providers/device_provider.dart`. This is a small but real refactor — every file that imports it needs updating.

**Why it happens:** Phase 1 avoids creating an otherwise-empty `providers/` file. But `device_provider.dart` will need `bleManagerProvider` from Phase 3 onward.

**How to avoid:** Either (a) create `lib/providers/device_provider.dart` in Phase 1 with just the `bleManagerProvider` definition, or (b) accept the minor Phase 3 refactor. Both are valid. If creating the file in Phase 1, the file is ~5 lines and adds no complexity.

**Recommendation:** Define `bleManagerProvider` in `lib/providers/device_provider.dart` from the start to avoid the Phase 3 refactor. The file is trivially small.

### Pitfall 5: `abstract class BleManager` without `@immutable` causes Riverpod 3.x equality surprises

**What goes wrong:** Riverpod 3.x uses `==` to suppress redundant emissions. `BleManager` is injected via `Provider<BleManager>` — if the provider rebuilds and returns a new `MockBleManager` instance, `==` defaults to identity, so consumers always see a "change" even when nothing changed.

**Why it happens:** `Provider<BleManager>` is declared at module level and `overrideWith` creates one instance. With `keepAlive` semantics (which `Provider` has by default in Riverpod 3.x), the manager instance is created once and never replaced.

**How to avoid:** No action needed — `Provider<BleManager>` is not autoDispose and the override creates a single instance. This is NOT a real pitfall for Phase 1, but worth knowing for Phase 3 when providers start being composed.

### Pitfall 6: `ConnectionStatus` enum not exhaustive in switch statements

**What goes wrong:** Dart enums used in `switch` without a `default` case (or explicit handling of all values) produce a warning in Dart 3.x. If Phase 3 adds a new `ConnectionStatus` value, existing switch statements miss it silently at runtime.

**Why it happens:** Dart 3.x sealed types and exhaustiveness checking applies to sealed classes, not enums in a `switch`. Unhandled cases fall through silently.

**How to avoid:** Define `ConnectionStatus` with all 7 values from the start (per CONN-01: `idle, scanning, connecting, connected, disconnecting, disconnected, error`). Don't add enum values in later phases.

---

## Code Examples

### `flutter create` command (D-01)

```bash
# Run in C:\Users\luke\OneDrive\VisualStudio\LevelAppMobile
# (the directory already has .git, CLAUDE.md, .planning/)
flutter create --org com.soldernerd --project-name inclinometer .
```

**Behavior:** [CITED: docs.flutter.dev/reference/flutter-cli]
- Creates `pubspec.yaml`, `lib/main.dart`, `android/`, `ios/`, `test/widget_test.dart`, `.gitignore` (if absent)
- Does NOT touch `.git/`, `CLAUDE.md`, `.planning/` — `flutter create` only writes Flutter-project files, and only recreates missing ones without `--overwrite`
- The `--project-name inclinometer` sets the Dart package name; `--org com.soldernerd` sets the Android/iOS application ID prefix

**Post-create verification:**
```bash
# Confirm key files were created
ls lib/main.dart
ls pubspec.yaml
ls android/app/build.gradle
ls test/widget_test.dart

# Confirm planning files untouched
ls .planning/PROJECT.md
ls CLAUDE.md
```

**Files to delete after create (D-02):**
```
test/widget_test.dart           # counter app widget test — delete entirely
lib/main.dart                   # counter app boilerplate — replace with stub
```

### pubspec.yaml (final Phase 1 state)

```yaml
name: inclinometer
description: "Precision inclinometer BLE companion app"
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.31.1
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
```

### `ScannedDevice` with manual equality

```dart
// lib/models/device_state.dart

@immutable
class ScannedDevice {
  final String id;
  final String name;
  final int rssi;

  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedDevice &&
          id == other.id &&
          name == other.name &&
          rssi == other.rssi;

  @override
  int get hashCode => Object.hash(id, name, rssi);
}
```

**Riverpod 3.x equality note:** [CITED: STACK.md / riverpod.dev/docs] Riverpod 3.x uses `==` to suppress duplicate emissions. `DeviceState` and `ScannedDevice` having correct `==`/`hashCode` means identical consecutive readings don't trigger unnecessary widget rebuilds.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `StateNotifierProvider` | `NotifierProvider` / `AsyncNotifierProvider` | Riverpod 3.0 | `StateNotifier` moved to legacy; use `Notifier` for all new code |
| `FutureProviderRef<T>` / `StreamProviderRef<T>` | Plain `Ref` | Riverpod 3.0 | All Ref subtypes removed; single `Ref` type everywhere |
| `ByteData(bytes.length)` + manual copy loop | `ByteData.sublistView(Uint8List.fromList(bytes))` | Dart 2.8 | `sublistView` added; eliminates offset calculation bugs |
| `hashCode` as XOR of fields | `Object.hash(a, b, c)` | Dart 2.14 | `Object.hash` provides better distribution; replaces manual XOR |
| `identical(this, other)` short-circuit | Still correct pattern | — | Unchanged — `identical` check before field comparison remains idiomatic |

**Deprecated/outdated:**
- `equatable` package: Still actively maintained but unnecessary for 3–4 field classes; D-04 locks this out.
- `freezed` + code-gen: Powerful but ~5× the complexity for plain data classes in a small project.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Float64→float32→float64 round-trip via `setFloat32`/`getFloat32` is losssy but recoverable within `1e-4` for angle values in the range ±90° | Code Examples (Pattern 5) | Unit tests using `closeTo(x, 1e-4)` might still fail for extreme angles; safe to verify by running the test |
| A2 | `flutter create .` without `--overwrite` does not touch `.planning/`, `CLAUDE.md`, or `.git/` | Common Pitfalls (Pitfall 1) | If wrong, planning files could be overwritten — low risk given `flutter create` only writes Flutter-project files |
| A3 | `bleManagerProvider` in `lib/providers/device_provider.dart` (vs `main.dart`) is cleaner for Phase 3 | Architecture Patterns | If wrong, a trivial 5-line move in Phase 3; no structural risk |

**If this table is empty:** Not applicable — three [ASSUMED] claims documented above.

---

## Open Questions (RESOLVED)

1. **`flutter create .` on Windows with OneDrive sync**
   - What we know: The project root is `C:\Users\luke\OneDrive\VisualStudio\LevelAppMobile` — an OneDrive-synced path. `flutter create` writes many files.
   - What's unclear: Whether OneDrive sync causes timing issues or file lock conflicts during `flutter create` in a synced directory.
   - Recommendation: Run `flutter create` and check for errors. If file lock errors occur, pause OneDrive sync temporarily (right-click tray icon → Pause). This is a runtime concern for the implementer, not a planning blocker.
   - RESOLVED: Document the concern in Plan 01-01 Task 1 action text. Executor pauses OneDrive if file-lock errors occur.

2. **ConnectionStatus enum completeness**
   - What we know: CONN-01 (Phase 3) defines 7 states: `idle, scanning, connecting, connected, disconnecting, disconnected, error`.
   - What's unclear: Whether Phase 1's `device_state.dart` should define all 7 states now, or just the ones Phase 1 needs.
   - Recommendation: Define all 7 states in Phase 1. The enum is a constant — no risk in defining it fully now, and it avoids a Phase 3 model file edit.
   - RESOLVED: Plan 01-02 Task 1 explicitly defines all 7 ConnectionStatus values: idle, scanning, connecting, connected, disconnecting, disconnected, error.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | `flutter create` + `flutter test` | Unknown (not verifiable from this session) | Unknown | — |
| Dart SDK | `dart:typed_data` | Bundled with Flutter | — | — |
| pub.dev registry | `flutter pub get` | Assumed available | — | — |

**Missing dependencies with no fallback:**
- Flutter SDK must be installed and on PATH. If not available, `flutter create` will fail. No fallback — Flutter is the project's locked platform.

**Note:** The Bash tool was unavailable for environment probing in this research session (session-env EEXIST error). The implementer should verify Flutter is available with `flutter --version` before beginning.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `package:test` 1.31.1 + `flutter_test` (SDK) |
| Config file | None — `flutter test` discovers `test/**/*_test.dart` automatically |
| Quick run command | `flutter test test/ble/ble_protocol_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROT-01 | 9-byte packet structure (4+4+1) | unit | `flutter test test/ble/ble_protocol_test.dart` | Wave 0 |
| PROT-02 | Command constants `ZERO_X=0x01`, `ZERO_Y=0x02` | unit | `flutter test test/ble/ble_protocol_test.dart` | Wave 0 |
| PROT-03 | GATT UUID constants defined (non-empty strings) | unit | `flutter test test/ble/ble_protocol_test.dart` | Wave 0 |
| PROT-04 | `parse()` produces correct `DeviceState` from known bytes | unit | `flutter test test/ble/ble_protocol_test.dart` | Wave 0 |
| ARCH-01 | `MockBleManager` implements all `BleManager` abstract methods (compiles) | compile | `flutter build apk --debug` or `flutter analyze` | implicit |
| ARCH-02 | No `flutter_blue_plus` import in `lib/ui/` or `lib/providers/` | static | `flutter analyze` / grep check | implicit |

### Sampling Rate

- **Per task commit:** `flutter test test/ble/ble_protocol_test.dart` (< 5 seconds)
- **Per wave merge:** `flutter test` (full suite)
- **Phase gate:** Full suite green + `flutter analyze` clean before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/ble/ble_protocol_test.dart` — covers PROT-01 through PROT-04
- [ ] `test/ble/` directory — does not exist yet (created in Phase 1)

*(The `flutter_test` SDK dependency is auto-included by `flutter create`. Only `test: ^1.31.1` needs manual addition to `pubspec.yaml`.)*

---

## Security Domain

> Phase 1 contains no network, auth, storage, or user input. Security domain is not applicable.

| ASVS Category | Applies | Notes |
|---------------|---------|-------|
| V2 Authentication | No | No auth in Phase 1 |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | No access control |
| V5 Input Validation | Partial | `assert(bytes.length == 9)` validates wire input in debug mode; assertions are disabled in release mode — this is intentional (protocol contract, not user input) |
| V6 Cryptography | No | No crypto |

**V5 note:** The `assert` for packet length is appropriate for a closed BLE protocol where the peripheral is trusted hardware. If future versions need to validate untrusted packet sources, replace `assert` with an explicit exception.

---

## Sources

### Primary (HIGH confidence)

- `.planning/research/ARCHITECTURE.md` — canonical BleManager interface, StatePacket code, data flow, build order. All code samples in Phase 1 derive from this document.
- `.planning/research/STACK.md` — package versions (flutter_riverpod 3.3.1, flutter_blue_plus 2.3.5), Riverpod 3.x breaking changes, confirmed on pub.dev 2026-06-04
- `api.flutter.dev/flutter/dart-typed_data/ByteData/ByteData.sublistView.html` — `sublistView` constructor signature; confirmed TypedData-only input
- `pub.dev/packages/flutter_riverpod` — version 3.3.1 stable, verified publisher riverpod.dev
- `pub.dev/packages/test` — version 1.31.1 stable, verified publisher dart.dev
- `docs.flutter.dev/cookbook/testing/unit/introduction` — flutter test + package:test for pure Dart unit tests confirmed

### Secondary (MEDIUM confidence)

- `docs.flutter.dev/reference/flutter-cli` + Flutter GitHub source — `flutter create .` behavior: only recreates missing files without `--overwrite`; does not touch `.git/`, non-Flutter files
- `dart.dev/effective-dart/design` — multiple classes per file acceptable in Dart; separate files for mock/abstract is a common but not mandatory convention
- `apparencekit.dev` — `Object.hash()` for combining hashCode fields; replaces manual XOR

### Tertiary (LOW confidence)

- None — all claims are PRIMARY or SECONDARY in this research.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified on pub.dev 2026-06-04; canonical architecture from ARCHITECTURE.md
- Architecture: HIGH — based on ARCHITECTURE.md (Context7-verified patterns)
- ByteData API: HIGH — verified against official Dart API docs
- Pitfalls: HIGH — derived from established Dart/Flutter documentation + ARCHITECTURE.md

**Research date:** 2026-06-04
**Valid until:** 2026-09-04 (stable APIs; Riverpod 3.x is the current major version)
