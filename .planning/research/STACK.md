# Stack Research: Inclinometer BLE Companion App

**Project:** LevelAppMobile — Flutter BLE companion for custom inclinometer
**Researched:** 2026-06-04
**Overall confidence:** HIGH (all packages verified against pub.dev, official docs, and changelogs)

---

## Recommended Versions

| Package | Version | Notes |
|---------|---------|-------|
| Flutter SDK | 3.44.0 | Current stable. Minimum Android SDK is now 24 (not 21). |
| flutter_blue_plus | 2.3.5 | Current stable. 2.x is the active branch. 1.x is legacy. |
| flutter_riverpod | 3.3.1 | Current stable. Riverpod 3.x is a major rewrite of 2.x. |
| riverpod_annotation | 3.x | Required if using code-gen (@riverpod) pattern. |
| riverpod_generator | 3.x | Required if using code-gen pattern. |
| permission_handler | 12.0.3 | Current stable. compileSdkVersion 35 required. |
| go_router | 17.3.0 | Current stable. Typed routes require go_router_builder 4.3.0. |
| go_router_builder | 4.3.0 | Code-gen companion for typed routes. Optional but recommended. |

**build.gradle minimum SDK note:** Flutter 3.44 officially supports Android 24+. Set `minSdkVersion 24` in `android/app/build.gradle`. flutter_blue_plus documents minSdkVersion 21, but Flutter's own engine now requires 24 — 21–23 are unsupported. Use 24.

---

## Critical Integration Notes

### flutter_blue_plus 2.x

**Licensing:** Version 2.1.0+ requires a commercial license for organisations with 15 or more employees. For individual/small-team use (this project), the package is free. Verify if the team size ever crosses this threshold.

**Manifest setup — Android 12+ (API 31+):**
The `neverForLocation` flag on `BLUETOOTH_SCAN` is the critical choice. Including it means BLE beacon-style location derivation is blocked, but the app does NOT need `ACCESS_FINE_LOCATION` on Android 12+. For a machine-shop inclinometer that never derives location from BLE scan results, always use `neverForLocation`.

```xml
<!-- AndroidManifest.xml — inside <manifest>, before <application> -->

<!-- Android 12+ permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Legacy permissions for Android < 12 -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />

<!-- Required for BLE scanning on Android 6–11 -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />

<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

**Connection state stream:** The canonical API is `device.connectionState` which returns `Stream<BluetoothConnectionState>`. The enum values are `connecting`, `connected`, `disconnecting`, and `disconnected`. This stream never emits errors and never closes — no error handler needed.

```dart
final sub = device.connectionState.listen((state) {
  if (state == BluetoothConnectionState.disconnected) {
    // trigger reconnect logic
  }
});
device.cancelWhenDisconnected(sub); // auto-cancels on disconnect
```

**Characteristic notifications:** The correct pattern is `onValueReceived` + `setNotifyValue`. `onValueReceived` emits on both explicit `read()` calls and incoming notifications. `lastValueStream` is a convenience alias that also emits on writes. For a notify-only state characteristic (this project's use case), prefer `onValueReceived`.

```dart
// CORRECT pattern for notifying characteristic (WP2 reference)
final sub = characteristic.onValueReceived.listen((List<int> value) {
  // parse 9-byte state packet: angle_x (float32LE), angle_y (float32LE), battery (uint8)
});
device.cancelWhenDisconnected(sub);  // critical — prevents leak on disconnect
await characteristic.setNotifyValue(true);
```

**API removed/renamed from 1.x:**
- `FlutterBluePlus.connectedDevices` — removed. Use `FlutterBluePlus.connectedSystemDevices` (renamed to `systemDevices`), but note these must be explicitly reconnected.
- `FlutterBluePlus.instance` singleton pattern from very old 1.x — gone. Use the static class API directly (`FlutterBluePlus.startScan(...)`, etc.).
- Streams no longer use RxDart (removed in late 1.x/2.x). Plain Dart streams throughout.

**Scan API (WP1 scan screen):**
```dart
await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
FlutterBluePlus.scanResults.listen((List<ScanResult> results) { ... });
// Filter by device name in the stream — not a built-in filter parameter
```

**Multiple simultaneous writes** (2.3.0+): `FlutterBluePlus.setOperationQueueMode` controls concurrent write behaviour. Relevant for WP2 when sending ZERO_X/ZERO_Y commands.

---

### Riverpod 3.x (flutter_riverpod 3.3.1)

**StateNotifier is dead in 3.x.** `StateNotifierProvider` was moved to `package:flutter_riverpod/legacy.dart`. Do not use it for new code. Use `Notifier` (sync) or `AsyncNotifier` (async/stream-backed) instead.

**StreamProvider for BLE notifications:** `StreamProvider` is the right tool for wrapping the raw `characteristic.onValueReceived` stream in WP2. In Riverpod 3.x, `StreamProvider` automatically pauses its `StreamSubscription` when no widget is listening — this is desirable for BLE to avoid draining battery when the instrument screen is not visible.

**Critical 3.x equality change:** All providers now use `==` (not `identical`) to filter duplicate emissions. For the 9-byte state packet parsed into a model struct, implement `==` on the model class (or use `@immutable` with auto-generated equality). Without this, rapid identical readings will correctly suppress redundant rebuilds — which is actually beneficial for angle display.

**Notifier lifecycle change (3.0):** Notifiers are recreated on every provider rebuild. Do not store `StreamSubscription` or timers directly inside an `AsyncNotifier` field. Use `ref.onDispose` to cancel subscriptions.

**Recommended BLE state pattern for this project:**

For WP1 (mock layer), a `Notifier` holding a connection-state enum and mock data is sufficient:

```dart
// lib/providers/ble_provider.dart
@riverpod
class BleConnection extends _$BleConnection {
  @override
  BleConnectionState build() => BleConnectionState.disconnected;

