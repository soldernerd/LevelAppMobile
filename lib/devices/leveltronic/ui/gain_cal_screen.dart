// ignore_for_file: sort_child_properties_last
// (WizardScaffold takes `children` before `actions` on purpose: the steps
// read top to bottom, the buttons last.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/calibration/calibration_math.dart';
import 'package:inclinometer/devices/leveltronic/providers/flip_cal_provider.dart' show SensorMask;
import 'package:inclinometer/devices/leveltronic/providers/gain_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/service_provider.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/format.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/instrument_diagram.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/service_card.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_scaffold.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_widgets.dart';

/// Gain (sensitivity k) calibration against a known tilt step: measure a
/// baseline, then the same with a shim of known height under one end of a
/// baseline of known length.
class GainCalScreen extends ConsumerStatefulWidget {
  const GainCalScreen({super.key});

  @override
  ConsumerState<GainCalScreen> createState() => _GainCalScreenState();
}

class _GainCalScreenState extends ConsumerState<GainCalScreen> {
  static const _title = 'Gain calibration';

  late final TextEditingController _height;
  late final TextEditingController _length;

  @override
  void initState() {
    super.initState();
    final s = ref.read(gainCalProvider);
    _height = TextEditingController(text: _num(s.shimHeightMm));
    _length = TextEditingController(text: _num(s.baselineMm));
  }

