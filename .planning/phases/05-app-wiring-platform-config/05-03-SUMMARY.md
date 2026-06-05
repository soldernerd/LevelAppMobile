---
phase: 05-app-wiring-platform-config
plan: "03"
subsystem: app-entry-navigation-permissions
tags: [main, go_router, permission_handler, riverpod, ProviderContainer, navigation]
dependency_graph:
  requires: [05-01, 05-02]
  provides: [production-main-dart, go_router-navigation, permission-rationale-ui]
  affects: [lib/main.dart, lib/ui/scan_screen.dart, test/ui/scan_screen_test.dart]
tech_stack:
  added: []
  patterns: [ProviderContainer+UncontrolledProviderScope, GoRouter-redirect-guard, go_router-context.go, permission-rationale-dialog]
key_files:
  modified:
    - lib/main.dart
    - lib/ui/scan_screen.dart
    - test/ui/scan_screen_test.dart
decisions:
  - "Used UncontrolledProviderScope(container: _container) instead of ProviderScope(parent:) — flutter_riverpod 3.3.1 does not expose a parent parameter on ProviderScope; UncontrolledProviderScope accepts a pre-built ProviderContainer directly"
  - "No refreshListenable on GoRouter (D-04) — redirect fires on navigation only; ScanScreen drives post-connect navigation via context.go('/instrument')"
  - "File-scope _blePermissionsRequested bool guards rationale dialog — ConsumerWidget has no instance state; file-scope bool persists across rebuilds within a session"
  - "Updated scan_screen_test.dart to use MaterialApp.router + GoRouter — context.go() requires a go_router context; MaterialApp(home:) does not provide one"
metrics:
  duration: "~20 minutes"
  completed: "2026-06-05"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 05 Plan 03: App Entry Point, Navigation, and Permission UI Summary

## One-liner

Production main.dart with GoRouter /scan+/instrument redirect guard, ProviderContainer MockBleManager injection, and ScanScreen permission rationale dialog + permanently-denied inline banner.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace main.dart with production entry point | def1a32 | lib/main.dart |
| 2 | Update ScanScreen for go_router nav, permission UI | 7322e72 | lib/ui/scan_screen.dart, test/ui/scan_screen_test.dart |

## Decisions Made

- `UncontrolledProviderScope(container: _container)` used instead of `ProviderScope(parent: _container)` — flutter_riverpod 3.3.1 does not expose a `parent:` parameter on `ProviderScope`. The `UncontrolledProviderScope` widget accepts a pre-built `ProviderContainer` directly and wires it into the widget tree. This satisfies D-07 (ProviderContainer carries overrides; ProviderScope uses parent container).
- No `refreshListenable` on GoRouter (D-04 honored) — redirect fires only on navigation attempts. Post-connect navigation is explicit via `context.go('/instrument')` in ScanScreen's `ref.listen` callback.
- File-scope `_blePermissionsRequested` bool prevents rationale dialog from re-showing on every `ScanScreen` rebuild — ConsumerWidget has no mutable instance state; file-scope persists within the session.
- `scan_screen_test.dart` updated to use `MaterialApp.router` + `GoRouter` — `context.go()` requires a GoRouter in the widget tree; old `MaterialApp(home:)` harness had no router, causing `GoRouter.of(context)` assertion failures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ProviderScope has no `parent:` parameter in flutter_riverpod 3.3.1**
- **Found during:** Task 1 — `flutter analyze lib/main.dart` returned `undefined_named_parameter`
- **Issue:** Plan specified `ProviderScope(parent: _container)` but this parameter does not exist in flutter_riverpod 3.3.1. The `parent:` parameter was either from an older API or documentation error.
- **Fix:** Replaced with `UncontrolledProviderScope(container: _container)` — the correct API for injecting a pre-built ProviderContainer into the widget tree.
- **Files modified:** lib/main.dart
- **Commit:** def1a32

**2. [Rule 1 - Bug] scan_screen_test.dart harness incompatible with context.go navigation**
- **Found during:** Task 2 verification — `flutter test test/ui/` showed `No GoRouter found in context` errors on SCAN-05 and INST-01
- **Issue:** Tests used `MaterialApp(home: ScanScreen())` which does not provide a GoRouter. `context.go('/instrument')` requires `GoRouter.of(context)` which asserts when no router is present.
- **Fix:** Updated `buildHarness()` and inline test scaffolds to use `MaterialApp.router(routerConfig: _buildRouter())` with a `GoRouter` providing `/scan` and `/instrument` routes.
- **Files modified:** test/ui/scan_screen_test.dart
- **Commit:** 7322e72

## Known Stubs

None.

## Threat Flags

None. All security surfaces from the threat model are implemented:
- T-05-03: GoRouter redirect guard (`matchedLocation == '/instrument' && status != connected`) is in place.
- T-05-04: Rationale dialog shown before system permission prompt (PERM-03 satisfied).

## Self-Check: PASSED

- lib/main.dart exists: confirmed
- lib/ui/scan_screen.dart exists: confirmed
- `grep "WidgetsFlutterBinding.ensureInitialized" lib/main.dart` — 1 match: confirmed
- `grep "ProviderContainer" lib/main.dart` — 1 match: confirmed
- `grep "UncontrolledProviderScope" lib/main.dart` — 1 match (satisfies D-07 parent: _container intent): confirmed
- `grep "refreshListenable" lib/main.dart` — 0 matches: confirmed
- `grep "matchedLocation.*instrument" lib/main.dart` — 1 match: confirmed
- `grep "context.go('/instrument')" lib/ui/scan_screen.dart` — 1 match: confirmed
- `grep "Navigator.of(context).push" lib/ui/scan_screen.dart` — 0 matches: confirmed
- `grep "openAppSettings" lib/ui/scan_screen.dart` — 1 match: confirmed
- `grep "sdkInt" lib/ui/scan_screen.dart` — 1 match: confirmed
- `flutter test` — 43/43 tests passed: confirmed
- `flutter analyze lib/` — No issues found: confirmed
- Commits def1a32, 7322e72 exist in git log: confirmed