  Future<void> connect(String deviceId) async {
    state = BleConnectionState.connecting;
    // mock: immediately transition to connected
    state = BleConnectionState.connected;
  }

  void disconnect() => state = BleConnectionState.disconnected;
}

@riverpod
Stream<InstrumentState> instrumentData(Ref ref) {
  // WP1: mock random-walk stream
  // WP2: swap for characteristic.onValueReceived mapped stream
  return _mockDataStream();
}
```

For WP2, the `instrumentData` provider body swaps to the real characteristic stream without changing any widget code. This is the abstraction boundary.

**AutoDispose is the default** in Riverpod 3.x when using code generation. Providers tear down when not listened. For BLE connection state that must persist across navigation, add `keepAlive: true` to the provider annotation:
```dart
@Riverpod(keepAlive: true)
class BleConnection extends _$BleConnection { ... }
```

**Ref changes:** All `Ref` subclass types (`FutureProviderRef<T>`, `StreamProviderRef<T>`, etc.) are removed. Use plain `Ref` everywhere.

---

### permission_handler 12.0.3

**Android 12+ (API 31+) permission model:** The old `Permission.bluetooth` maps only to the legacy single `BLUETOOTH` permission. On Android 12+, you must request the granular permissions explicitly.

**Runtime request pattern:**
```dart
Future<bool> requestBlePermissions() async {
  // Android 12+: request granular BLE permissions
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  return statuses.values.every((s) => s.isGranted);
}
```

On Android < 12, fall back to `Permission.bluetooth` and `Permission.locationWhenInUse`. However, since Flutter 3.44 sets minSdkVersion 24 and Android 12 is API 31, this app will run on Android 7–15. A version check is needed to request the right permissions:

```dart
import 'package:device_info_plus/device_info_plus.dart'; // optional helper

