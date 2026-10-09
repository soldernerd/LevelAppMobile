import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/ble/api_catalog.dart';
import 'package:inclinometer/ble/device_link.dart';
import 'package:inclinometer/providers/device_provider.dart';
import 'package:inclinometer/providers/service_provider.dart';
import 'package:inclinometer/providers/value_table_provider.dart';
import 'package:inclinometer/ui/widgets/service_card.dart';

/// Everything configurable: the Settings (auto power-off, charging voltage,
/// battery thresholds, …), the one-shot actions (power off, force charge,
/// reboot to DFU, …) and all Calibrations values.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Settings', style: TextStyle(fontSize: 18)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Settings'),
              Tab(text: 'Actions'),
              Tab(text: 'Calibration'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ValueList(settings: true),
            _ActionsTab(),
            _ValueList(settings: false),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Values (settings / calibrations)
// ---------------------------------------------------------------------------

class _ValueList extends ConsumerWidget {
  const _ValueList({required this.settings});

  final bool settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        settings ? settingsTableProvider : calibrationTableProvider;
    final defs = settings ? kSettings : kCalibrations;
    final table = ref.watch(provider);

    return table.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not read the values.'),
            TextButton(
              onPressed: () => ref.read(provider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (values) {
        final children = <Widget>[];
        if (!settings) {
          children.add(const ServiceModeCard(showEndButton: true));
          children.add(const SizedBox(height: 8));
        }
        String? group;
        for (final d in defs) {
          final v = values[d.id];
          if (d.optional && v == null) continue; // not in this firmware
          if (d.group != group) {
            group = d.group;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(group.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12, letterSpacing: 1.2, color: Colors.white38)),
            ));
          }
          children.add(_ValueTile(def: d, value: v, provider: provider));
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(provider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: children,
          ),
        );
      },
    );
  }
}

class _ValueTile extends ConsumerWidget {
  const _ValueTile({
    required this.def,
    required this.value,
    required this.provider,
  });

