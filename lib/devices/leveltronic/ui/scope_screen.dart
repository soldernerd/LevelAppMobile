import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/diagnostics_provider.dart';

/// Trace colours by signal name.
const Map<String, Color> kScopeColors = {
  'A': Color(0xFFFFC107),
  'B': Color(0xFF29B6F6),
  'S1': Color(0xFF66BB6A),
  'S2': Color(0xFFEC407A),
};

/// The ADC's input range, ± this many mV.
const double kScopeFullScaleMv = 1200;

/// The sensor panel when zoomed, ± this many mV.
const double kScopeZoomMv = 200;

/// An oscilloscope-style picture of the four channels.
///
/// The scale is fixed on purpose — the full ±1.2 V of the ADC, with the zero
/// line in the middle — so the traces can be watched while something is
/// adjusted by hand. The only change is the zoom button, which takes the
/// sensor panel to ±200 mV.
///
/// The instrument reports amplitude and phase of each channel, not raw
/// samples, so every trace is rebuilt as `peak · sin(ωt + φ)` with the peak
/// from the peak-to-peak value: it shows amplitudes and phase relations, not
/// the true waveform shape. A and B share the upper panel (same zero), S1 and
/// S2 the lower one.
class ScopeScreen extends ConsumerStatefulWidget {
  const ScopeScreen({super.key});

  @override
  ConsumerState<ScopeScreen> createState() => _ScopeScreenState();
}

class _ScopeScreenState extends ConsumerState<ScopeScreen> {
  bool _zoom = false;

  @override
  Widget build(BuildContext context) {
    final diag = ref.watch(signalDiagProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Oscilloscope', style: TextStyle(fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const ValueKey('scope-zoom'),
              onPressed: () => setState(() => _zoom = !_zoom),
              icon: Icon(_zoom ? Icons.zoom_out : Icons.zoom_in),
              label: Text(_zoom ? 'S1/S2 ±200 mV' : 'Zoom S1/S2'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: diag.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not read the signals.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          data: (d) {
            _Trace trace(String name) {
              final i = ApiSignalDiag.channelNames.indexOf(name);
              return _Trace(
                name: name,
                color: kScopeColors[name]!,
                peakMv: d.p2pMv[i] / 2,
                phaseDeg: d.phaseDeg[i],
              );
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: _Panel(
                      key: const ValueKey('scope-excitation'),
                      traces: [trace('A'), trace('B')],
                      fullScaleMv: kScopeFullScaleMv,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _Panel(
                      key: const ValueKey('scope-sensors'),
                      traces: [trace('S1'), trace('S2')],
                      fullScaleMv: _zoom ? kScopeZoomMv : kScopeFullScaleMv,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Trace {
  const _Trace({
    required this.name,
    required this.color,
    required this.peakMv,
    required this.phaseDeg,
  });

  final String name;
  final Color color;
  final double peakMv;
  final double phaseDeg;
}

/// One screen: a legend with the amplitudes above a fixed-scale plot.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.traces, required this.fullScaleMv});

  final List<_Trace> traces;
  final double fullScaleMv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            children: [
              for (final t in traces)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: t.color),
                    const SizedBox(width: 5),
                    Text(
                      '${t.name}  ${(t.peakMv * 2).toStringAsFixed(t.peakMv < 50 ? 2 : 1)} mV p–p',
                      style: TextStyle(
                        color: t.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              const Text('  ',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text('±${fullScaleMv.toStringAsFixed(0)} mV full scale',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CustomPaint(
                size: Size.infinite,
                painter: _ScopePainter(traces, fullScaleMv),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(this.traces, this.fullScaleMv);

  final List<_Trace> traces;
  final double fullScaleMv;

  /// 1¼ periods.
  static const _spanDeg = 450.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0B140E));

    final grid = Paint()
      ..color = const Color(0xFF1F3A26)
      ..strokeWidth = 1;
    const cols = 10, rows = 8;
    for (var i = 0; i <= cols; i++) {
      final x = size.width * i / cols;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var j = 0; j <= rows; j++) {
      final y = size.height * j / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = const Color(0xFF2F5A3A)
        ..strokeWidth = 1.5,
    );

    // Voltage labels on the horizontal grid lines.
    for (var j = 1; j < rows; j++) {
      final mv = fullScaleMv * (rows / 2 - j) / (rows / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: mv == 0 ? '0' : '${mv > 0 ? '+' : '−'}${mv.abs().toStringAsFixed(0)}',
          style: const TextStyle(color: Color(0xFF4F8A5C), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(3, size.height * j / rows - tp.height - 1));
    }

    final amp = size.height / 2;
    const steps = 300;
    for (final t in traces) {
      final path = Path();
      for (var k = 0; k <= steps; k++) {
        final deg = _spanDeg * k / steps;
        final v = t.peakMv * math.sin((deg + t.phaseDeg) * math.pi / 180);
        final p = Offset(size.width * k / steps, mid - v / fullScaleMv * amp);
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = t.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ScopePainter old) {
    if (old.fullScaleMv != fullScaleMv) return true;
    for (var i = 0; i < traces.length; i++) {
      if (traces[i].peakMv != old.traces[i].peakMv ||
          traces[i].phaseDeg != old.traces[i].phaseDeg) {
        return true;
      }
    }
    return false;
  }
}
