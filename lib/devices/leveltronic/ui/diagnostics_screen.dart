import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/diagnostics_provider.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/format.dart';

/// Folds an angle into [0°, 360°), the range the measured phases use.
double _wrap360(double deg) => ((deg % 360) + 360) % 360;

/// Signal diagnostics: RMS, peak-to-peak and phase of the four ADC channels
/// (A, B, S1, S2) at the converter pins, and the tilt each sensor channel's
/// amplitude would correspond to by the Wyler handbook figure. For setting up
/// and troubleshooting, not for measuring.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = ref.watch(signalDiagProvider);
    final pga = ref.watch(channelPgaProvider).value;
    final stored = ref.watch(sensorPhaseProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Diagnostics', style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: diag.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                e is ApiException && e.status == ApiStatus.unknownResource
                    ? 'This firmware has no signal diagnostics.'
                    : 'Could not read the diagnostics.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Channels A, B, S1, S2, with the ADC input each is wired to (A = ch2, '
                'B = ch1, S1 = ch3, S2 = ch0) and its PGA gain. A and B are the '
                'excitation references; S1 and S2 are the sensor signals. '
                'Phase is referenced so that A sits at about 90° and B at about '
                '270°. The calibrated phase of S1 and S2 is the measured phase '
                'less the stored phase: it follows A (90°) for a positive tilt '
                'and B (270°) for a negative one. The drive to the sensor is '
                'A − B, about 2 × A.',
                style: TextStyle(color: Colors.white60, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (final i in ApiSignalDiag.displayOrder) ...[
                _ChannelCard(
                  adc: i,
                  name: ApiSignalDiag.channelNames[i],
                  pga: pga?[i],
                  calibratedDeg: switch (ApiSignalDiag.channelNames[i]) {
                    // Measured phase minus the stored signal phase: follows
                    // A (90°) for a positive tilt, B (270°) for a negative.
                    'S1' || 'S2' => stored == null ||
                            stored[ApiSignalDiag.channelNames[i] == 'S1' ? 0 : 1] == null
                        ? null
                        : _wrap360(
                            d.phaseDeg[i] -
                                stored[ApiSignalDiag.channelNames[i] == 'S1'
                                        ? 0
                                        : 1]! /
                                    100,
                          ),
                    _ => null,
                  },
                  rmsMv: d.rmsMv[i],
                  p2pMv: d.p2pMv[i],
                  phaseDeg: d.phaseDeg[i],
                  maxRms: d.rmsMv.reduce((a, b) => a > b ? a : b),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theoretical tilt from the signal amplitude',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _kv('S1', '${fmtTilt(d.theoreticalTiltS1)} mm/m'),
                    _kv('S2', '${fmtTilt(d.theoreticalTiltS2)} mm/m'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: Colors.white)),
        Text(
          v,
          style: const TextStyle(
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.adc,
    required this.name,
    required this.pga,
    required this.calibratedDeg,
    required this.rmsMv,
    required this.p2pMv,
    required this.phaseDeg,
    required this.maxRms,
  });

  final int adc;
  final String name;

  /// ADC PGA gain; null where the firmware cannot tell.
  final int? pga;

  /// The measured phase relative to the drive, minus the stored phase; null
  /// for A and B or when the stored phase is unknown.
  final double? calibratedDeg;
  final double rmsMv;
  final double p2pMv;
  final double phaseDeg;
  final double maxRms;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 11, color: Colors.white38);
    const value = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      key: ValueKey('diag-$name'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text('ADC ch$adc', style: label),
              if (pga != null) ...[
                const Spacer(),
                Text(
                  'PGA ×$pga',
                  key: ValueKey('pga-$name'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: maxRms <= 0 ? 0 : (rmsMv / maxRms).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white10,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _cell('RMS', '${_mv(rmsMv)} mV', value, label)),
              Expanded(
                child: _cell('PEAK–PEAK', '${_mv(p2pMv)} mV', value, label),
              ),
              Expanded(
                child: _cell(
                  'PHASE',
                  '${fmtSigned(phaseDeg, decimals: 1)}°',
                  value,
                  label,
                ),
              ),
            ],
          ),
          if (calibratedDeg != null) ...[
            const SizedBox(height: 10),
            KeyedSubtree(
              key: ValueKey('cal-phase-$name'),
              child: _cell(
                'CALIBRATED PHASE',
                '${fmtSigned(calibratedDeg!, decimals: 1)}°',
                value,
                label,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _mv(double v) => v.toStringAsFixed(v.abs() < 100 ? 3 : 2);

  static Widget _cell(String k, String v, TextStyle vs, TextStyle ks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: ks),
      const SizedBox(height: 2),
      Text(v, style: vs),
    ],
  );
}