  final ApiValueDef def;
  final int? value;
  final AsyncNotifierProvider<ValueTableNotifier, Map<int, int?>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFlag = def.type == ValType.u8 && def.max == 1;
    final shown = value == null
        ? '—'
        : (isFlag
            ? (value == 1 ? 'on' : 'off')
            : '$value${def.unit.isEmpty ? '' : ' ${def.unit}'}');
    return ListTile(
      key: ValueKey('value-${def.category}-${def.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(def.label),
      subtitle: Text(def.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (def.service)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.lock_outline, size: 14, color: Colors.white38),
            ),
          Text(shown,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
      onTap: value == null ? null : () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    if (def.service && !ref.read(serviceModeProvider)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(def.label),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Writing this value needs service mode.'),
              SizedBox(height: 12),
              ServiceModeCard(),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final newValue = await showDialog<int>(
      context: context,
      builder: (_) => _EditDialog(def: def, current: value!),
    );
    if (newValue == null || newValue == value) return;
    if (!context.mounted) return;
    try {
      await ref.read(provider.notifier).write(def, newValue);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${def.label}: saved')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on LinkException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lost contact with the instrument.')));
      }
    }
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.def, required this.current});

  final ApiValueDef def;
  final int current;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _c;
  late bool _flag;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: '${widget.current}');
    _flag = widget.current == 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _isFlag => widget.def.type == ValType.u8 && widget.def.max == 1;

  void _save() {
    if (_isFlag) {
      Navigator.pop(context, _flag ? 1 : 0);
      return;
    }
    final v = int.tryParse(_c.text.trim());
    if (v == null || v < widget.def.min || v > widget.def.max) {
      setState(() => _error =
          'Enter a whole number from ${widget.def.min} to ${widget.def.max}.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    return AlertDialog(
      title: Text(d.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.description,
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 12),
          if (_isFlag)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _flag,
              onChanged: (v) => setState(() => _flag = v),
            )
          else
            TextField(
              key: const ValueKey('edit-field'),
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(
                  signed: d.min < 0, decimal: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(d.min < 0 ? r'[-0-9]' : r'[0-9]')),
              ],
              decoration: InputDecoration(
                suffixText: d.unit,
                helperText: 'Range ${d.min} … ${d.max}'
                    '${d.unit.isEmpty ? '' : ' ${d.unit}'}',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            key: const ValueKey('edit-save'),
            onPressed: _save,
            child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

class _ActionsTab extends ConsumerWidget {
  const _ActionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(instrumentApiProvider);
    final state = ref.watch(instrumentDataProvider).asData?.value;
    final service = ref.watch(serviceModeProvider);
    final inhibited = state?.status?.chargeInhibited ?? false;
    final forced = state?.status?.forceCharging ?? false;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _Section('Power'),
        _Action(
          keyName: 'power-off',
          icon: Icons.power_settings_new,
          label: 'Power off',
          subtitle: 'Put the instrument to sleep now. Wake it with a knob '
              'press or by plugging in USB.',
          confirm: 'Power the instrument off? The connection will end.',
          expectsLinkLoss: true,
          run: api.powerOff,
        ),
        _Action(
          keyName: 'reboot',
          icon: Icons.restart_alt,
          label: 'Reboot',
          subtitle: 'Restart the instrument.',
          confirm: 'Restart the instrument? The connection will end.',
          expectsLinkLoss: true,
          run: api.reboot,
        ),
        const _Section('Charging'),
        _Action(
          keyName: 'force-charge',
          icon: Icons.battery_charging_full,
          label: forced ? 'Forced charge is armed' : 'Force charge',
          subtitle: 'Charge regardless of the level while USB power is '
              'present, until full or USB is removed.',
          run: api.forceCharge,
        ),
        _Action(
          keyName: 'end-charge',
          icon: Icons.battery_alert,
          label: 'End forced charge',
          subtitle: 'Cancel an armed forced charge (normal automatic '
              'charging continues).',
          run: api.endCharging,
        ),
        SwitchListTile(
          key: const ValueKey('charge-inhibit'),
          secondary: const Icon(Icons.block, color: Colors.white70),
          title: const Text('Inhibit charging'),
          subtitle: const Text(
              'Hold charging off until cleared (e.g. during a measurement — '
              'charging adds noise).',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          value: inhibited,
          onChanged: (v) => _run(context, () => api.setChargeInhibit(v), null),
        ),
        const _Section('Maintenance'),
        _Action(
          keyName: 'beep',
          icon: Icons.volume_up,
          label: 'Test beep',
          subtitle: 'Sound the buzzer for 100 ms.',
          run: api.testBeep,
        ),
        _Action(
          keyName: 'clear-counters',
          icon: Icons.cleaning_services,
          label: 'Clear counters',
          subtitle: 'Zero the communication, drop and fault counters and the '
              'sticky error latches.',
          run: api.clearCounters,
        ),
        if (service)
          _Action(
            keyName: 'service-end',
            icon: Icons.lock,
            label: 'Leave service mode',
            subtitle: 'Lock calibration writes and maintenance commands '
                'again.',
            run: api.serviceEnd,
          ),
        const _Section('Service mode only'),
        const ServiceModeCard(),
        const SizedBox(height: 8),
        _Action(
          keyName: 'dfu',
          icon: Icons.system_update_alt,
          label: 'Reboot to DFU',
          subtitle: 'Put the instrument in the ROM bootloader for flashing. '
              'It STAYS there on every boot until reflashed.',
          confirm: 'The instrument will stay in the bootloader until its '
              'firmware is reflashed over USB (dfu_flash.ps1). Only continue '
              'if you have a computer and the firmware at hand.',
          confirmLabel: 'Reboot to DFU',
          danger: true,
          needsService: true,
          expectsLinkLoss: true,
          run: api.rebootToDfu,
        ),
        _Action(
          keyName: 'factory',
          icon: Icons.warning_amber,
          label: 'Factory defaults',
          subtitle: 'Reset ALL settings and calibrations to the compiled '
              'defaults. This wipes the tilt calibrations.',
          confirm: 'This erases every setting and every calibration of this '
              'instrument, including the sensor calibration.',
          confirmLabel: 'Erase everything',
          typedConfirm: 'RESET',
          danger: true,
          needsService: true,
          run: api.factoryDefaults,
        ),
      ],
    );
  }
}

Future<void> _run(
  BuildContext context,
  Future<void> Function() run,
  String? okMessage, {
  bool expectsLinkLoss = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await run();
    if (okMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(okMessage)));
    }
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on LinkException catch (_) {
    if (!expectsLinkLoss) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Lost contact with the instrument.')));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, letterSpacing: 1.2, color: Colors.white38)),
      );
}

class _Action extends ConsumerWidget {
  const _Action({
    required this.keyName,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.run,
    this.confirm,
    this.confirmLabel = 'OK',
    this.typedConfirm,
    this.danger = false,
    this.needsService = false,
    this.expectsLinkLoss = false,
  });

  final String keyName;
  final IconData icon;
  final String label;
  final String subtitle;
  final Future<void> Function() run;
  final String? confirm;
  final String confirmLabel;

  /// The user must type this word to proceed.
  final String? typedConfirm;
  final bool danger;
  final bool needsService;
  final bool expectsLinkLoss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceModeProvider);
    final disabled = needsService && !service;
    final color = danger ? const Color(0xFFE57373) : Colors.white70;
    return ListTile(
      key: ValueKey('action-$keyName'),
      enabled: !disabled,
      leading: Icon(icon, color: disabled ? Colors.white24 : color),
      title: Text(label, style: danger ? TextStyle(color: color) : null),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
      onTap: disabled
          ? null
          : () async {
              if (confirm != null) {
                final go = await showDialog<bool>(
                  context: context,
                  builder: (_) => _ConfirmDialog(
                    title: label,
                    message: confirm!,
                    confirmLabel: confirmLabel,
                    typedConfirm: typedConfirm,
                    danger: danger,
                  ),
                );
                if (go != true) return;
              }
              if (!context.mounted) return;
              await _run(context, run, '$label: done',
                  expectsLinkLoss: expectsLinkLoss);
            },
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.danger,
    this.typedConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String? typedConfirm;
  final bool danger;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.typedConfirm;
    final ok = typed == null || _c.text.trim() == typed;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          if (typed != null) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('confirm-field'),
              controller: _c,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Type $typed to confirm'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('confirm-ok'),
          style: widget.danger
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828))
              : null,
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
