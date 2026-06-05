import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Tracks whether the BLE permission rationale flow has been triggered this
/// session. File-scope bool so it survives ConsumerWidget rebuilds without
/// requiring a StatefulWidget.
bool _blePermissionsRequested = false;

/// Root scan screen — shown on app launch.
///
/// Displays scan state chip, a FAB to start/stop scanning, and a filtered list
/// of discovered BLE devices (unnamed devices are hidden per SCAN-03).
/// Navigates to /instrument via go_router when [connectionNotifierProvider]
/// reaches [ConnectionStatus.connected].
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final devices = ref.watch(scanResultsProvider)
        .where((d) => d.name.isNotEmpty)
        .toList();

    // Watch permanently-denied state for inline banner (D-02).
    final permanentlyDenied = ref.watch(blePermissionPermanentlyDeniedProvider);

    // Navigate to /instrument via go_router on connect (RESEARCH.md Pitfall 4).
    // Guard: prev != connected prevents duplicate navigation when provider
    // rebuilds while already connected (e.g. scan-revision increment).
    ref.listen(connectionNotifierProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        context.go('/instrument');
      }
    });

    // D-01: Show rationale dialog before system permission prompt on first render.
    // addPostFrameCallback ensures we are outside the build phase when showing
    // a dialog.
    if (!_blePermissionsRequested) {
      _blePermissionsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestBlePermissionsIfNeeded(context, ref);
      });
    }

    final isScanning = status == ConnectionStatus.scanning;

    // FAB is hidden when connecting/connected/disconnecting/reconnecting.
    final showFab = status == ConnectionStatus.idle ||
        status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.scanning ||
        status == ConnectionStatus.error;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Scan', style: TextStyle(fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Chip(
                backgroundColor: _chipColor(status),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                label: Text(
                  _chipLabel(status),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              backgroundColor:
                  isScanning ? Colors.red[400] : const Color(0xFF1E88E5),
              tooltip: isScanning ? 'Stop Scan' : 'Start Scan',
              onPressed: isScanning
                  ? () async {
                      // ConnectionNotifier.stopScan() catches errors and sets
                      // state = ConnectionStatus.error internally (WR-02).
                      await ref
                          .read(connectionNotifierProvider.notifier)
                          .stopScan();
                    }
                  : () async {
                      // ConnectionNotifier.startScan() catches errors and sets
                      // state = ConnectionStatus.error internally (WR-02).
                      await ref
                          .read(connectionNotifierProvider.notifier)
                          .startScan();
                    },
              child: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
            )
          : null,
      // D-02: Conditionally show permanently-denied banner above body.
      body: Column(
        children: [
          if (permanentlyDenied) _buildPermissionDeniedBanner(),
          Expanded(child: _buildBody(context, ref, status, devices)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ConnectionStatus status,
    List<ScannedDevice> devices,
  ) {
    if (status == ConnectionStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (devices.isNotEmpty) _buildDeviceList(ref, devices),
              const SizedBox(height: 16),
              const Text(
                'Could not start scan. Check Bluetooth is enabled.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white54),
            SizedBox(height: 12),
            Text(
              'No devices found',
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
            SizedBox(height: 8),
            Text(
              'Start scanning to discover devices.',
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return _buildDeviceList(ref, devices);
  }

  Widget _buildDeviceList(WidgetRef ref, List<ScannedDevice> devices) {
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return ListTile(
          tileColor: const Color(0xFF1E1E1E),
          leading: Icon(
            _rssiIcon(device.rssi),
            color: Colors.white70,
            size: 20,
          ),
          title: Text(
            device.name,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
          trailing: Text(
            '${device.rssi} dBm',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          onTap: () async {
            // ConnectionNotifier.connect() catches errors and sets
            // state = ConnectionStatus.error internally (WR-02).
            await ref
                .read(connectionNotifierProvider.notifier)
                .connect(device.id);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Permission helpers (D-01, D-02)
// ---------------------------------------------------------------------------

/// Requests BLE permissions on Android with a rationale dialog shown first.
///
/// SDK-aware: API >= 31 uses bluetoothScan + bluetoothConnect; older APIs use
/// bluetooth + locationWhenInUse. Writes permanentlyDenied state to
/// [blePermissionPermanentlyDeniedProvider] if any permission comes back
/// permanently denied.
Future<void> _requestBlePermissionsIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!Platform.isAndroid) return;

  // Determine API level to select the correct permission set.
  final sdkInt =
      (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  final permissions = sdkInt >= 31
      ? [Permission.bluetoothScan, Permission.bluetoothConnect]
      : [Permission.bluetooth, Permission.locationWhenInUse];

  // Skip if all permissions are already granted.
  final statuses = await Future.wait(permissions.map((p) => p.status));
  if (statuses.every((s) => s.isGranted)) return;

  // Show rationale dialog before the system prompt (PERM-03).
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Bluetooth Permission'),
      content: const Text(
        'This app needs Bluetooth to scan for and connect to your '
        'inclinometer instrument.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  // Request permissions after dialog is dismissed.
  final results = await permissions.request();

  // Check for permanently denied permissions and update provider.
  final anyPermanentlyDenied =
      results.values.any((s) => s.isPermanentlyDenied);
  if (anyPermanentlyDenied) {
    ref.read(blePermissionPermanentlyDeniedProvider.notifier).state = true;
  }
}

/// Inline banner shown when BLE permissions are permanently denied (D-02).
///
/// Background: Color(0xFF311B1B) — dark red tint to indicate a blocking state.
Widget _buildPermissionDeniedBanner() {
  return Container(
    color: const Color(0xFF311B1B),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Bluetooth permission is permanently denied. '
            'Open Settings to grant access.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        TextButton(
          onPressed: openAppSettings,
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

IconData _rssiIcon(int rssi) {
  if (rssi >= -60) return Icons.signal_wifi_4_bar;
  if (rssi >= -75) return Icons.network_wifi_3_bar;
  if (rssi >= -85) return Icons.network_wifi_2_bar;
  return Icons.network_wifi_1_bar;
}

Color _chipColor(ConnectionStatus status) {
  switch (status) {
    case ConnectionStatus.idle:
      return const Color(0xFF757575);
    case ConnectionStatus.scanning:
      return const Color(0xFF1E88E5);
    case ConnectionStatus.connecting:
      return const Color(0xFFFFA000);
    case ConnectionStatus.connected:
      return const Color(0xFF43A047);
    case ConnectionStatus.reconnecting:
      return const Color(0xFFF57F17);
    case ConnectionStatus.disconnecting:
      return const Color(0xFFD32F2F);
    case ConnectionStatus.disconnected:
      return const Color(0xFFD32F2F);
    case ConnectionStatus.error:
      return const Color(0xFFD32F2F);
  }
}

String _chipLabel(ConnectionStatus status) {
  switch (status) {
    case ConnectionStatus.idle:
      return 'Idle';
    case ConnectionStatus.scanning:
      return 'Scanning';
    case ConnectionStatus.connecting:
      return 'Connecting…';
    case ConnectionStatus.connected:
      return 'Connected';
    case ConnectionStatus.reconnecting:
      return 'Reconnecting…';
    case ConnectionStatus.disconnecting:
      return 'Disconnecting…';
    case ConnectionStatus.disconnected:
      return 'Disconnected';
    case ConnectionStatus.error:
      return 'Error';
  }
}
