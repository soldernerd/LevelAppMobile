# Pitfalls Research

**Project:** Inclinometer BLE Companion App
**Stack:** Flutter/Dart, flutter_blue_plus, riverpod, permission_handler, go_router
**Hardware target:** RN4871 BLE 5.0 module (Microchip), Android primary / iOS scaffold
**Researched:** 2026-06-04
**Confidence:** HIGH (flutter_blue_plus official docs + Punch Through Android BLE guide + community-verified patterns)

---

## Critical Pitfalls

These will cause broken behaviour, hard-to-reproduce crashes, or a full rewrite of the BLE layer if not addressed upfront.

---

### CP-1: Not re-discovering services after every reconnection

**What goes wrong:** After a disconnect/reconnect cycle the GATT service references held in Dart are stale. Characteristic reads, writes, and notification subscriptions all silently fail or throw because the `BluetoothCharacteristic` objects point to the old session.

**Why it happens:** flutter_blue_plus does not automatically re-run service discovery. Connection re-establishment creates a new GATT session at the OS level; the Dart objects are not re-hydrated automatically.

**Consequences:** Commands sent to the inclinometer after an auto-reconnect appear to succeed (no exception) but the device never receives them. This is the single most common "works first connection, breaks on reconnect" bug.

**Prevention:**
- Always call `device.discoverServices()` inside the `onConnected` branch of the `connectionState` stream listener, not once at startup.
- Additionally listen to `device.onServicesReset` (fires when the firmware changes the GATT table mid-connection) and call `discoverServices()` there too.

```dart
device.connectionState.listen((state) async {
  if (state == BluetoothConnectionState.connected) {
    await device.discoverServices(); // mandatory after every connect
  }
});

device.onServicesReset.listen((_) async {
  await device.discoverServices(); // firmware changed services
});
```

**Detection:** Write a reconnect loop in the BLE repository integration test (WP2): disconnect, wait 2 s, reconnect, send a Zero command. Any failure here points to stale services.

---

### CP-2: Android status 133 (GATT_ERROR) — unrecoverable GATT stack state

**What goes wrong:** After a connection attempt that hits the OS 5-second timeout (device out of range, firmware crash, radio interference) Android returns `ANDROID_SPECIFIC_ERROR` code 133. The Bluetooth framework internally may not have released the connection — calling `connect()` immediately afterwards produces "Device is already connected", and the app becomes unable to reconnect at all without Bluetooth toggle or phone restart.

**Why it happens:** This is an Android OS bug / undocumented internal state, not a flutter_blue_plus bug. It appears most on Android 8 (Oreo) at ~25% frequency but affects all versions. On Android 14 it manifests more frequently after rapid reconnect attempts.

**Consequences:** User has to toggle Bluetooth or restart the app to recover. In a machine-shop environment this is a genuine usability blocker.

**Prevention:**
- After receiving a 133 error: call `device.disconnect()`, wait at least 500 ms, then retry `connect()` with exponential backoff.
- Cap retry attempts (3–5 max) before surfacing a "tap to reconnect" UI action rather than auto-retrying indefinitely.
- Never use `autoConnect: true` on the first connection attempt; use `autoConnect: false` (direct connection). Reserve `autoConnect: true` only for background reconnect after an established session.
- The auto-reconnect stub required by WP1 must be built with this backoff logic, even if it is not activated — the structure must accommodate it.

---

### CP-3: Android scan hard-rate-limit — silent failure, no error returned

**What goes wrong:** Android enforces a limit of 5 `startScan()` calls per 30-second window. Exceeding this limit causes the OS to silently ignore subsequent scan calls. No exception is thrown. The scan appears to start but returns zero results forever.

**Why it happens:** OS-level throttle introduced to prevent battery drain by misbehaving apps. The limit resets every 30 seconds.

**Consequences:** Repeatedly tapping "Scan" (e.g. user gets impatient) rapidly exhausts the quota. After hitting the limit the scan screen shows nothing, with no user-visible error, and remains broken for up to 30 seconds.

**Prevention:**
- Enforce a cooldown in the scan state machine: if the last scan started less than 6 seconds ago, do not call `stopScan()`/`startScan()` again — extend the existing scan instead.
- Expose scan state to the UI so "Scanning..." is clearly shown and the tap target is disabled while scanning, removing the user's motivation to re-tap.
- In the BLE repository abstraction, track the timestamp of the last `startScan()` call and guard against rapid re-entry.

---

