// ignore_for_file: sort_child_properties_last
// (WizardScaffold takes `children` before `actions` on purpose: the steps
// read top to bottom, the buttons last.)

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/calibration/calibration_math.dart';
import 'package:inclinometer/devices/leveltronic/calibration/sensor_mask.dart';
import 'package:inclinometer/devices/leveltronic/providers/phase_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/service_provider.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/format.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/instrument_diagram.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/service_card.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_scaffold.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_widgets.dart';

/// Phase calibration: capture the signal with a clear positive and/or negative
/// tilt; its direction is each sensor's signal phase.
class PhaseCalScreen extends ConsumerWidget {
  const PhaseCalScreen({super.key});

  static const _title = 'Phase calibration';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serviceKeepAliveProvider);
    final s = ref.watch(phaseCalProvider);
    final n = ref.read(phaseCalProvider.notifier);
    final service = ref.watch(serviceModeProvider);

    switch (s.stage) {
      case PhaseStage.select:
        return WizardScaffold(
          title: _title,
          children: [
            const Text(
              'Each sensor\'s signal is rotated by a calibrated phase so that '
              'a tilt falls entirely in the in-phase part. To find it the app '
              'records the signal with a clear tilt: a positive tilt points '
              'along the phase, a negative one the opposite way. The size of '
              'the tilt does not matter — only that it is clearly larger than '
              'the noise (0.1 mm under a 1 m edge is plenty).',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.shimFront),
            const SizedBox(height: 8),
            const Text('Tilts to measure',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            SegmentedButton<PhaseMode>(
              segments: const [
                ButtonSegment(
                  value: PhaseMode.both,
                  label: Text('+ and −', key: ValueKey('phase-mode-both')),
                ),
                ButtonSegment(
                  value: PhaseMode.positiveOnly,
                  label: Text('+ only', key: ValueKey('phase-mode-pos')),
                ),
                ButtonSegment(
                  value: PhaseMode.negativeOnly,
                  label: Text('− only', key: ValueKey('phase-mode-neg')),
                ),
              ],
              selected: {s.mode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => n.selectMode(v.first),
            ),
            const SizedBox(height: 6),
            Text(
              switch (s.mode) {
                PhaseMode.both =>
                  'Most accurate: the sensor\'s zero offset cancels out.',
                PhaseMode.positiveOnly || PhaseMode.negativeOnly =>
                  'One tilt is quicker, but the sensor\'s zero offset then '
                      'adds a small error unless the tilt is large.',
              },
              style: const TextStyle(color: Colors.white54, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Text('Calibrate', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            SensorSelector(mask: s.mask, onChanged: n.selectSensors),
            const SizedBox(height: 16),
            _ValueSummary(label: 'Stored phase', values: s.current),
            const SizedBox(height: 16),
            const ServiceModeCard(),
          ],
          actions: [
            FilledButton(
              key: const ValueKey('phase-begin'),
              onPressed: service ? n.begin : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Start'),
            ),
          ],
        );

      case PhaseStage.ready:
        final positive = s.tilt == PhaseTilt.positive;
        return WizardScaffold(
          title: _title,
          children: [
            StepHeader(
                step: s.step,
                total: s.steps,
                title: positive ? 'Positive tilt' : 'Negative tilt'),
            const SizedBox(height: 16),
            InstrumentDiagram(
                pose: positive ? DiagramPose.shimFront : DiagramPose.shim),
            const SizedBox(height: 8),
            Instructions([
              positive
                  ? 'Raise the front (the end with the red mark) with a shim '
                      '— at least 0.1 mm under a 1 m edge. The instrument '
                      'should read a positive tilt.'
                  : 'Raise the back (the end opposite the red mark) with a '
                      'shim — at least 0.1 mm under a 1 m edge. The '
                      'instrument should read a negative tilt.',
              'Let it settle, keep it still, then capture (about 8 seconds).',
            ]),
          ],
          actions: [
            OutlinedButton(
              onPressed: s.step == 1 ? n.backToStart : n.redo,
              child: Text(s.step == 1 ? 'Back' : 'Redo'),
            ),
            FilledButton(
              key: const ValueKey('phase-capture'),
              onPressed: n.capture,
              child: Text(positive ? 'Capture positive' : 'Capture negative'),
            ),
          ],
        );

      case PhaseStage.capturing:
        final positive = s.tilt == PhaseTilt.positive;
        return WizardScaffold(
          title: _title,
          canPop: false,
          children: [
            StepHeader(
                step: s.step,
                total: s.steps,
                title: positive ? 'Positive tilt' : 'Negative tilt'),
            const SizedBox(height: 16),
            InstrumentDiagram(
                pose: positive ? DiagramPose.shimFront : DiagramPose.shim),
            const SizedBox(height: 16),
            ProgressPanel(
              key: const ValueKey('phase-progress'),
              value: s.captureProgress,
              title: 'Capturing… hold still',
              subtitle: '${s.samples} batches',
            ),
          ],
          actions: [
            OutlinedButton(
                onPressed: n.backToStart, child: const Text('Cancel')),
          ],
        );

      case PhaseStage.review:
        final canApply = service &&
            [
              for (var i = 0; i < 2; i++)
                SensorMask.has(s.mask, i) && s.estimates[i] != null,
            ].any((a) => a);
        return WizardScaffold(
          title: _title,
          children: [
            StepHeader(step: s.steps + 1, total: s.steps + 1, title: 'Result'),
            const SizedBox(height: 16),
            for (var i = 0; i < 2; i++)
              if (SensorMask.has(s.mask, i))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _EstimateCard(
                    sensor: 'S${i + 1}',
                    estimate: s.estimates[i],
                    storedCdeg: s.current?[i],
                  ),
                ),
            const SizedBox(height: 4),
            if (!service) const ServiceModeCard(),
          ],
          actions: [
            OutlinedButton(
              onPressed: n.redo,
              child: const Text('Redo'),
            ),
            FilledButton(
              key: const ValueKey('phase-apply'),
              onPressed: canApply ? n.apply : null,
              child: const Text('Apply'),
            ),
          ],
        );

      case PhaseStage.applying:
        return WizardScaffold(
          title: _title,
          canPop: false,
          children: const [
            SizedBox(height: 48),
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 16),
            Center(
                child: Text('Writing the phase…',
                    style: TextStyle(color: Colors.white70))),
          ],
        );

      case PhaseStage.done:
        return WizardScaffold(
          title: _title,
          children: [
            const Center(
                child: Icon(Icons.check_circle,
                    size: 56, color: Color(0xFF43A047))),
            const SizedBox(height: 8),
            const Center(
              child: Text('Phase stored',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(height: 16),
            BeforeAfterTable(
              key: const ValueKey('phase-result'),
              title: 'Phase',
              rows: [
                for (var i = 0; i < 2; i++)
                  if (SensorMask.has(s.mask, i))
                    BeforeAfterRow(
                      label: 'S${i + 1}',
                      before: fmtCdeg(s.before![i]),
                      after: fmtCdeg(s.after![i]),
                      delta: fmtCdeg(s.after![i] - s.before![i]),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Next in the usual order: gain (sensitivity k), then the zero '
              '(flip) calibration.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
          actions: [
            OutlinedButton(
                onPressed: n.backToStart, child: const Text('Again')),
            FilledButton(
              key: const ValueKey('phase-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );

      case PhaseStage.error:
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

String fmtCdeg(int cdeg) => '${fmtSigned(cdeg / 100, decimals: 2)}°';

class _ValueSummary extends StatelessWidget {
  const _ValueSummary({required this.label, required this.values});

  final String label;
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
          Text(label,
              style: const TextStyle(
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
                  Text(values == null ? '—' : fmtCdeg(values![i]),
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

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.sensor,
    required this.estimate,
    required this.storedCdeg,
  });

  final String sensor;
  final PhaseEstimate? estimate;
  final int? storedCdeg;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final Color color;
    final String verdict;
    if (e == null) {
      color = const Color(0xFFE53935);
      verdict = 'No usable signal was seen. Use a larger shim and redo.';
    } else if (!e.confident) {
      color = const Color(0xFFFFA000);
      verdict = 'Low confidence — a larger tilt or a quieter table would '
          'give a better value. You can still apply it.';
    } else {
      color = const Color(0xFF43A047);
      verdict = 'Good.';
    }
    return Container(
      key: ValueKey('phase-estimate-$sensor'),
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
                      '${fmtSigned(e.angleDeg, decimals: 2)}°  ± ${e.uncertaintyDeg.toStringAsFixed(2)}°',
                      key: ValueKey('phase-angle-$sensor'),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (e != null)
            Text(
              'Signal-to-noise ${e.snr >= 1e6 ? '∞' : e.snr.toStringAsFixed(0)}'
              '${storedCdeg == null ? '' : '   ·   stored now ${fmtCdeg(storedCdeg!)}'}'
              '${e.singleSided ? '   ·   one tilt only' : ''}',
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
          const SizedBox(height: 6),
          Text(verdict, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}
