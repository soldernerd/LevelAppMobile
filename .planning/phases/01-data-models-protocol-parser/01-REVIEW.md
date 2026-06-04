---
phase: 01-data-models-protocol-parser
reviewed: 2026-06-04T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - lib/ble/ble_manager.dart
  - lib/ble/ble_protocol.dart
  - lib/ble/mock_ble_manager.dart
  - lib/main.dart
  - lib/models/device_state.dart
  - lib/providers/device_provider.dart
  - pubspec.yaml
  - test/ble/ble_protocol_test.dart
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-06-04
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 1 delivers a clean minimal scaffold: the BleManager abstraction is well-drawn, the
StatePacket parser is correct for the happy path, and the MockBleManager stub pattern is
appropriate for WP1. However, two blockers require immediate attention before WP2 wiring
begins: a stated architectural requirement (`keepAlive: true`) is absent, and a logic error
in `ScannedDevice.operator==` will produce wrong behaviour the moment scan results are used
in any collection or deduplication context. Three additional warnings address release-mode
safety and model correctness.

---

## Critical Issues

### CR-01: `bleManagerProvider` missing `keepAlive: true` — violates stated architectural constraint

**File:** `lib/providers/device_provider.dart:13`

**Issue:** CLAUDE.md explicitly states: "BLE connection provider needs `keepAlive: true` — it
must not tear down on navigation." The current `Provider<BleManager>` definition has no
`keepAlive` annotation. Without it, Riverpod 3.x will auto-dispose the provider when its last
listener leaves the widget tree (e.g., during a navigation push). This tears down the
`BleManager` instance mid-connection, triggering an unexpected disconnect with no UI feedback.
The constraint is documented precisely because this is a known footgun in Riverpod BLE apps.

**Fix:**
```dart
// lib/providers/device_provider.dart
final bleManagerProvider = Provider<BleManager>(
  (ref) {
    throw UnimplementedError('bleManagerProvider must be overridden at root');
  },
  keepAlive: true,   // <-- add this
);
```

---

### CR-02: `ScannedDevice.operator==` includes `rssi` — device identity logic is wrong

**File:** `lib/models/device_state.dart:52-61`

**Issue:** RSSI is the received signal strength at the moment of the advertisement — it changes
on every BLE advertisement from the same physical device. Including `rssi` in `operator==`
means two `ScannedDevice` objects representing the *same* physical device with slightly
different signal readings compare as unequal. Any `Set<ScannedDevice>`, `List.contains()`,
deduplication, or `distinctUnique()` stream operator built on this model will accumulate
duplicate entries for the same device rather than updating them, filling the scan list with
phantom duplicates. The `hashCode` is computed consistently with `operator==`, so the hash
table behaviour is internally consistent but externally wrong.

**Fix:** Identity should be based on `id` alone (the BLE MAC address / peripheral UUID).
`name` and `rssi` are attributes, not identity:

```dart
@override
bool operator ==(Object other) =>
    identical(this, other) ||
    other is ScannedDevice && id == other.id;

@override
int get hashCode => id.hashCode;
```

---

## Warnings

### WR-01: Assert in `StatePacket.parse` is a no-op in release builds — unprotected index access at line 32

**File:** `lib/ble/ble_protocol.dart:23-26, 32`

**Issue:** Dart `assert()` statements are stripped in release and profile builds
(`flutter run --release`, `flutter build apk`). The length guard at lines 23-26 therefore
provides zero protection in the builds that ship to users. `bytes[8]` at line 32 will throw
an unhandled `RangeError` at runtime if a malformed BLE packet shorter than 9 bytes arrives
(e.g., a firmware regression or a different characteristic accidentally subscribed to).
`getFloat32(0, ...)` and `getFloat32(4, ...)` on the ByteData will similarly throw
`RangeError` for packets shorter than 8 bytes.

**Fix:** Replace the `assert` with a hard guard that also fires in release mode, and return
a typed error or throw a domain exception:

```dart
static DeviceState parse(List<int> bytes) {
  if (bytes.length != 9) {
    throw ArgumentError.value(
      bytes.length,
      'bytes',
      'State packet must be exactly 9 bytes',
    );
  }
  final bd = ByteData.sublistView(Uint8List.fromList(bytes));
  return DeviceState(
    angleX: bd.getFloat32(0, Endian.little),
    angleY: bd.getFloat32(4, Endian.little),
    battery: bytes[8],
  );
}
```

Callers (the BLE notification handler in WP2) should catch `ArgumentError` and log/discard
the malformed packet rather than crashing.

