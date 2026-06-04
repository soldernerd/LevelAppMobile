---
phase: 2
slug: ble-abstraction-mock-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-04
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `package:test` 1.31.0 + `package:fake_async` 1.3.3 |
| **Config file** | none (uses default `flutter test` discovery) |
| **Quick run command** | `flutter test test/ble/mock_ble_manager_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/ble/mock_ble_manager_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-T1 | 01 | 0 | MOCK-01..04 | — | N/A | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 | ⬜ pending |
| 2-01-T2 | 01 | 1 | MOCK-01 | — | N/A | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 | ⬜ pending |
| 2-01-T3 | 01 | 1 | MOCK-02 | — | N/A | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 | ⬜ pending |
| 2-01-T4 | 01 | 1 | MOCK-03 | — | N/A | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 | ⬜ pending |
| 2-01-T5 | 01 | 1 | MOCK-04 | — | N/A | unit (fakeAsync) | `flutter test test/ble/mock_ble_manager_test.dart` | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/ble/mock_ble_manager_test.dart` — stubs + imports for MOCK-01 through MOCK-04
- [ ] `package:fake_async` promoted to direct dev dep (`flutter pub add --dev fake_async`)

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
