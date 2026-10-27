import 'package:flutter/material.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';

/// Asks the user to confirm; false if cancelled.
Future<bool> confirmAction(
  BuildContext context,
  String title,
  String text,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Runs a device operation and shows a snack bar if it fails; returns whether
/// it succeeded. Capture the messenger before any `await`.
Future<bool> runAction(
  ScaffoldMessengerState messenger,
  Future<void> Function() f,
) async {
  try {
    await f();
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    return false;
  }
}

String describeError(Object e) => switch (e) {
  ApiException(status: ApiStatus.invalidParameter) =>
    'The device refused: the value is out of range, or the alignment '
        'is not OK.',
  ApiException() => e.message,
  _ => 'The command failed ($e).',
};
