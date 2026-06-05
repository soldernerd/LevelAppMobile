---
phase: 4
slug: ui-screens
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-05
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (Flutter SDK) |
| **Config file** | none — flutter test discovers `test/` automatically |
| **Quick run command** | `flutter test test/ui/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/ui/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | INST-05, INST-06 | — | N/A | unit | `flutter test test/providers/ -n "sendCommand"` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | SCAN-01–05, INST-01–07, CONN-04 | — | N/A | widget stub | `flutter test test/ui/` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | SCAN-01, SCAN-02, SCAN-03, SCAN-04, SCAN-05, INST-01 | — | N/A | widget | `flutter test test/ui/scan_screen_test.dart` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 2 | SCAN-01–05, INST-01 | — | N/A | widget | `flutter test test/ui/scan_screen_test.dart` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | INST-02, INST-03, INST-04, INST-05, INST-06, INST-07, CONN-04 | — | N/A | widget | `flutter test test/ui/instrument_screen_test.dart` | ❌ W0 | ⬜ pending |
| 04-04-01 | 04 | 3 | SCAN-01, SCAN-02, SCAN-03, SCAN-04, SCAN-05 | — | N/A | widget | `flutter test test/ui/scan_screen_test.dart` | ❌ W0 | ⬜ pending |
| 04-04-02 | 04 | 3 | INST-01, INST-02, INST-03, INST-04, INST-05, INST-06, INST-07, CONN-04 | — | N/A | widget | `flutter test test/ui/instrument_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/ui/scan_screen_test.dart` — stubs for SCAN-01 through SCAN-05; requires `ProviderScope` with `MockBleManager` override
- [ ] `test/ui/instrument_screen_test.dart` — stubs for INST-01 through INST-07, CONN-04; requires `ProviderScope` with `MockBleManager` override and manual state pump

Wave 0 is covered by plan 04-01, Task 2 (test scaffold creation in Wave 1).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual: 80sp angle text dominates screen | INST-02, INST-03 | Font size not directly assertable in widget tests | Run app, verify readout fills ~60% of instrument screen height |
| Visual: stale fade to 40% opacity | CONN-05 (Phase 3) | AnimatedOpacity final rendered opacity not assertable | Run app, trigger simulateDisconnect, verify readout visually fades |
| Visual: connection chip color (green/amber/red) | CONN-04 | Color rendering not assertable via widget key | Run app, observe chip changes through connecting→connected→disconnected |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
