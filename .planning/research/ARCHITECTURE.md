# Architecture Research

**Project:** Inclinometer BLE Companion App
**Researched:** 2026-06-04
**Confidence:** HIGH (Context7 + official docs for all core claims)

---

## Recommended Component Structure

The six defined files map to three distinct layers. Dependencies flow strictly downward — UI never touches BLE, providers never import flutter_blue_plus directly.

```
┌─────────────────────────────────────────────────┐
│  PRESENTATION LAYER                             │
│  lib/ui/scan_screen.dart                        │
│  lib/ui/instrument_screen.dart                  │
│  (ConsumerWidget — calls ref.watch only)        │
└────────────────────┬────────────────────────────┘
                     │ ref.watch / ref.read
┌────────────────────▼────────────────────────────┐
│  STATE / APPLICATION LAYER                      │
│  lib/providers/device_provider.dart             │
│  (NotifierProvider — owns connection state)     │
│  (StreamProvider.family — owns angle stream)    │
└────────────────────┬────────────────────────────┘
                     │ calls methods on
┌────────────────────▼────────────────────────────┐
│  SERVICE / BLE LAYER                            │
│  lib/ble/ble_manager.dart  (abstract class)     │
│    ├── MockBleManager  (WP1)                    │
│    └── RealBleManager  (WP2, wraps FBP)         │
│  lib/ble/ble_protocol.dart (pure constants)     │
│  lib/models/device_state.dart (data classes)    │
└─────────────────────────────────────────────────┘
```

### File responsibilities

| File | Owns | Does NOT touch |
|------|------|----------------|
| `ble_protocol.dart` | GATT UUIDs, command bytes, `StatePacket.parse()` | Nothing stateful |
| `ble_manager.dart` | `abstract class BleManager` + both impls | UI, Riverpod |
| `device_state.dart` | `DeviceState`, `ConnectionStatus` enum, `ScannedDevice` | BLE API |
| `device_provider.dart` | `ConnectionNotifier`, `angleStreamProvider`, `scanResultsProvider` | BLE API (only talks to `BleManager`) |
| `scan_screen.dart` | Scan UI, device list, connect tap | BLE API, providers other than scan/connection |
| `instrument_screen.dart` | Angle display, zero buttons, battery | BLE API, connection logic |

---

## BLE Abstraction Pattern

### Use an abstract class with two concrete implementations

Do not use a single class with an `isMock` flag. A flag couples both code paths permanently, causes dead code in production, and breaks the open/closed principle. Use an abstract class with two implementations instead.

```dart
// lib/ble/ble_manager.dart

abstract class BleManager {
  /// Emits ScannedDevice entries while scanning is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state stream for the active device.
  Stream<ConnectionStatus> get connectionStatus;

  /// Raw 9-byte state packet stream from the instrument characteristic.
  Stream<List<int>> get statePackets;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendCommand(int commandByte);

  void dispose();
}

class MockBleManager implements BleManager { ... }   // WP1
class RealBleManager implements BleManager { ... }   // WP2
```

### Inject via ProviderScope override at app entry point

Define the provider against the abstract type. In `main.dart`, override it with the concrete implementation. In WP2, change only that one line.

```dart
// lib/providers/device_provider.dart
final bleManagerProvider = Provider<BleManager>((ref) {
  throw UnimplementedError('bleManagerProvider must be overridden at root');
});

// lib/main.dart  (WP1)
void main() {
  runApp(
    ProviderScope(
      overrides: [
        bleManagerProvider.overrideWith((_) => MockBleManager()),
      ],
      child: const MyApp(),
    ),
  );
}

// lib/main.dart  (WP2 — the ONLY change)
// bleManagerProvider.overrideWith((_) => RealBleManager()),
```

This is the canonical Riverpod pattern confirmed by official Riverpod docs: `ProviderScope.overrides` replaces a provider's implementation without touching any consumer or notifier code. [Source: riverpod.dev/docs/how_to/testing, codewithandrea.com/articles/abstraction-repository-pattern-flutter/]

### MockBleManager implementation sketch

```dart
class MockBleManager implements BleManager {
  final _scanController = StreamController<ScannedDevice>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _packetController = StreamController<List<int>>.broadcast();

  double _angleX = 0.0;
  double _angleY = 0.0;
  int _battery = 85;
  Timer? _ticker;

  @override
  Stream<ScannedDevice> get scanResults => _scanController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<List<int>> get statePackets => _packetController.stream;

  @override
  Future<void> connect(String deviceId) async {
    _statusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    _statusController.add(ConnectionStatus.connected);
    _startTicker();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _angleX += (Random().nextDouble() - 0.5) * 0.2;
      _angleY += (Random().nextDouble() - 0.5) * 0.2;
      _packetController.add(StatePacket.encode(_angleX, _angleY, _battery));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scanController.close();
    _statusController.close();
    _packetController.close();
  }
}
```

