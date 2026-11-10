import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inclinometer/providers/device_names_provider.dart';
import 'package:inclinometer/providers/device_provider.dart';

/// Asks for a name for the instrument [id] and stores it. [technical] is the
/// identifier shown beside the name. Empty clears the name.
Future<void> showRenameDialog(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String technical,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(
      technical: technical,
      initial: ref.read(deviceNamesProvider)[id] ?? '',
    ),
  );
  if (name != null) {
    await ref.read(deviceNamesProvider.notifier).rename(id, name);
  }
}

/// The app-bar title of a device's home screen: the driver's name, or the
/// instrument's own name with the technical label beneath it.
class DeviceTitle extends ConsumerWidget {
  const DeviceTitle({super.key, required this.fallback});

  /// Shown when the instrument has no name (or none is connected).
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(activeSessionProvider);
    final name = s == null ? null : ref.watch(deviceNamesProvider)[s.id];
    if (s == null || name == null) {
      return Text(fallback, style: const TextStyle(fontSize: 18));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            key: const ValueKey('device-name'),
            style: const TextStyle(fontSize: 18)),
        Text(s.label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

/// Owns the text controller so it is disposed with the dialog, not before its
/// closing animation is over.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.technical, required this.initial});

  final String technical;
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this instrument'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.technical,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('rename-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Lathe bed',
              helperText: 'Leave empty to remove the name.',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('rename-save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