  @override
  void dispose() {
    _height.dispose();
    _length.dispose();
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double? _parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

  void _onInput() {
    ref.read(gainCalProvider.notifier).setShim(
          heightMm: _parse(_height.text) ?? 0,
          baselineMm: _parse(_length.text) ?? 0,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(serviceKeepAliveProvider);
    final s = ref.watch(gainCalProvider);
    final n = ref.read(gainCalProvider.notifier);
    final service = ref.watch(serviceModeProvider);

    switch (s.stage) {
      case GainStage.setup:
        final tilt = s.knownTilt;
        return WizardScaffold(
          title: _title,
          children: [
            const Text(
              'Sets the sensitivity k: how many mm/m a given signal means. '
              'It is found by measuring a tilt step you know exactly — a '
              'shim of known height under one end of an edge of known '
              'length.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            const InstrumentDiagram(pose: DiagramPose.shim),
            const SizedBox(height: 8),
            const Text('Calibrate', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            SensorSelector(mask: s.mask, onChanged: n.selectSensors),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('gain-height'),
                    controller: _height,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Shim height', suffixText: 'mm'),
                    onChanged: (_) => _onInput(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('gain-length'),
                    controller: _length,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Edge length', suffixText: 'mm'),
                    onChanged: (_) => _onInput(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tilt > 0
                  ? 'Known tilt step: ${tilt.toStringAsFixed(4)} mm/m'
                  : 'Enter a shim height and an edge length.',
              key: const ValueKey('gain-known-tilt'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(height: 12),
            _KSummary(values: s.currentK),
            const SizedBox(height: 16),
            const ServiceModeCard(),
          ],
          actions: [
            FilledButton(
              key: const ValueKey('gain-begin'),
              onPressed: tilt > 0 ? n.begin : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Start'),
            ),
          ],
        );

      case GainStage.baseline:
        return WizardScaffold(
          title: _title,
          children: [
            const StepHeader(step: 1, total: 3, title: 'Baseline'),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.level),
            const SizedBox(height: 8),
            const Instructions([
              'Put the instrument on the edge / surface without the shim.',
              'Keep the table still, then measure. Takes about 3 seconds.',
            ]),
            if (s.message != null) ...[
              const SizedBox(height: 8),
              Text(s.message!,
                  style: const TextStyle(color: Color(0xFFFFA000))),
            ],
          ],
          actions: [
            OutlinedButton(
                onPressed: n.backToStart, child: const Text('Back')),
            FilledButton(
              key: const ValueKey('gain-measure-baseline'),
              onPressed: n.measureBaseline,
              child: const Text('Measure baseline'),
            ),
          ],
        );

      case GainStage.measuringBaseline:
      case GainStage.measuringShim:
      case GainStage.verifying:
        final baseline = s.stage == GainStage.measuringBaseline;
        final verifying = s.stage == GainStage.verifying;
        return WizardScaffold(
          title: _title,
          canPop: false,
          children: [
            StepHeader(
              step: baseline ? 1 : (verifying ? 3 : 2),
              total: 3,
              title: baseline
                  ? 'Baseline'
                  : (verifying ? 'Checking the new k' : 'With the shim'),
            ),
            const SizedBox(height: 16),
            InstrumentDiagram(
              pose: baseline ? DiagramPose.level : DiagramPose.shim,
              label: baseline ? null : '${_num(s.shimHeightMm)} mm',
            ),
            const SizedBox(height: 16),
            ProgressPanel(
              key: const ValueKey('gain-progress'),
              value: s.progress.clamp(0.0, 1.0),
              title: 'Measuring… hold still',
              warning: s.disturbed
                  ? 'The table is not quiet yet — wait for it to calm down.'
                  : null,
            ),
          ],
          actions: [
            OutlinedButton(
                onPressed: n.backToStart, child: const Text('Cancel')),
          ],
        );

      case GainStage.shim:
        return WizardScaffold(
          title: _title,
          children: [
            const StepHeader(step: 2, total: 3, title: 'With the shim'),
            const SizedBox(height: 16),
            InstrumentDiagram(
                pose: DiagramPose.shim, label: '${_num(s.shimHeightMm)} mm'),
            const SizedBox(height: 8),
            Instructions([
              'Put the ${_num(s.shimHeightMm)} mm shim under one end of the '
                  '${_num(s.baselineMm)} mm edge.',
              'Let it settle, keep it still, then measure.',
            ]),
            if (s.message != null) ...[
              const SizedBox(height: 8),
              Text(s.message!,
                  style: const TextStyle(color: Color(0xFFFFA000))),
            ],
          ],
          actions: [
            OutlinedButton(
                onPressed: n.measureAgainBaseline,
                child: const Text('Redo baseline')),
            FilledButton(
              key: const ValueKey('gain-measure-shim'),
              onPressed: n.measureShim,
              child: const Text('Measure with shim'),
            ),
          ],
        );

      case GainStage.review:
        final applicable = [
          for (var i = 0; i < 2; i++)
            SensorMask.has(s.mask, i) &&
                s.estimates[i] != null &&
                s.estimates[i]!.inRange,
        ];
        return WizardScaffold(
          title: _title,
          children: [
            const StepHeader(step: 3, total: 3, title: 'Result'),
            const SizedBox(height: 16),
            for (var i = 0; i < 2; i++)
              if (SensorMask.has(s.mask, i))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GainCard(
                    sensor: 'S${i + 1}',
                    estimate: s.estimates[i],
                    baseline: s.baselineReading![i],
                    tilted: s.shimReading![i],
                  ),
                ),
            if (!service) const ServiceModeCard(),
          ],
          actions: [
            OutlinedButton(
                onPressed: n.measureAgainShim,
                child: const Text('Redo shim')),
            FilledButton(
              key: const ValueKey('gain-apply'),
              onPressed: service && applicable.any((a) => a) ? n.apply : null,
              child: const Text('Apply'),
            ),
          ],
        );

      case GainStage.applying:
        return WizardScaffold(
          title: _title,
          canPop: false,
          children: const [
            SizedBox(height: 48),
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 16),
            Center(
                child: Text('Writing k…',
                    style: TextStyle(color: Colors.white70))),
          ],
        );

      case GainStage.done:
        return WizardScaffold(
          title: _title,
          children: [
            const Center(
                child: Icon(Icons.check_circle,
                    size: 56, color: Color(0xFF43A047))),
            const SizedBox(height: 8),
            const Center(
              child: Text('Sensitivity stored',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(height: 16),
            BeforeAfterTable(
              key: const ValueKey('gain-result'),
              title: 'k  (1e-6 per mm/m)',
              rows: [
                for (var i = 0; i < 2; i++)
                  if (SensorMask.has(s.mask, i) && s.kBefore != null)
                    BeforeAfterRow(
                      label: 'S${i + 1}',
                      before: '${s.kBefore![i]}',
                      after: '${s.kAfter![i]}',
                      delta: fmtSigned(
                          (s.kAfter![i] / s.kBefore![i] - 1) * 100,
                          decimals: 1,
                          unit: '%'),
                    ),
              ],
            ),
            if (s.verifyReading != null) ...[
              const SizedBox(height: 12),
              BeforeAfterTable(
                key: const ValueKey('gain-verify'),
                title: 'Check: the shim now reads (known '
                    '${s.knownTilt.toStringAsFixed(4)} mm/m)',
                rows: [
                  for (var i = 0; i < 2; i++)
                    if (SensorMask.has(s.mask, i))
                      BeforeAfterRow(
                        label: 'S${i + 1}',
                        before: fmtSigned(s.shimReading![i] - s.baselineReading![i],
                            decimals: 4),
                        after: fmtSigned(s.verifyReading![i], decimals: 4),
                        delta: fmtSigned(
                            (s.verifyReading![i].abs() / s.knownTilt - 1) * 100,
                            decimals: 1,
                            unit: '%'),
                      ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('"Before" is the step as read with the old k, '
                  '"After" with the new k; "Change" is the new reading\'s '
                  'deviation from the known tilt.',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ],
            const SizedBox(height: 16),
            const Text(
              'Last in the usual order: the zero (flip) calibration.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
          actions: [
            OutlinedButton(
                onPressed: n.backToStart, child: const Text('Again')),
            FilledButton(
              key: const ValueKey('gain-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );

      case GainStage.error:
        return WizardScaffold(
          title: _title,
          children: [
            const SizedBox(height: 24),
            ErrorPanel(
              message: s.message ?? 'Something went wrong.',
              onRetry: n.backToStart,
            ),
            if (s.needsService) ...[
              const SizedBox(height: 16),
              const ServiceModeCard(),
            ],
          ],
        );
    }
  }
}

class _KSummary extends StatelessWidget {
  const _KSummary({required this.values});

  final List<int>? values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stored sensitivity k (1e-6 per mm/m)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
          const SizedBox(height: 8),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('S${i + 1}',
                      style: const TextStyle(color: Colors.white)),
                  Text(values == null ? '—' : '${values![i]}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GainCard extends StatelessWidget {
  const _GainCard({
    required this.sensor,
    required this.estimate,
    required this.baseline,
    required this.tilted,
  });

  final String sensor;
  final GainEstimate? estimate;
  final double baseline;
  final double tilted;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final Color color;
    final String verdict;
    if (e == null) {
      color = const Color(0xFFE53935);
      verdict = 'The reading did not change. Check the shim and measure '
          'again.';
    } else if (!e.inRange) {
      color = const Color(0xFFE53935);
      verdict = 'The new k would be outside the instrument\'s range.';
    } else if (!e.positive) {
      color = const Color(0xFFFFA000);
      verdict = 'The reading moved the other way (negative). Magnitudes are '
          'used for k; if "front up" should read positive, change the invert '
          'setting afterwards.';
    } else if (e.changePercent.abs() > 50) {
      color = const Color(0xFFFFA000);
      verdict = 'A very large correction — double-check the shim height and '
          'edge length.';
    } else {
      color = const Color(0xFF43A047);
      verdict = 'Good.';
    }
    return Container(
      key: ValueKey('gain-estimate-$sensor'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(sensor,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const Spacer(),
              if (e != null)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'k ${e.kOldMicro} to ${e.kNewMicro}',
                      key: ValueKey('gain-k-$sensor'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Baseline ${fmtTilt(baseline)}   ·   with shim ${fmtTilt(tilted)}'
            '   ·   change ${fmtSigned(tilted - baseline, decimals: 4)}'
            '${e == null ? '' : '  (known ${e.trueTilt.toStringAsFixed(4)})'}'
            '${e == null ? '' : '   ·   k ${fmtSigned(e.changePercent, decimals: 1, unit: '%')}'}',
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 6),
          Text(verdict, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}