---

## Data Flow

### Angle data: BLE bytes to widget

```
MockBleManager / RealBleManager
  └─ statePackets: Stream<List<int>>     (raw 9-byte packets)
       │
       ▼
  StatePacket.parse(bytes)               (in ble_protocol.dart)
       │  returns DeviceState(angleX, angleY, battery)
       ▼
  deviceStateProvider: StreamProvider<DeviceState>
       │  derived from bleManagerProvider.statePackets
       ▼
  instrument_screen.dart
    ref.watch(deviceStateProvider.select((s) => s.angleX))
    ref.watch(deviceStateProvider.select((s) => s.angleY))
    ref.watch(deviceStateProvider.select((s) => s.battery))
```

### Why parse in ble_protocol.dart, not in the manager or provider

- `BleManager` implementations are swappable — neither one should embed parsing logic that the other duplicates.
- Providers should transform streams, not own parsing algorithms.
- `ble_protocol.dart` is a pure utility file (no state, no Flutter imports). It contains `StatePacket.parse(List<int> bytes)` returning `DeviceState`, and `StatePacket.encode(...)` for the mock. This makes the byte format testable in isolation.

### Parsing implementation

```dart
// lib/ble/ble_protocol.dart

const String kServiceUuid       = '0000XXXX-0000-1000-8000-00805f9b34fb';
const String kStateCharUuid     = '0000YYYY-0000-1000-8000-00805f9b34fb';
const String kCommandCharUuid   = '0000ZZZZ-0000-1000-8000-00805f9b34fb';

const int kCmdZeroX = 0x01;
const int kCmdZeroY = 0x02;

class StatePacket {
  static DeviceState parse(List<int> bytes) {
    assert(bytes.length == 9, 'State packet must be 9 bytes');
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return DeviceState(
      angleX:  bd.getFloat32(0, Endian.little),
      angleY:  bd.getFloat32(4, Endian.little),
      battery: bytes[8],
    );
  }

  static List<int> encode(double ax, double ay, int battery) {
    final bd = ByteData(9);
    bd.setFloat32(0, ax, Endian.little);
    bd.setFloat32(4, ay, Endian.little);
    bd.setUint8(8, battery);
    return bd.buffer.asUint8List().toList();
  }
}
```

