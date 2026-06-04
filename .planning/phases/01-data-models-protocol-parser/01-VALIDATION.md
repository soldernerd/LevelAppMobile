---
phase: 1
phase_slug: data-models-protocol-parser
created: "2026-06-04"
---

# Validation Strategy — Phase 1: Data Models + Protocol Parser

## Test Framework

| Property | Value |
|----------|-------|
| Framework | `package:test` 1.31.1 + `flutter_test` (SDK) |
| Config file | None — `flutter test` discovers `test/**/*_test.dart` automatically |
| Quick run command | `flutter test test/ble/ble_protocol_test.dart` |
| Full suite command | `flutter test` |
| Analyze command | `flutter analyze` |

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Wave |
|--------|----------|-----------|-------------------|------|
| PROT-01 | 9-byte packet structure (4+4+1 layout, float32LE + uint8) | unit | `flutter test test/ble/ble_protocol_test.dart` | 4 |
| PROT-02 | `kCmdZeroX = 0x01`, `kCmdZeroY = 0x02` constants importable | unit | `flutter test test/ble/ble_protocol_test.dart` | 4 |
| PROT-03 | GATT UUID constants defined as non-null, non-empty String constants | unit | `flutter test test/ble/ble_protocol_test.dart` | 4 |
| PROT-04 | `StatePacket.parse(List<int>)` returns correct `DeviceState` using `ByteData.getFloat32(Endian.little)` | unit | `flutter test test/ble/ble_protocol_test.dart` | 4 |
| ARCH-01 | `MockBleManager implements BleManager` compiles without stub warnings — all abstract members overridden | compile | `flutter analyze lib/ble/` | 3 |
| ARCH-02 | No `flutter_blue_plus` import anywhere in `lib/ui/` or `lib/providers/` | static | `Select-String -Path lib/ui/*.dart,lib/providers/*.dart -Pattern flutter_blue_plus` (expect no matches) | 4 |

## Test Cases (Wave 4 — test/ble/ble_protocol_test.dart)

| Test | Assertion | Covers |
|------|-----------|--------|
| `encode then parse round-trips float values` | `closeTo(ax, 1e-4)`, `closeTo(ay, 1e-4)`, `equals(battery)` | PROT-01, PROT-04 |
| `parse asserts on wrong packet length` | `throwsA(isA<AssertionError>())` for 3-byte input | PROT-01 |
| `encode produces exactly 9 bytes` | `expect(bytes.length, equals(9))` | PROT-01 |
| `command constants have correct values` | `expect(kCmdZeroX, equals(0x01))`, `expect(kCmdZeroY, equals(0x02))` | PROT-02 |
| `UUID constants are non-empty strings` | `expect(kServiceUuid.isNotEmpty, isTrue)` etc. | PROT-03 |

**Float assertion note:** `closeTo(ax, 1e-4)` is mandatory for round-trip tests — `equals()` will fail due to float64→float32 precision loss. Tolerance `1e-4` is safe for angle values in ±180° range.

## Sampling Rate

| Trigger | Command | Gate |
|---------|---------|------|
| After each Dart file written | `dart analyze <file>` | No analysis errors on the specific file |
| After Wave 2 complete (models + parser) | `flutter test test/ble/ble_protocol_test.dart` | All parse/encode tests pass |
| After Wave 3 complete (interface + mock stub) | `flutter analyze lib/ble/` | No analyzer errors in BLE layer |
| Phase gate (after Wave 4) | `flutter test && flutter analyze` | Full suite green + clean analysis |

## Wave Gaps

Files that must be created before the validation commands will pass:

- [ ] `test/ble/ble_protocol_test.dart` — covers PROT-01 through PROT-04 (created in Wave 4)
- [ ] `test/ble/` directory — created alongside the test file in Wave 4

*(The `flutter_test` SDK dependency is auto-included by `flutter create`. Only `test: ^1.31.1` needs manual addition to `pubspec.yaml`.)*

## Security Notes

Phase 1 contains no network, auth, storage, or user input. Security domain is not applicable. The `assert(bytes.length == 9)` length check in `StatePacket.parse()` is a protocol contract assertion, not a security validation — assertions are disabled in release mode, which is intentional for a closed BLE protocol with trusted hardware.
