import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/neigmess2/protocol.dart';
import 'package:inclinometer/devices/neigmess2/providers/neigmess_provider.dart';
import 'package:inclinometer/devices/neigmess2/ui/actions.dart';

/// Everything the knobs and keys of the instrument do apart from the live
/// readings: the fine trim, the neutral capacitance, zeroing the sensors, and
/// storing / recalling the calibration.
///
/// The trim and a typed neutral capacitance are stored by the instrument as
/// soon as they are set; a captured neutral and nothing else stays in RAM until
/// it is stored.
class NeigMessCalibrationScreen extends ConsumerStatefulWidget {
  const NeigMessCalibrationScreen({super.key});

  @override
  ConsumerState<NeigMessCalibrationScreen> createState() =>
      _NeigMessCalibrationScreenState();
}

class _NeigMessCalibrationScreenState
    extends ConsumerState<NeigMessCalibrationScreen> {
  final _mul = TextEditingController();
  final _ofs = TextEditingController();
  final _neutral = TextEditingController();
  NmTiltTrim? _shownTrim;
  double? _shownNeutral;
  bool _unsaved = false;

  @override
  void dispose() {
    _mul.dispose();
    _ofs.dispose();
    _neutral.dispose();
    super.dispose();
  }

  /// Fills the fields from the device the first time and whenever the device
  /// value changes (after Apply, Recall, or a flip zero).
  void _sync(NmTiltTrim? trim, double? neutral) {
    if (trim != null && !identical(trim, _shownTrim)) {
      _shownTrim = trim;
      _mul.text = (trim.multiplierX1000 / 1000).toStringAsFixed(3);
      _ofs.text = (trim.offsetTenthUmPerM / 10).toStringAsFixed(1);
    }
    if (neutral != null && neutral != _shownNeutral) {
      _shownNeutral = neutral;
      _neutral.text = neutral.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(neigmessSessionProvider);
    final d = ref.watch(neigmessDataProvider).value;
    final live = session != null && d != null;
    _sync(d?.trim, d?.neutralCapPf);

    final messenger = ScaffoldMessenger.of(context);

    Future<void> applyTrim() async {
      final m = double.tryParse(_mul.text.replaceAll(',', '.'));
      final o = double.tryParse(_ofs.text.replaceAll(',', '.'));
      final mi = m == null ? null : (m * 1000).round();
      final oi = o == null ? null : (o * 10).round();
      if (mi == null ||
          oi == null ||
          mi < 1 ||
          mi > 65535 ||
          oi < -32768 ||
          oi > 32767) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Multiplier 0.001…65.535, offset -3276.8…3276.7.'),
          ),
        );
        return;
      }
      if (await runAction(
        messenger,
        () => session!.setTiltTrim(
          NmTiltTrim(multiplierX1000: mi, offsetTenthUmPerM: oi),
        ),
      )) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Trim set and stored.')),
        );
      }
    }

    Future<void> setNeutral() async {
      final v = double.tryParse(_neutral.text.replaceAll(',', '.'));
      if (v == null || v < 5 || v > 100) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Neutral capacitance 5…100 pF.')),
        );
        return;
      }
      if (await runAction(messenger, () => session!.setNeutralCapPf(v))) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Neutral set and stored.')),
        );
      }
    }

    Future<void> capture() async {
      if (await runAction(messenger, session!.captureNeutral)) {
        setState(() => _unsaved = true);
      }
    }

    Future<void> store() async {
      if (await confirmAction(
        context,
        'Store the calibration?',
        'Writes the calibration to the EEPROM.',
      )) {
        if (await runAction(messenger, session!.storeCalibration)) {
          setState(() => _unsaved = false);
          messenger.showSnackBar(
            const SnackBar(content: Text('Calibration stored.')),
          );
        }
      }
    }

    Future<void> recall() async {
      if (await confirmAction(
        context,
        'Recall the calibration?',
        'Unsaved changes are discarded and the stored calibration is '
            'loaded.',
      )) {
        if (await runAction(messenger, session!.recallCalibration)) {
          setState(() => _unsaved = false);
        }
      }
    }

    Future<void> zero() async {
      if (await confirmAction(
        context,
        'Zero the sensors?',
        'Open the air gap wide first. The present readings become the zero '
            'position and are stored in the EEPROM.',
      )) {
        await runAction(messenger, session!.zeroSensors);
      }
    }

    Future<void> clear() async {
      if (await confirmAction(
        context,
        'Clear the zero?',
        'All offsets go back to 0 and are stored in the EEPROM.',
      )) {
        await runAction(messenger, session!.clearZero);
      }
    }

    final tiltOk = d?.tiltStatus == NmTiltStatus.ok;
    final field = InputDecoration(
      border: const OutlineInputBorder(),
      isDense: true,
      enabled: live,
    );
    const number = TextInputType.numberWithOptions(decimal: true, signed: true);

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
            if (!live)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Connection lost — values are not live.',
                  style: TextStyle(color: Color(0xFFD32F2F)),
                ),
              ),
            _Section(
              title: 'Tilt fine trim',
              help:
                  'Result = multiplier × (theory + offset). The same two '
                  'values as the knobs on the instrument. Stored at once.',
              children: [
                TextField(
                  key: const ValueKey('trim-mul'),
                  controller: _mul,
                  keyboardType: number,
                  decoration: field.copyWith(labelText: 'Multiplier'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('trim-ofs'),
                  controller: _ofs,
                  keyboardType: number,
                  decoration: field.copyWith(labelText: 'Offset (µm/m)'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('trim-apply'),
                      onPressed: live ? applyTrim : null,
                      child: const Text('Apply'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('trim-reset'),
                      onPressed: live
                          ? () {
                              _mul.text = '1.000';
                              _ofs.text = '0.0';
                            }
                          : null,
                      child: const Text('Nominal'),
                    ),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'Neutral capacitance',
              help:
                  'The plate capacitance at the aligned neutral position '
                  '(nominal 16.38 pF). Capturing takes the present value and '
                  'only works while the alignment is OK.',
              children: [
                Text(
                  'Now: ${d?.plateCapPf?.toStringAsFixed(2) ?? '—'} pF'
                  '   Alignment: ${_statusText(d?.tiltStatus)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('neutral-field'),
                        controller: _neutral,
                        keyboardType: number,
                        decoration: field.copyWith(labelText: 'Cn (pF)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      key: const ValueKey('neutral-set'),
                      onPressed: live ? setNeutral : null,
                      child: const Text('Set'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('neutral-capture'),
                  onPressed: live && tiltOk ? capture : null,
                  child: const Text('Capture neutral'),
                ),
                if (_unsaved)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Captured but not stored yet — press Store.',
                      key: ValueKey('neutral-unsaved'),
                      style: TextStyle(color: Color(0xFFFFA000)),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Sensor zero',
              help:
                  'Zero the four sensors with the air gap open wide. For the '
                  'level zero use the flip zero.',
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('zero-sensors'),
                      onPressed: live ? zero : null,
                      child: const Text('Zero sensors'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('clear-zero'),
                      onPressed: live ? clear : null,
                      child: const Text('Clear zero'),
                    ),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'Memory',
              help:
                  'Store writes the present calibration to the EEPROM (the '
                  'STO key); Recall reloads it and discards unsaved changes '
                  '(RCL).',
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('store'),
                      onPressed: live ? store : null,
                      child: const Text('Store'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('recall'),
                      onPressed: live ? recall : null,
                      child: const Text('Recall'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(NmTiltStatus? s) => switch (s) {
    null => '—',
    NmTiltStatus.ok => 'OK',
    NmTiltStatus.over => 'over range',
    NmTiltStatus.under => 'no signal',
    NmTiltStatus.invalid => 'invalid',
  };
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.help,
    required this.children,
  });

  final String title, help;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF1E1E1E),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            help,
            style: const TextStyle(color: Colors.white54, height: 1.3),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}
