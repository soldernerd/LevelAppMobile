import 'package:flutter/material.dart';

/// Shows whether the last 0.6 s window of a reading looked disturbed (a bump,
/// footsteps, a machine starting): amber and labelled when it did, a quiet
/// green-grey when it is calm, dim when there is no reading at all.
class VibrationIndicator extends StatelessWidget {
  const VibrationIndicator({
    super.key,
    required this.disturbed,
    this.hasReading = true,
    this.size = 26,
  });

  final bool disturbed;
  final bool hasReading;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String tip;
    if (!hasReading) {
      color = Colors.white24;
      tip = 'No reading';
    } else if (disturbed) {
      color = const Color(0xFFFFA000);
      tip = 'Disturbed — do not trust this value';
    } else {
      color = const Color(0xFF66BB6A);
      tip = 'Calm';
    }
    return Tooltip(
      message: tip,
      child: Semantics(
        label: tip,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vibration, size: size, color: color),
            if (disturbed && hasReading)
              Text('disturbed',
                  style: TextStyle(fontSize: size * 0.4, color: color)),
          ],
        ),
      ),
    );
  }
}
