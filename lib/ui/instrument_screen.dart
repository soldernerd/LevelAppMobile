import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inclinometer/ble/ble_protocol.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Full InstrumentScreen shown after a successful BLE connection.
///
/// Displays angle X/Y readouts at 80sp with tabular figures, a connection
/// chip, battery indicator, Zero buttons, stale-data animation, and a
/// debug "Sim. Disconnect" button (kDebugMode only).
///
/// Architecture: no flutter_blue_plus import (CLAUDE.md). All BLE actions
/// go through [connectionNotifierProvider.notifier].
class InstrumentScreen extends ConsumerWidget {
  const InstrumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final dataAsync = ref.watch(instrumentDataProvider);

    // Navigate back to /scan on disconnect or error (D-04: no refreshListenable,
    // so we handle post-disconnect navigation imperatively here instead).
    ref.listen(connectionNotifierProvider, (prev, next) {
      if (next == ConnectionStatus.disconnected ||
          next == ConnectionStatus.error) {
        if (context.mounted) context.go('/scan');
      }
    });

    // CRITICAL: hasValue distinguishes AsyncData(null) [stale] from
    // AsyncLoading [not yet connected]. Do NOT use valueOrNull == null
    // alone — that conflates loading with disconnected (Pitfall 1).
    final isStale = dataAsync.hasValue && dataAsync.value == null;
    final DeviceState? deviceState = dataAsync.hasValue ? dataAsync.value : null;

    final isActiveConnection = status == ConnectionStatus.connected ||
        status == ConnectionStatus.connecting ||
        status == ConnectionStatus.reconnecting;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Inclinometer', style: TextStyle(fontSize: 18)),
        actions: [
          // 1. Battery indicator — only when deviceState is available
          if (deviceState != null) ...[
            Icon(_batteryIcon(deviceState.battery), color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              '${deviceState.battery}%',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          // 2. Connection chip — always visible (CONN-04)
          Chip(
            backgroundColor: _chipColor(status),
            label: Text(
              _chipLabel(status),
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          const SizedBox(width: 8),
          // 3. Debug button — kDebugMode only; never compiled into release builds.
          // Routes through ConnectionNotifier.debugSimulateDisconnect() to keep
          // MockBleManager import out of lib/ui/ (CLAUDE.md architecture rule).
          if (kDebugMode) ...[
            TextButton(
              onPressed: () => ref
                  .read(connectionNotifierProvider.notifier)
                  .debugSimulateDisconnect(),
              child: const Text(
                'Sim. Disconnect',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedOpacity(
                      opacity: isStale ? 0.40 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: Column(
                        children: [
                          _AngleRow(
                            label: 'X',
                            value: deviceState?.angleX ?? 0.0,
                            onZero: status == ConnectionStatus.connected
                                ? () => ref
                                    .read(connectionNotifierProvider.notifier)
                                    .sendCommand(kCmdZeroX)
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _AngleRow(
                            label: 'Y',
                            value: deviceState?.angleY ?? 0.0,
                            onZero: status == ConnectionStatus.connected
                                ? () => ref
                                    .read(connectionNotifierProvider.notifier)
                                    .sendCommand(kCmdZeroY)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    if (isStale)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'DISCONNECTED',
                          style: TextStyle(
                            fontSize: 13,
                            color: const Color(0xFFD32F2F),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isActiveConnection)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () =>
                    ref.read(connectionNotifierProvider.notifier).disconnect(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red[400]!),
                  foregroundColor: Colors.red[400],
                ),
                child: const Text('Disconnect'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Private row widget displaying an axis label, formatted angle, and Zero button.
class _AngleRow extends StatelessWidget {
  const _AngleRow({
    required this.label,
    required this.value,
    required this.onZero,
  });

  final String label;
  final double value;
  final VoidCallback? onZero; // null = disabled (Material default disabled appearance)

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.white54),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _formatAngle(value),
                style: const TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  height: 1.0,
                ),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: onZero,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 44),
            ),
            child: Text('Zero $label'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level private helpers
// ---------------------------------------------------------------------------

/// Formats a double as ±NNN.NN° with sign always shown and zero-padded integers.
///
/// Uses Unicode minus (U+2212) for negative values to match typographic convention.
/// Example: +012.34°, −003.00°
///
/// Guards against non-finite values (NaN/Infinity) that [StatePacket.parse]
/// may produce from raw BLE data, and clamps to ±999.99° so the fixed-width
/// layout is never broken by out-of-range firmware values.
String _formatAngle(double value) {
  if (!value.isFinite) return '  ---.--°';
  final clamped = value.clamp(-999.99, 999.99);
  final sign = clamped >= 0 ? '+' : '−'; // U+2212 Unicode minus, not ASCII hyphen
  final abs = clamped.abs();
  // toStringAsFixed(2) on 3.0 → "3.00"; padLeft(6,'0') → "003.00" (NNN.NN)
  return '$sign${abs.toStringAsFixed(2).padLeft(6, '0')}°';
}

/// Returns the appropriate battery icon for a battery level percentage.
IconData _batteryIcon(int battery) {
  if (battery > 75) return Icons.battery_full;
  if (battery > 40) return Icons.battery_6_bar;
  if (battery > 15) return Icons.battery_3_bar;
  return Icons.battery_0_bar;
}

/// Maps [ConnectionStatus] to its chip background color.
Color _chipColor(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.idle => const Color(0xFF757575),
    ConnectionStatus.scanning => const Color(0xFF1E88E5),
    ConnectionStatus.connecting => const Color(0xFFFFA000),
    ConnectionStatus.connected => const Color(0xFF43A047),
    ConnectionStatus.reconnecting => const Color(0xFFF57F17),
    ConnectionStatus.disconnecting => const Color(0xFFD32F2F),
    ConnectionStatus.disconnected => const Color(0xFFD32F2F),
    ConnectionStatus.error => const Color(0xFFD32F2F),
  };
}

/// Maps [ConnectionStatus] to its chip label string.
String _chipLabel(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.idle => 'Idle',
    ConnectionStatus.scanning => 'Scanning',
    ConnectionStatus.connecting => 'Connecting…',
    ConnectionStatus.connected => 'Connected',
    ConnectionStatus.reconnecting => 'Reconnecting…',
    ConnectionStatus.disconnecting => 'Disconnecting…',
    ConnectionStatus.disconnected => 'Disconnected',
    ConnectionStatus.error => 'Error',
  };
}
