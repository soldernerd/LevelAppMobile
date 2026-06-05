# Phase 5: App Wiring + Platform Config - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 6
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/main.dart` | config/entry-point | request-response + event-driven | `lib/main.dart` (Phase 4) | exact — full replacement |
| `lib/providers/device_provider.dart` | provider | event-driven | self (add `blePermissionPermanentlyDeniedProvider`) | role-match — additive edit |
| `lib/ui/scan_screen.dart` | component | request-response | `lib/ui/scan_screen.dart` (current) | exact — targeted edit |
| `android/app/build.gradle.kts` | config | — | self (current file) | exact — two-line replacement |
| `android/app/src/main/AndroidManifest.xml` | config | — | self (current file) | exact — insert before `<application>` |
| `ios/Runner/Info.plist` | config | — | self (current file) | exact — insert inside root `<dict>` |

---

## Pattern Assignments

### `lib/main.dart` (entry-point, full replacement)

**Analog:** `lib/main.dart` lines 1–24 (Phase 4 temporary entry point)

**Imports pattern** (lines 1–8 of existing file — carry forward, extend):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/scan_screen.dart';
// ADD in Phase 5:
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/ui/instrument_screen.dart';
```

**ProviderScope + overrides pattern** (lines 11–14 of existing file — carry forward unchanged):
```dart
ProviderScope(
  parent: _container,       // Phase 5: use parent: instead of overrides:
  child: ...
)
// overrides go into _container, NOT into ProviderScope (Pitfall 3 from RESEARCH.md)
```

**Phase 4 theme pattern** (line 18 of existing file — unchanged):
```dart
theme: ThemeData.dark(),
debugShowCheckedModeBanner: false,
```

**New Phase 5 core pattern — top-level wiring** (from RESEARCH.md Pattern 2):
```dart
// Top-level ProviderContainer (carries overrides; passed as parent: to ProviderScope)
final _container = ProviderContainer(
  overrides: [bleManagerProvider.overrideWithValue(MockBleManager())],
);

// RouterNotifier — ChangeNotifier bridge between Riverpod and go_router
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(ProviderContainer container) {
    container.listen<ConnectionStatus>(
      connectionNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final _routerNotifier = _RouterNotifier(_container);

// Route guard: only blocks entry to /instrument; returns null for all other paths
// (returning current path causes redirect loop — Pitfall 1 from RESEARCH.md)
final _router = GoRouter(
  refreshListenable: _routerNotifier,
  initialLocation: '/scan',
  redirect: (BuildContext context, GoRouterState state) {
    final status = _container.read(connectionNotifierProvider);
    if (state.matchedLocation == '/instrument' &&
        status != ConnectionStatus.connected) {
      return '/scan';
    }
    return null; // allow all other paths including /scan itself
  },
  routes: [
    GoRoute(path: '/scan',       builder: (_, __) => const ScanScreen()),
    GoRoute(path: '/instrument', builder: (_, __) => const InstrumentScreen()),
  ],
);
```

**main() async pattern** (from RESEARCH.md Pattern 4 + Pitfall 2):
```dart
void main() async {
  // REQUIRED before any platform channel call (permission_handler uses channels)
  WidgetsFlutterBinding.ensureInitialized();

  // D-01: Check permanently-denied state on every cold start before runApp.
  // Rationale dialog and .request() happen inside ScanScreen.initState because
  // AlertDialog requires a BuildContext (RESEARCH.md Pattern 4 note).
  if (Platform.isAndroid) {
    final permanentlyDenied = await _areBlePermissionsPermanentlyDenied();
    _container
        .read(blePermissionPermanentlyDeniedProvider.notifier)
        .state = permanentlyDenied;
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

---

### `lib/providers/device_provider.dart` (provider — additive edit only)

**Analog:** `lib/providers/device_provider.dart` lines 1–24 (existing provider declarations)

**Existing pattern to match** (lines 22–24):
```dart
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});
```

**New StateProvider to append** (after existing providers, before EOF):
```dart
/// Whether BLE permissions are permanently denied on this device.
///
/// Set by main() on cold start (Android only). Watched by ScanScreen to
/// show the inline "Open Settings" message (D-02).
final blePermissionPermanentlyDeniedProvider = StateProvider<bool>((ref) => false);
```

**Import additions:** None needed — `StateProvider` is already in scope via `flutter_riverpod`.

---

### `lib/ui/scan_screen.dart` (component — targeted edit)

**Analog:** `lib/ui/scan_screen.dart` lines 1–33 (current file)

**Existing import pattern** (lines 1–5 — extend, do not replace):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
// REMOVE: import 'package:inclinometer/ui/instrument_screen.dart'; (no longer needed)
// ADD:
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
```

**Navigation pattern — replace** (lines 26–33, current `ref.listen` + `Navigator.push` block):
```dart
// REMOVE (Phase 4 temporary):
ref.listen(connectionNotifierProvider, (prev, next) {
  if (next == ConnectionStatus.connected &&
      prev != ConnectionStatus.connected) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InstrumentScreen()),
    );
  }
});

// REPLACE WITH (Phase 5 go_router):
ref.listen(connectionNotifierProvider, (prev, next) {
  if (next == ConnectionStatus.connected &&
      prev != ConnectionStatus.connected) {
    context.go('/instrument');
  }
});
```

**Permission rationale + request pattern** (new, added to build() before return Scaffold):
```dart
// D-01: show rationale dialog on first build if permissions not yet granted.
// D-02: inline message shown if permanentlyDenied == true.
final permanentlyDenied = ref.watch(blePermissionPermanentlyDeniedProvider);
```

