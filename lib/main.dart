// main.dart — Phase 4 temporary entry point.
// Replaced entirely in Phase 5 by the go_router + permission-handler version.
// Do NOT add go_router, permission_handler, or platform wiring here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/scan_screen.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        bleManagerProvider.overrideWithValue(MockBleManager()),
      ],
      child: MaterialApp(
        title: 'Inclinometer',
        theme: ThemeData.dark(),
        home: const ScanScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
