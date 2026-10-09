import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/service_provider.dart';

/// Shows whether service mode is on and, when it is off, how to switch it on
/// — it can only be done at the instrument. Calibration writes and the flip
/// calibration need it. Put it above the start button of a wizard step; the
/// step's own button should be disabled while [serviceModeProvider] is false.
class ServiceModeCard extends ConsumerWidget {
  const ServiceModeCard({super.key, this.showEndButton = false});

  /// Offer "Leave service mode" when it is on.
  final bool showEndButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(serviceModeProvider);
    final color = on ? const Color(0xFF43A047) : const Color(0xFFFFA000);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(on ? Icons.lock_open : Icons.lock_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on ? 'Service mode is on' : 'Service mode is off',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: color, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  on
                      ? 'Calibration values can be written. It ends by itself '
                          '10 minutes after the last request, or when the '
                          'instrument sleeps.'
                      : 'Switch it on at the instrument: SETTINGS > '
                          'Service mode, press the right knob twice. This '
                          'screen continues by itself.',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                if (on && showEndButton)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          ref.read(instrumentApiProvider).serviceEnd(),
                      child: const Text('Leave service mode'),
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