### CP-4: Permission failures are silent — missing permissions produce empty scan results, not exceptions

**What goes wrong:** On Android 12+ (API 31+), BLE scanning requires `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` in the manifest AND as runtime permissions. If either is missing or denied, `startScan()` returns immediately with zero results and no error or exception. `connect()` throws a `SecurityException` (which may be uncaught).

**Why it happens:** Android's BLE stack silently drops operations when permissions are missing rather than propagating a meaningful error upward through flutter_blue_plus.

**Consequences:** The scan screen looks functional but shows nothing. In WP1 this is invisible because the mock bypasses all permissions. WP2 will fail silently on first test unless the full permission flow is validated.

**Prevention — manifest:**
```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android <= 11 fallback -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

**Prevention — runtime request sequence (exact order matters):**
1. Check SDK version >= 31
2. Request `[Permission.bluetoothScan, Permission.bluetoothConnect]` together (single dialog)
3. Check `FlutterBluePlus.adapterState` is `on` before starting scan
4. On `permanentlyDenied`: show explanation + `openAppSettings()` — do NOT retry the permission request (OS will ignore it)

**Detection flag for WP2:** The integration test must be run on a freshly-installed build with no permissions granted to validate the full request flow.

---

### CP-5: iOS adapter state starts as `unknown` — scaffold must handle this

**What goes wrong:** On iOS, `FlutterBluePlus.adapterState` emits `BluetoothAdapterState.unknown` as its first value. Any code that immediately acts on adapter state (e.g. auto-starts scan, shows "Bluetooth off" error) will fire incorrectly during the 0.5–1 s initialization window while CoreBluetooth starts up.

**Why it happens:** iOS initialises `CBCentralManager` asynchronously. The initial state is genuinely unknown until the OS confirms.

**Consequences:** iOS scaffold shows a spurious "Bluetooth unavailable" error on every cold launch, even when Bluetooth is on. This will surface in WP3 iOS testing even though it's a WP1 scaffold issue.

**Prevention:**
```dart
// Correct iOS-safe adapter state check
final state = await FlutterBluePlus.adapterState
    .where((s) => s != BluetoothAdapterState.unknown)
    .first
    .timeout(const Duration(seconds: 3));
