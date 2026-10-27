/// GATT identifiers of the shared BLE transport.
///
/// The instrument's BLE link is a Microchip RN4871 module in **Transparent
/// UART** mode — a raw byte stream carrying framed API v3 packets (see
/// [api_v3.dart]). These are the Microchip ISSC Transparent UART service and
/// characteristic UUIDs the firmware exposes (`docs/api-reference.md`).
library;

/// Transparent UART service.
const String kServiceUuid = '49535343-fe7d-4ae5-8fa9-9fafd205e455';

/// Host → module: request packets are written here (Write Without Response).
const String kRxCharUuid = '49535343-8841-43f4-a8d4-ecbe34729bb3';

/// Module → host: responses and subscription pushes arrive as notifications.
const String kTxCharUuid = '49535343-1e4d-4bd9-ba61-23c647249616';
