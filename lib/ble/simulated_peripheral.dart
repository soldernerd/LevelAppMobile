import 'package:inclinometer/ble/device_link.dart';

/// An in-memory device for [MockBleManager]: answers requests and pushes
/// subscriptions like the real one, and can vanish (power off, out of range).
/// Each device family brings its own (e.g. the Leveltronic's `SimulatedDevice`).
abstract class SimulatedPeripheral implements DeviceLink {
  /// Called when the device drops the link (power off, reboot, DFU).
  abstract void Function()? onLinkDown;

  /// The device vanishes: all subscriptions end and [onLinkDown] fires.
  void linkDown();

  void dispose();
}
