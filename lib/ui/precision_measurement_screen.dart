import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/measurement_provider.dart';

/// Triggers a single precise measurement: the instrument averages up to 64
/// quality-good batches per sensor (typically ~3.2 s) and reports one
/// reliable value per sensor, as opposed to watching the continuous live
/// readout on the instrument screen.
class PrecisionMeasurementScreen extends ConsumerWidget {
  const PrecisionMeasurementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(precisionMeasurementProvider);
    final notifier = ref.read(precisionMeasurementProvider.notifier);
    final canPop = state.phase != PrecisionUiPhase.running;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancel the measurement before leaving this screen.'),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Precision Measurement'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: _body(context, state, notifier)),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PrecisionUiState state,
    PrecisionMeasurementNotifier notifier,
  ) {
    switch (state.phase) {
      case PrecisionUiPhase.idle:
        return _Explainer(
          icon: Icons.center_focus_strong,
          title: 'Precision measurement',
          body: 'Hold the instrument steady, then trigger a measurement. '
              'The instrument takes the time it needs (typically ~3 s) and '
              'reports one precise, repeatable reading.',
          actions: [
            FilledButton(onPressed: notifier.start, child: const Text('Measure')),
          ],
        );

      case PrecisionUiPhase.running:
        final fraction = state.progress.clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Measuring…',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            const Text('Hold the instrument steady.',
                style: TextStyle(fontSize: 15, color: Colors.white70)),
            const SizedBox(height: 28),
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(value: fraction, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text(
              'S1 ${state.count1}/${state.target}  ·  '
              'S2 ${state.count2}/${state.target}  ·  '
              '${(state.elapsedMs / 1000).toStringAsFixed(1)} s',
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 28),
            OutlinedButton(onPressed: notifier.cancel, child: const Text('Cancel')),
          ],
        );

      case PrecisionUiPhase.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 48, color: Color(0xFF43A047)),
            const SizedBox(height: 20),
            const Text('Measurement complete',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 20),
            _ResultRow(label: 'S1', valueMm: state.delta1Mm),
            const SizedBox(height: 8),
            _ResultRow(label: 'S2', valueMm: state.delta2Mm),
            if (state.timedOut) ...[
              const SizedBox(height: 16),
              Text(
                'Reached the 4 s time limit — averaged '
                '${state.count1}/${state.target} (S1), '
                '${state.count2}/${state.target} (S2) samples.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFFFFA000)),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () {
                    notifier.reset();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: notifier.start,
                  child: const Text('Measure Again'),
                ),
              ],
            ),
          ],
        );

      case PrecisionUiPhase.error:
        return _Explainer(
          icon: Icons.error_outline,
          iconColor: const Color(0xFFD32F2F),
          title: 'Measurement failed',
          body: state.errorMessage ?? 'Something went wrong.',
          actions: [
            OutlinedButton(
              onPressed: () {
                notifier.reset();
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: notifier.start, child: const Text('Try Again')),
          ],
        );
    }
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.valueMm});

  final String label;
  final double valueMm;

  @override
  Widget build(BuildContext context) {
    final sign = valueMm >= 0 ? '+' : '−';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          child: Text(label,
              style: const TextStyle(fontSize: 18, color: Colors.white54)),
        ),
        const SizedBox(width: 12),
        Text(
          '$sign${valueMm.abs().toStringAsFixed(4)} mm',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.iconColor = Colors.white70,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 20),
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 28),
        Row(mainAxisSize: MainAxisSize.min, children: actions),
      ],
    );
  }
}