---

### WR-02: `battery` field has no range validation — out-of-range values propagate silently

**File:** `lib/models/device_state.dart:19`

**Issue:** `battery` is declared as `int` with no bounds constraint. A raw BLE byte is 0–255,
so a firmware bug reporting 0xFF (255) would be stored and displayed as "255%" battery with
no indication of an error. The comment in `ble_protocol.dart` documents the field as `uint8`
(0–255), but semantically the app intends a percentage (0–100). Values above 100 will reach
the UI and produce nonsensical readings.

**Fix:** Add a range clamp or assertion in `StatePacket.parse` after parsing the battery byte,
and document the valid range in `DeviceState`:

```dart
// In DeviceState:
/// Battery level, 0–100 (percent). Values outside this range
/// indicate a firmware protocol error.
final int battery;

// In StatePacket.parse, after reading bytes[8]:
final rawBattery = bytes[8];
if (rawBattery > 100) {
  throw ArgumentError.value(rawBattery, 'battery', 'Battery must be 0–100');
}
```

Alternatively, clamp silently and emit a log warning rather than throwing, depending on how
aggressively the app should handle firmware regressions.

---

### WR-03: Assert-on-wrong-length test only exercises debug-mode behaviour

**File:** `test/ble/ble_protocol_test.dart:21-25`

**Issue:** The test at line 21 asserts that `StatePacket.parse([0, 1, 2])` throws an
`AssertionError`. Tests run via `flutter test` do execute with asserts enabled, so the test
passes today. However, the test documents a behaviour that does not hold in release builds
(see WR-01). If WR-01 is fixed by replacing the `assert` with an `ArgumentError`, this test
will break because it expects `AssertionError` specifically. This is a test–implementation
contract mismatch waiting to happen.

**Fix:** After applying WR-01's fix, update this test to expect `ArgumentError`:

```dart
test('parse throws on wrong packet length', () {
  expect(
    () => StatePacket.parse([0, 1, 2]),
    throwsA(isA<ArgumentError>()),
  );
});
```

---

## Info

### IN-01: Placeholder UUID constants are not valid UUID format

**File:** `lib/ble/ble_protocol.dart:6-8`

**Issue:** The UUID constants contain literal `XXXX`, `YYYY`, `ZZZZ` as hex fields:

```dart
const String kServiceUuid = '0000XXXX-0000-1000-8000-00805f9b34fb';
```

These are not valid UUIDs (hex digits are `[0-9a-fA-F]` only; `X`, `Y`, `Z` are not valid).
`flutter_blue_plus`'s GUID parsing will reject them when WP2 passes them to
`FlutterBluePlus.servicesByUuid()` or characteristic lookup. The failure mode will be a
runtime exception or silent empty result with no clear error pointing back to these constants.
A TODO comment flagging this for WP2 replacement would prevent a confusing WP2 debugging
session.

**Fix:** Add an inline comment making the placeholder status unambiguous:

```dart
// TODO(WP2): Replace with actual GATT UUIDs from instrument firmware spec.
const String kServiceUuid    = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid  = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid = '0000ZZZZ-0000-1000-8000-00805f9b34fb';
```

---

### IN-02: WP2 dependency declarations absent from `pubspec.yaml`

**File:** `pubspec.yaml`

**Issue:** CLAUDE.md lists five required packages with pinned versions:
`flutter_blue_plus 2.3.5`, `permission_handler 12.0.3`, `go_router 17.3.0`,
`wakelock_plus latest`. None of these appear in `pubspec.yaml`. While Phase 1 intentionally
does not use them, their absence means version conflicts (especially the
`compileSdkVersion 35` requirement for `permission_handler`, and the
`flutter_blue_plus` commercial license note) will surface as surprises at the start of WP2
rather than being acknowledged upfront. Adding them as commented stubs or
documenting them in a `# WP2 dependencies:` comment block would prevent a
context-switch cost during WP2 kickoff.

**Fix:** Add a commented block in `pubspec.yaml` noting the WP2 additions:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^3.3.1

  # WP2 — uncomment when wiring real BLE:
  # flutter_blue_plus: 2.3.5   # NOTE: commercial license required for 15+ employees
  # permission_handler: ^12.0.3 # Requires compileSdkVersion 35 (already set)
  # go_router: ^17.3.0          # Needs refreshListenable bridge for Riverpod
  # wakelock_plus: any          # Acquire on connected, release on disconnected
```

---

_Reviewed: 2026-06-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
