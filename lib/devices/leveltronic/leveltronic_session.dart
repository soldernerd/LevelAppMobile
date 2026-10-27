import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/devices/leveltronic/device_state.dart';
import 'package:inclinometer/devices/leveltronic/instrument_api.dart';
import 'package:inclinometer/devices/leveltronic/live_feed.dart';

/// An open Leveltronic: the typed [api] and the always-on [LiveFeed], which
/// keeps running for as long as the connection does — also while another
/// device is the one on screen.
class LeveltronicSession extends DeviceSession {
  LeveltronicSession({
    required super.driver,
    required super.connection,
    required super.identity,
  })  : api = InstrumentApi(connection),
        feed = LiveFeed(InstrumentApi(connection));

  final InstrumentApi api;
  final LiveFeed feed;

  /// The last merged snapshot (parts are null until their first push).
  DeviceState get state => feed.state;

  /// Emits the merged snapshot on every update of any part; completes when the
  /// session is closed.
  Stream<DeviceState> get states => feed.stream;

  void start() => feed.start();

  @override
  Future<void> close() async {
    await feed.stop();
    await super.close();
  }
}
