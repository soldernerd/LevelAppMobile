import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/models/device_state.dart';

/// Abstract interface for all BLE operations.
///
/// [RealBleManager] talks to the instrument over `flutter_blue_plus`;
/// [MockBleManager] drives the UI with synthetic data for tests and for
/// running without hardware. The concrete class is chosen once, in
/// `main.dart`, via a `ProviderScope` override — nothing else in the app
/// imports `flutter_blue_plus`. That import isolation boundary lives here.
abstract class BleManager {
  /// Emits [ScannedDevice] entries while a scan is active.
  Stream<ScannedDevice> get scanResults;

  /// Current connection state for the instrument.
  Stream<ConnectionStatus> get connectionStatus;

  /// Live merged instrument snapshots. Emits `null` as a stale-data sentinel
  /// on disconnect/error so the UI never shows last-known values as live.
  Stream<DeviceState?> get deviceStream;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();

  // --- Zero calibration (Commands 0x1/0x06 — the 180° reversal test) ---

  /// Step 1: place the instrument in its starting orientation, then call
  /// this. Returns the ack status ([Api2Status.ok] if accepted); the
  /// averaging itself runs in the background — poll [pollZeroCalibration].
  Future<Api2Status> zeroCalibrationStep1();

  /// Step 2: after physically rotating the instrument 180°, call this. On
  /// completion the new zero offsets are persisted to the instrument's own
  /// EEPROM. Requires step 1 to have finished ([ZeroCalPhase.step1Done]).
  Future<Api2Status> zeroCalibrationStep2();

  /// Aborts an in-progress zero calibration. `OK` even if already idle.
  Future<Api2Status> zeroCalibrationCancel();

  /// One-shot progress poll (`GET Raw data 0x7/0x03`). Null on a comms
  /// failure — callers should keep polling rather than treat it as terminal.
  Future<Api2ZeroCalStatus?> pollZeroCalibration();

  // --- Triggered precision measurement (Commands 0x1/0x07) ---

  /// Starts averaging up to 64 quality-good batches per sensor. Restarts a
  /// fresh run if one was already in progress.
  Future<Api2Status> startPrecisionMeasurement();

  /// Aborts an in-progress measurement. `OK` even if already idle/done.
  Future<Api2Status> cancelPrecisionMeasurement();

  /// One-shot progress/result poll (`GET Raw data 0x7/0x04`). Null on a
  /// comms failure.
  Future<Api2PrecisionStatus?> pollPrecisionMeasurement();

  void dispose();
}
