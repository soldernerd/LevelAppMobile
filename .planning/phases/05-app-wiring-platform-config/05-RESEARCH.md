# Phase 5: App Wiring + Platform Config - Research

**Researched:** 2026-06-05
**Domain:** Flutter app entry point wiring — go_router, permission_handler, Android/iOS platform config
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Rationale dialog fires on first app launch (before the system prompt), every cold start until permissions are granted. Does NOT defer until the user taps Scan.
- **D-02:** When BLE permissions are permanently denied, show an inline message on the scan screen (not a dialog, not a full-screen replacement) with a "Open Settings" button that calls `openAppSettings()`. The scan screen remains mounted beneath the message.
- **D-03:** The go_router redirect allows instrument screen access only when `ConnectionStatus == connected`. All other states redirect to `/scan`.
- **D-04:** The guard fires only on navigation *attempts* to `/instrument` — it does NOT re-evaluate while the user is already on the instrument screen. A disconnect while on the instrument screen keeps the user there (honoring Phase 4 D-10 stay-on-screen convention). Implementation: do not wire `refreshListenable` for redirect-on-disconnect; use it only to unblock navigation after permissions/connection are established.
- **D-05:** Theme: `ThemeData.dark()` only — no light theme, no system-adaptive theming.
- **D-06:** go_router instance lives as a top-level `final` variable in `main.dart` (not a Riverpod provider). refreshListenable bridge implemented via a custom `ChangeNotifier` that listens to `connectionNotifierProvider` — standard go_router + Riverpod pattern.
- **D-07:** `ProviderScope.overrides` retains `bleManagerProvider.overrideWithValue(MockBleManager())` — the WP2 swap is one line change here.
- **D-08:** `build.gradle.kts` must hardcode `minSdk = 24` and `compileSdk = 35` (replace `flutter.minSdkVersion` / `flutter.compileSdkVersion` delegates).

### Claude's Discretion

