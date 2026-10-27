import 'package:flutter/material.dart';

import 'package:inclinometer/devices/leveltronic/providers/flip_cal_provider.dart' show SensorMask;

/// Choose S1, S2 or both.
class SensorSelector extends StatelessWidget {
  const SensorSelector({super.key, required this.mask, this.onChanged});

  final int mask;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: SensorMask.s1, label: Text('S1')),
        ButtonSegment(value: SensorMask.s2, label: Text('S2')),
        ButtonSegment(value: SensorMask.both, label: Text('Both')),
      ],
      selected: {mask},
      showSelectedIcon: false,
      onSelectionChanged:
          onChanged == null ? null : (s) => onChanged!(s.first),
    );
  }
}

/// "Step 2 of 4 — title" with a thin progress line.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
  });

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP $step OF $total',
          style: const TextStyle(
              fontSize: 12, letterSpacing: 1.2, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: step / total,
          minHeight: 3,
          backgroundColor: Colors.white12,
        ),
      ],
    );
  }
}

/// A big ring with a percentage (or spinning when [value] is null) and a
/// caption — for the "hold still" phases.
class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.warning,
  });

  final double? value;
  final String title;
  final String? subtitle;

  /// Shown in amber under the ring (e.g. "table not quiet").
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                ),
              ),
              if (value != null)
                Text(
                  '${(value! * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white70)),
        ],
        if (warning != null) ...[
          const SizedBox(height: 10),
          Text(warning!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFFFFA000))),
        ],
      ],
    );
  }
}

/// One line of a before / after table.
class BeforeAfterRow {
  const BeforeAfterRow({
    required this.label,
    required this.before,
    required this.after,
    this.delta,
  });

  final String label;
  final String before;
  final String after;
  final String? delta;
}

class BeforeAfterTable extends StatelessWidget {
  const BeforeAfterTable({super.key, required this.rows, this.title});

  final List<BeforeAfterRow> rows;
  final String? title;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, color: Colors.white54);
    const cell = TextStyle(
      fontSize: 15,
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );
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
          if (title != null) ...[
            Text(title!,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
            const SizedBox(height: 8),
          ],
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
              3: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              const TableRow(children: [
                SizedBox.shrink(),
                Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 12),
                    child: Text('Before', style: head)),
                Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 12),
                    child: Text('After', style: head)),
                Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 12),
                    child: Text('Change', style: head)),
              ]),
              for (final r in rows)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(r.label,
                        style: const TextStyle(
                            fontSize: 15, color: Colors.white70)),
                  ),
                  Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(r.before, style: cell)),
                  Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(r.after, style: cell)),
                  Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(r.delta ?? '', style: cell)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

/// An error panel with an optional retry.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Color(0xFFE53935)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.white70)),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ],
    );
  }
}

/// A bulleted instruction list.
class Instructions extends StatelessWidget {
  const Instructions(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}.',
                      style: const TextStyle(color: Colors.white54)),
                ),
                Expanded(
                  child: Text(lines[i],
                      style: const TextStyle(
                          fontSize: 14, color: Colors.white70, height: 1.35)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
