import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inclinometer/devices/neigmess2/neigmess_state.dart';
import 'package:inclinometer/devices/neigmess2/protocol.dart';
import 'package:inclinometer/devices/neigmess2/providers/neigmess_provider.dart';
import 'package:inclinometer/devices/neigmess2/ui/actions.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/ui/device_switcher.dart';

/// The NeigMess2 live screen: the tilt of the centre sensor in large type
/// (or why there is none), plate capacitance, the four sensors above their
/// zero position and the X / Y angles. The menu zeroes the sensors.
class NeigMessScreen extends ConsumerWidget {
  const NeigMessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(neigmessDataProvider);
    final connected = ref.watch(neigmessSessionProvider) != null;
    final isStale = dataAsync.hasValue && dataAsync.value == null;
    final NeigMessState? d = dataAsync.hasValue ? dataAsync.value : null;

    return ActiveSessionRedirect(
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('NeigMess2', style: TextStyle(fontSize: 18)),
          actions: [
            const DeviceSwitcherButton(),
            PopupMenuButton<String>(
              key: const ValueKey('menu'),
              enabled: connected,
              onSelected: (v) => _onMenu(context, ref, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'flip', child: Text('Flip zero…')),
                PopupMenuItem(
                  value: 'calibration',
                  child: Text('Calibration…'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(value: 'zero', child: Text('Zero sensors')),
                PopupMenuItem(value: 'clear', child: Text('Clear zero')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isStale)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Connection lost — values are not live.',
                      key: ValueKey('stale'),
                      style: TextStyle(color: Color(0xFFD32F2F)),
                    ),
                  ),
                _TiltCard(state: isStale ? null : d),
                const SizedBox(height: 12),
                _Table(state: isStale ? null : d),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String v) async {
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(neigmessSessionProvider);
    if (session == null) return;
    switch (v) {
      case 'flip':
        context.push('/neigmess2/zero');
      case 'calibration':
        context.push('/neigmess2/calibration');
      case 'zero':
        if (await confirmAction(
          context,
          'Zero the sensors?',
          'Open the air gap wide first. The present readings become the '
              'zero position and are stored in the EEPROM.',
        )) {
          await runAction(messenger, session.zeroSensors);
        }
      case 'clear':
        if (await confirmAction(
          context,
          'Clear the zero?',
          'All offsets go back to 0 and are stored in the EEPROM.',
        )) {
          await runAction(messenger, session.clearZero);
        }
      case 'disconnect':
        await ref.read(connectionNotifierProvider.notifier).disconnect();
    }
  }
}

class _TiltCard extends StatelessWidget {
  const _TiltCard({required this.state});

  final NeigMessState? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final String big;
    final String? note;
    if (s == null || s.tiltStatus == null) {
      big = '—';
      note = null;
    } else if (s.hasTilt) {
      big = s.tilt!.toStringAsFixed(1);
      note = null;
    } else {
      big = '—';
      note = switch (s.tiltStatus!) {
        NmTiltStatus.over => 'Over range: the plates would touch.',
        NmTiltStatus.under => 'No signal: sensor missing or baseline wrong.',
        _ => 'No valid measurement yet.',
      };
    }
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('TILT', style: TextStyle(color: Colors.white54)),
            Text(
              big,
              key: const ValueKey('tilt'),
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300),
            ),
            const Text('µm/m', style: TextStyle(color: Colors.white54)),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note,
                  key: const ValueKey('tilt-note'),
                  style: const TextStyle(color: Color(0xFFFFA000)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.state});

  final NeigMessState? state;

  static String _f(double? v, int decimals, String unit) =>
      v == null ? '—' : '${v.toStringAsFixed(decimals)} $unit';

  @override
  Widget build(BuildContext context) {
    final s = state;
    final rows = <(String, String)>[
      ('Plate capacitance', _f(s?.plateCapPf, 2, 'pF')),
      for (var i = 0; i < 4; i++)
        (
          i == 3 ? 'Sensor 3 (centre)' : 'Sensor $i',
          _f(s?.sensorPf(i), 3, 'pF'),
        ),
      ('Angle X', _f(s?.angleXDeg, 2, '°')),
      ('Angle Y', _f(s?.angleYDeg, 2, '°')),
    ];
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          for (final (label, value) in rows)
            ListTile(
              dense: true,
              title: Text(label, style: const TextStyle(color: Colors.white70)),
              trailing: Text(value, key: ValueKey('row-$label')),
            ),
        ],
      ),
    );
  }
}