**Inline denied message pattern** (D-02 — inside _buildBody or as overlay above Scaffold body):
```dart
// Insert as Column child at top of body when permanentlyDenied == true
if (permanentlyDenied)
  Container(
    color: const Color(0xFF311B1B),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Bluetooth permission is permanently denied. '
            'Open Settings to grant access.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        TextButton(
          onPressed: openAppSettings,
          child: const Text('Open Settings'),
        ),
      ],
    ),
  ),
```

**Permission rationale dialog pattern** (D-01 — shown before `.request()` via `initState` / `WidgetsBinding.addPostFrameCallback`):
```dart
// Show rationale AlertDialog, then call .request()
// Must run after first frame (BuildContext required for showDialog)
Future<void> _requestBlePermissions(BuildContext context, WidgetRef ref) async {
  final granted = await Permission.bluetoothScan.isGranted &&
                  await Permission.bluetoothConnect.isGranted;
  if (granted) return;

  // D-01: rationale dialog before system prompt
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bluetooth Permission'),
        content: const Text(
          'This app needs Bluetooth to scan for and connect to '
          'your inclinometer instrument.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // Request after dialog dismissed
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  final permanentlyDenied = statuses.values
      .any((s) => s.isPermanentlyDenied);
  ref.read(blePermissionPermanentlyDeniedProvider.notifier).state =
      permanentlyDenied;
}
```

---

### `android/app/build.gradle.kts` (config — two-line replacement)

**Analog:** `android/app/build.gradle.kts` lines 9 and 20 (current file)

**Existing pattern** (lines 9 and 20 — replace these two lines only):
```kotlin
// Line 9 — BEFORE:
compileSdk = flutter.compileSdkVersion
// Line 9 — AFTER:
compileSdk = 35

// Line 20 — BEFORE:
minSdk = flutter.minSdkVersion
// Line 20 — AFTER:
minSdk = 24
```

**Lines to leave unchanged** (all others — do not touch):
- `ndkVersion = flutter.ndkVersion` (line 10)
- `targetSdk = flutter.targetSdkVersion` (line 23)
- `versionCode = flutter.versionCode` (line 24)
- `versionName = flutter.versionName` (line 25)

**Kotlin DSL syntax rule** (from RESEARCH.md Pitfall 6): Assignment operator `= 24` (not `24`). The file already uses Kotlin DSL — no syntax change needed beyond replacing the delegate references.

---

### `android/app/src/main/AndroidManifest.xml` (config — insert before `<application>`)

**Analog:** `android/app/src/main/AndroidManifest.xml` lines 1–45 (current file)

**Insertion point:** After `<manifest xmlns:android="...">` opening tag (line 1), before `<application` block (line 2). Insert these lines:

```xml
<!-- Android 12+ (API 31+) BLE runtime permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- ACCESS_FINE_LOCATION: required for BLE scanning on Android < 12 (API 24-30) -->
<!-- Also declared per PERM-01 literal requirement -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Legacy permissions for Android < 12 backward compatibility -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
```

**Lines to leave unchanged:** The entire `<application>` block (lines 2–33) and the `<queries>` block (lines 39–44) remain untouched.

---

### `ios/Runner/Info.plist` (config — insert inside root `<dict>`)

**Analog:** `ios/Runner/Info.plist` lines 1–70 (current file)

**Insertion point:** Inside the root `<dict>` element, after the last existing key/value pair (before `</dict>` on line 69). Insert:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to connect to your inclinometer instrument.</string>
```

**Note:** `NSBluetoothPeripheralUsageDescription` (deprecated iOS 13) is NOT needed. `NSBluetoothAlwaysUsageDescription` covers iOS 13+ (RESEARCH.md State of the Art).

---

## Shared Patterns

### ProviderContainer as app root (D-06, D-07)
**Source:** `lib/main.dart` lines 11–14 (Phase 4 `ProviderScope.overrides` pattern) + RESEARCH.md Pattern 2
**Apply to:** `lib/main.dart` only
```dart
// Overrides go into the container, not ProviderScope.
// Pass container as parent: to ProviderScope to avoid double-initialization (Pitfall 3).
final _container = ProviderContainer(
  overrides: [bleManagerProvider.overrideWithValue(MockBleManager())],
);
// ...
ProviderScope(parent: _container, child: ...)
```

### ConsumerWidget + ref.watch pattern
**Source:** `lib/ui/scan_screen.dart` lines 13–21 (existing ScanScreen)
**Apply to:** ScanScreen edits — permission state read follows same ref.watch pattern as existing status/devices reads:
```dart
final status = ref.watch(connectionNotifierProvider);
final devices = ref.watch(scanResultsProvider)...;
final permanentlyDenied = ref.watch(blePermissionPermanentlyDeniedProvider); // new
```

### StateProvider mutation from outside widget tree
**Source:** `lib/providers/device_provider.dart` lines 22–24 (bleManagerProvider pattern), combined with RESEARCH.md Pattern 4
**Apply to:** `lib/main.dart` — writing permission state via container before runApp:
```dart
_container.read(blePermissionPermanentlyDeniedProvider.notifier).state = value;
```

### Kotlin DSL assignment syntax
**Source:** `android/app/build.gradle.kts` lines 8–25 (existing file)
**Apply to:** `build.gradle.kts` edits — all assignments use `= value` form, matching existing `namespace = "..."`, `applicationId = "..."` etc. No Groovy-style bare values.

---

## No Analog Found

All files have direct analogs in the codebase (self-modification) or in RESEARCH.md verified patterns. No files require novel pattern invention.

---

## Metadata

**Analog search scope:** `lib/`, `android/app/`, `ios/Runner/`
**Files scanned:** 6 (main.dart, device_provider.dart, scan_screen.dart, build.gradle.kts, AndroidManifest.xml, Info.plist)
**Pattern extraction date:** 2026-06-05
