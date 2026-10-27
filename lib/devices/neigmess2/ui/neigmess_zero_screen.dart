import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/neigmess2/protocol.dart';
import 'package:inclinometer/devices/neigmess2/providers/neigmess_provider.dart';
import 'package:inclinometer/devices/neigmess2/ui/actions.dart';

/// The flip-test zero, driven from the app (the keys on the instrument do the
/// same): measure in position 1, turn the instrument 180°, measure again; the
/// instrument stores the offset itself. Follows the routine state it pushes,
/// so it also shows a routine started with the keys.
class NeigMessZeroScreen extends ConsumerWidget {
  const NeigMessZeroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(neigmessSessionProvider);
    final data = ref.watch(neigmessDataProvider).value;
    final r = data?.zeroRoutine ?? const NmZeroRoutine();
    final live = session != null && data != null;

    void next() =>
        runAction(ScaffoldMessenger.of(context), session!.zeroRoutineNext);
    void quit() =>
        runAction(ScaffoldMessenger.of(context), session!.zeroRoutineQuit);

    final (String title, String text, String? action) = switch (r.state) {
      NmZeroState.idle => (
        'Flip zero',
        'A real tilt reverses its sign when the instrument is turned 180°; '
            'its own zero error does not. Measuring both ways and averaging '
            'gives the zero error, which is then stored.\n\n'
            'Put the instrument on a stable surface and keep it undisturbed '
            'during both measurements (about 5 s each).',
        'Start',
      ),
      NmZeroState.readyPos1 => (
        'Position 1',
        'Place the instrument in position 1, hold it still, then measure.',
        'Measure position 1',
      ),
      NmZeroState.measuring1 => (
        'Measuring position 1',
        'Hold the instrument still.',
        null,
      ),
      NmZeroState.readyPos2 => (
        'Position 2',
        'Rotate the instrument 180°, hold it still, then measure.',
        'Measure position 2',
      ),
      NmZeroState.measuring2 => (
        'Measuring position 2',
        'Hold the instrument still.',
        null,
      ),
      NmZeroState.done => (
        'Zero stored',
        'The new zero offset is stored in the instrument.',
        'Done',
      ),
      NmZeroState.failed => (
        'Zero failed',
        'The resulting offset is out of range, so nothing was stored. Check '
            'that the instrument sits on a stable, flat surface and that the '
            'mark faced the same way both times.',
        null,
      ),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Flip zero', style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!live)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Connection lost — values are not live.',
                  style: TextStyle(color: Color(0xFFD32F2F)),
                ),
              ),
            Text(
              title,
              key: const ValueKey('zero-title'),
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            if (r.state.isMeasuring) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                key: const ValueKey('zero-progress'),
                value: r.progress / 100,
              ),
              if (r.unsteady)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The instrument moved — measuring again.',
                    key: ValueKey('zero-unsteady'),
                    style: TextStyle(color: Color(0xFFFFA000)),
                  ),
                ),
            ],
            if (r.pos1Valid || r.pos2Valid) ...[
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFF1E1E1E),
                child: Column(
                  children: [
                    if (r.pos1Valid)
                      _Row('Position 1', '${r.pos1.toStringAsFixed(1)} µm/m'),
                    if (r.pos2Valid)
                      _Row('Position 2', '${r.pos2.toStringAsFixed(1)} µm/m'),
                    if (r.state == NmZeroState.done)
                      _Row(
                        'Zero offset',
                        '${r.offsetUmPerM.toStringAsFixed(1)} µm/m',
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (action != null)
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('zero-next'),
                      onPressed: live ? next : null,
                      child: Text(action),
                    ),
                  ),
                if (r.state.isActive && r.state != NmZeroState.done) ...[
                  if (action != null) const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('zero-quit'),
                      onPressed: live ? quit : null,
                      child: Text(
                        r.state == NmZeroState.failed ? 'Close' : 'Cancel',
                      ),
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label, style: const TextStyle(color: Colors.white70)),
    trailing: Text(value),
  );
}
