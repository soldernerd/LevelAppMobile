# Phase 5: App Wiring + Platform Config - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the Phase 4 temporary `main.dart` with the production entry point: go_router navigation with a route guard, `permission_handler` BLE permission flow, and correct Android/iOS build config. Phases 1–4 provide all providers and widgets — this phase is pure wiring. No new providers, no new UI components.

</domain>

<decisions>
## Implementation Decisions

### Permission Flow
- **D-01:** Rationale dialog fires on first app launch (before the system prompt), every cold start until permissions are granted. Does NOT defer until the user taps Scan.
- **D-02:** When BLE permissions are permanently denied, show an inline message on the scan screen (not a dialog, not a full-screen replacement) with a "Open Settings" button that calls `openAppSettings()`. The scan screen remains mounted beneath the message.

### Route Guard
- **D-03:** The go_router redirect allows instrument screen access only when `ConnectionStatus == connected`. All other states redirect to `/scan`.
- **D-04:** The guard fires only on navigation *attempts* to `/instrument` — it does NOT re-evaluate while the user is already on the instrument screen. A disconnect while on the instrument screen keeps the user there (honoring Phase 4 D-10 stay-on-screen convention). Implementation: do not wire `refreshListenable` for redirect-on-disconnect; use it only to unblock navigation after permissions/connection are established.

### App Entry Point (main.dart)
- **D-05:** Theme: `ThemeData.dark()` only — no light theme, no system-adaptive theming. Consistent with Phase 4 temporary main.dart and workshop readability requirement.
- **D-06:** go_router instance lives as a top-level `final` variable in `main.dart` (not a Riverpod provider). refreshListenable bridge implemented via a custom `ChangeNotifier` that listens to `connectionNotifierProvider` — standard go_router + Riverpod pattern.
- **D-07:** `ProviderScope.overrides` retains `bleManagerProvider.overrideWithValue(MockBleManager())` — the WP2 swap is one line change here.

### Build Config
- **D-08:** `build.gradle.kts` must hardcode `minSdk = 24` and `compileSdk = 35` (replace `flutter.minSdkVersion` / `flutter.compileSdkVersion` delegates). Satisfies BUILD-01 and BUILD-02 + `permission_handler` 12.x requirement.

### Claude's Discretion
- Exact wording of the rationale dialog and permanently-denied inline message.
- Named routes vs. path strings in go_router — use whatever is idiomatic for go_router 17.x.
- iOS `Info.plist` Bluetooth usage description string wording.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — Phase 5 covers: PERM-01, PERM-02, PERM-03, PERM-04, PERM-05, BUILD-01, BUILD-02. These are the acceptance criteria.

### Architecture Constraints
- `CLAUDE.md` — Stack table: `permission_handler 12.0.3` requires `compileSdkVersion 35`; `go_router 17.3.0` needs refreshListenable bridge for Riverpod; `wakelock_plus` acquire/release on connected/disconnected (already wired in Phase 3 providers).

### Phase 4 Context (decisions carried forward)
- `.planning/phases/04-ui-screens/04-CONTEXT.md` — D-10: on disconnect, app stays on instrument screen (no auto-navigate). Route guard must not override this.

### Existing Platform Files (read before modifying)
- `android/app/build.gradle.kts` — currently uses `flutter.minSdkVersion` delegates; must be replaced with hardcoded values.
- `android/app/src/main/AndroidManifest.xml` — no BLE permissions declared yet; add `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`.
- `ios/Runner/Info.plist` — add `NSBluetoothAlwaysUsageDescription` key.
- `lib/main.dart` — Phase 4 temporary entry point; replace entirely in Phase 5.

### Provider API
- `lib/providers/device_provider.dart` — `connectionNotifierProvider`, `bleManagerProvider`. Route guard reads `connectionNotifierProvider` state.
- `lib/ble/mock_ble_manager.dart` — injected via `bleManagerProvider.overrideWithValue(MockBleManager())`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `connectionNotifierProvider` (Riverpod `Notifier`) — source of truth for `ConnectionStatus`; the go_router refreshListenable bridge wraps this.
- `ScanScreen` and `InstrumentScreen` in `lib/ui/` — already built; main.dart just routes to them.

### Established Patterns
- `ProviderScope.overrides` with `bleManagerProvider.overrideWithValue(MockBleManager())` — established in Phase 4 main.dart; carry forward unchanged.
- `ThemeData.dark()` — established in Phase 4 main.dart.

### Integration Points
- `lib/main.dart` — full replacement. New file wires: `ProviderScope` → `ConsumerWidget` (or `WidgetsApp`) → `MaterialApp.router(routerConfig: _router)`.
- `android/app/build.gradle.kts` — minSdk + compileSdk values only; leave all other config untouched.
- `android/app/src/main/AndroidManifest.xml` — add permission declarations inside `<manifest>`; leave `<application>` block untouched.

</code_context>

<specifics>
## Specific Ideas

- Route guard is a *navigation guard* (prevent entry), not a *presence guard* (auto-eject). This distinction must be preserved in the go_router `redirect` callback.
- `permission_handler` flow runs before any scan attempt — not lazily. The rationale dialog should explain the BLE need in plain terms (e.g., "This app needs Bluetooth to connect to your inclinometer.").
- `build.gradle.kts` uses Kotlin DSL (`= 24` not `24`). Replacements must use the correct syntax.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 5-App Wiring + Platform Config*
*Context gathered: 2026-06-05*
