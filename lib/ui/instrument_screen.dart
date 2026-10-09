import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/tare_provider.dart';
import 'package:inclinometer/ui/precision_sheet.dart';
import 'package:inclinometer/ui/widgets/battery_indicator.dart';
import 'package:inclinometer/ui/widgets/format.dart';
import 'package:inclinometer/ui/widgets/vibration_indicator.dart';

/// The live screen: S1, S2 and Diff in large type with a vibration indicator
/// each, the battery and on-board temperature small in the top bar, a button
/// to zero the difference and one to take a precision measurement.
///
/// Architecture: no `flutter_blue_plus` import here; everything goes through
/// the providers.
class InstrumentScreen extends ConsumerWidget {
  const InstrumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final dataAsync = ref.watch(instrumentDataProvider);
    final tare = ref.watch(tareProvider);

    ref.listen(connectionNotifierProvider, (prev, next) {
      if (next == ConnectionStatus.disconnected ||
          next == ConnectionStatus.error) {
        if (context.mounted) context.go('/scan');
      }
    });

    // hasValue distinguishes AsyncData(null) [stale] from AsyncLoading
    // [not yet connected]. Do not collapse the two.
    final isStale = dataAsync.hasValue && dataAsync.value == null;
    final DeviceState? d = dataAsync.hasValue ? dataAsync.value : null;
    final connected = status == ConnectionStatus.connected;
    final hasReading = d?.hasReading ?? false;

    final diff = d?.tiltDiff;
    final shownDiff = diff == null ? null : diff - (tare ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Leveltronic', style: TextStyle(fontSize: 18)),
        actions: [
          if (d?.onboardTempC != null) ...[
            const Icon(Icons.thermostat, size: 18, color: Colors.white54),
            Text(
              fmtSigned(d!.onboardTempC, decimals: 1, unit: '°C'),
              key: const ValueKey('onboard-temp'),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(width: 12),
          ],
          if (d?.status != null) ...[
            BatteryIndicator(
              key: const ValueKey('battery'),
              percent: d!.batteryPercent,
              charging: d.charging,
              state: d.batteryState,
              size: 18,
            ),
            const SizedBox(width: 4),
          ],
          if (kDebugMode)
            IconButton(
              tooltip: 'Simulate disconnect',
              icon: const Icon(Icons.link_off, size: 20),
              onPressed: () => ref
                  .read(connectionNotifierProvider.notifier)
                  .debugSimulateDisconnect(),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('menu'),
            onSelected: (v) => _onMenu(context, ref, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'calibration', child: Text('Calibration')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'info', child: Text('All values')),
              PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              if (isStale)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DISCONNECTED',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFD32F2F),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              Expanded(
                child: AnimatedOpacity(
                  opacity: isStale ? 0.40 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _ReadingCard(
                          label: 'S1',
                          value: d?.tiltS1,
                          hasReading: hasReading,
                          disturbed: d?.s1Doubtful ?? false,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 2,
                        child: _ReadingCard(
                          label: 'S2',
                          value: d?.tiltS2,
                          hasReading: hasReading,
                          disturbed: d?.s2Doubtful ?? false,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3,
                        child: _ReadingCard(
                          label: 'DIFF',
                          sublabel: 'S1 − S2',
                          value: shownDiff,
                          hasReading: hasReading,
                          disturbed: d?.diffDoubtful ?? false,
                          emphasis: true,
                          zeroed: tare != null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (d != null && !d.demodRunning)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The tilt measurement is stopped.',
                    style: TextStyle(color: Color(0xFFFFA000)),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('zero-diff'),
                      onPressed: connected && hasReading && diff != null
                          ? () => _zeroDiff(context, ref, d!)
                          : null,
                      onLongPress: tare != null
                          ? () => ref.read(tareProvider.notifier).clear()
                          : null,
                      icon: Icon(tare == null
                          ? Icons.exposure_zero
                          : Icons.restart_alt),
                      label: Text(tare == null ? 'Zero Diff' : 'Re-zero Diff'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('precision'),
                      onPressed:
                          connected ? () => showPrecisionSheet(context) : null,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Precision'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ],
              ),
              if (tare != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Diff is zeroed at ${fmtTilt(tare)} mm/m (long-press the '
                    'button to clear)',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _zeroDiff(
      BuildContext context, WidgetRef ref, DeviceState d) async {
    final notifier = ref.read(tareProvider.notifier);
    if (d.diffDoubtful) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reading is disturbed'),
          content: const Text(
              'The table is not quiet. Zeroing now would bake the disturbance '
              'in. Zero anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Zero anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    await notifier.set(d.tiltDiff!);
  }

  void _onMenu(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'calibration':
        context.push('/instrument/calibration');
      case 'settings':
        context.push('/instrument/settings');
      case 'info':
        context.push('/instrument/info');
      case 'diagnostics':
        context.push('/instrument/diagnostics');
      case 'disconnect':
        ref.read(connectionNotifierProvider.notifier).disconnect();
    }
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.label,
    required this.value,
    required this.hasReading,
    required this.disturbed,
    this.sublabel,
    this.emphasis = false,
    this.zeroed = false,
  });

  final String label;
  final String? sublabel;
  final double? value;
  final bool hasReading;
  final bool disturbed;
  final bool emphasis;
  final bool zeroed;

  @override
  Widget build(BuildContext context) {
    final show = hasReading && value != null;
    final color = !show
        ? Colors.white38
        : (disturbed ? const Color(0xFFFFA000) : Colors.white);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: emphasis ? const Color(0xFF1B2A38) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: emphasis ? const Color(0xFF3D6A94) : Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: emphasis ? 24 : 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54)),
                if (sublabel != null)
                  Text(zeroed ? 'zeroed' : sublabel!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    show ? fmtTilt(value) : '––.––––',
                    key: ValueKey('reading-$label'),
                    style: TextStyle(
                      fontSize: emphasis ? 76 : 62,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('mm/m',
                      style: TextStyle(
                          fontSize: emphasis ? 22 : 18,
                          color: Colors.white54)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          VibrationIndicator(disturbed: disturbed, hasReading: hasReading),
        ],
      ),
    );
  }
}
