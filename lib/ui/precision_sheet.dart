import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/precision_provider.dart';
import 'package:inclinometer/providers/tare_provider.dart';
import 'package:inclinometer/ui/widgets/format.dart';
import 'package:inclinometer/ui/widgets/wizard_widgets.dart';

/// Opens the precision-measurement sheet and starts a measurement at once.
/// Closing the sheet cancels a measurement still running.
Future<void> showPrecisionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF1E1E1E),
    builder: (_) => const PrecisionSheet(),
  );
}

class PrecisionSheet extends ConsumerStatefulWidget {
  const PrecisionSheet({super.key});

  @override
  ConsumerState<PrecisionSheet> createState() => _PrecisionSheetState();
}

class _PrecisionSheetState extends ConsumerState<PrecisionSheet> {
  @override
  void initState() {
    super.initState();
    Future(() => ref.read(precisionProvider.notifier).start());
  }

  Future<void> _close() async {
    final notifier = ref.read(precisionProvider.notifier);
    if (ref.read(precisionProvider).stage == PrecisionStage.running) {
      await notifier.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(precisionProvider);
    final tare = ref.watch(tareProvider);
    final notifier = ref.read(precisionProvider.notifier);

    Widget body;
    switch (s.stage) {
      case PrecisionStage.idle:
      case PrecisionStage.running:
        body = ProgressPanel(
          key: const ValueKey('precision-running'),
          value: s.stage == PrecisionStage.idle ? null : s.progress,
          title: 'Hold still…',
          subtitle: s.stage == PrecisionStage.idle
              ? 'Starting'
              : 'Looking for a quiet 2 s window  ·  '
                  '${s.count}/${s.target}  ·  '
                  '${(s.elapsedMs / 1000).toStringAsFixed(1)} s',
          warning: s.disturbed
              ? 'The table is not quiet yet — wait for it to calm down.'
              : null,
        );
      case PrecisionStage.done:
        final diff = s.tiltDiff - (tare ?? 0);
        body = Column(
          key: const ValueKey('precision-done'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 40, color: Color(0xFF43A047)),
            const SizedBox(height: 8),
            _Result(label: 'S1', value: s.tiltS1),
            _Result(label: 'S2', value: s.tiltS2),
            _Result(
              label: 'DIFF',
              value: diff,
              emphasis: true,
              note: tare != null ? 'zeroed' : null,
            ),
          ],
        );
      case PrecisionStage.failed:
        body = ErrorPanel(
          key: const ValueKey('precision-failed'),
          message: s.message ?? 'No result.',
          onRetry: notifier.start,
        );
      case PrecisionStage.error:
        body = ErrorPanel(
          key: const ValueKey('precision-error'),
          message: s.message ?? 'Something went wrong.',
          onRetry: notifier.start,
        );
    }

    final running =
        s.stage == PrecisionStage.running || s.stage == PrecisionStage.idle;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Precision measurement',
                style: TextStyle(
                    fontSize: 14, color: Colors.white54, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            body,
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('precision-close'),
                    onPressed: _close,
                    child: Text(running ? 'Cancel' : 'Close'),
                  ),
                ),
                if (s.stage == PrecisionStage.done) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('precision-again'),
                      onPressed: notifier.start,
                      child: const Text('Measure again'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.note,
  });

  final String label;
  final double value;
  final bool emphasis;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontSize: emphasis ? 20 : 17, color: Colors.white54)),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${fmtTilt(value)} mm/m',
                key: ValueKey('precision-$label'),
                style: TextStyle(
                  fontSize: emphasis ? 44 : 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(note!,
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ),
        ],
      ),
    );
  }
}
