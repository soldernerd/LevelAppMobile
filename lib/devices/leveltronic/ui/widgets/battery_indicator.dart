import 'package:flutter/material.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';

/// A small drawn battery: the fill level is the state of charge, its colour
/// the urgency (green / amber / red), and while charging an up-arrow sits on
/// the cell. [percent] null draws an empty outline (no data yet).
class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({
    super.key,
    required this.percent,
    this.charging = false,
    this.state = BatteryState.normal,
    this.showLabel = true,
    this.size = 22,
  });

  final int? percent;
  final bool charging;
  final BatteryState state;
  final bool showLabel;

  /// Height of the battery glyph.
  final double size;

  /// The fill colour for a charge level.
  static Color colorFor(int? percent, BatteryState state) {
    if (state == BatteryState.critical) return const Color(0xFFE53935);
    if (state == BatteryState.low) return const Color(0xFFFFA000);
    if (percent == null) return Colors.white38;
    if (percent <= 15) return const Color(0xFFE53935);
    if (percent <= 35) return const Color(0xFFFFA000);
    return const Color(0xFF43A047);
  }

  @override
  Widget build(BuildContext context) {
    final fill = colorFor(percent, state);
    final label = percent == null ? '—' : '$percent%';
    return Semantics(
      label: charging
          ? 'Battery $label, charging'
          : 'Battery $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(size * 1.9, size),
            painter: _BatteryPainter(
              fraction: ((percent ?? 0) / 100).clamp(0.0, 1.0),
              fill: fill,
              charging: charging,
              hasData: percent != null,
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: size * 0.62,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({
    required this.fraction,
    required this.fill,
    required this.charging,
    required this.hasData,
  });

  final double fraction;
  final Color fill;
  final bool charging;
  final bool hasData;

  @override
  void paint(Canvas canvas, Size size) {
    final capW = size.width * 0.07;
    final body = Rect.fromLTWH(0, 0, size.width - capW - 1, size.height);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.1
      ..color = Colors.white70;

    final bodyR = RRect.fromRectAndRadius(body, Radius.circular(size.height * 0.22));
    canvas.drawRRect(bodyR, outline);

    // Terminal cap.
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        body.right + 1,
        size.height * 0.3,
        capW,
        size.height * 0.4,
      ),
      Radius.circular(size.height * 0.1),
    );
    canvas.drawRRect(cap, Paint()..color = Colors.white70);

    // Fill, inset from the outline.
    if (hasData && fraction > 0) {
      final inset = size.height * 0.16;
      final inner = body.deflate(inset);
      final w = inner.width * fraction;
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(inner.left, inner.top, w.clamp(size.height * 0.1, inner.width), inner.height),
        Radius.circular(size.height * 0.1),
      );
      canvas.drawRRect(fillRect, Paint()..color = fill);
    }

    // Charging: an up-arrow over the cell, outlined so it reads on any fill.
    if (charging) {
      final cx = body.center.dx;
      final cy = body.center.dy;
      final h = size.height * 0.62;
      final w = size.height * 0.46;
      final arrow = Path()
        ..moveTo(cx, cy - h / 2)
        ..lineTo(cx + w / 2, cy - h / 2 + h * 0.45)
        ..lineTo(cx + w * 0.17, cy - h / 2 + h * 0.45)
        ..lineTo(cx + w * 0.17, cy + h / 2)
        ..lineTo(cx - w * 0.17, cy + h / 2)
        ..lineTo(cx - w * 0.17, cy - h / 2 + h * 0.45)
        ..lineTo(cx - w / 2, cy - h / 2 + h * 0.45)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.12
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF121212),
      );
      canvas.drawPath(arrow, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.charging != charging ||
      old.hasData != hasData;
}
