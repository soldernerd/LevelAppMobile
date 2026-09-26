import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inclinometer/ble/api_v2.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Instrument screen shown after a successful BLE connection.
///
/// Shows the live displacement readings (S1/S2, mm — the instrument's core
/// "live readings" value), plus battery voltage/state and on-board/external/
/// ambient temperature, humidity and pressure. Values grey out and a
/// DISCONNECTED badge appears when the data goes stale. "Zero Calibration"
/// and "Measure" open the two triggered-action flows.
///
/// Architecture: no `flutter_blue_plus` import here. All BLE actions go
/// through [connectionNotifierProvider.notifier] or [bleManagerProvider]
/// (via the measurement notifiers) — never directly from this widget.
class InstrumentScreen extends ConsumerWidget {
  const InstrumentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final dataAsync = ref.watch(instrumentDataProvider);

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

    final isActiveConnection = status == ConnectionStatus.connected ||
        status == ConnectionStatus.connecting ||
        status == ConnectionStatus.reconnecting;
    final isConnected = status == ConnectionStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Leveltronic', style: TextStyle(fontSize: 18)),
        actions: [
          if (d != null) ...[
            Icon(_batteryIcon(d.batteryPercent, d.charging),
                color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text('${d.batteryPercent}%',
                style: const TextStyle(fontSize: 13, color: Colors.white)),
            const SizedBox(width: 8),
          ],
          Chip(
            backgroundColor: _chipColor(status),
            label: Text(_chipLabel(status),
                style: const TextStyle(fontSize: 13, color: Colors.white)),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          const SizedBox(width: 8),
          if (kDebugMode)
            TextButton(
              onPressed: () => ref
                  .read(connectionNotifierProvider.notifier)
                  .debugSimulateDisconnect(),
              child: const Text('Sim. Disconnect',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: AnimatedOpacity(
                opacity: isStale ? 0.40 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LiveReadings(state: d),
                    if (isStale)
                      const Padding(
                        padding: EdgeInsets.only(top: 12, bottom: 4),
                        child: Center(
                          child: Text(
                            'DISCONNECTED',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFD32F2F),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isConnected
                                ? () => context.push('/instrument/zero')
                                : null,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Zero Calibration'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isConnected
                                ? () => context.push('/instrument/precision')
                                : null,
                            icon: const Icon(Icons.center_focus_strong),
                            label: const Text('Measure'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel('Battery'),
                    _ReadoutTile(
                      label: 'Voltage',
                      value: _fmtVolts(d?.batteryMillivolts),
                    ),
                    _ReadoutTile(
                      label: 'Charge',
                      value: d == null ? '—' : '${d.batteryPercent} %',
                    ),
                    _ReadoutTile(
                      label: 'State',
                      value: d == null ? '—' : _batteryStateLabel(d),
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel('Temperature'),
                    _ReadoutTile(
                      label: 'On-board',
                      value: _fmtTemp(d?.onboardTempC),
                    ),
                    _ReadoutTile(
                      label: 'External probe',
                      value: _fmtTemp(d?.externalTempC),
                    ),
                    _ReadoutTile(
                      label: 'Ambient (BME280)',
                      value: _fmtTemp(d?.bme280TempC),
                      stale: d != null && !d.bme280Fresh,
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel('Environment'),
                    _ReadoutTile(
                      label: 'Humidity',
                      value: d?.humidityPct == null
                          ? '—'
                          : '${d!.humidityPct!.toStringAsFixed(1)} %RH',
                      stale: d != null && !d.bme280Fresh,
                    ),
                    _ReadoutTile(
                      label: 'Pressure',
                      value: d?.pressureHpa == null
                          ? '—'
                          : '${d!.pressureHpa!.toStringAsFixed(1)} hPa',
                      stale: d != null && !d.bme280Fresh,
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

/// Live displacement readout — the instrument's core "live readings" value.
/// Two sensors (S1/S2), mm, updated continuously while [DeviceState.displacementOk]
/// is true; greyed placeholders otherwise (demod not running yet).
class _LiveReadings extends StatelessWidget {
  const _LiveReadings({required this.state});

  final DeviceState? state;

  @override
  Widget build(BuildContext context) {
    final ok = state?.displacementOk ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          _DisplacementRow(
            label: 'S1',
            valueMm: state?.displacementS1Mm,
            ok: ok,
            qualityOk: state?.quality1Ok ?? true,
          ),
          const SizedBox(height: 4),
          _DisplacementRow(
            label: 'S2',
            valueMm: state?.displacementS2Mm,
            ok: ok,
            qualityOk: state?.quality2Ok ?? true,
          ),
          if (!ok) ...[
            const SizedBox(height: 8),
            const Text(
              'Live readings not available — sensor not running',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white30),
            ),
          ],
        ],
      ),
    );
  }
}

class _DisplacementRow extends StatelessWidget {
  const _DisplacementRow({
    required this.label,
    required this.valueMm,
    required this.ok,
    required this.qualityOk,
  });

  final String label;
  final double? valueMm;
  final bool ok;
  final bool qualityOk;

  @override
  Widget build(BuildContext context) {
    final show = ok && valueMm != null;
    final color = !show
        ? Colors.white38
        : (qualityOk ? Colors.white : const Color(0xFFFFA000));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 28, color: Colors.white38)),
        Row(
          children: [
            if (show && !qualityOk)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.warning_amber_rounded,
                    size: 18, color: Color(0xFFFFA000)),
              ),
            Text(
              show ? '${_fmtDisplacement(valueMm!)} mm' : '––.––– mm',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white38,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReadoutTile extends StatelessWidget {
  const _ReadoutTile({
    required this.label,
    required this.value,
    this.stale = false,
  });

  final String label;
  final String value;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 15, color: Colors.white60)),
          Row(
            children: [
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.history_toggle_off,
                      size: 14, color: Colors.white30),
                ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _fmtDisplacement(double v) =>
    '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(3)}';

String _fmtTemp(double? c) =>
    c == null ? '—' : '${c >= 0 ? '+' : '−'}${c.abs().toStringAsFixed(2)} °C';

String _fmtVolts(int? mv) =>
    mv == null || mv == 0 ? '—' : '${(mv / 1000).toStringAsFixed(3)} V';

String _batteryStateLabel(DeviceState d) {
  final base = switch (d.batteryState) {
    BatteryState.normal => 'Normal',
    BatteryState.low => 'Low',
    BatteryState.critical => 'Critical',
    BatteryState.charging => 'Charging',
    BatteryState.full => 'Full',
    BatteryState.unknown => 'Unknown',
  };
  if (d.charging && d.batteryState != BatteryState.charging) return '$base · chg';
  return base;
}

IconData _batteryIcon(int battery, bool charging) {
  if (charging) return Icons.battery_charging_full;
  if (battery > 75) return Icons.battery_full;
  if (battery > 40) return Icons.battery_6_bar;
  if (battery > 15) return Icons.battery_3_bar;
  return Icons.battery_0_bar;
}

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
