# Phase 1: Data Models + Protocol Parser - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 01-data-models-protocol-parser
**Areas discussed:** Flutter project scaffold, StatePacket.encode() scope, Model equality strategy

---

## Flutter Project Scaffold

### Q1: How should the Flutter project be created?

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 1 runs `flutter create` first | `flutter create .` in project root; planning docs coexist alongside Flutter project files | ✓ |
| Manual creation before Phase 1 | User runs `flutter create` themselves before executing Phase 1 | |
| Existing scaffold elsewhere | Flutter project exists in a different folder | |

**User's choice:** Phase 1 runs `flutter create` first
**Notes:** Project root currently has only CLAUDE.md and .planning/ — no pubspec.yaml or Dart files.

### Q2: Where should `flutter create` target?

| Option | Description | Selected |
|--------|-------------|----------|
| In-place: `flutter create .` | Creates Flutter files directly in LevelAppMobile/ | ✓ |
| Subdirectory: `flutter create app` | Flutter project in LevelAppMobile/app/ | |

**User's choice:** In-place — `flutter create .`
**Notes:** Planning docs already live in this directory; in-place keeps all project files at the same root level.

### Q3: Generated boilerplate handling

| Option | Description | Selected |
|--------|-------------|----------|
| Wipe defaults, Phase 1 creates its own files | Delete counter app; Phase 1 writes minimal main.dart stub and proper test/ structure | ✓ |
| Keep generated files | Leave lib/main.dart as counter app; Phase 1 only adds layer files | |

**User's choice:** Wipe the defaults, Phase 1 creates its own files

---

## StatePacket.encode() Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Include encode() in Phase 1 | encode() and parse() defined together; enables round-trip testing | ✓ |
| Defer encode() to Phase 2 | PROT-04 only requires parse(); add encode() when MockBleManager needs it | |

**User's choice:** Include encode() in Phase 1
**Notes:** Round-trip testing (encode → parse) provides a clean correctness check for the float32LE endianness implementation.

---

## Model Equality Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Manual == / hashCode | Write equals + hashCode by hand; no extra dependencies | ✓ |
| equatable package | Extend Equatable; reduces boilerplate but adds dependency | |
| freezed codegen | Full codegen: immutable classes, copyWith, equality | |

**User's choice:** Manual == / hashCode
**Notes:** Models have 3–4 fields each. Manual implementation avoids expanding the dependency footprint beyond the declared stack.

---

## Claude's Discretion

- **Error handling in StatePacket.parse():** Dart `assert(bytes.length == 9, ...)` for length validation — appropriate for dev-time protocol errors, not user-facing error handling.
- **MockBleManager file placement:** Claude decides whether to place in `ble_manager.dart` or a separate `mock_ble_manager.dart` based on file length at implementation time.

## Deferred Ideas

None — discussion stayed within phase scope.
