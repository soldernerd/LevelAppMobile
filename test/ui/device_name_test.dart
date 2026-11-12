import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inclinometer/providers/device_names_provider.dart';
import 'package:inclinometer/providers/device_provider.dart';

import '../support/app_harness.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('a name is shown beside the technical label and survives',
      (tester) async {
    final h = await AppHarness.start(tester);
    final s = h.container.read(activeSessionProvider)!;
    expect(find.text('Precision level'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name this instrument…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Lathe bed');
    await tester.tap(find.byKey(const ValueKey('rename-save')));
    await tester.pumpAndSettle();

    // Name as title, technical label beneath it.
    expect(find.byKey(const ValueKey('device-name')), findsOneWidget);
    expect(find.text('Lathe bed'), findsOneWidget);
    expect(find.text(s.label), findsOneWidget);

    // Stored: a fresh notifier reads it back.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('device_names'), contains('Lathe bed'));

    // Switcher lists both.
    await tester.tap(find.byKey(const ValueKey('device-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('Lathe bed · ${s.label}'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Empty removes it again.
    await h.container.read(deviceNamesProvider.notifier).rename(s.id, '  ');
    await h.pump(tester, const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('device-name')), findsNothing);
    await h.dispose(tester);
  });
}