// OR use simpler runtime check:
if (Platform.isAndroid) {
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  if (androidInfo.version.sdkInt >= 31) {
    // request BLUETOOTH_SCAN + BLUETOOTH_CONNECT
  } else {
    // request Permission.bluetooth + Permission.locationWhenInUse
  }
}
```

Alternatively, request all of them — the OS ignores permissions not declared in the manifest or not applicable to the SDK version.

**Permanently denied:** `PermissionStatus.permanentlyDenied` means the user tapped "Don't ask again." At this point, the OS will never show the permission dialog again. The only recovery is `openAppSettings()`:
```dart
final status = await Permission.bluetoothScan.status;
if (status.isPermanentlyDenied) {
  await openAppSettings(); // directs user to app settings screen
}
```

**`compileSdkVersion 35` required (12.0.0 breaking change):** Update `android/app/build.gradle`:
```gradle
android {
    compileSdkVersion 35   // was 34 in older projects
    ...
}
```

---

### go_router 17.3.0

**Typed routes:** go_router 17.x supports typed routes natively via `GoRouteData`. The companion package `go_router_builder 4.3.0` generates boilerplate. For a two-screen app (scan screen + instrument screen), typed routes are optional but worth it for maintainability.

Without code-gen (simpler for WP1):
```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ScanScreen()),
    GoRoute(path: '/instrument', builder: (_, __) => const InstrumentScreen()),
  ],
  redirect: (context, state) {
    final connected = ref.read(bleConnectionProvider) == BleConnectionState.connected;
    if (state.matchedLocation == '/instrument' && !connected) return '/';
    return null;
  },
  refreshListenable: // wrap BLE connection notifier as Listenable
);
```

**`refreshListenable` pattern for connection-driven routing:**
`refreshListenable` accepts a `Listenable`. Riverpod providers are not `Listenable` by default. The standard bridge is a `ChangeNotifier` that listens to the Riverpod provider and calls `notifyListeners()`:

```dart
class BleConnectionNotifier extends ChangeNotifier {
  BleConnectionNotifier(this._ref) {
    _ref.listen(bleConnectionProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}
```

Then pass an instance to `GoRouter(refreshListenable: notifier)`. An alternative is `GoRouterRefreshStream` if the connection state is exposed as a `Stream`.

**Breaking change in 16.0.0:** URLs are now case-sensitive by default. Use lowercase paths only (e.g., `/instrument`, not `/Instrument`).

**Breaking change in 14.0.0:** `GoRouteData.onExit` now requires `(BuildContext context, GoRouterState state)` — two parameters. Not relevant for WP1 but relevant for WP2 when adding a "disconnect confirmation" guard.

**Typed routes with go_router_builder (if used):**
```dart
@TypedGoRoute<ScanRoute>(path: '/')
class ScanRoute extends GoRouteData {
  @override
  Widget build(BuildContext context, GoRouterState state) => const ScanScreen();
}

@TypedGoRoute<InstrumentRoute>(path: '/instrument')
class InstrumentRoute extends GoRouteData {
  @override
  Widget build(BuildContext context, GoRouterState state) => const InstrumentScreen();
}
```
Run `dart run build_runner build` to generate `*.g.dart` files. The generated `$appRoutes` list is passed to `GoRouter(routes: $appRoutes)`.

---

## What NOT To Do

| Anti-pattern | Why | Instead |
|---|---|---|
| Use `StateNotifierProvider` | Moved to legacy in Riverpod 3.x; will require migration | Use `Notifier` (sync) or `AsyncNotifier` (async) |
| Use `FutureProviderRef<T>`, `StreamProviderRef<T>` | All Ref subtypes removed in Riverpod 3.0 | Use plain `Ref` |
| Store `StreamSubscription` as a field in a Notifier | Notifiers are recreated on rebuild; subscription leaks | Use `ref.onDispose` to cancel |
| Request `Permission.bluetooth` on Android 12+ | Maps to legacy permission, not the 12+ granular ones | Request `Permission.bluetoothScan` + `Permission.bluetoothConnect` |
| Use `ACCESS_FINE_LOCATION` without `neverForLocation` | Triggers location permission dialog on Android 12+ for a non-location app | Add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN` |
| Set `minSdkVersion 21` | Flutter 3.44 does not support Android < 24 | Set `minSdkVersion 24` |
| Use `FlutterBluePlus.connectedDevices` | Removed in 2.x | No direct replacement; track connected devices yourself |
| Subscribe to `onValueReceived` without `cancelWhenDisconnected` | Subscription survives disconnect, emits stale data | Always call `device.cancelWhenDisconnected(subscription)` |
| Hard-code route strings like `/instrument` in `context.go('/instrument')` | String typos, no compile-time safety | Use typed `InstrumentRoute().go(context)` with go_router_builder |
| Put `GoRouter` construction inside a `build()` method | Recreates the router on every rebuild, resets navigation state | Construct router at top level, in a `riverpod` provider, or as a final field |
| Use `characteristic.lastValueStream` for notify-only characteristics | `lastValueStream` also emits on writes; misleading semantics | Use `onValueReceived` for notify/read characteristics |

---

## Confidence

| Area | Confidence | Source |
|------|------------|--------|
| flutter_blue_plus version (2.3.5) | HIGH | pub.dev verified 2026-06-04 |
| flutter_blue_plus manifest/permission setup | HIGH | Official README (chipweinberger/flutter_blue_plus) |
| flutter_blue_plus characteristic API | HIGH | Official README + pub.dev docs |
| flutter_blue_plus 1.x vs 2.x API differences | MEDIUM | Changelog + GitHub issues; some specifics inferred from partial changelog |
| flutter_blue_plus commercial licensing | HIGH | Changelog entries 2.1.0–2.2.0 |
| Riverpod version (3.3.1) | HIGH | pub.dev verified 2026-06-04 |
| Riverpod 3.x breaking changes (StateNotifier, Ref, equality) | HIGH | Official changelog + riverpod.dev migration guide |
| Riverpod StreamProvider pause-on-unlistened behavior | HIGH | Official 3.0 changelog |
| Riverpod keepAlive requirement for BLE connection state | HIGH | Riverpod 3.x autoDispose-by-default, confirmed in docs |
| permission_handler version (12.0.3) | HIGH | pub.dev verified 2026-06-04 |
| permission_handler Android 12+ granular permissions | HIGH | Changelog 8.2.0 + BLE Flutter course official guide |
| permission_handler permanentlyDenied + openAppSettings | HIGH | Changelog + pub.dev API docs |
| permission_handler compileSdkVersion 35 requirement | HIGH | Changelog 12.0.0 breaking change |
| go_router version (17.3.0) | HIGH | pub.dev verified 2026-06-04 |
| go_router redirect + refreshListenable pattern | HIGH | pub.dev docs + official documentation |
| go_router case-sensitive URLs (16.0.0) | HIGH | Official changelog |
| go_router_builder version (4.3.0) | HIGH | pub.dev verified 2026-06-04 |
| Flutter 3.44 / minSdkVersion 24 | HIGH | docs.flutter.dev/reference/supported-platforms |

---

## Sources

- flutter_blue_plus pub.dev: https://pub.dev/packages/flutter_blue_plus
- flutter_blue_plus changelog: https://pub.dev/packages/flutter_blue_plus/changelog
- flutter_blue_plus README (official): https://github.com/chipweinberger/flutter_blue_plus/blob/master/packages/flutter_blue_plus/README.md
- flutter_riverpod pub.dev: https://pub.dev/packages/flutter_riverpod
- riverpod changelog: https://pub.dev/packages/riverpod/changelog
- Riverpod 3.0 migration guide: https://riverpod.dev/docs/3.0_migration
- Riverpod what's new: https://riverpod.dev/docs/whats_new
- permission_handler pub.dev: https://pub.dev/packages/permission_handler
- permission_handler changelog: https://pub.dev/packages/permission_handler/changelog
- go_router pub.dev: https://pub.dev/packages/go_router
- go_router changelog: https://pub.dev/packages/go_router/changelog
- go_router_builder pub.dev: https://pub.dev/packages/go_router_builder
- Flutter supported platforms: https://docs.flutter.dev/reference/supported-platforms
- BLE Flutter Course — permissions guide: https://blog.blefluttercourse.com/blog/flutter-ble-permissions-android-ios
