import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inclinometer/devices/device_driver.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Wraps a driver's home screen: when the active device changes — it was
/// disconnected, or the user switched to another — the app goes to the new
/// active device's home, or back to /scan if none is left. Every driver's
/// home screen wears one, so none has to deal with it.
class ActiveSessionRedirect extends ConsumerWidget {
  const ActiveSessionRedirect({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<DeviceSession?>(activeSessionProvider, (prev, next) {
      if (prev?.id == next?.id || !context.mounted) return;
      context.go(next?.driver.homeLocation ?? '/scan');
    });
    return child;
  }
}

/// An app-bar button listing the open devices (tap one to switch to it) and
/// leading to the scan screen to add another.
class DeviceSwitcherButton extends ConsumerWidget {
  const DeviceSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(sessionsProvider);
    return PopupMenuButton<Object>(
      key: const ValueKey('device-switcher'),
      tooltip: 'Devices',
      icon: const Icon(Icons.devices, size: 20),
      onSelected: (v) {
        if (v is DeviceSession) {
          ref.read(sessionsProvider.notifier).activate(v.id);
        } else {
          context.go('/scan');
        }
      },
      itemBuilder: (_) => [
        for (final s in open.all)
          CheckedPopupMenuItem<Object>(
            value: s,
            checked: s.id == open.activeId,
            child: Text(s.label),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: 'add', child: Text('Add device…')),
      ],
    );
  }
}
