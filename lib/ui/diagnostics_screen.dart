import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_v3.dart';
import 'package:inclinometer/providers/diagnostics_provider.dart';
import 'package:inclinometer/ui/widgets/format.dart';

/// Signal diagnostics: RMS, peak-to-peak and phase of the four ADC channels
/// (S2, B, A, S1) at the converter pins, and the tilt each sensor channel's
/// amplitude would correspond to by the Wyler handbook figure. For setting up
/// and troubleshooting, not for measuring.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = ref.watch(signalDiagProvider);

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
                e is Exception && e.toString().contains('unknownResource')
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
                'Channels in ADC order. A and B are the excitation '
                'references (A is the phase reference, 0°); S1 and S2 are the '
                'sensor signals.',
                style: TextStyle(color: Colors.white60, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < 4; i++) ...[
                _ChannelCard(
                  index: i,
                  name: ApiSignalDiag.channelNames[i],
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
                    const Text('Theoretical tilt from the signal amplitude',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70)),
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
            Text(v,
                style: const TextStyle(
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.index,
    required this.name,
    required this.rmsMv,
    required this.p2pMv,
    required this.phaseDeg,
    required this.maxRms,
  });

  final int index;
  final String name;
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
              Text(name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(width: 8),
              Text('channel $index', style: label),
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
                  child: _cell('PEAK–PEAK', '${_mv(p2pMv)} mV', value, label)),
              Expanded(
                  child: _cell('PHASE',
                      '${fmtSigned(phaseDeg, decimals: 1)}°', value, label)),
            ],
          ),
        ],
      ),
    );
  }

  static String _mv(double v) => v.toStringAsFixed(v.abs() < 100 ? 2 : 1);

  static Widget _cell(String k, String v, TextStyle vs, TextStyle ks) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(k, style: ks), const SizedBox(height: 2), Text(v, style: vs)],
      );
}
