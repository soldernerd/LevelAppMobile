/// GATT identifiers and scan parameters for the Leveltronic instrument.
///
/// The instrument's BLE link is a Microchip RN4871 module in **Transparent
/// UART** mode — a raw byte stream carrying framed API v2 packets (see
/// [api_v2.dart]). These are the Microchip ISSC Transparent UART service and
/// characteristic UUIDs the firmware exposes (`docs/api-reference.md`).
library;

/// Transparent UART service.
const String kServiceUuid = '49535343-fe7d-4ae5-8fa9-9fafd205e455';

/// Host → module: request packets are written here (Write Without Response).
const String kRxCharUuid = '49535343-8841-43f4-a8d4-ecbe34729bb3';

/// Module → host: responses and subscription pushes arrive as notifications.
const String kTxCharUuid = '49535343-1e4d-4bd9-ba61-23c647249616';

/// The instrument advertises as `Leveltronic-<last 2 MAC bytes>`
/// (firmware `Config/config.h` `BLE_DEVICE_NAME`). Scans filter on this prefix.
const String kDeviceNamePrefix = 'Leveltronic';

/// How often the app asks the instrument to push the topic-group snapshots
/// once connected. 50 ms floor is enforced by firmware.
const Duration kSubscriptionInterval = Duration(milliseconds: 250);
