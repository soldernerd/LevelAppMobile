import 'dart:math';

import 'package:flutter/material.dart';

/// What the diagram shows.
enum DiagramPose {
  /// The instrument on a level plate, mark facing you.
  level,

  /// The same, turned by 180° (the mark now faces away).
  rotated,

  /// The plate raised at one end by a shim of known height.
  shim,
}

/// A schematic of the instrument on a plate, animated between poses. Used by
/// the calibration wizards to show *what to do*: hold still, turn 180°, put a
/// shim under one end.
class InstrumentDiagram extends StatelessWidget {
  const InstrumentDiagram({
    super.key,
    required this.pose,
    this.height = 150,
    this.label,
  });

  final DiagramPose pose;
  final double height;

  /// Short caption drawn under the shim ("0.100 mm").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final rotation = pose == DiagramPose.rotated ? pi : 0.0;
    final plateTilt = pose == DiagramPose.shim ? -0.09 : 0.0;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        key: const ValueKey('instrument-diagram'),
        tween: Tween<double>(begin: rotation, end: rotation),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        builder: (context, rot, _) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: plateTilt, end: plateTilt),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          builder: (context, tilt, _) => CustomPaint(
            painter: _DiagramPainter(
              rotation: rot,
              plateTilt: tilt,
              showShim: pose == DiagramPose.shim,
              shimLabel: label,
              showTurnArrow: pose == DiagramPose.rotated,
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.rotation,
    required this.plateTilt,
    required this.showShim,
    required this.shimLabel,
    required this.showTurnArrow,
  });

  final double rotation;
  final double plateTilt;
  final bool showShim;
  final String? shimLabel;
  final bool showTurnArrow;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final base = size.height * 0.78;
    final plateW = min(size.width * 0.86, 360.0);

    // Table line.
    canvas.drawLine(
      Offset(cx - plateW / 2 - 12, base + 22),
      Offset(cx + plateW / 2 + 12, base + 22),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 2,
    );

    // Shim block under the right end of the plate.
    if (showShim) {
      final shim = Rect.fromLTWH(cx + plateW / 2 - 34, base + 8, 26, 14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shim, const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFB300),
      );
      if (shimLabel != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: shimLabel,
            style: const TextStyle(color: Color(0xFFFFB300), fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(shim.center.dx - tp.width / 2, base + 26));
      }
    }

    // Plate (pivots on its left end when shimmed).
    canvas.save();
    canvas.translate(cx - plateW / 2, base + 8);
    canvas.rotate(plateTilt);
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, -8, plateW, 8),
      const Radius.circular(2),
    );
    canvas.drawRRect(plate, Paint()..color = const Color(0xFF546E7A));

    // The instrument on the plate, turned by [rotation].
    canvas.translate(plateW / 2, -8);
    canvas.rotate(0); // keep the plate frame
    final bodyW = plateW * 0.62;
    const bodyH = 34.0;
    canvas.save();
    // Turning in the drawing plane: mirror horizontally (a 180° turn seen
    // from the side swaps left and right).
    final flip = cos(rotation);
    canvas.scale(flip, 1);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(-bodyW / 2, -bodyH, bodyW, bodyH),
      const Radius.circular(6),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF263238));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF90CAF9),
    );
    // Sensor heads.
    for (final dx in [-bodyW * 0.3, bodyW * 0.3]) {
      canvas.drawCircle(
        Offset(dx, -bodyH / 2),
        7,
        Paint()..color = const Color(0xFF64B5F6),
      );
    }
    // The front mark: a triangle on the left end.
    final mark = Path()
      ..moveTo(-bodyW / 2 - 10, -bodyH / 2)
      ..lineTo(-bodyW / 2, -bodyH / 2 - 8)
      ..lineTo(-bodyW / 2, -bodyH / 2 + 8)
      ..close();
    canvas.drawPath(mark, Paint()..color = const Color(0xFFEF5350));
    canvas.restore();
    canvas.restore();

    // The "turn 180°" arrow above.
    if (showTurnArrow) {
      final r = size.height * 0.22;
      final c = Offset(cx, size.height * 0.28);
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF90CAF9);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi * 1.05,
          pi * 0.9, false, arcPaint);
      final tip = Offset(c.dx + r * cos(pi * 1.95), c.dy + r * sin(pi * 1.95));
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 10, tip.dy - 4)
        ..lineTo(tip.dx - 3, tip.dy + 9)
        ..close();
      canvas.drawPath(head, Paint()..color = const Color(0xFF90CAF9));
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.rotation != rotation ||
      old.plateTilt != plateTilt ||
      old.showShim != showShim ||
      old.shimLabel != shimLabel ||
      old.showTurnArrow != showTurnArrow;
}