Source: [Dart ByteData.getFloat32 API](https://api.flutter.dev/flutter/dart-typed_data/ByteData/getFloat32.html)

### Selective rebuilds with .select()

The angle display only needs to rebuild when `angleX` or `angleY` changes. Battery can update at a different cadence. Use `.select()` to avoid rebuilding the full instrument screen on every 100 ms packet:

```dart
// instrument_screen.dart
final angleX = ref.watch(deviceStateProvider.select((s) => s.value?.angleX));
final angleY = ref.watch(deviceStateProvider.select((s) => s.value?.angleY));
final battery = ref.watch(deviceStateProvider.select((s) => s.value?.battery));
```

This is confirmed by official Riverpod docs: `.select()` causes a consumer to rebuild only when the selected sub-value changes, with immutable selections. [Source: rrousselgit/riverpod — how_to/select.mdx]

### Connection state machine in Riverpod

Use `NotifierProvider<ConnectionNotifier, ConnectionStatus>`. This is the right choice over `StateProvider` because connection management requires methods (connect, disconnect, reconnect) alongside state transitions.

```dart
// lib/models/device_state.dart
enum ConnectionStatus { idle, scanning, connecting, connected, disconnecting, disconnected, error }

// lib/providers/device_provider.dart
class ConnectionNotifier extends Notifier<ConnectionStatus> {
  @override
  ConnectionStatus build() => ConnectionStatus.idle;

  Future<void> connect(String deviceId) async {
    state = ConnectionStatus.connecting;
    try {
      await ref.read(bleManagerProvider).connect(deviceId);
      // BleManager drives further transitions via connectionStatus stream
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  Future<void> disconnect() async {
    state = ConnectionStatus.disconnecting;
    await ref.read(bleManagerProvider).disconnect();
    state = ConnectionStatus.disconnected;
  }

  // Stub for WP2 auto-reconnect — wired in but inactive in WP1
  void scheduleReconnect(String deviceId) {
    // TODO WP2: implement Timer-based reconnect loop
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionStatus>(
  ConnectionNotifier.new,
);
```

Mirror the BLE manager's `connectionStatus` stream into `connectionProvider.state` by listening inside `ConnectionNotifier.build()` with `ref.onDispose` for cleanup — the canonical Riverpod lifecycle pattern. [Source: rrousselgit/riverpod — concepts2/refs.mdx]

### Stream providers for scan results and device state

```dart
// Scan results — active only while scanning
final scanResultsProvider = StreamProvider<List<ScannedDevice>>((ref) {
  return ref.watch(bleManagerProvider).scanResults
      .scan(<ScannedDevice>[], (acc, device, _) {
        // deduplicate by deviceId, update RSSI
        final idx = acc.indexWhere((d) => d.id == device.id);
        if (idx >= 0) {
          acc[idx] = device;
        } else {
          acc.add(device);
        }
        return [...acc];
      });
});

// Device state — active while connected
final deviceStateProvider = StreamProvider<DeviceState>((ref) {
  return ref.watch(bleManagerProvider)
      .statePackets
      .map(StatePacket.parse);
});
```

---

## Build Order

Build bottom-up. Each layer depends on the layer below being stable before the layer above can be verified.

### Phase 1 — Pure data layer (no Flutter, no BLE)

1. `lib/models/device_state.dart` — `DeviceState`, `ScannedDevice`, `ConnectionStatus` enum. These are plain Dart data classes. Everything else depends on them.
2. `lib/ble/ble_protocol.dart` — `StatePacket.parse()`, `StatePacket.encode()`, UUID constants, command constants. Pure Dart, unit-testable immediately.

### Phase 2 — BLE abstraction

3. `lib/ble/ble_manager.dart` abstract class — define the interface contract. No implementation yet.
4. `MockBleManager` (in same file or `lib/ble/mock_ble_manager.dart`) — implements the abstract class, produces random-walk data via `Timer` and `StreamController`. This is the entire WP1 BLE layer.

### Phase 3 — State layer

5. `lib/providers/device_provider.dart` — `bleManagerProvider`, `connectionProvider`, `scanResultsProvider`, `deviceStateProvider`. Depends on models and BleManager interface; does not care which implementation is active.

### Phase 4 — UI layer

6. `lib/ui/scan_screen.dart` — depends only on `scanResultsProvider` and `connectionProvider`.
7. `lib/ui/instrument_screen.dart` — depends only on `deviceStateProvider` and `connectionProvider`.

### Phase 5 — Entry point wiring

8. `lib/main.dart` — `ProviderScope` with `bleManagerProvider.overrideWith((_) => MockBleManager())`, `go_router` setup, permission requests.

### WP2 delta (the swap)

- Add `RealBleManager` implementing `BleManager` using `flutter_blue_plus` calls.
- Change one line in `main.dart`: `MockBleManager()` → `RealBleManager()`.
- No changes to models, protocol parser, providers, or UI.

---

## Anti-Patterns to Avoid

### Putting flutter_blue_plus imports in providers

If `device_provider.dart` imports `flutter_blue_plus`, you lose the mock/real swap. The provider must only see the `BleManager` abstract interface.

### Parsing bytes inside RealBleManager (or MockBleManager)

Both managers should emit raw `List<int>` packets. Parsing in `ble_protocol.dart` keeps the format logic in one place and makes it testable without any BLE infrastructure.

### Using a single DeviceProvider god-object

Keep connection state, scan results, and device state as separate providers. They have different lifecycles (scan is transient, device state is active only when connected) and different consumers (scan screen vs instrument screen).

### Rebuilding the instrument screen on every packet

At 10 Hz, a whole-widget rebuild is harmless on modern devices, but using `.select()` is free and makes the architecture scalable. Do it from the start.

### Storing ConnectionStatus inside DeviceState

`ConnectionStatus` changes independently of angle data. Mixing them forces the instrument screen to rebuild on connection transitions, and makes the state machine harder to reason about.

---

## Sources

- flutter_blue_plus characteristic stream API: https://github.com/chipweinberger/flutter_blue_plus/blob/master/packages/flutter_blue_plus/README.md
- Riverpod provider override pattern: https://riverpod.dev/docs/how_to/testing
- Riverpod abstraction/repository pattern: https://codewithandrea.com/articles/abstraction-repository-pattern-flutter/
- Riverpod layered architecture: https://codewithandrea.com/articles/flutter-app-architecture-riverpod-introduction/
- Riverpod .select() for granular rebuilds: https://github.com/rrousselgit/riverpod/blob/master/website/docs/how_to/select.mdx
- Riverpod ref.onDispose lifecycle: https://github.com/rrousselgit/riverpod/blob/master/website/docs/concepts2/refs.mdx
- Dart ByteData.getFloat32: https://api.flutter.dev/flutter/dart-typed_data/ByteData/getFloat32.html
