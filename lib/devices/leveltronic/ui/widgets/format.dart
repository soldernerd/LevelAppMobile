/// Display formatting shared by the screens. Signs use a real minus (U+2212).
library;

String _sign(double v) => v < 0 ? '−' : '+';

/// Tilt in mm/m with four decimals and an explicit sign: `+0.1234`.
String fmtTilt(double? v, {int decimals = 4}) =>
    v == null || !v.isFinite
        ? '––.––––'
        : '${_sign(v)}${v.abs().toStringAsFixed(decimals)}';

/// A signed number with [decimals] decimals and optional unit.
String fmtSigned(double? v, {int decimals = 2, String unit = ''}) {
  if (v == null || !v.isFinite) return '—';
  final s = '${_sign(v)}${v.abs().toStringAsFixed(decimals)}';
  return unit.isEmpty ? s : '$s $unit';
}

String fmtTempC(double? c) => fmtSigned(c, decimals: 2, unit: '°C');

String fmtVolts(int? mv) =>
    mv == null || mv == 0 ? '—' : '${(mv / 1000).toStringAsFixed(3)} V';

String fmtPercent(num? v, {int decimals = 0}) =>
    v == null ? '—' : '${v.toStringAsFixed(decimals)} %';

/// Seconds as `1 d 03:04:05` / `03:04:05`.
String fmtUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  final hms = '${two(h)}:${two(m)}:${two(s)}';
  return d > 0 ? '$d d $hms' : hms;
}

String two(int v) => v.toString().padLeft(2, '0');

String fmtDateTime(DateTime t) =>
    '${t.year}-${two(t.month)}-${two(t.day)}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

/// The level point of a sensor: `zero_ppm / k_micro` mm/m.
String fmtZero(int zeroPpm, int kMicro) =>
    '${fmtSigned(zeroPpm / kMicro, decimals: 4)} mm/m';