- Exact wording of the rationale dialog and permanently-denied inline message.
- Named routes vs. path strings in go_router — use whatever is idiomatic for go_router 17.x.
- iOS `Info.plist` Bluetooth usage description string wording.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PERM-01 | `AndroidManifest.xml` declares `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and `ACCESS_FINE_LOCATION` permissions | Android 12+ BLE manifest format verified from Android developer docs |
| PERM-02 | App requests runtime BLE permissions via `permission_handler` before initiating any scan | `permission_handler` 12.0.3 API verified; use `[Permission.bluetoothScan, Permission.bluetoothConnect].request()` |
| PERM-03 | Permission request includes a rationale dialog shown before the system permission prompt | Dart-side dialog before `.request()` call; no built-in rationale mechanism in permission_handler — must be explicit |
| PERM-04 | App handles the permanently-denied case by directing the user to `openAppSettings()` with an explanation | `Permission.bluetoothScan.isPermanentlyDenied` + `openAppSettings()` from permission_handler |
| PERM-05 | iOS `Info.plist` includes a Bluetooth usage description string | `NSBluetoothAlwaysUsageDescription` key in Info.plist |
| BUILD-01 | `minSdkVersion` set to 24 | `minSdk = 24` in Kotlin DSL `build.gradle.kts` |
| BUILD-02 | `compileSdkVersion` set to 35 | `compileSdk = 35` in Kotlin DSL `build.gradle.kts` |
</phase_requirements>

---

## Summary

Phase 5 wires together the production `main.dart` entry point using go_router 17.3.0 for navigation, permission_handler 12.0.3 for Android BLE runtime permissions, and correct Android/iOS build configuration. All packages are already specified in CLAUDE.md; none need to be added to pubspec.yaml in this phase — they must be added first via `flutter pub add`.

The primary integration challenge is the go_router + Riverpod `refreshListenable` bridge: go_router needs a `Listenable`, but `connectionNotifierProvider` is a Riverpod `Notifier`. The solution is a custom `ChangeNotifier` subclass that wraps a Riverpod `ProviderSubscription` and calls `notifyListeners()` on state changes. This bridge is passed to GoRouter's `refreshListenable` parameter so the router re-evaluates the redirect callback whenever connection status changes — enabling navigation to `/instrument` after connecting, without triggering an unwanted redirect-on-disconnect (D-04).

The permission flow must run eagerly on cold start (D-01), before any BLE scan, using a rationale dialog that the app shows itself (permission_handler has no built-in rationale dialog). Permanently-denied state is detected via `Permission.bluetoothScan.isPermanentlyDenied` and handled inline on the scan screen rather than with a dialog (D-02).

**Primary recommendation:** Implement `RouterNotifier extends ChangeNotifier` wrapping a `ProviderSubscription<ConnectionStatus>`. Wire `refreshListenable: routerNotifier` and keep redirect logic simple: return `/scan` if attempting `/instrument` while not connected, return `null` otherwise. Permission flow in a top-level async function called from `main()` before `runApp`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Route navigation guard | App shell (main.dart / go_router) | Provider layer (ConnectionStatus) | go_router redirect is the entry control; provider is read-only source of truth |
| Permission flow | App shell (main.dart startup) | UI layer (ScanScreen inline message) | Eager permission check belongs at startup; denied state displayed where BLE is used |
| Connection state → router bridge | App shell (RouterNotifier) | Provider layer | Translation layer between Riverpod state and go_router Listenable interface |
| Android manifest permissions | Platform config | — | Declared at build time; no Flutter code involved |
| Build SDK versions | Platform config (build.gradle.kts) | — | Kotlin DSL config file only |
| iOS usage description | Platform config (Info.plist) | — | Plist key/value; no Flutter code involved |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| go_router | 17.3.0 | Declarative routing with redirect guards | Flutter Favorite; official flutter.dev publisher; 5.7k likes, 3M+ downloads [VERIFIED: pub.dev] |
| permission_handler | 12.0.3 | Runtime permission requests + openAppSettings | Baseflow verified publisher; 5.9k likes, 2.6M downloads; most widely used permission library for Flutter [VERIFIED: pub.dev] |

### Supporting

No new supporting libraries needed beyond what is already in pubspec.yaml.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom ChangeNotifier bridge | Make GoRouter a Riverpod Provider | D-06 locks the approach: top-level final variable, not a provider |
| Explicit rationale dialog (AlertDialog) | `shouldShowRequestPermissionRationale` from native layer | Flutter-only approach is simpler and cross-platform; native method unavailable via permission_handler API |

**Installation:**
```bash
flutter pub add go_router:17.3.0
flutter pub add permission_handler:12.0.3
```

Note: `wakelock_plus` already in pubspec.yaml from Phase 3. `flutter_riverpod` already installed. No further dependencies needed.

**Version verification:**

```
go_router: 17.3.0 — published 2026-06-03 [VERIFIED: pub.dev]
permission_handler: 12.0.3 — published recently [VERIFIED: pub.dev]
```

---

## Package Legitimacy Audit

> slopcheck was unavailable at research time. Packages assessed via pub.dev publisher verification, download counts, and official Flutter endorsement.

| Package | Registry | Publisher | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----------|-----------|-------------|-----------|-------------|
| go_router | pub.dev | flutter.dev (verified) | 3M+/wk | github.com/flutter/packages | N/A — pub.dev verified publisher | Approved |
| permission_handler | pub.dev | baseflow.com (verified) | 2.6M+ | github.com/Baseflow/flutter-permission-handler | N/A — pub.dev verified publisher | Approved |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck was unavailable at research time. Both packages are from verified pub.dev publishers (flutter.dev and baseflow.com) with millions of downloads — risk level is negligible.*

---

## Architecture Patterns

### System Architecture Diagram

```
cold start
    │
    ▼
main() ──► _checkAndRequestPermissions()
               │
               ├── permanently denied ──► sets permissionDenied flag
               ├── denied ──────────────► show rationale dialog ──► request() ──► re-check
               └── granted ─────────────► clears flag
                   │
                   ▼
           runApp(ProviderScope(overrides: [bleManagerProvider.overrideWithValue(MockBleManager())]))
                   │
                   ▼
           MaterialApp.router(routerConfig: _router, theme: ThemeData.dark())
                   │
           _router = GoRouter(
               refreshListenable: _routerNotifier,   ◄─── ChangeNotifier bridge
               redirect: _guardRedirect,             ◄─── returns null or '/scan'
               routes: [/scan → ScanScreen, /instrument → InstrumentScreen]
           )
                   │
            on navigation to /instrument
                   │
                   ▼
           _guardRedirect() checks connectionNotifierProvider state
               │
               ├── connected ──────────────► return null (allow)
               └── any other state ─────────► return '/scan'

