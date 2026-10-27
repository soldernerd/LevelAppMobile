/// The transport-independent view of an open connection to a device:
/// send an API request and get its reply, or subscribe to a resource and get
/// its pushes. `RealBleManager` implements it over BLE; the simulator behind
/// `MockBleManager` implements it in memory. Everything above this line
/// (typed API, live feed, calibration wizards) is plain Dart and tested
/// against the simulator.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:inclinometer/ble/api_v3.dart';

/// A device reply: the status byte plus the data that follows an OK status.
class ApiReply {
  const ApiReply(this.status, [Uint8List? data]) : _data = data;

  final ApiStatus status;
  final Uint8List? _data;

  Uint8List get data => _data ?? Uint8List(0);
  bool get ok => status == ApiStatus.ok;

  /// Throws [ApiException] unless the status is OK.
  ApiReply orThrow(String what) {
    if (!ok) throw ApiException(status, what);
    return this;
  }
}

/// The device answered, but not with OK.
class ApiException implements Exception {
  const ApiException(this.status, this.what);

  final ApiStatus status;
  final String what;

  bool get isServiceModeRequired => status == ApiStatus.serviceModeRequired;

  /// A message fit for a snackbar / error panel.
  String get message => switch (status) {
        ApiStatus.serviceModeRequired =>
          'Service mode is off. Switch it on at the instrument '
              '(SETTINGS > Service mode, press the right knob twice).',
        ApiStatus.busyResource =>
          'The instrument is busy. Make sure the measurement is running and '
              'no other procedure is active, then try again.',
        ApiStatus.busyExclusive =>
          'Another activity (raw capture or phasor stream) is using the '
              'sensor. Wait for it to finish.',
        ApiStatus.invalidParameter =>
          'The instrument rejected the value (out of range or conflicting '
              'with another setting).',
        ApiStatus.unknownResource =>
          'This instrument firmware does not support "$what".',
        _ => 'The instrument answered ${status.name} to "$what".',
      };

  @override
  String toString() => 'ApiException($what: ${status.name})';
}

/// The link itself failed (not connected, timeout, dropped) — as opposed to
/// the device answering with an error status.
class LinkException implements Exception {
  const LinkException(this.message);
  final String message;

  @override
  String toString() => 'LinkException($message)';
}

abstract class DeviceLink {
  /// Sends one request and waits for its reply. Throws [LinkException] if the
  /// link is down or the device does not answer in time; any device status,
  /// including errors, comes back as an [ApiReply].
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]);

  /// Subscribes to a resource. [subscribeOpcode] is a SUBSCRIBE opcode;
  /// [payload] is the request body (default: `u32 intervalMs`). The stream
  /// emits each push's data (after `[issue_seq][page]`), errors with an
  /// [ApiException] if the device refuses, and completes when the link goes
  /// down. The subscription is shared between listeners and ended
  /// (UNSUBSCRIBE) when the last one cancels.
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  });
}

/// A [DeviceLink] that was opened by a [BleManager] to one particular device:
/// it knows which one, and when it is gone. A manager can hold several of these
/// at once; each has its own request correlation and subscriptions.
abstract class DeviceConnection implements DeviceLink {
  /// The BLE address / peripheral id this connection was opened to.
  String get id;

  /// Completes (never with an error) when the link is down — closed on
  /// purpose, dropped by the device, or lost.
  Future<void> get closed;

  /// Ends the connection and everything riding on it. Safe to call twice.
  Future<void> close();
}

/// The link of "no device": every request fails the way one on a dropped
/// connection does.
class DisconnectedLink implements DeviceLink {
  const DisconnectedLink();

  @override
  Future<ApiReply> request(
    int opcode, [
    List<int> payload = const [],
    Duration? timeout,
  ]) =>
      Future<ApiReply>.error(const LinkException('not connected'));

  @override
  Stream<Uint8List> subscribe(
    int subscribeOpcode, {
    int intervalMs = 250,
    List<int>? payload,
  }) =>
      Stream<Uint8List>.error(const LinkException('not connected'));
}
