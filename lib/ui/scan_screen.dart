import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/instrument_screen.dart';

/// Root scan screen — shown on app launch.
///
/// Displays scan state chip, a FAB to start/stop scanning, and a filtered list
/// of discovered BLE devices (unnamed devices are hidden per SCAN-03).
/// Navigates to [InstrumentScreen] when [connectionNotifierProvider] reaches
/// [ConnectionStatus.connected].
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final devices = ref.watch(scanResultsProvider)
        .where((d) => d.name.isNotEmpty)
        .toList();

    // Navigate to InstrumentScreen on connect (post-frame to avoid build-phase push).
    // Guard: prev != connected prevents duplicate push when provider rebuilds
    // while already connected (e.g. scan-revision increment triggers rebuild).
    ref.listen(connectionNotifierProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const InstrumentScreen()),
        );
      }
    });

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
      body: _buildBody(context, ref, status, devices),
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