```

Additionally: on iOS, `turnOn()` does not exist — users must enable Bluetooth via Control Centre. The scaffold must not call or expose a "turn on Bluetooth" action.

---

### CP-6: Subscription leaks from forgotten `cancelWhenDisconnected`

**What goes wrong:** Every `listen()` call on a characteristic value stream or connection state stream creates a `StreamSubscription`. If these are not cancelled when the device disconnects and then reconnects, multiple subscriptions to the same stream accumulate. Each fires independently, causing duplicate state updates, memory growth, and eventual ANR/OOM on long sessions.

**Why it happens:** flutter_blue_plus streams never close and never error — they are designed to be persistent. This means `StreamProvider.autoDispose` in riverpod alone is not sufficient: the underlying flutter_blue_plus subscription must also be explicitly cancelled.

**Consequences:** After 5–10 reconnect cycles the inclinometer display updates multiple times per BLE packet, angle values flicker, and the app becomes progressively slower.

**Prevention:**
- Use `device.cancelWhenDisconnected(subscription)` for all characteristic-level subscriptions.
- For `connectionState` listeners that must survive disconnect (to detect reconnect), pass `delayed: true` so the subscription receives the disconnection event before being cancelled.
- In the riverpod BLE provider, cancel all characteristic subscriptions in the provider's `dispose` method (or `ref.onDispose`).

```dart
// Pattern for characteristic subscription
final sub = characteristic.onValueReceived.listen(_handlePacket);
device.cancelWhenDisconnected(sub, delayed: true);
ref.onDispose(() => sub.cancel());
```

---

## Common Mistakes

Less catastrophic but reliably encountered.

---

### CM-1: Calling `discoverServices()` too early — before connection state confirms `connected`

Calling `discoverServices()` in the same async frame as `connect()` races the OS. The connection state may still be `connecting` and the call either throws or returns an empty service list. Always gate `discoverServices()` on the `connectionState == connected` event.

---

### CM-2: Using `ref.watch()` inside go_router's `redirect` callback

go_router's `redirect` callback is not a widget build context — it does not participate in the normal rebuild cycle. Using `ref.watch()` here causes the entire router to rebuild on every state change including unrelated providers. The correct pattern is `ref.read()` inside `redirect`, with a `refreshListenable` connected to a `NavigationNotifier` (a `Notifier` that implements `Listenable`) that only notifies when navigation-relevant state changes.

```dart
// BLE-aware router setup
final router = GoRouter(
  refreshListenable: ref.read(bleNavigationNotifierProvider.notifier),
  redirect: (context, state) {
    final connectionState = ref.read(bleConnectionProvider);
    if (connectionState == BleState.disconnected && state.uri.path == '/instrument') {
      return '/scan';
    }
    return null;
  },
);
```

If the `refreshListenable` fires on every BLE data packet (because it watches the data stream rather than just the connection state), the router rebuilds at the characteristic notification rate — potentially 10–100 times per second.

---

### CM-3: go_router redirect loop on disconnect

If the redirect logic sends a disconnected user to `/scan` and the scan screen itself checks connection state and redirects elsewhere, a redirect loop forms. go_router will log "redirect loop detected" and the app freezes on a blank screen.

**Prevention:** The redirect guard must have exactly one "safe" landing route for disconnected state (`/scan`) that is not itself guarded by the same condition. Test the disconnect redirect in isolation before WP2 integration.

---

### CM-4: MTU assumption — assuming 512 bytes without confirming

flutter_blue_plus automatically requests 512-byte MTU on Android during connection. However:
- The RN4871 negotiates MTU during connection; whether it accepts 512 depends on firmware configuration.
- The 9-byte state packet is safely below any realistic MTU (minimum 23 bytes without negotiation), so this is not a WP2 blocker.
- Single-byte command writes are also safe.
- Where it matters: if the protocol ever grows (e.g., configuration packets), do not assume 512 bytes is available. Read the `mtu` property after connection and clamp writes accordingly.
- iOS auto-negotiates to 135–255 bytes; never hard-code 512 in platform-shared code.

---

### CM-5: `withoutResponse: true` on command writes — no acknowledgment, silent data loss

The RN4871 Transparent UART characteristic supports both `Write` (with response) and `Write Without Response`. Using `withoutResponse: true` skips the GATT acknowledgment round-trip (faster) but provides no confirmation the device received the command. For Zero X / Zero Y commands that modify instrument state, silent loss is a user-visible defect (instrument doesn't zero).

**Prevention:** Use `withoutResponse: false` for all command writes. The 9-byte command is tiny; the latency cost of a GATT ack is negligible (~1 connection interval, typically 7.5–30 ms).

---

### CM-6: Android GATT cache staleness after firmware updates

Android caches the GATT service/characteristic table per device. If the RN4871 firmware is updated between WP1 and WP2 and the GATT UUIDs change, Android may serve stale cached services and characteristic discovery returns the old layout. `discoverServices()` reads from cache, not from the device.

**Prevention:** During WP2 hardware bring-up, call `device.clearGattCache()` after the first connection if characteristic discovery returns unexpected results. This is only needed for development; shipping apps should not routinely clear the cache.

---

### CM-7: Location services must be enabled at the OS level on Android, not just location permission granted

On Android 6–11, BLE scanning requires both `ACCESS_FINE_LOCATION` permission AND location services enabled in device settings. If location is turned off in settings, `startScan()` silently returns nothing even with permission granted. Flutter has no API to detect this state directly.

**Prevention:** After permission is granted, check `FlutterBluePlus.adapterState` and also surface a message "Enable location services to scan for devices" if running API <= 30 and scan returns nothing after 5 seconds.

---

### CM-8: `permanentlyDenied` permission state — requesting again crashes silently

After a user denies a permission twice on Android, `permission_handler` returns `PermissionStatus.permanentlyDenied`. Calling `.request()` again on a permanently-denied permission produces no dialog — it silently returns `permanentlyDenied` again. If the app then calls `startScan()` it silently fails (see CP-4). The correct response is `openAppSettings()`.

**Prevention:**
```dart
final status = await Permission.bluetoothScan.request();
if (status.isPermanentlyDenied) {
  // Show explanation dialog, then:
  await openAppSettings();
  return; // do NOT call startScan
}
```

---

### CM-9: RN4871 write throttling — 8-write-then-silent-drop bug

Community reports (B4X forum) show the RN4871 stops responding to GATT writes after approximately 8 consecutive transmissions in quick succession, with the `WriteComplete` callback still returning success on the app side. This is believed to be a buffer/flow-control issue in the RN4871 firmware when writes arrive faster than it can process them.

**For WP2:** If Zero commands stop working after repeated rapid taps, this is likely the cause. Introduce a minimum inter-command gap (~100 ms) and debounce the Zero buttons.

---

## WP1-Specific Risks

Things that look correct in the mock but will break when real BLE is wired in WP2.

---

### WP1-R1: Mock delivers data synchronously / deterministically — real BLE is async and drops

The random-walk mock emits data on a regular timer (`Stream.periodic`). Real BLE characteristic notifications arrive asynchronously, can be delayed by connection intervals (7.5–30 ms default, iOS minimum 15 ms), and can be dropped during radio contention. If the UI or providers assume a data value is always freshly updated within N milliseconds, it will break on real hardware.

**What to do in WP1:** Design the `InstrumentState` model with a `lastUpdated` timestamp. The UI should tolerate stale data gracefully (e.g., dim the angle readout after 2 seconds without update) rather than asserting data freshness. Wire this into the mock too so the behavior is tested in WP1.

---

### WP1-R2: Mock connection is instantaneous — real BLE connection takes 100 ms–5 s

The mock's `connect()` likely resolves in one async frame. Real BLE on Android takes 100 ms to 5 s depending on advertising interval, radio conditions, and whether a prior GATT session needs cleanup (status 133 scenario). Any UI loading state that assumes fast connection will produce a jarring experience or appear frozen.

**What to do in WP1:** Implement a proper `connecting` state in the connection state machine with a visible loading indicator. Do not skip this state in the mock — simulate a 300 ms delay to make the WP1 UI test the connecting state for real.

---

### WP1-R3: Mock `disconnect()` is clean — real BLE disconnect is often involuntary and unclean

The mock `disconnect()` is likely a clean, app-initiated operation. Real BLE must handle: OS-initiated disconnect, device power-off, out-of-range, adapter turned off, phone radio reset. Each arrives as a `connectionState == disconnected` event, often without warning.

**What to do in WP1:** The BLE repository interface must treat all disconnections as equivalent — there is no "clean" vs "dirty" disconnect distinction at the interface level. The auto-reconnect stub must trigger on any `disconnected` event, not just expected ones.

---

### WP1-R4: Mock ignores permissions — WP2 will fail silently on first test device

The mock never calls `permission_handler` — it streams data regardless. This means the full permission request flow (CP-4) is never exercised in WP1, and the first test on a real device with no prior Bluetooth permissions will produce a blank scan screen with no actionable error.

**What to do in WP1:** Implement the full permission check / request / permanently-denied flow as part of WP1 even though the mock does not need it. Gate the scan screen entry on permission status. Write a manual test checklist item: "Fresh install, deny permission once, deny twice, grant — verify each state is handled."

---

### WP1-R5: Mock streams never pause — real BLE notifications stop mid-connection and on reconnect

The mock's `Stream.periodic` emits indefinitely once started. Real BLE: characteristic notifications must be explicitly re-enabled after every reconnect (by re-calling `setNotifyValue(true)` after service re-discovery), and can be paused by the peripheral at any time. If the provider only enables notifications once at startup, notifications will silently stop after the first reconnect.

**What to do in WP1:** In the BLE repository abstraction, model notification enable/disable as part of the connect flow, not as a one-time setup. The mock implementation should honour this contract (i.e., mock's data stream starts only after `enableNotifications()` is called on the mock characteristic).

---

### WP1-R6: go_router redirect not exercised in mock — navigation bugs surface in WP2

The mock always returns `connected` state (or simulates it). The go_router redirect guard for "disconnected -> redirect to scan" is never triggered under normal WP1 usage. It may have redirect loop bugs (see CM-3) that only surface when the real BLE layer starts dropping connections.

**What to do in WP1:** Manually test the redirect by simulating a mid-session disconnect via the mock's `simulateDisconnect()` debug method. Confirm the app navigates cleanly to the scan screen and does not loop. This must be done in WP1 before the mock is replaced.

---

## Prevention Strategies Summary

| Pitfall | Primary Prevention | Secondary Safety Net |
|---------|-------------------|----------------------|
| CP-1 Stale services | `discoverServices()` in every `connected` handler | Listen to `onServicesReset` |
| CP-2 GATT 133 | Disconnect + 500 ms delay + exponential backoff | Cap retries, surface manual reconnect UI |
| CP-3 Scan rate limit | Cooldown guard in scan state machine | Disable scan button while scanning |
| CP-4 Silent permission failure | Full manifest + runtime request in correct order | `permanentlyDenied` -> `openAppSettings()` |
| CP-5 iOS unknown adapter state | Wait for non-unknown state with timeout | No `turnOn()` call on iOS |
| CP-6 Subscription leaks | `cancelWhenDisconnected()` on every `listen()` | `ref.onDispose` cancels remaining subscriptions |
| CM-1 Early `discoverServices` | Gate on `connectionState == connected` event | Unit test the connection flow |
| CM-2 `ref.watch` in redirect | `ref.read` + `refreshListenable` on `NavigationNotifier` | Scope `refreshListenable` to connection state only |
| CM-3 Redirect loop | One unconditional safe route for disconnected | Manual test: disconnect mid-session |
| CM-4 MTU assumption | Read `mtu` property; clamp writes | 9-byte packet is safe; revisit if protocol grows |
| CM-5 Write without ack | `withoutResponse: false` for commands | Debounce Zero buttons |
| CM-6 GATT cache | `clearGattCache()` during WP2 firmware bring-up | Expect UUID changes during development |
| CM-7 Location services off | Surface hint if scan returns nothing after 5 s | Affects API <= 30 only |
| CM-8 Permanent deny | Check `isPermanentlyDenied`, call `openAppSettings()` | Never retry `.request()` after permanent deny |
| CM-9 RN4871 write throttle | 100 ms inter-command gap; debounce UI buttons | WP2 test: rapid Zero taps |
| WP1-R1 Sync mock vs async BLE | `lastUpdated` timestamp in model; tolerate stale data | Dim readout after 2 s no update |
| WP1-R2 Fast mock connect | Simulate 300 ms delay; show `connecting` state | Do not let mock skip `connecting` state |
| WP1-R3 Clean vs involuntary disconnect | Treat all `disconnected` events equally at interface | Auto-reconnect stub triggers on any disconnect |
| WP1-R4 No permissions in mock | Implement full permission flow in WP1 | Manual test checklist for fresh install |
| WP1-R5 Mock streams never pause | Notification enable modeled as part of connect flow | Mock honours `enableNotifications()` contract |
| WP1-R6 Redirect untested in mock | `simulateDisconnect()` debug method in mock | Redirect test before removing mock |

---

## Sources

- flutter_blue_plus official README (chipweinberger/flutter_blue_plus): https://github.com/chipweinberger/flutter_blue_plus
- Punch Through — Android BLE Ultimate Guide: https://punchthrough.com/android-ble-guide/
- Punch Through — BLE Throughput Part 4 (connection intervals): https://punchthrough.com/ble-throughput-part-4/
- flutter_blue_plus pub.dev package page: https://pub.dev/packages/flutter_blue_plus
- flutter_blue_plus changelog: https://pub.dev/packages/flutter_blue_plus/changelog
- Sparkleo — Advanced BLE Development with Flutter Blue Plus: https://medium.com/@sparkleo/advanced-ble-development-with-flutter-blue-plus-ec6dd17bf275
- Flutter BLE Permissions Guide (blefluttercourse.com): https://blog.blefluttercourse.com/blog/flutter-ble-permissions-android-ios
- Baseflow permission_handler — Android 12 Bluetooth issues: https://github.com/Baseflow/flutter-permission-handler/issues/868
- chipweinberger/flutter_blue_plus — GATT 133 issue: https://github.com/chipweinberger/flutter_blue_plus/issues/501
- DEV.to — Demystifying GATT Status 133: https://dev.to/ble_advertiser/demystifying-android-ble-gatt-status-133-common-causes-and-robust-solutions-for-connection-32la
- Apparence.io — GoRouter + Riverpod redirect pitfalls: https://apparencekit.dev/blog/flutter-riverpod-gorouter-redirect/
- DEV.to — Guarding routes in Flutter with GoRouter and Riverpod: https://dev.to/dinko7/guarding-routes-in-flutter-with-gorouter-and-riverpod-40h4
- Riverpod StreamProvider memory leak issue #3853: https://github.com/rrousselGit/riverpod/issues/3853
- Danielle H — Mocking Bluetooth in Flutter (Updated): https://dsavir-h.medium.com/mocking-bluetooth-in-flutter-updated-cb3b9484ae02
- RN4871 write throttle report (B4X forum): https://www.b4x.com/android/forum/threads/ble2-writedata-to-rn4871-ble-stops-sending-data-after-8-transmissions.140882/
- Microchip RN4870/71 User Guide: https://ww1.microchip.com/downloads/en/DeviceDoc/RN4870-71-Bluetooth-Low-Energy-Module-User-Guide-DS50002466C.pdf
