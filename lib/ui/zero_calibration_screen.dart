import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/measurement_provider.dart';

/// Guides the user through the classic 180°-reversal zero calibration:
/// measure, rotate the instrument 180°, measure again. The device computes
/// and persists the new zero offset itself — this screen only drives the
/// two EXECUTE steps and shows progress polled from the instrument.
class ZeroCalibrationScreen extends ConsumerWidget {
  const ZeroCalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(zeroCalibrationProvider);
    final notifier = ref.read(zeroCalibrationProvider.notifier);
    final canPop = switch (state.phase) {
      ZeroCalUiPhase.idle ||
      ZeroCalUiPhase.success ||
      ZeroCalUiPhase.error =>
        true,
      ZeroCalUiPhase.runningStep1 ||
      ZeroCalUiPhase.awaitingRotation ||
      ZeroCalUiPhase.runningStep2 =>
        false,
    };

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancel the calibration before leaving this screen.'),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Zero Calibration'),
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
    ZeroCalUiState state,
    ZeroCalibrationNotifier notifier,
  ) {
    switch (state.phase) {
      case ZeroCalUiPhase.idle:
        return _Explainer(
          icon: Icons.restart_alt,
          title: 'Zero calibration',
          body: 'The classic 180° reversal test. Place the instrument in '
              'its starting orientation and hold it steady, then start. '
              'You will be asked to rotate it 180° partway through.',
          actions: [
            FilledButton(
              onPressed: notifier.start,
              child: const Text('Start'),
            ),
          ],
        );

      case ZeroCalUiPhase.runningStep1:
        return _Progress(
          title: 'Step 1 of 2',
          subtitle: 'Hold the instrument steady in its starting position…',
          progress: state.progress,
          target: state.target,
          onCancel: notifier.cancel,
        );

      case ZeroCalUiPhase.awaitingRotation:
        return _Explainer(
          icon: Icons.screen_rotation_alt,
          title: 'Rotate 180°',
          body: 'Step 1 complete. Rotate the instrument 180° to its '
              'reversed position, then continue.',
          actions: [
            OutlinedButton(
              onPressed: notifier.cancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: notifier.confirmRotated,
              child: const Text('Continue'),
            ),
          ],
        );

      case ZeroCalUiPhase.runningStep2:
        return _Progress(
          title: 'Step 2 of 2',
          subtitle: 'Hold the instrument steady in the rotated position…',
          progress: state.progress,
          target: state.target,
          onCancel: notifier.cancel,
        );

      case ZeroCalUiPhase.success:
        return _Explainer(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF43A047),
          title: 'Calibration complete',
          body: 'The new zero offset has been saved to this instrument.',
          actions: [
            FilledButton(
              onPressed: () {
                notifier.reset();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );

      case ZeroCalUiPhase.error:
        return _Explainer(
          icon: Icons.error_outline,
          iconColor: const Color(0xFFD32F2F),
          title: 'Calibration failed',
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
            FilledButton(
              onPressed: notifier.start,
              child: const Text('Try Again'),
            ),
          ],
        );
    }
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

class _Progress extends StatelessWidget {
  const _Progress({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.target,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final int progress;
  final int target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final fraction = target == 0 ? 0.0 : (progress / target).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 12),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.white70)),
        const SizedBox(height: 28),
        SizedBox(
          width: 220,
          child: LinearProgressIndicator(value: fraction, minHeight: 8),
        ),
        const SizedBox(height: 8),
        Text('$progress / $target',
            style: const TextStyle(fontSize: 13, color: Colors.white54)),
        const SizedBox(height: 28),
        OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
