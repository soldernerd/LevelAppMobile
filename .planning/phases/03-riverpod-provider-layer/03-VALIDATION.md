---
phase: 03-riverpod-provider-layer
slug: riverpod-provider-layer
date: 2026-06-05
---

# Phase 3 Validation Architecture

## Test Framework

| Property | Value |
|----------|-------|
| Framework | test ^1.31.0 + fake_async ^1.3.3 (already in pubspec) |
| Config file | None — pure dart test runner |
| Quick run command | `flutter test test/providers/` |
| Full suite command | `flutter test` |

## Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command |
|--------|----------|-----------|-------------------|
| CONN-01 | State machine: idle→scanning→connecting→connected | unit | `flutter test test/providers/connection_notifier_test.dart` |
| CONN-01 | State machine: connected→disconnecting→disconnected | unit | same |
| CONN-01 | State machine: error state on unexpected disconnect | unit | same |
| CONN-02 | `disconnect()` transitions to disconnected | unit | same |
| CONN-03 | `_autoReconnectEnabled = false` — reconnecting not entered in WP1 | unit | same |
| CONN-05 | null emitted to instrumentDataProvider on disconnect | unit | `flutter test test/providers/instrument_data_provider_test.dart` |
| CONN-06 | `ConnectionStatus.reconnecting` exists in enum | unit | `flutter test test/providers/connection_notifier_test.dart` |
| SYS-01 | WakelockPlus.enable/disable calls present in device_provider.dart | grep | `grep -c 'WakelockPlus.enable' lib/providers/device_provider.dart` >= 1 |

## Wave 0 Gaps (files that must exist before tests compile)

- [ ] `test/providers/connection_notifier_test.dart` — CONN-01, CONN-02, CONN-03, CONN-06
- [ ] `test/providers/instrument_data_provider_test.dart` — CONN-05
- [ ] `lib/models/device_state.dart` — add `reconnecting` to `ConnectionStatus` enum

## Sampling Rate

- Per task commit: `flutter test test/providers/`
- Per wave merge: `flutter test`
- Phase gate: full suite green before `/gsd:verify-work 3`

## Note on Wakelock Testing

`WakelockPlus.enable/disable` are static platform methods. In a pure Dart test environment
they may throw `MissingPluginException`. Tests proxy SYS-01 via state-machine assertions
(connected/disconnected transitions). The grep criterion above provides static code
verification that the calls are present in the production code.
