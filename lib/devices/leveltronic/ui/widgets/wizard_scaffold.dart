import 'package:flutter/material.dart';

/// The common frame of the wizard screens: dark scaffold, title, scrollable
/// padded column, optional bottom action bar.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.canPop = true,
    this.onBlockedPop,
  });

  final String title;
  final List<Widget> children;

  /// Buttons pinned to the bottom (e.g. Cancel / Continue).
  final List<Widget>? actions;

  /// False while a measurement runs: leaving would orphan it.
  final bool canPop;
  final VoidCallback? onBlockedPop;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onBlockedPop?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancel the running step first.')),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(title, style: const TextStyle(fontSize: 18)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: actions![i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
