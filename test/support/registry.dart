import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/leveltronic/leveltronic_driver.dart';
import 'package:inclinometer/devices/neigmess2/neigmess_driver.dart';

/// The drivers a test app knows (what `main.dart` registers).
final testRegistry = DeviceRegistry(const [LeveltronicDriver(), NeigMessDriver()]);
