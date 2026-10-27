// ignore_for_file: sort_child_properties_last
// (WizardScaffold takes `children` before `actions` on purpose: the steps
// read top to bottom, the buttons last.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/providers/flip_cal_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/service_provider.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/format.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/instrument_diagram.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/service_card.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_scaffold.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/wizard_widgets.dart';

/// Zero (flip) calibration: measure, turn the instrument 180°, measure again;
/// the instrument stores the new level point itself. Leads through the steps
/// and shows the stored zero before and after.
class FlipCalScreen extends ConsumerWidget {
  const FlipCalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serviceKeepAliveProvider);
    final s = ref.watch(flipCalProvider);
    final n = ref.read(flipCalProvider.notifier);
    final service = ref.watch(serviceModeProvider);

    switch (s.stage) {
      case FlipStage.select:
        return WizardScaffold(
          title: 'Zero (flip) calibration',
          children: [
            const Text(
              'A real tilt reverses its sign when the instrument is turned '
              '180°; the instrument\'s own zero error does not. Measuring '
              'both ways and averaging gives the zero error, which is then '
              'stored.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.level),
            const SizedBox(height: 8),
            const Instructions([
              'Put the instrument on a stable surface with the mark facing you.',
              'Keep the table undisturbed during both steps.',
            ]),
            const SizedBox(height: 16),
            const Text('Calibrate', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            SensorSelector(mask: s.mask, onChanged: n.selectSensors),
            const SizedBox(height: 16),
            _ZeroTable(snapshot: s.current, mask: s.mask),
            const SizedBox(height: 16),
            const ServiceModeCard(),
          ],
          actions: [
            FilledButton(
              key: const ValueKey('flip-start'),
              onPressed: service ? n.start : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Start step 1'),
            ),
          ],
        );

      case FlipStage.measuring1:
        return WizardScaffold(
          title: 'Zero (flip) calibration',
          canPop: false,
          children: [
            const StepHeader(
                step: 1, total: 3, title: 'Measure in the starting position'),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.level),
            const SizedBox(height: 16),
            ProgressPanel(
              key: const ValueKey('flip-progress'),
              value: s.target == 0 ? null : s.progress / s.target,
              title: 'Hold still…',
              subtitle: '${s.progress} / ${s.target} batches',
            ),
          ],
          actions: [
            OutlinedButton(onPressed: n.cancel, child: const Text('Cancel')),
          ],
        );

      case FlipStage.turn:
        return WizardScaffold(
          title: 'Zero (flip) calibration',
          canPop: false,
          children: [
            const StepHeader(
                step: 2, total: 3, title: 'Turn the instrument 180°'),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.rotated),
            const SizedBox(height: 8),
            const Instructions([
              'Turn the instrument 180° in place — same spot, same surface. '
                  'The mark now faces away from you.',
              'Let it settle for a moment, then continue.',
            ]),
            const SizedBox(height: 12),
            if (!service) const ServiceModeCard(),
          ],
          actions: [
            OutlinedButton(onPressed: n.cancel, child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('flip-continue'),
              onPressed: service ? n.confirmTurned : null,
              child: const Text('Turned — measure'),
            ),
          ],
        );

      case FlipStage.measuring2:
        return WizardScaffold(
          title: 'Zero (flip) calibration',
          canPop: false,
          children: [
            const StepHeader(
                step: 3, total: 3, title: 'Measure in the turned position'),
            const SizedBox(height: 16),
            const InstrumentDiagram(pose: DiagramPose.rotated),
            const SizedBox(height: 16),
            ProgressPanel(
              key: const ValueKey('flip-progress'),
              value: s.target == 0 ? null : s.progress / s.target,
              title: 'Hold still…',
              subtitle: '${s.progress} / ${s.target} batches',
            ),
          ],
          actions: [
            OutlinedButton(onPressed: n.cancel, child: const Text('Cancel')),
          ],
        );

      case FlipStage.result:
        final run = s.lastRun!;
        final prev = s.runs.length >= 2 ? s.runs[s.runs.length - 2] : null;
        return WizardScaffold(
          title: 'Zero (flip) calibration',
          children: [
            const Center(
                child: Icon(Icons.check_circle,
                    size: 56, color: Color(0xFF43A047))),
            const SizedBox(height: 8),
            const Center(
              child: Text('New zero stored',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(height: 16),
            BeforeAfterTable(
              key: const ValueKey('flip-result'),
              title: 'Level point in mm/m (zero ÷ k)',
              rows: [
                for (var i = 0; i < 2; i++)
                  if (SensorMask.has(run.mask, i))
                    BeforeAfterRow(
                      label: 'S${i + 1}',
                      before: fmtSigned(run.before.zeroMmPerM(i), decimals: 4),
                      after: fmtSigned(run.after.zeroMmPerM(i), decimals: 4),
                      delta: fmtSigned(
                          run.after.zeroMmPerM(i) - run.before.zeroMmPerM(i),
                          decimals: 4),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            BeforeAfterTable(
              title: 'Stored zero (ppm of the ratio)',
              rows: [
                for (var i = 0; i < 2; i++)
                  if (SensorMask.has(run.mask, i))
                    BeforeAfterRow(
                      label: 'S${i + 1}',
                      before: fmtSigned(run.before.zeroPpm[i].toDouble(), decimals: 0),
                      after: fmtSigned(run.after.zeroPpm[i].toDouble(), decimals: 0),
                      delta: fmtSigned(
                          (run.after.zeroPpm[i] - run.before.zeroPpm[i]).toDouble(),
                          decimals: 0),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              prev == null
                  ? 'Run it once more: the second run should change the zero '
                      'hardly at all. If it does, the table moved.'
                  : 'This was run ${s.runs.length}. A good calibration '
                      'changes the zero only slightly from run to run.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
          actions: [
            OutlinedButton(
              key: const ValueKey('flip-again'),
              onPressed: n.backToStart,
              child: const Text('Run again'),
            ),
            FilledButton(
              key: const ValueKey('flip-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );

      case FlipStage.error:
        return WizardScaffold(
          title: 'Zero (flip) calibration',
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

class _ZeroTable extends StatelessWidget {
  const _ZeroTable({required this.snapshot, required this.mask});

  final ZeroSnapshot? snapshot;
  final int mask;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
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
          const Text('Stored level point now',
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
                      style: TextStyle(
                          color: SensorMask.has(mask, i)
                              ? Colors.white
                              : Colors.white38)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      snap == null
                          ? '—'
                          : '${fmtZero(snap.zeroPpm[i], snap.kMicro[i])}   '
                              '(${snap.zeroPpm[i]} ppm)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: SensorMask.has(mask, i)
                            ? Colors.white
                            : Colors.white38,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
