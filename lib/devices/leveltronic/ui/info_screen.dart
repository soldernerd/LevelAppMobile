import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/devices/leveltronic/protocol.dart';
import 'package:inclinometer/devices/leveltronic/providers/leveltronic_provider.dart';
import 'package:inclinometer/devices/leveltronic/providers/info_provider.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/battery_indicator.dart';
import 'package:inclinometer/devices/leveltronic/ui/widgets/format.dart';

/// Every value the instrument reports besides the tilt: battery, all
/// temperatures, humidity, pressure, the clock, identity and health.
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(instrumentDataProvider).asData?.value;
    final status = d?.status;
    final env = d?.env;
    final identity = ref.watch(identityProvider).asData?.value;
    final health = ref.watch(healthProvider).asData?.value.value;
    final rtc = ref.watch(rtcProvider).asData?.value;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('All values', style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Group('Battery', [
              _Row('Charge', fmtPercent(status?.batterySocPct),
                  trailing: status == null
                      ? null
                      : BatteryIndicator(
                          percent: status.batterySocPct,
                          charging: status.charging,
                          state: status.batteryState,
                          showLabel: false,
                          size: 16,
                        )),
              _Row('Voltage', fmtVolts(status?.batteryMv)),
              _Row('State', _batteryState(status)),
              _Row('USB power', _yesNo(status?.usbConnected)),
              _Row('Charging', _yesNo(status?.charging)),
              _Row('Forced charge armed', _yesNo(status?.forceCharging)),
              _Row('Charging inhibited', _yesNo(status?.chargeInhibited)),
            ]),
            _Group('Temperature', [
              _Row('On-board (TMP236)', fmtTempC(env?.onboardTempC)),
              _Row('Ambient (BME280)', fmtTempC(env?.bmeTempC),
                  note: env != null && !env.bmeOk ? 'stale' : null),
              _Row(
                'External probe (LM35)',
                env == null || !env.externalTempOk
                    ? (env == null ? '—' : 'not connected')
                    : fmtTempC(env.externalTempC),
              ),
            ]),
            _Group('Environment', [
              _Row(
                'Humidity',
                env == null
                    ? '—'
                    : '${env.humidityPct.toStringAsFixed(1)} %RH',
                note: env != null && !env.bmeOk ? 'stale' : null,
              ),
              _Row(
                'Pressure',
                env == null
                    ? '—'
                    : '${env.pressureHpa.toStringAsFixed(1)} hPa',
                note: env != null && !env.bmeOk ? 'stale' : null,
              ),
            ]),
            _Group('Clock', [
              _Row('Instrument time', rtc == null ? '—' : fmtDateTime(rtc.value.dateTime),
                  note: rtc != null && !rtc.value.isSet ? 'not set' : null),
              _Row('Phone time', rtc == null ? '—' : fmtDateTime(rtc.at)),
              _Row('Difference', rtc == null ? '—' : _drift(rtc)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('set-clock'),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: const Text('Set instrument clock to phone time'),
                  onPressed: () => _setClock(context, ref),
                ),
              ),
            ]),
            _Group('Instrument', [
              _Row('Product', identity?.product ?? '—'),
              _Row('Serial', identity?.serial ?? '—'),
              _Row('Firmware', identity?.firmware ?? '—'),
              _Row('Build', identity?.build ?? '—'),
              _Row('API version', identity == null ? '—' : '${identity.apiVersion}'),
            ]),
            _Group('Activity', [
              _Row('Tilt measurement running', _yesNo(status?.demodRunning)),
              _Row('Phasor stream active', _yesNo(status?.phasorStreamActive)),
              _Row('Bulk capture active', _yesNo(status?.bulkActive)),
              _Row('Service mode', _yesNo(status?.serviceMode)),
              _Row('3.3 V rail', _yesNo(status?.rail3v3On)),
              _Row('5 V rail', _yesNo(status?.rail5vOn)),
            ]),
            _Group('Health', [
              _Row('Uptime', health == null ? '—' : fmtUptime(health.uptimeS)),
              _Row('Last reset',
                  health == null ? '—' : _resetCause(health)),
              _Row('Settings storage', health == null ? '—' : _eeprom(health)),
              _Row('ADC / ADS / DAC',
                  health == null ? '—' : '${_ok(health.adcOk)} / ${_ok(health.adsOk)} / ${_ok(health.dacOk)}'),
              _Row('Display / BME280',
                  health == null ? '—' : '${_ok(health.displayOk)} / ${_ok(health.bmeOk)}'),
              _Row('Dropped frames (USB/BLE/UART)',
                  health == null ? '—' : '${health.usbTxDropped} / ${health.bleTxDropped} / ${health.uartTxDropped}'),
              _Row('Malformed requests',
                  health == null ? '—' : '${health.rxMalformed}'),
              _Row('Last fault', health == null ? '—' : _fault(health)),
            ]),
          ],
        ),
      ),
    );
  }

  static String _yesNo(bool? v) => v == null ? '—' : (v ? 'yes' : 'no');
  static String _ok(bool v) => v ? 'ok' : 'FAIL';

  static String _batteryState(ApiSystemState? s) => s == null
      ? '—'
      : switch (s.batteryState) {
          BatteryState.normal => 'Normal',
          BatteryState.low => 'Low',
          BatteryState.critical => 'Critical',
          BatteryState.charging => 'Charging',
          BatteryState.full => 'Full',
          BatteryState.unknown => 'Unknown',
        };

  static String _drift(Timed<ApiRtc> rtc) {
    final diff = rtc.value.dateTime.difference(rtc.at);
    final s = diff.inSeconds;
    if (s.abs() < 2) return 'within 2 s';
    final sign = s > 0 ? 'ahead' : 'behind';
    final a = s.abs();
    final txt = a >= 3600
        ? '${a ~/ 3600} h ${(a % 3600) ~/ 60} min'
        : (a >= 60 ? '${a ~/ 60} min ${a % 60} s' : '$a s');
    return '$txt $sign';
  }

  static String _resetCause(ApiHealth h) {
    final n = h.resetCauseNames;
    return n.isEmpty ? 'none' : n.join(', ');
  }

  static String _eeprom(ApiHealth h) {
    if (h.settingsSaveFailed) return 'SAVE FAILED';
    return switch (h.eepromSelftest) {
      1 => 'ok (self-test passed)',
      2 => 'self-test FAILED',
      _ => 'self-test not run',
    };
  }

  static String _fault(ApiHealth h) => switch (h.lastFaultKind) {
        0 => 'none',
        1 => 'HardFault  pc 0x${h.lastFaultPc.toRadixString(16)}  lr 0x${h.lastFaultLr.toRadixString(16)}',
        2 => 'init failure',
        _ => 'unknown (${h.lastFaultKind})',
      };

  Future<void> _setClock(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(instrumentApiProvider).setRtc(DateTime.now());
      messenger.showSnackBar(
          const SnackBar(content: Text('Instrument clock set.')));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not set the clock.')));
    }
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 1.2, color: Colors.white38)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.note, this.trailing});

  final String label;
  final String value;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.white60)),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(note!,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFFFA000))),
            ),
          if (trailing != null)
            Padding(
                padding: const EdgeInsets.only(right: 8), child: trailing),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
