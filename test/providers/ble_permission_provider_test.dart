import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inclinometer/providers/device_provider.dart';

void main() {
  group('blePermissionPermanentlyDeniedProvider', () {
    test('defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(blePermissionPermanentlyDeniedProvider), false);
    });

    test('can be set to true via notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(blePermissionPermanentlyDeniedProvider.notifier)
          .set(true);

      expect(container.read(blePermissionPermanentlyDeniedProvider), true);
    });
  });
}
