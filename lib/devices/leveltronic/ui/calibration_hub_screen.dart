import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inclinometer/devices/leveltronic/ui/widgets/service_card.dart';

/// The entry to the three calibration wizards, in the order they should be
/// run: phase, gain (sensitivity), then zero (flip).
class CalibrationHubScreen extends ConsumerWidget {
  const CalibrationHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Calibration', style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ServiceModeCard(showEndButton: true),
            const SizedBox(height: 16),
            const Text(
              'Run them in this order — each step assumes the one before it. '
              'Writing calibration values needs service mode, which can only '
              'be switched on at the instrument.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            _Tile(
              key: const ValueKey('cal-phase'),
              step: '1',
              icon: Icons.waves,
              title: 'Phase',
              body: 'Finds the phase of each sensor\'s signal from a tilt '
                  'step. S1, S2 or both.',
              onTap: () => context.push('/leveltronic/calibration/phase'),
            ),
            _Tile(
              key: const ValueKey('cal-gain'),
              step: '2',
              icon: Icons.straighten,
              title: 'Gain (sensitivity)',
              body: 'Sets k from a shim of known height under an edge of '
                  'known length. S1, S2 or both.',
              onTap: () => context.push('/leveltronic/calibration/gain'),
            ),
            _Tile(
              key: const ValueKey('cal-flip'),
              step: '3',
              icon: Icons.screen_rotation_alt,
              title: 'Zero (flip)',
              body: 'The 180° reversal test: measure, turn the instrument, '
                  'measure again. S1, S2 or both.',
              onTap: () => context.push('/leveltronic/calibration/flip'),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            ListTile(
              key: const ValueKey('cal-values'),
              leading: const Icon(Icons.tune, color: Colors.white70),
              title: const Text('All calibration values'),
              subtitle: const Text('Read, or edit in service mode'),
              onTap: () => context.push('/leveltronic/settings?tab=2'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.step,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String step;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF263238),
          child: Text(step, style: const TextStyle(color: Colors.white)),
        ),
        title: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(body, style: const TextStyle(color: Colors.white60)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
