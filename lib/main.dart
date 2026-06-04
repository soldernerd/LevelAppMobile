import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [bleManagerProvider.overrideWith((_) => MockBleManager())],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Text('Phase 1'))),
      ),
    ),
  );
}