ScanScreen (inline)
    │
    ├── permissionDenied == true ──► inline message + "Open Settings" button
    │                                calls openAppSettings()
    └── permissionDenied == false ──► normal scan UI

RouterNotifier (ChangeNotifier)
    │  wraps ProviderSubscription<ConnectionStatus>
    └── on state change ──► notifyListeners() ──► go_router re-evaluates redirect
```

### Recommended Project Structure

```
lib/
├── main.dart              # Full replacement: ProviderScope + GoRouter + permission flow
├── ble/                   # Unchanged from Phases 1-3
├── models/                # Unchanged from Phase 1
├── providers/             # Unchanged from Phases 2-3
└── ui/                    # ScanScreen + InstrumentScreen — small edits only
    ├── scan_screen.dart   # Remove Navigator.push, add permissionDenied inline UI
    └── instrument_screen.dart  # No changes needed for Phase 5

android/app/
├── build.gradle.kts       # Replace flutter.minSdkVersion / flutter.compileSdkVersion
└── src/main/
    └── AndroidManifest.xml  # Add BLE permission declarations

ios/Runner/
└── Info.plist             # Add NSBluetoothAlwaysUsageDescription
```

### Pattern 1: RouterNotifier — ChangeNotifier Bridge

**What:** A `ChangeNotifier` that holds a Riverpod `ProviderSubscription` and calls `notifyListeners()` whenever `connectionNotifierProvider` changes. Passed to `GoRouter.refreshListenable`.

**When to use:** Any time go_router needs to re-evaluate redirect logic in response to Riverpod state changes.

```dart
// Source: go_router + Riverpod bridge pattern — verified via multiple official examples
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    ref.listen<ConnectionStatus>(
      connectionNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}
```

Note: `RouterNotifier` needs a `Ref` to set up the listener. Since GoRouter is a top-level `final` variable (D-06), not inside a provider, you cannot use `ref.listen` at construction time without a container. The recommended approach is to instantiate `RouterNotifier` inside a temporary `ProviderContainer` or use `ProviderScope`'s `onInit` callback. The canonical workaround: create a `ProviderContainer`, instantiate `RouterNotifier(container)`, then pass `container` to `ProviderScope(parent: container)`.

**Alternative (simpler for D-06):** Use a `ValueNotifier<ConnectionStatus>` pattern — read the container, update it from a stream listener. See Pattern 2.

### Pattern 2: ProviderContainer + top-level router (D-06 canonical)

**What:** Create a `ProviderContainer` at app startup, read the notifier from it, subscribe to state changes, and pass the container to `ProviderScope(parent: container)`.

```dart
// Source: [ASSUMED] based on go_router + Riverpod community pattern; D-06 requires top-level final

final _container = ProviderContainer(
  overrides: [bleManagerProvider.overrideWithValue(MockBleManager())],
);

final _routerNotifier = _RouterNotifier(_container);

final _router = GoRouter(
  refreshListenable: _routerNotifier,
  redirect: (context, state) {
    final status = _container.read(connectionNotifierProvider);
    // Only guard /instrument routes — return null everywhere else to avoid loops
    if (state.matchedLocation == '/instrument' &&
        status != ConnectionStatus.connected) {
      return '/scan';
    }
    return null; // allow navigation
  },
  routes: [
    GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
    GoRoute(path: '/instrument', builder: (_, __) => const InstrumentScreen()),
  ],
  initialLocation: '/scan',
);

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(ProviderContainer container) {
    container.listen<ConnectionStatus>(
      connectionNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _checkPermissions();
  runApp(
    ProviderScope(
      parent: _container,
      child: MaterialApp.router(
        routerConfig: _router,
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
```

### Pattern 3: Redirect Callback — Loop Prevention

**What:** The redirect callback must return `null` for all routes except the guarded one, or when the condition is already satisfied. Returning the current location causes a redirect loop.

```dart
// Source: go_router official docs on redirect — verified at pub.dev/documentation/go_router
FutureOr<String?> _guardRedirect(BuildContext context, GoRouterState state) {
  final status = _container.read(connectionNotifierProvider);
  final onInstrument = state.matchedLocation == '/instrument';

  if (onInstrument && status != ConnectionStatus.connected) {
    return '/scan'; // redirect: not connected
  }
  return null; // allow: all other cases
}
```

Key rule: never return the path the user is already at. Never check `/scan` inside the guard — only check `/instrument`. This prevents the guard from running on `/scan` → `/scan` loops.

### Pattern 4: permission_handler BLE Flow

**What:** Request BLE permissions on Android before any scan. Show rationale dialog first, detect permanently denied, show inline UI.

```dart
// Source: permission_handler 12.x official API — VERIFIED: pub.dev
import 'package:permission_handler/permission_handler.dart';

Future<PermissionCheckResult> checkAndRequestBlePermissions() async {
  // Android 12+ (API 31+): use granular BLE permissions
  // minSdk=24 means we ALWAYS run on API 31+ eventually, but devices
  // below API 31 exist. Use Platform.isAndroid check.
  if (!Platform.isAndroid) return PermissionCheckResult.granted;

  final permissions = [Permission.bluetoothScan, Permission.bluetoothConnect];

  // Check for permanently denied first (avoids showing rationale when already denied)
  for (final p in permissions) {
    if (await p.isPermanentlyDenied) {
      return PermissionCheckResult.permanentlyDenied;
    }
  }

  // Check if already granted
  final statuses = await permissions.request();
  if (statuses.values.every((s) => s.isGranted)) {
    return PermissionCheckResult.granted;
  }

  return PermissionCheckResult.denied;
}

// Open app settings for permanently denied case:
await openAppSettings();
```

Note: `ACCESS_FINE_LOCATION` is declared in the manifest for manifest-level compliance (PERM-01 literal requirement), but does NOT need to be requested at runtime for this inclinometer app since `neverForLocation` is used on `BLUETOOTH_SCAN`. The REQUIREMENTS.md says "declares" for PERM-01, not "requests" — manifest declaration is sufficient for PERM-01.

### Pattern 5: ScanScreen modification for permission state

**What:** The scan screen needs to optionally show a permanently-denied inline message. Since permission state lives in `main()` startup and is not a Riverpod provider, the cleanest approach is a top-level `ValueNotifier<bool>` or a simple Riverpod `StateProvider<bool>` for `permissionDeniedProvider`.

```dart
// In device_provider.dart or a dedicated permissions_provider.dart:
// [ASSUMED] — exact provider structure is Claude's discretion
final blePermissionGrantedProvider = StateProvider<bool>((ref) => false);
final blePermissionPermanentlyDeniedProvider = StateProvider<bool>((ref) => false);
```

The scan screen watches `blePermissionPermanentlyDeniedProvider`. When `true`, it shows the inline message and "Open Settings" button. The rationale dialog logic lives in `main()` and updates these providers via `container.read(...).state = ...`.

### Anti-Patterns to Avoid

- **Redirect on current location:** Returning `'/scan'` inside the redirect callback when `state.matchedLocation == '/scan'` causes an infinite loop. Only guard `/instrument`.
- **GoRouter as Riverpod Provider:** D-06 locks the approach to a top-level final variable. Do not wrap GoRouter in a provider.
- **Passing `ref` into top-level functions:** `ref` is a build-time construct. Use `ProviderContainer.read()` for reads outside widget tree.
- **`shouldShowRequestPermissionRationale` native check:** Not available via permission_handler Dart API. Use explicit Dart-side rationale dialog instead (show `AlertDialog` before calling `.request()`).
- **Requesting `ACCESS_FINE_LOCATION` at runtime on Android 12+:** With `neverForLocation` on `BLUETOOTH_SCAN`, location permission is not needed for BLE on Android 12+. Requesting it unnecessarily may confuse users and trigger Google Play review flags.
- **`WidgetsFlutterBinding.ensureInitialized()` missing:** Required before any async work in `main()` including permission checks. Without it, platform channel calls crash.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Route guard with redirect | Custom Navigator observer or wrapping each push | `GoRouter.redirect` callback | Built-in, well-tested, handles deep links correctly |
| Opening app settings | Platform channel code | `openAppSettings()` from permission_handler | Handles Android/iOS differences; single call |
| Permission status check | `MethodChannel` to native | `Permission.bluetoothScan.status` | Handles all states including permanently denied |
| Listenable from Riverpod state | StreamController + ListenableBuilder | Custom ChangeNotifier wrapping `ProviderContainer.listen` | Well-established pattern; < 10 lines |

---

## Common Pitfalls

### Pitfall 1: Redirect Loop on `/scan`
**What goes wrong:** Redirect callback is called for ALL routes. If the guard returns `'/scan'` when not connected AND the user is already at `/scan`, go_router loops until hitting the `redirectLimit` (default: 5) and shows error screen.
**Why it happens:** Guard logic checks connection status without checking current location.
**How to avoid:** Guard condition: `if (state.matchedLocation == '/instrument' && status != connected)`. For all other locations, return `null`.
**Warning signs:** `GoException: Redirect limit exceeded` in debug console.

### Pitfall 2: `WidgetsFlutterBinding.ensureInitialized()` omission
**What goes wrong:** App crashes on startup when `_checkPermissions()` is called before Flutter binding is initialized.
**Why it happens:** Platform channels (including permission_handler) require the binding to be set up before first use.
**How to avoid:** `void main() async { WidgetsFlutterBinding.ensureInitialized(); await _checkPermissions(); runApp(...); }`
**Warning signs:** `ServicesBinding.defaultBinaryMessenger was accessed before the binding was initialized`.

### Pitfall 3: ProviderContainer lifecycle mismatch with ProviderScope
**What goes wrong:** `ProviderContainer` created at top-level is disposed by Riverpod's ProviderScope separately from the container you passed. Providers get initialized twice; `keepAlive` on `connectionNotifierProvider` may not apply to the right instance.
**Why it happens:** Passing `parent: _container` to ProviderScope should prevent double initialization, but incorrect usage creates two containers.
**How to avoid:** Always use `ProviderScope(parent: _container, ...)` — not `ProviderScope(overrides: [...])` when a container already exists. The `overrides` go into the container, not the scope.
**Warning signs:** BLE scan results not appearing; connection state not propagating to router.

### Pitfall 4: ScanScreen `Navigator.push` conflict with go_router
**What goes wrong:** ScanScreen currently uses `Navigator.of(context).push(MaterialPageRoute(...))` to navigate to InstrumentScreen (Phase 4 temporary code). With go_router installed, this bypasses the go_router stack and breaks the back button/deep link handling.
**Why it happens:** Phase 4 used vanilla Navigator because go_router wasn't wired yet.
**How to avoid:** Replace the `ref.listen` + `Navigator.push` block in ScanScreen with `context.go('/instrument')` (or `context.push('/instrument')`). The route guard handles the access control.
**Warning signs:** Back button takes user to black screen; go_router `redirect` callback never fires.

### Pitfall 5: `Permission.bluetooth` vs `Permission.bluetoothScan`
**What goes wrong:** Requesting `Permission.bluetooth` on Android 12+ does nothing — it refers to the adapter state, not the runtime BLE permission.
**Why it happens:** The legacy `BLUETOOTH` permission (API < 31) maps to `Permission.bluetooth`. New granular permissions are `Permission.bluetoothScan` / `Permission.bluetoothConnect`.
**How to avoid:** Request `[Permission.bluetoothScan, Permission.bluetoothConnect]` explicitly. No version gating needed since minSdk=24 — but devices on API 24-30 require `Permission.bluetooth` and `Permission.locationWhenInUse` instead. With minSdk=24, version check via `Platform.version` or `device_info_plus.androidInfo.version.sdkInt` is needed if targeting pre-31 devices. Simplified approach: since CLAUDE.md pins minSdk=24, handle both.
**Warning signs:** Permission always returns `granted` on Android 12+ without a real dialog appearing; Bluetooth scan silently fails.

### Pitfall 6: `build.gradle.kts` Kotlin DSL syntax errors
**What goes wrong:** Using `minSdkVersion 24` (Groovy syntax) in a `.kts` file causes a build error.
**Why it happens:** `.kts` = Kotlin DSL; `minSdk = 24` (with `=`) is correct Kotlin syntax.
**How to avoid:** Replace `minSdk = flutter.minSdkVersion` with `minSdk = 24` and `compileSdk = flutter.compileSdkVersion` with `compileSdk = 35`. Leave `targetSdk = flutter.targetSdkVersion` unchanged (not a Phase 5 requirement).
**Warning signs:** `e: build.gradle.kts:X:Y: Expecting member declaration` during gradle sync.

---

## Code Examples

### build.gradle.kts — Correct Kotlin DSL replacements

```kotlin
// Source: Android developer docs + Kotlin DSL spec [CITED: developer.android.com/build/gradle-build-overview]
android {
    namespace = "com.soldernerd.inclinometer"
    compileSdk = 35              // was: flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // ...
    defaultConfig {
        applicationId = "com.soldernerd.inclinometer"
        minSdk = 24              // was: flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion   // leave unchanged
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    // ...
}
```

### AndroidManifest.xml — BLE permissions for Android 12+

```xml
<!-- Source: developer.android.com/guide/topics/connectivity/bluetooth/permissions [VERIFIED] -->
<!-- Add BEFORE <application> tag, inside <manifest> -->

<!-- Android 12+ (API 31+) BLE runtime permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Required for BLE scanning on Android < 12 (API 24-30) -->
<!-- Also declared per PERM-01 literal requirement -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Legacy permissions for Android < 12 backward compat -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
```

Note: `neverForLocation` on `BLUETOOTH_SCAN` tells Android this app does not derive physical location from BLE scans. This is correct for an inclinometer — no iBeacon/Eddystone proximity scanning. It also means `ACCESS_FINE_LOCATION` is not required at runtime on Android 12+, though it remains declared in the manifest per PERM-01.

### iOS Info.plist — Bluetooth usage description

```xml
<!-- Source: Apple developer docs [CITED: developer.apple.com/documentation/corebluetooth] -->
<!-- Add inside the root <dict> -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to connect to your inclinometer instrument.</string>
```

Note: `NSBluetoothPeripheralUsageDescription` (deprecated in iOS 13) is not needed. `NSBluetoothAlwaysUsageDescription` covers all use cases for iOS 13+.

### GoRouter construction with top-level final variable

```dart
// Source: go_router 17.3.0 constructor API [VERIFIED: pub.dev/documentation/go_router/latest]
// Bridge pattern [CITED: q.agency/blog/handling-authentication-state-with-go_router-and-riverpod]

final _container = ProviderContainer(
  overrides: [bleManagerProvider.overrideWithValue(MockBleManager())],
);

final _routerNotifier = _RouterNotifier(_container);

final _router = GoRouter(
  refreshListenable: _routerNotifier,
  initialLocation: '/scan',
  redirect: (BuildContext context, GoRouterState state) {
    final status = _container.read(connectionNotifierProvider);
    if (state.matchedLocation == '/instrument' &&
        status != ConnectionStatus.connected) {
      return '/scan';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/scan',
      builder: (context, state) => const ScanScreen(),
    ),
    GoRoute(
      path: '/instrument',
      builder: (context, state) => const InstrumentScreen(),
    ),
  ],
);

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(ProviderContainer container) {
    container.listen<ConnectionStatus>(
      connectionNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}
```

### Permission check flow in main()

```dart
// Source: permission_handler 12.x API [VERIFIED: pub.dev]
// [ASSUMED] exact implementation structure

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // D-01: check permissions on every cold start until granted
  if (Platform.isAndroid) {
    final permanentlyDenied = await _areBlePermissionsPermanentlyDenied();
    if (!permanentlyDenied) {
      // Rationale dialog shown by the app before system prompt (D-01)
      // Actual dialog shown at widget build time — see ScanScreen
    }
    _container.read(blePermissionPermanentlyDeniedProvider.notifier).state
        = permanentlyDenied;
  }

  runApp(
    ProviderScope(
      parent: _container,
      child: MaterialApp.router(
        routerConfig: _router,
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        title: 'Inclinometer',
      ),
    ),
  );
}

Future<bool> _areBlePermissionsPermanentlyDenied() async {
  return await Permission.bluetoothScan.isPermanentlyDenied ||
         await Permission.bluetoothConnect.isPermanentlyDenied;
}
```

The rationale dialog (D-01, D-03) and the actual `.request()` call are better placed in `ScanScreen.initState` (or a `ref.listen` on first render) rather than before `runApp`, because:
1. `AlertDialog` requires a `BuildContext`
2. The system permission dialog must be shown after the app is running

Practical implementation: `ScanScreen` shows the rationale `AlertDialog` on first build if permissions are not yet granted, then calls `[Permission.bluetoothScan, Permission.bluetoothConnect].request()`.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `state.subloc` for location check in redirect | `state.matchedLocation` | go_router 6+ | `subloc` removed; use `matchedLocation` |
| `Navigator.push` for screen transitions | `context.go()` / `context.push()` | go_router adoption | Deep link support, back button correctness |
| `Permission.bluetooth` (legacy) | `Permission.bluetoothScan` + `Permission.bluetoothConnect` | Android 12 (API 31) | Granular BLE permissions replace single BLUETOOTH permission |
| Groovy `build.gradle` | Kotlin DSL `build.gradle.kts` | Flutter 3.16+ new project template | Assignment syntax: `minSdk = 24` not `minSdkVersion 24` |

**Deprecated/outdated:**
- `state.subloc`: Removed in go_router 6+. Use `state.matchedLocation`.
- `NSBluetoothPeripheralUsageDescription` (iOS): Deprecated in iOS 13. Use `NSBluetoothAlwaysUsageDescription`.
- `Permission.bluetooth` for Android 12+: Does not trigger the runtime BLE permission dialog on API 31+. Use `Permission.bluetoothScan`/`Permission.bluetoothConnect`.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ProviderContainer.listen()` is available and works for setting up the RouterNotifier bridge outside of widget tree | Code Examples — GoRouter construction | If API differs, bridge won't receive updates; use `container.read(...).addListener()` instead |
| A2 | `blePermissionPermanentlyDeniedProvider` as a `StateProvider<bool>` in providers is the right approach for sharing permission state with ScanScreen | Code Examples — Permission check | May use a different state mechanism; alternative: pass state down as widget constructor param |
| A3 | `Platform.isAndroid` guard around permission check is correct; no permission_handler calls needed on iOS for WP1 | Pattern 4 | If iOS permission check is needed in WP1, add `NSBluetoothAlwaysUsageDescription` check |
| A4 | ScanScreen's `ref.listen` + `Navigator.push` block should be replaced with `context.go('/instrument')` | Pitfall 4 / Architecture | If go_router push semantics differ from `context.go` for this use case, route history may be wrong |

---

## Open Questions (RESOLVED)

1. **Android API < 31 permission handling**
   - What we know: `minSdk=24` means the app runs on API 24-30 where `Permission.bluetoothScan` doesn't exist as a runtime permission — only `Permission.bluetooth` and `Permission.locationWhenInUse`.
   - **RESOLVED (2026-06-05):** Implement dual-path handling. Branch on `(await DeviceInfoPlugin().androidInfo).version.sdkInt >= 31`: API 31+ requests `[Permission.bluetoothScan, Permission.bluetoothConnect]`; API < 31 requests `[Permission.bluetooth, Permission.locationWhenInUse]`. Adds ~10 lines to `_requestBlePermissionsIfNeeded()` but prevents silent failures on API 24–30 devices.

2. **ScanScreen navigation change scope**
   - What we know: ScanScreen currently uses `Navigator.push` (Phase 4 code). Phase 5 description says "no new UI components" but the navigation call must change.
   - **RESOLVED (2026-06-05):** Yes — this is a wiring change (replacing `Navigator.push` with `context.go`), not a UI component change. It must happen in Phase 5 or go_router won't control the route stack.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| flutter pub (dart SDK) | Adding go_router, permission_handler | Assumed ✓ | ^3.12.1 (pubspec.yaml) | — |
| Android SDK 35 | compileSdk = 35 | Unknown | Unknown | Must be installed; Gradle will download if AGP configured |
| go_router 17.3.0 | Route navigation | Not yet in pubspec.yaml | — | — |
| permission_handler 12.0.3 | BLE runtime permissions | Not yet in pubspec.yaml | — | — |

**Missing dependencies with no fallback:**
- `go_router` and `permission_handler` must be added to pubspec.yaml before Phase 5 implementation begins.

**Missing dependencies with fallback:**
- Android SDK 35: Gradle may auto-download if `compileSdkVersion 35` is set and Android SDK manager is configured. If not available locally, build will fail with a meaningful error.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) |
| Config file | none — flutter test runs without config file |
| Quick run command | `flutter test test/` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERM-01 | AndroidManifest.xml declares BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION | manual-only | — inspect file | ❌ — verified by file diff |
| PERM-02 | Runtime BLE permission request via permission_handler | manual-only | — requires device/emulator | ❌ — verified on device |
| PERM-03 | Rationale dialog shown before system prompt | manual-only | — UI interaction | ❌ — verified on device |
| PERM-04 | Permanently denied → openAppSettings() path | manual-only | — requires device state | ❌ — verified on device |
| PERM-05 | iOS Info.plist has NSBluetoothAlwaysUsageDescription | manual-only | — inspect file | ❌ — verified by file diff |
| BUILD-01 | minSdk = 24 in build.gradle.kts | unit/smoke | `grep "minSdk = 24" android/app/build.gradle.kts` | ❌ Wave 0 |
| BUILD-02 | compileSdk = 35 in build.gradle.kts | unit/smoke | `grep "compileSdk = 35" android/app/build.gradle.kts` | ❌ Wave 0 |

Note: PERM requirements are platform-interaction tests that cannot be automated without a physical device or emulator. They are manual verification items.

### Sampling Rate

- **Per task commit:** `flutter test` (existing provider and model tests must remain green)
- **Per wave merge:** `flutter test` + manual device verification of permission flow
- **Phase gate:** All automated tests green + manual BLE permission flow verified on Android device/emulator before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] No new test files needed for Phase 5 — file changes are platform config (manifest, plist, gradle) and wiring (main.dart). Existing tests cover providers.
- [ ] Verify existing tests still pass after adding go_router and permission_handler to pubspec.yaml (`flutter test` green baseline).

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (route guard) | go_router redirect callback — server-less, local guard only |
| V5 Input Validation | no | — |
| V6 Cryptography | no | — |

### Known Threat Patterns for BLE + Router Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Route bypass (navigate to /instrument without connection) | Elevation of Privilege | go_router redirect guard — returns /scan for any non-connected state |
| Permission bypass (skip rationale, access BLE without consent) | Spoofing | Android runtime permission system enforces; app shows rationale before requesting |
| Stale data shown as live post-disconnect | Information Disclosure | Already mitigated in Phase 3 (null sentinel from ConnectionNotifier); Phase 5 does not regress this |

---

## Sources

### Primary (HIGH confidence)
- [pub.dev/packages/go_router](https://pub.dev/packages/go_router) — version 17.3.0 confirmed, publisher flutter.dev verified
- [pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html) — constructor signature, redirect, refreshListenable
- [pub.dev/documentation/go_router/latest/go_router/GoRouterRedirect.html](https://pub.dev/documentation/go_router/latest/go_router/GoRouterRedirect.html) — `FutureOr<String?> Function(BuildContext, GoRouterState)` typedef
- [pub.dev/documentation/go_router/latest/go_router/GoRouterState-class.html](https://pub.dev/documentation/go_router/latest/go_router/GoRouterState-class.html) — `matchedLocation`, `uri`, `fullPath` properties
- [pub.dev/packages/permission_handler](https://pub.dev/packages/permission_handler) — version 12.0.3, publisher baseflow.com verified
- [pub.dev/documentation/permission_handler/latest/permission_handler/Permission-class.html](https://pub.dev/documentation/permission_handler/latest/permission_handler/Permission-class.html) — `bluetoothScan`, `bluetoothConnect`, `isPermanentlyDenied`, `openAppSettings()`
- [developer.android.com/guide/topics/connectivity/bluetooth/permissions](https://developer.android.com/guide/topics/connectivity/bluetooth/permissions) — AndroidManifest.xml BLE permission format, `neverForLocation` flag

### Secondary (MEDIUM confidence)
- [go_router changelog on pub.dev](https://pub.dev/packages/go_router/changelog) — confirmed no breaking changes to redirect/refreshListenable between 14.x and 17.x
- [blog.blefluttercourse.com/blog/flutter-ble-permissions-android-ios](https://blog.blefluttercourse.com/blog/flutter-ble-permissions-android-ios) — AndroidManifest.xml and permission_handler Dart patterns for BLE, cross-verified with official docs
- [q.agency/blog/handling-authentication-state-with-go_router-and-riverpod/](https://q.agency/blog/handling-authentication-state-with-go_router-and-riverpod/) — ChangeNotifier bridge pattern for go_router + Riverpod

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — both packages verified at pub.dev with verified publishers
- Architecture: HIGH — GoRouter constructor API verified from official docs; redirect signature verified
- Permission patterns: HIGH — permission_handler API verified from official docs; Android manifest from Android developer docs
- Bridge pattern: MEDIUM — ChangeNotifier wrapping ProviderContainer.listen is well-documented community pattern, not in official go_router docs but verified across multiple sources
- Pitfalls: HIGH — redirect loop prevention verified from go_router docs; WidgetsFlutterBinding requirement is Flutter SDK standard

**Research date:** 2026-06-05
**Valid until:** 2026-09-05 (stable libraries; go_router changes infrequently after major versions)
